#!/usr/bin/env python3
"""system_access — sign-in and access facts this computer actually uses, read only.

    system_access.py directory    {"sssd", "slapd", "nsswitch", "error"}
    system_access.py kerberos     {"realm", "domainRealm", "cache", "loaded", "error"}
    system_access.py smartcard    {"mapper", "provider", "mappings", "readers", ...}
    system_access.py smartcard-stage   JSON on stdin -> staged mapping text
    system_access.py privileges   {"rules": [{"file", "actions": [...]}], "error"}
    system_access.py sudoers      {"path", "text", "rows", "other", "unreadable"}
    system_access.py sshd         {"path", "settings", "kept", "unreadable", "mode", "owner"}
    system_access.py sshd-stage   JSON on stdin -> staged sshd drop-in text
    system_access.py lsm          {"active", "available", "error"}
    system_access.py sshkeys      {"path", "keys": [{"type", "comment", "fingerprint"}], "error"}
    system_access.py totp         {"users": [...], "pamWired", "pamStacks", "usersfile", ...}

One JSON object per verb. Nothing is written and no root is needed: a file that
cannot be read is reported as such, never filled in. No password, key blob or
secret is returned. Service states are systemctl's own words ("active",
"inactive", "unknown"); nsswitch is one line per switch; domainRealm is the
first "domain = realm" line; cache is the credential cache file's path when one
exists; available LSM names are the known names named by the kernel.

Test overrides: SHANI_SYSTEM_SYSTEMCTL, SHANI_NSSWITCH, SHANI_KRB5_CONF,
SHANI_KRB5_CCACHE, SHANI_SYSTEM_PAM_DIR, SHANI_PKCS11_CONF, SHANI_PKCS11_MAP,
SHANI_POLKIT_DIR, SHANI_SUDOERS, SHANI_SSHD_CONF, SHANI_LSM_FILE,
SHANI_SYSTEM_SSH_KEYGEN, SHANI_AUTHORIZED_KEYS, SHANI_OATH_FILE,
SHANI_OATHTOOL, SHANI_PCSC_SCAN.
"""

from __future__ import annotations

import glob
import grp
import hashlib
import json
import os
import pwd
import re
import shlex
import shutil
import subprocess
import sys

KNOWN_LSM = (
    "capability",
    "seccomp",
    "yama",
    "apparmor",
    "selinux",
    "smack",
    "tomoyo",
    "integrity",
    "evm",
    "ima",
    "lockdown",
    "bpf",
    "landlock",
    "ipe",
)
SECRET_VALUE = re.compile(r"private key|secret|token|credential|password", re.I)
STATES = {"active", "inactive", "activating", "deactivating", "failed", "unknown"}
_SSH_NAME = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
MANAGED_SSH = {
    "PasswordAuthentication",
    "PubkeyAuthentication",
    "PermitRootLogin",
    "AllowTcpForwarding",
    "X11Forwarding",
    "MaxAuthTries",
    "AllowUsers",
    "AllowGroups",
}
PAM_OATH = "pam_oath.so"
PAM_PKCS11 = "pam_pkcs11.so"
PCSC_DOWN = re.compile(
    r"daemon|service not available|SCardEstablishContext|can't be loaded|"
    r"unable to load|not running|connection refused|failed to connect|no pcsc",
    re.I,
)


def _cmd(env: str, default: str) -> list[str]:
    return shlex.split(os.environ.get(env, default))


def _text(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def _run(cmd: list[str], *args: str, timeout: int = 10):
    try:
        return subprocess.run(
            cmd + list(args), capture_output=True, text=True, timeout=timeout
        ), ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)


def _last_line(text: str, fallback: str) -> str:
    return (text.strip().splitlines() or [fallback])[-1][:200]


def _stat_info(path: str) -> tuple[str, str]:
    """Mode as octal digits and owner as user:group, empty when stat fails."""
    try:
        st = os.stat(path)
    except OSError:
        return "", ""
    mode = format(st.st_mode & 0o7777, "o")
    try:
        user = pwd.getpwuid(st.st_uid).pw_name
    except KeyError:
        user = str(st.st_uid)
    try:
        group = grp.getgrgid(st.st_gid).gr_name
    except KeyError:
        group = str(st.st_gid)
    return mode, f"{user}:{group}"


def _pam_lines(directory: str, path: str, seen: set[str]):
    """Yield (stack name, line) for every module line reachable from a stack."""
    real = os.path.realpath(path)
    if real in seen:
        return
    seen.add(real)
    text = _text(path) or ""
    name = os.path.basename(path)
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        include = re.match(r"^@?(?:include|substack)\s+(.+?)\s*$", s)
        if include:
            target = os.path.basename(include.group(1).strip().strip("\"'"))
            if target:
                yield from _pam_lines(directory, os.path.join(directory, target), seen)
            continue
        yield name, s


def pam_scan() -> dict:
    """One PAM stack scan shared by the sign-in-code and smartcard reads."""
    out = {
        "pamWired": False,
        "pamStacks": [],
        "usersfile": "",
        "pamPkcs11": False,
    }
    directory = os.environ.get("SHANI_SYSTEM_PAM_DIR", "/etc/pam.d")
    stacks: set[str] = set()
    seen: set[str] = set()
    if os.path.isdir(directory):
        for entry in sorted(os.listdir(directory)):
            for name, line in _pam_lines(
                directory, os.path.join(directory, entry), seen
            ):
                if PAM_OATH in line:
                    out["pamWired"] = True
                    stacks.add(name)
                    arg = re.search(
                        r"usersfile\s*=\s*(\"[^\"]*\"|'[^']*'|\S+)", line, re.I
                    )
                    if arg:
                        out["usersfile"] = arg.group(1).strip("\"'")
                if PAM_PKCS11 in line:
                    out["pamPkcs11"] = True
    out["pamStacks"] = sorted(stacks)
    if not out["usersfile"]:
        candidate = os.path.expanduser("~/.config/oath/users.oath")
        out["usersfile"] = (
            candidate
            if os.path.exists(candidate)
            else os.environ.get("SHANI_OATH_FILE", "/etc/users.oath")
        )
    return out


def _state(unit: str) -> str:
    r, err = _run(_cmd("SHANI_SYSTEM_SYSTEMCTL", "systemctl"), "is-active", unit)
    if err or r is None:
        return "unknown"
    value = r.stdout.strip().splitlines()
    value = value[-1].strip() if value else ""
    return value if value in STATES else "unknown"


def directory() -> dict:
    """Directory services and the name-service switches that use them."""
    out = {"sssd": "unknown", "slapd": "unknown", "nsswitch": "", "error": ""}
    switches: dict[str, str] = {}
    systemctl = _cmd("SHANI_SYSTEM_SYSTEMCTL", "systemctl")
    if shutil.which(systemctl[0] if systemctl else ""):
        out["sssd"] = _state("sssd.service")
        out["slapd"] = _state("slapd.service")
    else:
        out["error"] = "systemctl is not available"
    text = _text(os.environ.get("SHANI_NSSWITCH", "/etc/nsswitch.conf"))
    if text is None:
        out["error"] = out["error"] or "name service file is not readable"
    else:
        for line in text.splitlines():
            m = re.match(r"^\s*(passwd|group)\s*:\s*(.*)$", line)
            if m:
                switches[m.group(1)] = m.group(2).strip()
        out["nsswitch"] = ", ".join(f"{k}: {v}" for k, v in switches.items())
    return out


def _sections(text: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    name = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("[") and line.endswith("]"):
            name = line[1:-1]
            sections.setdefault(name, [])
        elif "=" in line:
            sections.setdefault(name, []).append(line)
    return sections


def kerberos() -> dict:
    """Realm, domain mapping, cache presence and whether PAM loads the module."""
    out = {"realm": "", "domainRealm": "", "cache": "", "loaded": False, "error": ""}
    text = _text(os.environ.get("SHANI_KRB5_CONF", "/etc/krb5.conf"))
    if text is None:
        out["error"] = "Kerberos configuration is not readable"
    else:
        conf = _sections(text)
        for line in conf.get("libdefaults", []):
            key, value = line.split("=", 1)
            if key.strip().lower() == "default_realm":
                out["realm"] = value.strip().strip('"')
        mappings = []
        for line in conf.get("domain_realm", []):
            key, value = line.split("=", 1)
            if key.strip() and value.strip():
                mappings.append(f"{key.strip()} = {value.strip().strip(chr(34))}")
        out["domainRealm"] = mappings[0] if mappings else ""
    # Existence only: a credential cache is never opened or copied.
    pattern = os.environ.get("SHANI_KRB5_CCACHE", "/tmp/krb5cc_*")
    found = sorted(glob.glob(pattern))
    out["cache"] = found[0] if found else ""
    pam_dir = os.environ.get("SHANI_SYSTEM_PAM_DIR", "/etc/pam.d")
    if not os.path.isdir(pam_dir):
        out["error"] = out["error"] or "PAM directory is not readable"
    else:
        for name in os.listdir(pam_dir):
            stack = _text(os.path.join(pam_dir, name)) or ""
            if "pam_krb5.so" in stack:
                out["loaded"] = True
                break
    return out


def pcsc_readers() -> list[dict]:
    """Reader states and names from pcsc_scan. No card, PIN or certificate data."""
    cmd = _cmd("SHANI_PCSC_SCAN", "pcsc_scan")
    if not cmd or not shutil.which(cmd[0]):
        return [{"state": "tool_missing", "name": ""}]
    r, err = _run(cmd, "-n")
    if err:
        state = "daemon_down" if "timed out" in err.lower() else "tool_missing"
        return [{"state": state, "name": ""}]
    output = ((r.stdout or "") + "\n" + (r.stderr or "")) if r else ""
    readers = []
    for line in output.splitlines():
        m = re.match(r"^\s*Reader\s+\d+\s*:\s*(.+?)\s*$", line, re.I)
        if m and m.group(1).strip():
            readers.append({"state": "ready", "name": m.group(1).strip()})
    if readers:
        return readers
    state = (
        "daemon_down"
        if (r.returncode != 0 or PCSC_DOWN.search(output))
        else "no_reader"
    )
    return [{"state": state, "name": ""}]


def smartcard() -> dict:
    """Configured mapper, provider, mappings and reader states. No card data."""
    out = {
        "mapper": "",
        "provider": "",
        "mappings": [],
        "error": "",
        "readers": [],
        "pamPkcs11": False,
        "mappingPath": "",
        "mappingMode": "",
        "mappingOwner": "",
    }
    out["readers"] = pcsc_readers()
    out["pamPkcs11"] = pam_scan()["pamPkcs11"]
    text = _text(os.environ.get("SHANI_PKCS11_CONF", "/etc/pam_pkcs11/pam_pkcs11.conf"))
    if text is None:
        out["error"] = "smartcard configuration is not readable"
    else:
        module = ""
        for line in text.splitlines():
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            m = re.match(r"use_mappers\s*=\s*(.+?)\s*;?\s*$", s)
            if m and not out["mapper"]:
                out["mapper"] = m.group(1).strip().strip('"')
            m = re.match(r'pkcs11_module\s*=\s*"?([^";]+)', s)
            if m:
                out["provider"] = m.group(1).strip()
            else:
                m = re.match(r'module\s*=\s*"?([^";]+)', s)
                if m and not module:
                    value = m.group(1).strip()
                    if value.startswith("/") or ".so" in value:
                        module = value
        out["provider"] = out["provider"] or module
    mapping_path = os.environ.get("SHANI_PKCS11_MAP", "/etc/pam_pkcs11/subject_mapping")
    out["mappingPath"] = mapping_path
    out["mappingMode"], out["mappingOwner"] = _stat_info(mapping_path)
    mapping_text = _text(mapping_path)
    if mapping_text is None:
        out["error"] = out["error"] or "smartcard mapping file is not readable"
    else:
        for line in mapping_text.splitlines():
            s = line.split("#", 1)[0].strip()
            if "->" not in s:
                continue
            identity, login = (part.strip() for part in s.split("->", 1))
            if identity and login:
                out["mappings"].append(
                    {
                        "identity": identity,
                        "login": login,
                        "name": identity,
                        "user": login,  # the two names callers use
                    }
                )
    return out


def smartcard_stage(req: dict) -> dict:
    """Stage an identity -> login mapping file from plain data, never card data."""
    out = {
        "text": "",
        "sha256": "",
        "mappings": [],
        "other": [],
        "refuse": False,
        "error": "",
    }
    items = req.get("mappings", []) if isinstance(req, dict) else []
    if not isinstance(items, list):
        out["refuse"], out["error"] = True, "bad_request"
        return out
    cleaned: list[dict] = []
    identities: set[str] = set()
    pairs: set[tuple[str, str]] = set()
    for item in items:
        if not isinstance(item, dict):
            out["refuse"], out["error"] = True, "bad_mapping"
            continue
        identity = str(item.get("identity", "") or "")
        login = str(item.get("login", "") or "")
        if any(
            not value
            or len(value) > 256
            or "->" in value
            or "\n" in value
            or "\r" in value
            for value in (identity, login)
        ):
            out["refuse"], out["error"] = True, "bad_mapping"
            continue
        if identity in identities or (identity, login) in pairs:
            out["refuse"], out["error"] = True, "duplicate_mapping"
            continue
        identities.add(identity)
        pairs.add((identity, login))
        cleaned.append({"identity": identity, "login": login})
    out["mappings"] = cleaned
    path = os.environ.get("SHANI_PKCS11_MAP", "/etc/pam_pkcs11/subject_mapping")
    current = _text(path)
    keep: list[str] = []
    if current is not None:
        for raw in current.splitlines(keepends=True):
            s = raw.strip()
            if s.startswith("#"):
                keep.append(raw)
            elif "->" not in s:
                keep.append(raw)
    out["other"] = [line for line in keep if not line.strip().startswith("#")]
    text = "".join(keep)
    if text and not text.endswith(("\n", "\r")):
        text += "\n"
    for item in cleaned:
        text += f"{item['identity']} -> {item['login']}\n"
    out["text"] = text
    out["sha256"] = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return out


def _rule_blocks(text: str) -> list[str]:
    """Bodies of polkit.addRule calls, braces matched without treating strings as code."""
    blocks = []
    for m in re.finditer(r"polkit\.addRule\s*\(", text):
        start = text.find("{", m.end())
        if start < 0:
            continue
        depth, quote, i = 0, "", start
        while i < len(text):
            ch = text[i]
            if quote:
                if ch == "\\":
                    i += 2
                    continue
                if ch == quote:
                    quote = ""
            elif ch in "\"'":
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(text[start + 1 : i])
                    break
            i += 1
    return blocks


def privileges() -> dict:
    """Only action ids written in the system's own polkit rule blocks."""
    out = {"rules": [], "error": ""}
    directory = os.environ.get("SHANI_POLKIT_DIR", "/etc/polkit-1/rules.d")
    if not os.path.isdir(directory):
        out["error"] = "polkit rules directory is not readable"
        return out
    for path in sorted(glob.glob(os.path.join(directory, "*.rules"))):
        text = _text(path) or ""
        actions = []
        for block in _rule_blocks(text):
            for action in re.findall(r"['\"](org\.[A-Za-z0-9_.-]+)['\"]", block):
                if action not in actions:
                    actions.append(action)
        if actions:
            out["rules"].append({"file": path, "actions": actions})
    return out


def sudoers_rows(text: str) -> dict:
    """Parse a sudoers drop-in into managed rows and byte-preserved other lines."""
    out: dict[str, list] = {"rows": [], "other": [], "unreadable": []}
    for raw in text.splitlines(keepends=True):
        s = raw.strip()
        if (
            not s
            or s.startswith("#")
            or re.match(
                r"^(Defaults|User_Alias|Runas_Alias|Host_Alias|Cmnd_Alias)\b", s
            )
        ):
            out["other"].append(raw)
            continue
        if "=" not in s:
            out["unreadable"].append(raw)
            continue
        left, right = (part.strip() for part in s.split("=", 1))
        if not left or not right:
            out["unreadable"].append(raw)
            continue
        runas = ""
        m = re.match(r"^\(([^)]*)\)\s*(.*)$", right)
        if m:
            runas = m.group(1).strip()
            right = m.group(2).strip()
        elif "(" in right and ")" not in right:
            out["unreadable"].append(raw)
            continue
        tags: list[str] = []
        while True:
            m = re.match(r"^([A-Za-z_]+):\s*(.*)$", right)
            if not m:
                break
            tags.append(m.group(1).upper())
            right = m.group(2).strip()
        commands = [part.strip() for part in right.split(",") if part.strip()]
        if not commands:
            out["unreadable"].append(raw)
            continue
        out["rows"].append(
            {
                "who": left,
                "runas": runas,
                "tags": tags,
                "commands": commands,
                "raw": raw.rstrip("\r\n"),
                "nopasswd": "NOPASSWD" in tags,
                "warning": (
                    "all_commands" if any(c.upper() == "ALL" for c in commands) else ""
                ),
            }
        )
    return out


def sudoers() -> dict:
    """The one drop-in the Security page also reads; absent means empty."""
    path = os.environ.get("SHANI_SUDOERS", "/etc/sudoers.d/50-shani-shell")
    text = _text(path) or ""
    out = {"path": path, "text": text, "error": ""}
    out.update(sudoers_rows(text))
    return out


def _redact(raw: str) -> str:
    """Keep a line's bytes unless its value looks secret or is over-long."""
    s = raw.rstrip("\r\n")
    ending = raw[len(s) :]
    m = re.match(r"^\s*([A-Za-z][A-Za-z0-9]*)\s+(.+)$", s)
    value = m.group(2).strip() if m else s.lstrip("#").strip()
    if value not in {"yes", "no", "prohibit-password"} and (
        SECRET_VALUE.search(value) or len(s) > 200
    ):
        return "[hidden]" + ending
    return raw


SSH_VALUES = {
    "PasswordAuthentication": {"yes", "no"},
    "PubkeyAuthentication": {"yes", "no"},
    "PermitRootLogin": {"yes", "no", "prohibit-password"},
    "AllowTcpForwarding": {"yes", "no"},
    "X11Forwarding": {"yes", "no"},
}


def _ssh_line_manageable(keyword: str, value: str) -> bool:
    """Only a value this bridge can write is managed; the rest is kept as-is."""
    if keyword in SSH_VALUES:
        return value.lower() in SSH_VALUES[keyword]
    if keyword in ("AllowUsers", "AllowGroups"):
        return all(_SSH_NAME.match(tok) for tok in value.split()) and bool(value)
    if keyword == "MaxAuthTries":
        return value.isdigit() and 1 <= int(value) <= 10
    return False


def sshd_parse(text: str) -> dict:
    """Classify sshd lines into managed, byte-preserved and unreadable lines.

    An unmanaged directive is kept byte-for-byte; a Match block, an indented
    line inside one and a Key=Value line cannot be rewritten safely, so they
    are reported as unreadable and block a save. The public view redacts them;
    this parser returns the raw text so a staged file keeps its other lines.
    """
    out: dict = {"settings": {}, "kept": [], "unreadable": [], "lines": []}
    for raw in text.splitlines(keepends=True):
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        m = re.match(r"^([A-Za-z][A-Za-z0-9]*)\s+(.+)$", s)
        if not m or raw[:1] in (" ", "\t") or s.startswith("Match "):
            out["unreadable"].append(raw)
            out["lines"].append(("", raw))
            continue
        keyword, value = m.group(1), m.group(2).strip()
        out["settings"][keyword] = (
            "[hidden]"
            if value not in {"yes", "no", "prohibit-password"}
            and (SECRET_VALUE.search(value) or len(value) > 200)
            else value
        )
        if keyword in MANAGED_SSH and _ssh_line_manageable(keyword, value):
            out["lines"].append((keyword, raw))
        else:
            out["kept"].append(raw)
            out["lines"].append(("", raw))
    return out


def _ssh_yes_no(value) -> str:
    if isinstance(value, bool):
        return "yes" if value else "no"
    text = str(value or "").strip().lower()
    if text in {"yes", "true", "1"}:
        return "yes"
    if text in {"no", "false", "0"}:
        return "no"
    raise ValueError("bad_value")


def _ssh_root(value) -> str:
    if isinstance(value, bool):
        return "yes" if value else "prohibit-password"
    text = str(value or "").strip().lower()
    if text in {"yes", "no", "prohibit-password"}:
        return text
    raise ValueError("bad_value")


def _ssh_names(raw, label: str) -> str:
    tokens = str(raw or "").split()
    if len(tokens) > 32 or any(not _SSH_NAME.match(t) for t in tokens):
        raise ValueError("bad_" + label)
    return " ".join(tokens)


def sshd_stage(req: dict) -> dict:
    """Stage an sshd drop-in from plain data; refuse lines we cannot interpret."""
    out = {
        "text": "",
        "sha256": "",
        "settings": [],
        "kept": [],
        "unreadable": [],
        "refuse": False,
        "error": "",
    }
    vals: dict[str, str] = {}
    try:
        vals["PasswordAuthentication"] = _ssh_yes_no(req.get("password", True))
        vals["PubkeyAuthentication"] = _ssh_yes_no(req.get("pubkey", True))
        vals["PermitRootLogin"] = _ssh_root(req.get("root", False))
        vals["AllowTcpForwarding"] = _ssh_yes_no(req.get("tcpForwarding", True))
        vals["X11Forwarding"] = _ssh_yes_no(req.get("x11Forwarding", False))
        tries = req.get("maxAuthTries", 6)
        if isinstance(tries, bool):
            raise ValueError("bad_maxAuthTries")
        mat = int(tries)
        if mat < 1 or mat > 10:
            raise ValueError("bad_maxAuthTries")
        vals["MaxAuthTries"] = str(mat)
        users = _ssh_names(req.get("allowUsers", ""), "allow_users")
        groups = _ssh_names(req.get("allowGroups", ""), "allow_groups")
        if users:
            vals["AllowUsers"] = users
        if groups:
            vals["AllowGroups"] = groups
    except (ValueError, TypeError):
        out["refuse"], out["error"] = True, "bad_value"
        return out

    path = os.environ.get(
        "SHANI_SSHD_CONF", "/etc/ssh/sshd_config.d/50-shani-shell.conf"
    )
    parsed = sshd_parse(_text(path) or "")
    seen: set[str] = set()
    staged = ""
    for keyword, raw in parsed["lines"]:
        if keyword in vals and keyword not in seen:
            staged += f"{keyword} {vals[keyword]}\n"
            seen.add(keyword)
        else:
            staged += raw
    for keyword, value in vals.items():
        if keyword not in seen:
            staged += f"{keyword} {value}\n"
    # The public answer hides a secret on an unmanaged line. Such a line must
    # never be written back from that redacted copy, so staging refuses it.
    hidden = [_redact(raw) for raw in parsed["kept"] + parsed["unreadable"]]
    # Rebuild the visible text from the staged one, line by line.
    managed = set(vals)
    visible = []
    for line in staged.splitlines(keepends=True):
        key = line.split(None, 1)[0] if line.split(None, 1) else ""
        visible.append(_redact(line) if key not in managed else line)
    text = "".join(visible)
    out["text"] = text
    out["sha256"] = hashlib.sha256(text.encode("utf-8")).hexdigest()
    out["kept"] = [_redact(raw) for raw in parsed["kept"]]
    out["unreadable"] = [_redact(raw) for raw in parsed["unreadable"]]
    out["settings"] = [
        {"keyword": keyword, "value": value} for keyword, value in vals.items()
    ]
    out["refuse"] = (
        bool(parsed["unreadable"]) or hidden != parsed["kept"] + parsed["unreadable"]
    )
    if hidden != parsed["kept"] + parsed["unreadable"]:
        out["error"] = "secret_in_unmanaged_line"
    return out


def sshd() -> dict:
    """Key/value lines of the sign-in drop-in, with secret-looking values hidden."""
    path = os.environ.get(
        "SHANI_SSHD_CONF", "/etc/ssh/sshd_config.d/50-shani-shell.conf"
    )
    out = {"path": path, "settings": {}, "error": "", "kept": [], "unreadable": []}
    out["mode"], out["owner"] = _stat_info(path)
    text = _text(path)
    if text is None:
        return out
    parsed = sshd_parse(text)
    out["settings"] = parsed["settings"]
    out["kept"] = [_redact(raw) for raw in parsed["kept"]]
    out["unreadable"] = [_redact(raw) for raw in parsed["unreadable"]]
    return out


def lsm() -> dict:
    """Security modules the kernel names, and which of those we can name plainly."""
    out = {"active": [], "available": [], "error": ""}
    text = _text(os.environ.get("SHANI_LSM_FILE", "/sys/kernel/security/lsm"))
    if text is None or not text.strip():
        out["error"] = "security module list is not readable"
        return out
    out["active"] = [name.strip() for name in text.strip().split(",") if name.strip()]
    out["available"] = [name for name in KNOWN_LSM if name in out["active"]]
    return out


def sshkeys() -> dict:
    """Public key comments and fingerprints from ssh-keygen -lf; never the key data."""
    path = os.environ.get(
        "SHANI_AUTHORIZED_KEYS",
        os.path.join(os.path.expanduser("~"), ".ssh", "authorized_keys"),
    )
    out = {"path": path, "keys": [], "error": ""}
    if not os.path.exists(path):
        return out
    keygen = _cmd("SHANI_SYSTEM_SSH_KEYGEN", "ssh-keygen")
    if not keygen or not shutil.which(keygen[0]):
        out["error"] = "ssh-keygen is not available"
        return out
    r, err = _run(keygen, "-lf", path)
    if err:
        out["error"] = err
        return out
    if r.returncode != 0:
        out["error"] = _last_line(
            (r.stderr or r.stdout), "ssh-keygen could not read the file"
        )
        return out
    for line in r.stdout.splitlines():
        parts = line.split()
        fingerprint = next((p for p in parts if p.startswith(("SHA256:", "MD5:"))), "")
        if not fingerprint:
            continue
        kind = ""
        comment = parts[2:]
        if comment and comment[-1].startswith("("):
            kind = comment.pop().strip("()")
        out["keys"].append(
            {
                "type": kind,
                "comment": " ".join(comment),
                "fingerprint": fingerprint,
            }
        )
    return out


def totp() -> dict:
    """Sign-in code users and their settings, never the shared secrets."""
    pam = pam_scan()
    path = pam["usersfile"]
    out = {
        "users": [],
        "error": "",
        "pamWired": pam["pamWired"],
        "pamStacks": pam["pamStacks"],
        "usersfile": path,
        "readable": False,
        "mode": "",
        "owner": "",
        "unknown": False,
        "skipped": 0,
        "toolVersion": "",
    }
    out["mode"], out["owner"] = _stat_info(path)
    text = _text(path)
    if text is None:
        out["error"] = "sign-in code file is not readable"
        out["unknown"] = True
    else:
        out["readable"] = True
        for raw in text.splitlines():
            s = raw.strip()
            if not s:
                continue
            disabled = s.startswith("#")
            body = s.lstrip("#").strip()
            parts = body.split()
            if len(parts) < 2 or not re.match(r"^(HOTP|TOTP)", parts[0], re.I):
                out["skipped"] += 1
                continue  # a comment, not an entry
            kind = parts[0]
            digits = re.search(r"/(\d+)$", kind)
            period = re.search(r"T(\d+)", kind, re.I)
            out["users"].append(
                {
                    "user": parts[1],
                    "enabled": not disabled,
                    "digits": int(digits.group(1)) if digits else 6,
                    "period": int(period.group(1)) if period else 30,
                }
            )
    tool = _cmd("SHANI_OATHTOOL", "oathtool")
    if tool and shutil.which(tool[0]):
        r, err = _run(tool, "--version")
        if not err and r.returncode == 0:
            lines = r.stdout.strip().splitlines()
            out["toolVersion"] = lines[0][:200] if lines else ""
    return out


SUDOERS_TAGS = ("NOPASSWD", "PASSWD", "EXEC", "NOEXEC")
_SUDOERS_PRINCIPAL = re.compile(r"^[%A-Za-z0-9._-]{1,64}$")
_SUDOERS_RUNAS = re.compile(r"^[A-Za-z0-9._%:-]{0,64}$")
_SUDOERS_BAD = re.compile(r"[;|&$`\\\n\r]")


def sudoers_stage(req: dict) -> dict:
    """Stage one grant list, keeping the lines this bridge does not manage."""
    out = {
        "text": "",
        "sha256": "",
        "rows": [],
        "other": [],
        "unreadable": [],
        "refuse": False,
        "error": "",
    }
    given, other = req.get("rows") or [], req.get("other") or []
    if not isinstance(given, list) or not isinstance(other, list):
        out["refuse"], out["error"] = True, "bad_request"
        return out
    lines = []
    for item in given:
        if not isinstance(item, dict):
            out["refuse"], out["error"] = True, "bad_request"
            return out
        who, runas = (
            str(item.get("who") or "").strip(),
            str(item.get("runas") or "").strip(),
        )
        tags = item.get("tags") or []
        commands = item.get("commands") or []
        if isinstance(tags, str):
            tags = tags.replace(",", " ").split()
        if isinstance(commands, str):
            commands = [commands]
        if (
            not _SUDOERS_PRINCIPAL.match(who)
            or not _SUDOERS_RUNAS.match(runas)
            or not isinstance(tags, list)
            or not isinstance(commands, list)
            or not commands
        ):
            out["refuse"], out["error"] = True, "bad_grant"
            return out
        clean_tags = []
        for tag in tags:
            tag = str(tag).strip()
            if tag not in SUDOERS_TAGS:
                out["refuse"], out["error"] = True, "bad_tag"
                return out
            if tag not in clean_tags:
                clean_tags.append(tag)
        clean_tags.sort(key=SUDOERS_TAGS.index)
        clean_commands = []
        for command in commands:
            command = str(command).strip()
            head = command.split()[0] if command.split() else ""
            if (
                not command
                or _SUDOERS_BAD.search(command)
                or (head != "ALL" and not head.startswith("/"))
            ):
                out["refuse"], out["error"] = True, "bad_command"
                return out
            clean_commands.append(command)
        row = {
            "who": who,
            "runas": runas,
            "tags": clean_tags,
            "commands": clean_commands,
            "warning": "all_commands"
            if any(c.split()[0] == "ALL" for c in clean_commands)
            else "",
        }
        lines.append(
            f"{who} ALL"
            + (f"=({runas})" if runas else "")
            + (" " + ", ".join(clean_tags) + ":" if clean_tags else "")
            + " "
            + ", ".join(clean_commands)
        )
        out["rows"].append(row)
    kept = []
    for line in other:
        if not isinstance(line, str) or "\n" in line or "\r" in line:
            out["refuse"], out["error"] = True, "bad_other"
            return out
        kept.append(line)
    text = "\n".join([*kept, *lines]).rstrip("\n")
    text = text + "\n" if text else ""
    out["text"] = text
    out["sha256"] = hashlib.sha256(text.encode("utf-8")).hexdigest()
    out["other"] = kept
    return out


VERBS = {
    "directory": directory,
    "kerberos": kerberos,
    "smartcard": smartcard,
    "privileges": privileges,
    "sudoers": sudoers,
    "sshd": sshd,
    "lsm": lsm,
    "sshkeys": sshkeys,
    "totp": totp,
    "smartcard-stage": smartcard_stage,
    "sshd-stage": sshd_stage,
    "sudoers-stage": sudoers_stage,
}
STAGED = {"smartcard-stage", "sshd-stage", "sudoers-stage"}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if cmd not in VERBS or args:
        print(
            json.dumps({"error": "usage: system_access.py <" + "|".join(VERBS) + ">"})
        )
        return 2
    if cmd in STAGED:
        try:
            req = json.loads(sys.stdin.read(65536) or "{}")
            if not isinstance(req, dict):
                raise ValueError
        except ValueError:
            print(json.dumps({"refuse": True, "error": "bad_request"}))
            return 2
        result = VERBS[cmd](req)
        print(json.dumps(result))
        return 1 if result.get("refuse") or result.get("error") else 0
    result = VERBS[cmd]()
    print(json.dumps(result))
    return 1 if result.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
