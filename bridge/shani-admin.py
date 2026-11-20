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
    shani-admin.py wakeup          {"path", "enabled": bool}  (a device of bridge/wakeup.py's list)
    shani-admin.py lighting        {"led", "color": "#rrggbb", "level": 0..100}  (bridge/lighting.py's)
    shani-admin.py power-limit     {"watts"}               (bridge/powerlimit.py's range)

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
RESERVED = {
    "root",
    "greeter",
    "nobody",
    "admin",
    "daemon",
    "bin",
    "sys",
    "dbus",
    "guest",
}
# the guest account (a classroom board, a shared computer): no password, its home
# wiped before and after every session by shani-desktop-niri's guest-reset - which
# wipes only the account named in this file, the one this tool made
GUEST = "guest"
GUEST_MARKER = Path("/etc/shani/guest")
FIRST_UID, LAST_UID = 1000, 60000
ADMIN_GROUP = "wheel"

GREETD_CONFIG = Path("/etc/greetd/shani-niri.toml")
AUTOLOGIN_CONFIG = Path("/etc/greetd/shani-niri-autologin.toml")
AUTOLOGIN_DROPIN = Path("/etc/systemd/system/greetd.service.d/20-shani-autologin.conf")
LOGIND_DROPIN = Path("/etc/systemd/logind.conf.d/50-shani-shell.conf")
POWER_SUPPLY = Path("/sys/class/power_supply")
BATTERY_TMPFILES = Path("/etc/tmpfiles.d/50-shani-battery.conf")
SYSFS_DEVICES = Path("/sys/devices")
WAKEUP_TMPFILES = Path("/etc/tmpfiles.d/50-shani-wakeup.conf")
LEDS = Path("/sys/class/leds")
LIGHTING_TMPFILES = Path("/etc/tmpfiles.d/50-shani-lighting.conf")
LED_NAME = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")
COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
SYSFS = Path("/sys")
POWER_LIMIT_TMPFILES = Path("/etc/tmpfiles.d/50-shani-power-limit.conf")
LID_ACTIONS = {
    "suspend",
    "hibernate",
    "hybrid-sleep",
    "suspend-then-hibernate",
    "lock",
    "ignore",
    "poweroff",
}
KEY_ACTIONS = {"poweroff", "suspend", "hibernate", "ignore", "lock", "reboot"}


def extra_groups() -> list:
    """The groups every person's account joins when they exist on this system."""
    import grp

    out = []
    for g in ("sambashare",):
        try:
            grp.getgrnam(g)
            out.append(g)
        except KeyError:
            pass
    return out


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
    return sorted(
        n
        for n in members
        if n in {p.pw_name for p in pwd.getpwall() if FIRST_UID <= p.pw_uid < LAST_UID}
    )


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
        raise Refused(
            "the user name must start with a letter and use only a–z, 0–9, '-' and '_'"
        )
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
    # sambashare (shani-settings makes it): sharing a folder works from the start
    groups = ([ADMIN_GROUP] if req.get("admin") else []) + extra_groups()
    if groups:
        cmd += ["-G", ",".join(groups)]
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
    if req.get("admin") and p.pw_name == GUEST and GUEST_MARKER.exists():
        raise Refused("the guest account is never an administrator")
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
        m = re.search(
            r'^\[initial_session\][^\[]*?^user\s*=\s*"([^"]*)"',
            AUTOLOGIN_CONFIG.read_text(),
            re.M | re.S,
        )
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
    AUTOLOGIN_CONFIG.write_text(
        base
        + f'\n# shani-shell: Settings > Users > Automatic login\n[initial_session]\ncommand = "niri-session"\nuser = "{name}"\n'
    )
    AUTOLOGIN_CONFIG.chmod(0o644)
    AUTOLOGIN_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    AUTOLOGIN_DROPIN.write_text(
        "# shani-shell: Settings > Users > Automatic login (delete to turn off)\n"
        f"[Service]\nExecStart=\nExecStart=/usr/bin/greetd --config {AUTOLOGIN_CONFIG}\n"
    )
    run(["systemctl", "daemon-reload"])


def autologin(req: dict) -> dict:
    name = req.get("username", "")
    if name:
        person(name)
    set_autologin(name)
    return {"autologin": name}


def power_keys(req: dict) -> dict:
    lid, lid_ac, key = (
        req.get("lid", "suspend"),
        req.get("lidOnPower", "suspend"),
        req.get("powerKey", "poweroff"),
    )
    if lid not in LID_ACTIONS or lid_ac not in LID_ACTIONS or key not in KEY_ACTIONS:
        raise Refused("unknown action")
    LOGIND_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    LOGIND_DROPIN.write_text(
        "# shani-shell: Settings > Power (delete for the defaults)\n[Login]\n"
        f"HandleLidSwitch={lid}\nHandleLidSwitchExternalPower={lid_ac}\nHandlePowerKey={key}\n"
    )
    LOGIND_DROPIN.chmod(0o644)
    # logind rereads its configuration on reload; a failure is not fatal — it applies at boot
    subprocess.run(
        ["systemctl", "reload", "systemd-logind"], capture_output=True, timeout=20
    )
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
        BATTERY_TMPFILES.write_text(
            "# shani-shell: Settings > Power > charge limit (delete to charge fully)\n"
            + "".join(f"w {f} - - - - {pct}\n" for f in files)
        )
        BATTERY_TMPFILES.chmod(0o644)
    return {"batteries": len(files)}


def wakeup(req: dict) -> dict:
    """Whether a device may wake the computer from sleep: its sysfs
    power/wakeup, now and - through tmpfiles.d - at every boot (the kernel
    resets it to the driver's default). Only a device directory under
    /sys/devices that has that switch; a USB device keeps its choice for the
    port it is plugged into (its sysfs path is the port's)."""
    path, on = req.get("path"), req.get("enabled")
    if not isinstance(path, str) or not isinstance(on, bool):
        raise Refused("a device path and enabled true or false")
    dev = Path(path).resolve()
    try:
        dev.relative_to(SYSFS_DEVICES.resolve())
    except ValueError:
        raise Refused("not a device") from None
    switch = dev / "power" / "wakeup"
    if not switch.is_file():
        raise Refused("this device cannot wake the computer")
    state = "enabled" if on else "disabled"
    switch.write_text(state + "\n")
    lines = {}
    if WAKEUP_TMPFILES.exists():
        for line in WAKEUP_TMPFILES.read_text().splitlines():
            f = line.split()
            if len(f) == 7 and f[0] == "w":
                lines[f[1]] = f[6]
    lines[str(switch)] = state
    WAKEUP_TMPFILES.parent.mkdir(parents=True, exist_ok=True)
    WAKEUP_TMPFILES.write_text(
        "# shani-shell: Settings > Power > what can wake this computer\n"
        + "".join(f"w {p} - - - - {s}\n" for p, s in sorted(lines.items()))
    )
    WAKEUP_TMPFILES.chmod(0o644)
    return {}


def lighting(req: dict) -> dict:
    """A coloured light's colour and level: the kernel's multicolour LED class
    (multi_intensity in multi_index's channel order, then brightness). A
    built-in light (a handheld's stick rings) keeps it at every boot through
    tmpfiles.d; a controller's light bar (an input<N>: light) is named anew
    each time it connects, so it is set for now only."""
    led, color, level = req.get("led"), req.get("color"), req.get("level")
    if not isinstance(led, str) or not LED_NAME.match(led) or ".." in led:
        raise Refused("not a light")
    if not isinstance(color, str) or not COLOR.match(color):
        raise Refused("a colour as #rrggbb")
    if not isinstance(level, int) or isinstance(level, bool) or not 0 <= level <= 100:
        raise Refused("a level between 0 and 100")
    d = LEDS / led
    try:
        index = (d / "multi_index").read_text().split()
        top = int((d / "max_brightness").read_text().strip() or 255) or 255
    except (OSError, ValueError):
        raise Refused("this light has no colour") from None
    if sorted(index) != ["blue", "green", "red"]:
        raise Refused("this light has no colour")
    rgb = {
        "red": int(color[1:3], 16),
        "green": int(color[3:5], 16),
        "blue": int(color[5:7], 16),
    }
    intensity = " ".join(str(round(rgb[c] * top / 255)) for c in index)
    brightness = str(round(level * top / 100))
    (d / "multi_intensity").write_text(intensity + "\n")
    (d / "brightness").write_text(brightness + "\n")
    if not led.startswith("input"):
        lines = {}
        if LIGHTING_TMPFILES.exists():
            for line in LIGHTING_TMPFILES.read_text().splitlines():
                f = line.split(maxsplit=6)
                if len(f) == 7 and f[0] == "w":
                    lines[f[1]] = f[6]
        lines[str(d / "multi_intensity")] = intensity
        lines[str(d / "brightness")] = brightness
        LIGHTING_TMPFILES.parent.mkdir(parents=True, exist_ok=True)
        # multi_intensity before brightness for the same light: tmpfiles applies in this order
        LIGHTING_TMPFILES.write_text(
            "# shani-shell: Settings > Controllers > lights\n"
            + "".join(
                f"w {p} - - - - {v}\n"
                for p, v in sorted(
                    lines.items(),
                    key=lambda kv: (
                        str(Path(kv[0]).parent),
                        kv[0].endswith("brightness"),
                    ),
                )
            )
        )
        LIGHTING_TMPFILES.chmod(0o644)
    return {}


def power_limit(req: dict) -> dict:
    """A handheld's chip power limit in watts, where the kernel offers one
    (bridge/powerlimit.py: ASUS firmware attributes, or the AMD graphics
    driver's power cap) - now and, through tmpfiles.d, at every boot. Within
    the range the firmware or driver itself reports."""
    import importlib.util

    try:
        spec = importlib.util.spec_from_file_location(
            "powerlimit", Path(__file__).with_name("powerlimit.py")
        )
        pl = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pl)
    except Exception as e:
        # a broken backend must be one JSON error, not a traceback on stderr
        raise Refused("the power-limit backend is not available") from e
    watts = req.get("watts")
    if not isinstance(watts, int) or isinstance(watts, bool):
        raise Refused("a whole number of watts")
    found, info = pl.find(SYSFS), pl.show(SYSFS)
    if not found or not info:
        raise Refused("this computer's power limit cannot be changed")
    if not info["min"] <= watts <= info["max"]:
        raise Refused(f"between {info['min']} and {info['max']} W")
    method, d = found
    if method == "asus":
        files = [
            d / a / "current_value"
            for a in ("ppt_pl1_spl", "ppt_pl2_sppt", "ppt_fppt")
            if (d / a / "current_value").exists()
        ]
        value = str(watts)
    else:
        files, value = [d / "power1_cap"], str(watts * 1_000_000)
    for f in files:
        f.write_text(value + "\n")
    POWER_LIMIT_TMPFILES.parent.mkdir(parents=True, exist_ok=True)
    POWER_LIMIT_TMPFILES.write_text(
        "# shani-shell: Settings > Power > power limit\n"
        + "".join(f"w {f} - - - - {value}\n" for f in files)
    )
    POWER_LIMIT_TMPFILES.chmod(0o644)
    return {"watts": watts}


def guest(req: dict) -> dict:
    # JSON gives a real bool, but callers also send the string "false": bool()
    # would turn that into True and create the guest account by mistake
    on = req.get("on") is True or str(req.get("on", "")).lower() in (
        "true",
        "1",
        "yes",
        "on",
    )
    if on:
        try:
            pwd.getpwnam(GUEST)
            made = GUEST_MARKER.exists() and GUEST_MARKER.read_text().strip() == GUEST
            if not made:
                raise Refused(
                    "an account named guest is someone's own; it is left as it is"
                )
        except KeyError:
            run(["useradd", "-m", "-c", "Guest", "-s", "/bin/bash", GUEST])
        # no password: the greeter signs in on Enter (pam_unix nullok); never an admin
        run(["passwd", "-d", GUEST])
        GUEST_MARKER.parent.mkdir(parents=True, exist_ok=True)
        GUEST_MARKER.write_text(GUEST + "\n")
        GUEST_MARKER.chmod(0o644)
        return {}
    if caller() == GUEST:
        raise Refused("the guest cannot turn the guest account off")
    if GUEST_MARKER.exists() and GUEST_MARKER.read_text().strip() == GUEST:
        if autologin_user() == GUEST:
            set_autologin("")
        try:
            pwd.getpwnam(GUEST)
            run(["userdel", "-r", GUEST])
        except KeyError:
            pass
    GUEST_MARKER.unlink(missing_ok=True)
    return {}


COMMANDS = {
    "guest": guest,
    "wakeup": wakeup,
    "lighting": lighting,
    "power-limit": power_limit,
    "user-add": user_add,
    "user-remove": user_remove,
    "user-admin": user_admin,
    "user-password": user_password,
    "autologin": autologin,
    "power-keys": power_keys,
    "battery-limit": battery_limit,
}


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in COMMANDS:
        print(
            json.dumps(
                {"ok": False, "error": "usage: shani-admin.py " + "|".join(COMMANDS)}
            )
        )
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
