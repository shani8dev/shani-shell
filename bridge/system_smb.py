#!/usr/bin/env python3
"""system_smb — Samba shares, accounts, ports and units as plain data.

    system_smb.py state                   (no stdin)
    system_smb.py stage                   (one JSON object on stdin)
    system_smb.py set                     (one JSON object on stdin)

Reads use a closed set of options: `testparm -s -d 0`, `pdbedit -L -v`,
`ss -tulpn` and `systemctl is-active <unit>`. The passdb is never quoted in
full: only flags, a well-formed SID, home and the password date are reported,
never a hash. Writes go to one drop-in through the administrator helper via
pkexec; content and digest are on stdin, the verb in argv.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys

PKEXEC = shlex.split(os.environ.get("SHANI_SYSTEM_PKEXEC", "pkexec"))
ADMIN_TOOL = os.environ.get("SHANI_ADMIN_TOOL", "/usr/lib/shani-shell/shani-admin.py")
TIMEOUT = 30
PRIV_TIMEOUT = 120

HEADER = "# Managed by this system"
RESERVED = {"global", "homes", "printers", "print$", "ipc$", "admin$", "c$", "d$"}
NAME_MAX = 32

_SECTION_RE = re.compile(r"^\[([^\]]+)\]\s*$")
_NAME_RE = re.compile(r"^[A-Za-z0-9_.%-]+$")
_PATH_RE = re.compile(r"^/[A-Za-z0-9._+@ /-]*$")
_SMB_ROW_RE = re.compile(r":(139|445)\b")
_PROC_RE = re.compile(r'users:\(\("([^"]*)"')
_PDB_RULE = "---------------"
_SID_RE = re.compile(r"^S-\d+-\d+-\d+(?:-\d+)+$")
_USERSHARE_PARAM_RE = re.compile(r"^(?P<key>[A-Za-z0-9 _-]+?)\s*=\s*(?P<value>.*)$")


# --- parsers ---------------------------------------------------------------


def parse_testparm(text):
    """(global params, shares) out of a `testparm -s -d 0` dump."""
    sections = []
    current = None
    for raw in (text or "").splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = _SECTION_RE.match(line)
        if match:
            current = {"name": match.group(1), "params": {}}
            sections.append(current)
            continue
        if not line.startswith("\t") or current is None:
            continue
        key, sep, value = line.lstrip("\t").partition(" = ")
        if sep:
            current["params"][key.strip()] = value.strip()
    globals_ = {}
    shares = []
    for section in sections:
        if section["name"] == "global":
            globals_ = section["params"]
        else:
            shares.append({"name": section["name"], "params": section["params"]})
    return globals_, shares


def parse_verdict(err):
    """(loaded, problems) out of testparm's stderr."""
    loaded = False
    problems = []
    for raw in (err or "").splitlines():
        line = raw.strip()
        if line == "Loaded services file OK.":
            loaded = True
        elif (
            line.startswith("Error loading services.")
            or line.startswith("Unknown parameter encountered")
            or line.startswith("Ignored ")
        ):
            problems.append(line)
    return loaded, problems


def parse_pdbedit(text):
    """Accounts out of `pdbedit -L -v`, with no hash or password field."""
    blocks = []
    current = None
    for raw in (text or "").splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.strip() == _PDB_RULE:
            current = {}
            blocks.append(current)
            continue
        key, sep, value = line.partition(":")
        if not sep:
            continue
        if current is None:
            current = {}
            blocks.append(current)
        current[key.strip()] = value.strip()
    out = []
    for fields in blocks:
        user = fields.get("Unix username", "")
        if not user:
            continue
        sid = fields.get("User SID", "")
        if not _SID_RE.match(sid):
            sid = ""
        out.append(
            {
                "user": user,
                "flags": fields.get("Account Flags", ""),
                "sid": sid,
                "home": fields.get("Home Directory", ""),
                "passwordDate": fields.get("Password last set", ""),
            }
        )
    return out


def parse_smb_sockets(text):
    """One entry per SMB port, from `ss -tulpn`."""
    found = {445: False, 139: False}
    process = {445: "", 139: ""}
    for raw in (text or "").splitlines():
        match = _SMB_ROW_RE.search(raw)
        if match is None:
            continue
        port = int(match.group(1))
        found[port] = True
        named = _PROC_RE.search(raw)
        if named:
            process[port] = named.group(1)
    return [
        {"port": port, "listening": found[port], "process": process[port]}
        for port in (445, 139)
    ]


def parse_usershare(text):
    """Share name and path out of one usershare file."""
    name = ""
    path = ""
    for raw in (text or "").splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = _SECTION_RE.match(line)
        if match:
            name = match.group(1)
            continue
        if not line.startswith("\t"):
            continue
        param = _USERSHARE_PARAM_RE.match(line.lstrip("\t"))
        if param and param.group("key").strip().lower() == "path":
            path = param.group("value").strip()
    return {"name": name, "path": path}


def _read(argv):
    try:
        proc = subprocess.run(argv, capture_output=True, timeout=TIMEOUT)
        return {
            "out": (proc.stdout or b"").decode("utf-8", "replace"),
            "err": (proc.stderr or b"").decode("utf-8", "replace"),
            "code": proc.returncode,
            "error": "",
        }
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"out": "", "err": "", "code": None, "error": str(exc)}


def _usershares(directory):
    out = []
    try:
        entries = sorted(os.listdir(directory))
    except OSError:
        return out
    for entry in entries:
        try:
            with open(
                os.path.join(directory, entry), encoding="utf-8", errors="replace"
            ) as fh:
                parsed = parse_usershare(fh.read())
        except OSError:
            continue
        if parsed["name"]:
            out.append(parsed)
    return out


def state():
    """Read Samba: validated config, passdb, ports, units and usershares."""
    testparm = os.environ.get("SHANI_TESTPARM", "testparm")
    pdbedit = os.environ.get("SHANI_PDBEDIT", "pdbedit")
    ss = os.environ.get("SHANI_SS", "ss")
    systemctl = os.environ.get("SHANI_SYSTEMCTL", "systemctl")
    usershare_dir = os.environ.get("SHANI_USERSHARE_DIR", "/var/lib/samba/usershares")
    config_path = os.environ.get("SHANI_SMB_CONF", "/etc/samba/smb.conf")

    tp = _read([testparm, "-s", "-d", "0"])
    loaded, problems = parse_verdict(tp["err"])
    available = not tp["error"]
    globals_, shares = parse_testparm(tp["out"]) if tp["out"].strip() else ({}, [])
    tp_error = "; ".join(problems)
    if not tp_error and tp["error"]:
        tp_error = tp["error"]
    testparm_state = {
        "available": available,
        "valid": loaded if available else None,
        "globals": globals_,
        "shares": shares,
        "error": tp_error,
    }

    pd = _read([pdbedit, "-L", "-v"])
    accounts = parse_pdbedit(pd["out"]) if pd["out"].strip() else []

    soc = _read([ss, "-tulpn"])
    ports = parse_smb_sockets(soc["out"])

    units = {}
    for key, service in (
        ("smb", "smb.service"),
        ("nmb", "nmb.service"),
        ("winbind", "winbind.service"),
    ):
        units[key] = _read([systemctl, "is-active", service])["out"].strip()

    errors = []
    for label, result in (("testparm", tp), ("pdbedit", pd), ("ss", soc)):
        if result["error"]:
            errors.append(f"{label}: {result['error']}")
    return {
        "testparm": testparm_state,
        "accounts": accounts,
        "ports": ports,
        "units": units,
        "usershares": _usershares(usershare_dir),
        "configPath": config_path,
        "error": "; ".join(errors),
    }


def valid_unix_user(name):
    """A portable Unix account name: lowercase start, then letters/digits/_.-."""
    if not isinstance(name, str) or not name or len(name) > 32:
        return False
    if not (name[0].isalpha() and name[0].islower()):
        return False
    return all(ch.isalnum() or ch in "_-." for ch in name)


def stage(req):
    """Validate the requested shares and build the drop-in text."""
    shares_in = req.get("shares") or []
    out = {"text": "", "sha256": "", "shares": [], "refuse": False, "error": ""}

    def refuse(code):
        out["refuse"] = True
        out["error"] = code
        return out

    if not isinstance(shares_in, list):
        return refuse("bad_request")
    validated = []
    for share in shares_in:
        if not isinstance(share, dict):
            return refuse("bad_request")
        if share.get("guestOk") is True:
            return refuse("guest_denied")
        name = share.get("name", "")
        if (
            not isinstance(name, str)
            or len(name) > NAME_MAX
            or not _NAME_RE.match(name)
        ):
            return refuse("bad_name")
        if name.lower() in RESERVED:
            return refuse("reserved_name")
        path = share.get("path", "")
        if (
            not isinstance(path, str)
            or not path.startswith("/")
            or ".." in path
            or "\n" in path
            or "\r" in path
            or not _PATH_RE.match(path)
        ):
            return refuse("bad_path")
        users = list(share.get("users") or [])
        if any(not valid_unix_user(user) for user in users):
            return refuse("bad_user")
        validated.append(
            {
                "name": name,
                "path": path,
                "users": users,
                "guestOk": False,
                "readOnly": bool(share.get("readOnly", True)),
            }
        )

    lines = [HEADER]
    for share in validated:
        lines.extend(
            [
                f"[{share['name']}]",
                f"   path = {share['path']}",
                f"   read only = {'yes' if share['readOnly'] else 'no'}",
                "   guest ok = no",
                f"   valid users = {' '.join(share['users'])}",
                "",
            ]
        )
    text = "\n".join(lines) + "\n"
    out.update(
        text=text,
        sha256=hashlib.sha256(text.encode("utf-8")).hexdigest(),
        shares=validated,
    )
    return out


def shani_admin_write(verb, payload):
    """The only call to a ShaniOS-only tool here: the helper through pkexec.

    File content and digest travel together on stdin; argv carries only the
    helper path and the verb.
    """
    if not PKEXEC:
        return {"ok": False, "error": "pkexec is not available"}
    cmd = PKEXEC + [ADMIN_TOOL, verb]
    try:
        proc = subprocess.run(
            cmd,
            input=json.dumps(payload).encode("utf-8"),
            capture_output=True,
            timeout=PRIV_TIMEOUT,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)}
    if proc.returncode != 0:
        lines = (proc.stderr or b"").decode("utf-8", "replace").strip().splitlines()
        return {"ok": False, "error": lines[-1] if lines else f"exit {proc.returncode}"}
    data = {}
    try:
        data = json.loads((proc.stdout or b"").decode("utf-8", "replace"))
    except ValueError:
        pass
    if isinstance(data, dict):
        if data.get("ok") is False:
            return {"ok": False, "error": str(data.get("error") or "helper refused")}
        return {
            "ok": True,
            "error": "",
            "mode": str(data.get("mode", "") or ""),
            "owner": str(data.get("owner", "") or ""),
        }
    return {"ok": True, "error": "", "mode": "", "owner": ""}


def set_shares(req):
    """Stage, write through the helper, then read back."""
    staged = stage(req)
    if staged["refuse"] or staged["error"]:
        return {
            "ok": False,
            "error": staged["error"] or "stage_refused",
            "mode": "",
            "owner": "",
            "state": state(),
        }
    result = shani_admin_write(
        "smb-share-set", {"text": staged["text"], "sha256": staged["sha256"]}
    )
    if not result["ok"]:
        return {
            "ok": False,
            "error": result["error"],
            "mode": "",
            "owner": "",
            "state": state(),
        }
    return {
        "ok": True,
        "error": "",
        "mode": result["mode"],
        "owner": result["owner"],
        "state": state(),
    }


VERBS = {"state": lambda req: state(), "stage": stage, "set": set_shares}


def main(argv):
    if len(argv) != 2 or argv[1] not in VERBS:
        print(json.dumps({"error": "usage: system_smb.py " + "|".join(VERBS)}))
        return 2
    req = {}
    if argv[1] in ("stage", "set"):
        try:
            req = json.loads(sys.stdin.read(65536) or "{}")
            if not isinstance(req, dict):
                raise ValueError
        except ValueError:
            print(json.dumps({"error": "expected one JSON object on stdin"}))
            return 2
    print(json.dumps(VERBS[argv[1]](req)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
