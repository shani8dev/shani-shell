#!/usr/bin/env python3
"""first-account — create the machine's first account, and set it up.

ShaniOS installs no account: the first one is made at first boot (and again
after a factory reset, which wipes /etc/passwd). On the niri desktop that is
the setup wizard's job (shani-setup, run by greetd as the `greeter` user); this
is the one privileged step it needs, run through pkexec. A polkit rule
(shani-desktop-niri) lets the `greeter` user run this program and nothing else.

It refuses outright once any regular account exists, so it can make the first
account and never another: whoever reaches the login screen of a set-up
machine gains nothing from it.

Input, one JSON object on stdin:
  {"username": "asha", "fullname": "Asha Patil", "password": "…",
   "locale": "mr_IN.UTF-8", "keymap": ["us", "in+marathi"],
   "keymapSwitch": "grp:win_space_toggle", "timezone": "Asia/Kolkata",
   "hostname": "asha-laptop"}
Only username and password are required. Output, one JSON object:
  {"ok": true, "warnings": [...]}   or   {"ok": false, "error": "..."}

The account joins `wheel` (an administrator, as the first account must be);
shani-user-setup.path sees the new passwd entry and adds the rest — groups,
/etc/skel, container ranges — as it does for every account.
"""

from __future__ import annotations

import json
import pwd
import re
import subprocess
import sys

USERNAME = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
HOSTNAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,62}$")
XKB = re.compile(r"^[a-z0-9_]+(\+[A-Za-z0-9_-]+)?$")
RESERVED = {"root", "greeter", "nobody", "admin", "daemon", "bin", "sys", "sync", "games", "man",
            "lp", "mail", "news", "uucp", "proxy", "www-data", "backup", "list", "irc", "dbus"}
FIRST_UID, LAST_UID = 1000, 60000


def regular_accounts() -> list[str]:
    """Accounts a person signs in to: UID 1000–59999 with a login shell."""
    return [p.pw_name for p in pwd.getpwall()
            if FIRST_UID <= p.pw_uid < LAST_UID and not p.pw_shell.endswith(("nologin", "false"))]


def listed(cmd: list[str]) -> set[str]:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        return set(out.stdout.split()) if out.returncode == 0 else set()
    except (OSError, subprocess.SubprocessError):
        return set()


def validate(req: dict) -> str:
    """The reason the request cannot be applied, or "" when it can."""
    user = req.get("username", "")
    if not isinstance(user, str) or not USERNAME.match(user) or user in RESERVED:
        return "the user name must start with a letter and use only a–z, 0–9, '-' and '_'"
    name = req.get("fullname", "")
    if not isinstance(name, str) or any(c in name for c in ":,\n\r") or len(name) > 100:
        return "the name cannot contain ':' ',' or line breaks"
    pw = req.get("password", "")
    if not isinstance(pw, str) or pw == "" or "\n" in pw:
        return "a password is needed"
    host = req.get("hostname", "")
    if host and (not isinstance(host, str) or not HOSTNAME.match(host)):
        return "the computer name may use letters, digits and '-' only"
    keymap = req.get("keymap", [])
    if not isinstance(keymap, list) or not all(isinstance(k, str) and XKB.match(k) for k in keymap):
        return "unknown keyboard layout"
    switch = req.get("keymapSwitch", "")
    if switch and not re.match(r"^grp:[a-z_]+$", str(switch)):
        return "unknown layout switch"
    for key in ("locale", "timezone"):
        if not isinstance(req.get(key, ""), str):
            return f"bad {key}"
    return ""


def run(cmd: list[str], stdin: str | None = None) -> str:
    """Run a step; its error text, or "" on success."""
    try:
        out = subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as e:
        return f"{cmd[0]}: {e}"
    return "" if out.returncode == 0 else (out.stderr.strip().splitlines() or [f"{cmd[0]} failed"])[-1]


def apply(req: dict) -> dict:
    if regular_accounts():
        return {"ok": False, "error": "this computer already has an account"}
    why = validate(req)
    if why:
        return {"ok": False, "error": why}
    user = req["username"]
    try:
        pwd.getpwnam(user)
        return {"ok": False, "error": f"the name {user} is taken by the system"}
    except KeyError:
        pass

    err = run(["useradd", "-m", "-c", req.get("fullname", ""), "-G", "wheel", "-s", "/bin/bash", user])
    if err:
        return {"ok": False, "error": err}
    err = run(["chpasswd"], stdin=f"{user}:{req['password']}\n")
    if err:
        run(["userdel", "-r", user])          # no account without a password
        return {"ok": False, "error": err}

    # the rest is the machine's settings: each one on its own, a failure noted
    warnings = []
    locale = req.get("locale", "")
    if locale:
        if locale in listed(["localectl", "list-locales"]):
            warnings.append(run(["localectl", "set-locale", f"LANG={locale}"]))
        else:
            warnings.append(f"language {locale} is not installed")
    keymap = req.get("keymap", [])
    if keymap:
        layouts = ",".join(k.split("+")[0] for k in keymap)
        variants = ",".join((k.split("+") + [""])[1] for k in keymap)
        warnings.append(run(["localectl", "set-x11-keymap", layouts, "", variants,
                             req.get("keymapSwitch", "") if len(keymap) > 1 else ""]))
    tz = req.get("timezone", "")
    if tz:
        if tz in listed(["timedatectl", "list-timezones"]):
            warnings.append(run(["timedatectl", "set-timezone", tz]))
        else:
            warnings.append(f"unknown time zone {tz}")
    if req.get("hostname"):
        warnings.append(run(["hostnamectl", "hostname", req["hostname"]]))
    return {"ok": True, "warnings": [w for w in warnings if w]}


def main() -> int:
    try:
        req = json.loads(sys.stdin.read(65536))
        if not isinstance(req, dict):
            raise ValueError
    except ValueError:
        print(json.dumps({"ok": False, "error": "expected one JSON object on stdin"}))
        return 2
    result = apply(req)
    print(json.dumps(result))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
