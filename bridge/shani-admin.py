#!/usr/bin/env python3
"""shani-admin — the shell's administrator actions: accounts, automatic login,
the lid and the power button. Run through pkexec; one JSON object on stdin,
one on stdout ({"ok": true} or {"ok": false, "error": "..."}).

    shani-admin.py user-add        {"username", "fullname", "password", "admin": bool}
    shani-admin.py user-remove     {"username", "deleteHome": bool}
    shani-admin.py user-admin      {"username", "admin": bool}
    shani-admin.py user-password   {"username", "password"}
    shani-admin.py autologin       {"username"}            ("" turns it off)
    shani-admin.py power-keys      {"lid", "lidOnPower", "powerKey"}
    shani-admin.py battery-limit   {"percent"}             (100 = charge fully)

polkit (shani-desktop-niri's 50-shani-admin.rules) asks a wheel member for an
administrator's password for the user-* commands, and their own for the
others — the same tiers as ShaniOS's 99-shani.rules.

What it refuses, whoever asks: any account outside UID 1000–59999 (root and
system accounts), removing or demoting the account that asked (PKEXEC_UID), and
leaving the machine with no administrator. A new account gets its groups,
/etc/skel and container ranges from shani-user-setup.path, like every account.

Automatic login is greetd's `initial_session`: a copy of the desktop's greetd
config with it added, and a systemd drop-in that points greetd at the copy —
the packaged file is never edited, and turning it off deletes both. Lid and
power button are a logind drop-in, logind reloaded.
"""

from __future__ import annotations

import grp
import json
import os
import pwd
import re
import subprocess
import sys
from pathlib import Path

USERNAME = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
RESERVED = {"root", "greeter", "nobody", "admin", "daemon", "bin", "sys", "dbus"}
FIRST_UID, LAST_UID = 1000, 60000
ADMIN_GROUP = "wheel"

GREETD_CONFIG = Path("/etc/greetd/shani-niri.toml")
AUTOLOGIN_CONFIG = Path("/etc/greetd/shani-niri-autologin.toml")
AUTOLOGIN_DROPIN = Path("/etc/systemd/system/greetd.service.d/20-shani-autologin.conf")
LOGIND_DROPIN = Path("/etc/systemd/logind.conf.d/50-shani-shell.conf")
POWER_SUPPLY = Path("/sys/class/power_supply")
BATTERY_TMPFILES = Path("/etc/tmpfiles.d/50-shani-battery.conf")
LID_ACTIONS = {"suspend", "hibernate", "hybrid-sleep", "suspend-then-hibernate", "lock", "ignore", "poweroff"}
KEY_ACTIONS = {"poweroff", "suspend", "hibernate", "ignore", "lock", "reboot"}


class Refused(Exception):
    pass


def run(cmd: list[str], stdin: str | None = None) -> None:
    out = subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise Refused((out.stderr.strip().splitlines() or [f"{cmd[0]} failed"])[-1])


def person(name: str) -> pwd.struct_passwd:
    """A person's account (not root, not a system account), or Refused."""
    if not isinstance(name, str) or not USERNAME.match(name):
        raise Refused("not a user name")
    try:
        p = pwd.getpwnam(name)
    except KeyError:
        raise Refused(f"there is no account {name}") from None
    if not FIRST_UID <= p.pw_uid < LAST_UID:
        raise Refused(f"{name} is a system account")
    return p


def admins() -> list[str]:
    try:
        members = set(grp.getgrnam(ADMIN_GROUP).gr_mem)
    except KeyError:
        return []
    return sorted(n for n in members if n in {p.pw_name for p in pwd.getpwall() if FIRST_UID <= p.pw_uid < LAST_UID})


def caller() -> str:
    try:
        return pwd.getpwuid(int(os.environ.get("PKEXEC_UID", "-1"))).pw_name
    except (KeyError, ValueError):
        return ""


def password_ok(pw) -> str:
    if not isinstance(pw, str) or pw == "" or "\n" in pw:
        raise Refused("a password is needed")
    return pw


def user_add(req: dict) -> dict:
    name = req.get("username", "")
    if not isinstance(name, str) or not USERNAME.match(name) or name in RESERVED:
        raise Refused("the user name must start with a letter and use only a–z, 0–9, '-' and '_'")
    try:
        pwd.getpwnam(name)
        raise Refused(f"the name {name} is taken")
    except KeyError:
        pass
    full = req.get("fullname", "")
    if not isinstance(full, str) or any(c in full for c in ":,\n\r") or len(full) > 100:
        raise Refused("the name cannot contain ':' ',' or line breaks")
    pw = password_ok(req.get("password"))
    cmd = ["useradd", "-m", "-c", full, "-s", "/bin/bash"]
    if req.get("admin"):
        cmd += ["-G", ADMIN_GROUP]
    run(cmd + [name])
    try:
        run(["chpasswd"], stdin=f"{name}:{pw}\n")
    except Refused:
        run(["userdel", "-r", name])
        raise
    return {}


def user_remove(req: dict) -> dict:
    p = person(req.get("username", ""))
    if p.pw_name == caller():
        raise Refused("you cannot remove your own account while signed in to it")
    if admins() == [p.pw_name]:
        raise Refused("this is the only administrator")
    if autologin_user() == p.pw_name:
        set_autologin("")
    run(["userdel"] + (["-r"] if req.get("deleteHome") else []) + [p.pw_name])
    return {}


def user_admin(req: dict) -> dict:
    p = person(req.get("username", ""))
    if req.get("admin"):
        run(["gpasswd", "-a", p.pw_name, ADMIN_GROUP])
        return {}
    if p.pw_name == caller():
        raise Refused("you cannot take away your own administrator rights")
    if admins() == [p.pw_name]:
        raise Refused("this is the only administrator")
    run(["gpasswd", "-d", p.pw_name, ADMIN_GROUP])
    return {}


def user_password(req: dict) -> dict:
    p = person(req.get("username", ""))
    run(["chpasswd"], stdin=f"{p.pw_name}:{password_ok(req.get('password'))}\n")
    return {}


def autologin_user() -> str:
    try:
        m = re.search(r'^\[initial_session\][^\[]*?^user\s*=\s*"([^"]*)"', AUTOLOGIN_CONFIG.read_text(), re.M | re.S)
        return m.group(1) if m and AUTOLOGIN_DROPIN.exists() else ""
    except OSError:
        return ""


def set_autologin(name: str) -> None:
    if not name:
        AUTOLOGIN_DROPIN.unlink(missing_ok=True)
        AUTOLOGIN_CONFIG.unlink(missing_ok=True)
        run(["systemctl", "daemon-reload"])
        return
    base = GREETD_CONFIG.read_text()
    base = re.sub(r"(?ms)^\[initial_session\].*?(?=^\[|\Z)", "", base).rstrip() + "\n"
    AUTOLOGIN_CONFIG.write_text(base + f'\n# shani-shell: Settings > Users > Automatic login\n[initial_session]\ncommand = "niri-session"\nuser = "{name}"\n')
    AUTOLOGIN_CONFIG.chmod(0o644)
    AUTOLOGIN_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    AUTOLOGIN_DROPIN.write_text("# shani-shell: Settings > Users > Automatic login (delete to turn off)\n"
                                f"[Service]\nExecStart=\nExecStart=/usr/bin/greetd --config {AUTOLOGIN_CONFIG}\n")
    run(["systemctl", "daemon-reload"])


def autologin(req: dict) -> dict:
    name = req.get("username", "")
    if name:
        person(name)
    set_autologin(name)
    return {"autologin": name}


def power_keys(req: dict) -> dict:
    lid, lid_ac, key = req.get("lid", "suspend"), req.get("lidOnPower", "suspend"), req.get("powerKey", "poweroff")
    if lid not in LID_ACTIONS or lid_ac not in LID_ACTIONS or key not in KEY_ACTIONS:
        raise Refused("unknown action")
    LOGIND_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    LOGIND_DROPIN.write_text("# shani-shell: Settings > Power (delete for the defaults)\n[Login]\n"
                             f"HandleLidSwitch={lid}\nHandleLidSwitchExternalPower={lid_ac}\nHandlePowerKey={key}\n")
    LOGIND_DROPIN.chmod(0o644)
    # logind rereads its configuration on reload; a failure is not fatal — it applies at boot
    subprocess.run(["systemctl", "reload", "systemd-logind"], capture_output=True, timeout=20)
    return {}


def battery_limit(req: dict) -> dict:
    """Stop charging at a percentage (laptops whose firmware offers it): the
    kernel's charge_control_end_threshold, now and — through tmpfiles.d — at
    every boot. 100 removes the limit."""
    pct = req.get("percent")
    if not isinstance(pct, int) or not 50 <= pct <= 100:
        raise Refused("a limit between 50 and 100")
    files = sorted(POWER_SUPPLY.glob("BAT*/charge_control_end_threshold"))
    if not files:
        raise Refused("this computer's battery has no charge limit")
    for f in files:
        f.write_text(f"{pct}\n")
    if pct == 100:
        BATTERY_TMPFILES.unlink(missing_ok=True)
    else:
        BATTERY_TMPFILES.parent.mkdir(parents=True, exist_ok=True)
        BATTERY_TMPFILES.write_text("# shani-shell: Settings > Power > charge limit (delete to charge fully)\n"
                                    + "".join(f"w {f} - - - - {pct}\n" for f in files))
        BATTERY_TMPFILES.chmod(0o644)
    return {"batteries": len(files)}


COMMANDS = {"user-add": user_add, "user-remove": user_remove, "user-admin": user_admin,
            "user-password": user_password, "autologin": autologin, "power-keys": power_keys,
            "battery-limit": battery_limit}


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in COMMANDS:
        print(json.dumps({"ok": False, "error": "usage: shani-admin.py " + "|".join(COMMANDS)}))
        return 2
    try:
        req = json.loads(sys.stdin.read(65536) or "{}")
        if not isinstance(req, dict):
            raise ValueError
        out = {"ok": True, **COMMANDS[argv[1]](req)}
    except ValueError:
        out = {"ok": False, "error": "expected one JSON object on stdin"}
    except (Refused, OSError, subprocess.SubprocessError) as e:
        out = {"ok": False, "error": str(e)}
    print(json.dumps(out))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
