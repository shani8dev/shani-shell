#!/usr/bin/env python3
"""system_access — sign-in and access facts this computer actually uses, read only.

    system_access.py directory    {"sssd", "slapd", "nsswitch", "error"}
    system_access.py kerberos     {"realm", "domainRealm", "cache", "loaded", "error"}
    system_access.py smartcard    {"mapper", "provider", "mappings", "error"}
    system_access.py privileges   {"rules": [{"file", "actions": [...]}], "error"}
    system_access.py sudoers      {"path", "text", "error"}
    system_access.py sshd         {"path", "settings", "error"}
    system_access.py lsm          {"active", "available", "error"}
    system_access.py sshkeys      {"path", "keys": [{"type", "comment", "fingerprint"}], "error"}
    system_access.py totp         {"users": [{"user", "enabled", "digits", "period"}], "error"}

One JSON object per verb. Nothing is written and no root is needed: a file that
cannot be read is reported as such, never filled in. No password, key blob or
secret is returned. Service states are systemctl's own words ("active",
"inactive", "unknown"); nsswitch is one line per switch; domainRealm is the
first "domain = realm" line; cache is the credential cache file's path when one
exists; available LSM names are the known names named by the kernel.

Test overrides: SHANI_SYSTEMCTL, SHANI_NSSWITCH, SHANI_KRB5_CONF,
SHANI_KRB5_CCACHE, SHANI_SYSTEM_PAM_DIR, SHANI_PKCS11_CONF, SHANI_PKCS11_MAP,
SHANI_POLKIT_DIR, SHANI_SUDOERS, SHANI_SSHD_CONF, SHANI_LSM_FILE,
SHANI_SYSTEM_SSH_KEYGEN, SHANI_AUTHORIZED_KEYS, SHANI_OATH_FILE.
"""

from __future__ import annotations

import glob
import json
import os
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


def _state(unit: str) -> str:
    r, err = _run(_cmd("SHANI_SYSTEMCTL", "systemctl"), "is-active", unit)
    if err or r is None:
        return "unknown"
    value = r.stdout.strip().splitlines()
    value = value[-1].strip() if value else ""
    return value if value in STATES else "unknown"


def directory() -> dict:
    """Directory services and the name-service switches that use them."""
    out = {"sssd": "unknown", "slapd": "unknown", "nsswitch": "", "error": ""}
    switches: dict[str, str] = {}
    systemctl = _cmd("SHANI_SYSTEMCTL", "systemctl")
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


def smartcard() -> dict:
    """The configured mapper, provider and identity -> login mappings. No card data."""
    out = {"mapper": "", "provider": "", "mappings": [], "error": ""}
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
    mapping_text = _text(
        os.environ.get("SHANI_PKCS11_MAP", "/etc/pam_pkcs11/subject_mapping")
    )
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


def sudoers() -> dict:
    """The one drop-in the Security page also reads; absent means empty."""
    path = os.environ.get("SHANI_SUDOERS", "/etc/sudoers.d/50-shani-shell")
    return {"path": path, "text": _text(path) or "", "error": ""}


def sshd() -> dict:
    """Key/value lines of the sign-in drop-in, with secret-looking values hidden."""
    path = os.environ.get(
        "SHANI_SSHD_CONF", "/etc/ssh/sshd_config.d/50-shani-shell.conf"
    )
    settings: dict[str, str] = {}
    text = _text(path)
    if text is None:
        return {"path": path, "settings": settings, "error": ""}
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = re.match(r"^([A-Za-z][A-Za-z0-9]*)\s+(.+)$", s)
        if not m:
            continue
        value = m.group(2).strip()
        settings[m.group(1)] = (
            "[hidden]" if SECRET_VALUE.search(value) or len(value) > 200 else value
        )
    return {"path": path, "settings": settings, "error": ""}


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
    path = os.environ.get("SHANI_OATH_FILE", "/etc/users.oath")
    out = {"users": [], "error": ""}
    text = _text(path)
    if text is None:
        out["error"] = "sign-in code file is not readable"
        return out
    for raw in text.splitlines():
        s = raw.strip()
        if not s:
            continue
        disabled = s.startswith("#")
        body = s.lstrip("#").strip()
        parts = body.split()
        if len(parts) < 2 or not re.match(r"^(HOTP|TOTP)", parts[0], re.I):
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
}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if cmd not in VERBS or args:
        print(
            json.dumps({"error": "usage: system_access.py <" + "|".join(VERBS) + ">"})
        )
        return 2
    result = VERBS[cmd]()
    print(json.dumps(result))
    return 1 if result.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
