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
     shani-admin.py remote-access-set  {"text", "sha256"} or the boolean fields
     shani-admin.py sudoers-rows-get   {}                  (parsed grants)
     shani-admin.py sudoers-set        {"rows", "other"} or {"text", "sha256"}
     shani-admin.py hosts-set          {"text", "sha256"?}
     shani-admin.py nfs-exports-set    {"text", "sha256"}
     shani-admin.py smb-share-set      {"text", "sha256"}
     shani-admin.py pam-config-set     {"target": "fido2"|"yubico", "text", "sha256"}
     shani-admin.py pkcs11-mapping-set {"text", "sha256"}

Staged text travels on stdin with its SHA-256, never in argv. The file is
pre-checked on a temp file in its own directory, installed with os.replace,
then checked live; a failed live check restores the old bytes.

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
import hashlib
import ipaddress
import json
import os
import pwd
import re
import shutil
import subprocess
import sys
import tempfile
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
# feature groups a person can be switched into (not wheel: the desktop owns that)
MANAGED_GROUPS = {
    "sambashare",
    "libvirt",
    "kvm",
    "uucp",
    "video",
    "input",
    "realtime",
    "wireshark",
    "docker",
}

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


def _tool_error(result, default: str) -> str:
    """The tool's own last error line; no UI words."""
    lines = (
        (getattr(result, "stderr", "") or getattr(result, "stdout", ""))
        .strip()
        .splitlines()
    )
    return lines[-1][:200] if lines else default


def _verify_digest(req: dict, text: str, required: bool = True) -> None:
    sha = req.get("sha256")
    if sha is None:
        if required:
            raise Refused("sha256 required for text")
        return
    if hashlib.sha256(text.encode("utf-8")).hexdigest() != str(sha).lower():
        raise Refused("SHA-256 does not match the content")


def _install_atomic(path: Path, content: str, mode: int, precheck=None) -> bytes | None:
    """Pre-check on a sibling temp file, then replace. Return the old bytes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    old = path.read_bytes() if path.exists() else None
    fd, tmp = tempfile.mkstemp(
        prefix="." + path.name + ".", suffix=".tmp", dir=str(path.parent)
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(tmp, mode)
        if precheck is not None:
            precheck(tmp)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return old


def _restore(path: Path, old: bytes | None, mode: int) -> None:
    if old is None:
        path.unlink(missing_ok=True)
    else:
        path.write_bytes(old)
        os.chmod(path, mode)


def _file_meta(path: Path) -> dict:
    """Read back mode and owner as plain data."""
    try:
        st = path.stat()
    except OSError:
        return {"mode": "", "owner": ""}
    try:
        user = pwd.getpwuid(st.st_uid).pw_name
    except KeyError:
        user = str(st.st_uid)
    try:
        group = grp.getgrgid(st.st_gid).gr_name
    except KeyError:
        group = str(st.st_gid)
    return {"mode": format(st.st_mode & 0o777, "03o"), "owner": f"{user}:{group}"}


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


def user_group(req: dict) -> dict:
    p = person(req.get("username", ""))
    group = req.get("group", "")
    if group not in MANAGED_GROUPS:
        raise Refused("not a group this tool manages")
    try:
        grp.getgrnam(group)
    except KeyError:
        raise Refused(f"{group} does not exist on this system")
    if req.get("member"):
        run(["gpasswd", "-a", p.pw_name, group])
    else:
        run(["gpasswd", "-d", p.pw_name, group])
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


SSHD_DROPIN = Path(
    os.environ.get("SHANI_SSHD_DROPIN", "/etc/ssh/sshd_config.d/50-shani-shell.conf")
)
SSHD_TOOL = os.environ.get("SHANI_SSHD", "sshd")
SYSTEMCTL_TOOL = os.environ.get("SHANI_SYSTEMCTL", "systemctl")
VISUDO_TOOL = os.environ.get("SHANI_VISUDO", "visudo")
SSH_MANAGED_KEYS = (
    "PasswordAuthentication",
    "PubkeyAuthentication",
    "PermitRootLogin",
    "AllowTcpForwarding",
    "X11Forwarding",
    "MaxAuthTries",
    "AllowUsers",
    "AllowGroups",
)
PWQUALITY = Path("/etc/security/pwquality.conf")
PW_KEYS = {
    "minlen",
    "dcredit",
    "ucredit",
    "lcredit",
    "ocredit",
    "difok",
    "minclass",
    "maxrepeat",
    "maxclassrepeat",
    "enforce_for_root",
}
FAILLOCK_CONF = Path("/etc/security/faillock.conf")
FAILLOCK_KEYS = {
    "deny": (0, 999),
    "unlock_time": (0, 604800),
    "fail_interval": (0, 604800),
    "even_deny_root": None,
}
RESOLVED_DROPIN = Path("/etc/systemd/resolved.conf.d/50-shani-shell.conf")
RESOLVED_KEYS = {
    "DNS": "servers",
    "FallbackDNS": "servers",
    "DNSOverTLS": {"no", "yes", "opportunistic"},
    "DNSSEC": {"no", "yes", "allow-downgrade"},
}
LOGIN_DEFS = Path("/etc/login.defs")
LOGIN_DEFS_KEYS = {
    "PASS_MAX_DAYS": (-1, 99999),
    "PASS_MIN_DAYS": (-1, 99999),
    "PASS_WARN_AGE": (-1, 99999),
    "LOGIN_RETRIES": (1, 20),
    "LOGIN_TIMEOUT": (1, 600),
}


def remote_access_get(_req: dict) -> dict:
    def on(name):
        try:
            r = subprocess.run(
                [SYSTEMCTL_TOOL, "is-active", name],
                capture_output=True,
                text=True,
                timeout=5,
            )
            return r.stdout.strip() == "active"
        except Exception:
            return False

    cfg = {
        "PasswordAuthentication": "yes",
        "PubkeyAuthentication": "yes",
        "PermitRootLogin": "prohibit-password",
        "AllowUsers": "",
        "AllowGroups": "",
        "AllowTcpForwarding": "yes",
        "X11Forwarding": "no",
        "MaxAuthTries": "6",
    }
    try:
        for line in SSHD_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2 and parts[0] in cfg:
                cfg[parts[0]] = parts[1]
    except OSError:
        pass
    return {
        "enabled": on("sshd"),
        "password": cfg["PasswordAuthentication"].lower() == "yes",
        "pubkey": cfg["PubkeyAuthentication"].lower() == "yes",
        "root": cfg["PermitRootLogin"].lower() == "yes",
        "allowUsers": cfg["AllowUsers"],
        "allowGroups": cfg["AllowGroups"],
        "tcpForwarding": cfg["AllowTcpForwarding"].lower() == "yes",
        "x11Forwarding": cfg["X11Forwarding"].lower() == "yes",
        "maxAuthTries": cfg["MaxAuthTries"],
    }


_SSH_NAME = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def _ssh_names(raw: str, label: str) -> str:
    raw = str(raw or "").strip()
    if not raw:
        return ""
    toks = raw.split()
    if len(toks) > 32:
        raise Refused(f"too many {label}")
    for t in toks:
        if not _SSH_NAME.match(t):
            raise Refused(f"bad {label}: {t!r}")
    return " ".join(toks)


def _remote_access_content(req: dict) -> str:
    """Build the drop-in, replacing managed lines in place, keeping the rest."""
    vals = {
        "PasswordAuthentication": "yes" if req.get("password", True) else "no",
        "PubkeyAuthentication": "yes" if req.get("pubkey", True) else "no",
        "PermitRootLogin": "yes" if req.get("root", False) else "prohibit-password",
        "AllowTcpForwarding": "yes" if req.get("tcpForwarding", True) else "no",
        "X11Forwarding": "yes" if req.get("x11Forwarding", False) else "no",
    }
    try:
        mat = int(req.get("maxAuthTries", 6))
    except Exception:
        raise Refused("MaxAuthTries must be an integer")
    if mat < 1 or mat > 10:
        raise Refused("MaxAuthTries out of range 1-10")
    vals["MaxAuthTries"] = str(mat)
    allow_users = _ssh_names(req.get("allowUsers", ""), "AllowUsers")
    allow_groups = _ssh_names(req.get("allowGroups", ""), "AllowGroups")
    if allow_users:
        vals["AllowUsers"] = allow_users
    if allow_groups:
        vals["AllowGroups"] = allow_groups
    try:
        old = SSHD_DROPIN.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        old = [
            "# Managed by shani-shell. sshd reads this drop-in after the main config;",
            "# a bad line here can be removed by deleting this file.",
        ]
    seen = set()
    out = []
    for line in old:
        s = line.strip()
        parts = s.split(None, 1)
        if s and not s.startswith("#") and parts[0] in SSH_MANAGED_KEYS:
            key = parts[0]
            if key in vals:
                out.append(f"{key} {vals[key]}")
                seen.add(key)
            continue
        out.append(line)
    for key in SSH_MANAGED_KEYS:
        if key in vals and key not in seen:
            out.append(f"{key} {vals[key]}")
    return "\n".join(out).rstrip("\n") + "\n"


def remote_access_set(req: dict) -> dict:
    if "text" in req:
        text = req["text"]
        if not isinstance(text, str):
            raise Refused("text must be a string")
        _verify_digest(req, text)
        content = text
    else:
        content = _remote_access_content(req)
    available = bool(shutil.which(SSHD_TOOL))

    def precheck(tmp: str) -> None:
        if not available:
            return
        r = subprocess.run(
            [SSHD_TOOL, "-t", "-f", tmp], capture_output=True, text=True, timeout=10
        )
        if r.returncode != 0:
            raise Refused(_tool_error(r, "sshd rejected the config"))

    old = _install_atomic(SSHD_DROPIN, content, 0o644, precheck)
    if available:
        r = subprocess.run(
            [SSHD_TOOL, "-t"], capture_output=True, text=True, timeout=10
        )
        if r.returncode != 0:
            _restore(SSHD_DROPIN, old, 0o644)
            raise Refused(_tool_error(r, "sshd rejected the config"))
    # reload sshd if active; enable/disable handled separately
    run([SYSTEMCTL_TOOL, "reload-or-restart", "sshd"])
    out = remote_access_get(req)
    out.update(_file_meta(SSHD_DROPIN))
    return out


def pwquality_get(_req: dict) -> dict:
    settings = {}
    try:
        for line in PWQUALITY.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("[") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in PW_KEYS:
                settings[k] = v
    except OSError:
        pass
    return {"settings": settings, "path": str(PWQUALITY)}


def pwquality_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        if k not in PW_KEYS:
            raise Refused(f"unknown key: {k}")
        if k == "enforce_for_root":
            clean[k] = "1" if str(v).lower() in ("1", "true", "yes", "on") else "0"
        else:
            try:
                iv = int(v)
            except Exception:
                raise Refused(f"{k} must be an integer")
            if iv < -128 or iv > 128:
                raise Refused(f"{k} out of range")
            clean[k] = str(iv)
    try:
        lines = PWQUALITY.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        lines = []
    seen = set()
    out = []
    for line in lines:
        s = line.strip()
        if s and not s.startswith("#") and not s.startswith("[") and "=" in s:
            k = s.split("=", 1)[0].strip()
            if k in clean:
                out.append(f"{k} = {clean[k]}")
                seen.add(k)
                continue
        out.append(line)
    for k, v in clean.items():
        if k not in seen:
            out.append(f"{k} = {v}")
    content = "\n".join(out).rstrip("\n") + "\n"
    PWQUALITY.write_text(content, encoding="utf-8")
    os.chmod(PWQUALITY, 0o644)
    return pwquality_get(req)


def faillock_get(_req: dict) -> dict:
    settings = {}
    try:
        for line in FAILLOCK_CONF.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in FAILLOCK_KEYS:
                settings[k] = v
    except OSError:
        pass
    return {"settings": settings, "path": str(FAILLOCK_CONF)}


def faillock_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        if k not in FAILLOCK_KEYS:
            raise Refused(f"unknown key: {k}")
        spec = FAILLOCK_KEYS[k]
        if spec is None:
            clean[k] = "1" if str(v).lower() in ("1", "true", "yes", "on") else "0"
        else:
            try:
                iv = int(v)
            except Exception:
                raise Refused(f"{k} must be an integer")
            lo, hi = spec
            if iv < lo or iv > hi:
                raise Refused(f"{k} out of range {lo}-{hi}")
            clean[k] = str(iv)
    try:
        lines = FAILLOCK_CONF.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        lines = []
    seen = set()
    out = []
    for line in lines:
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            k = s.split("=", 1)[0].strip()
            if k in clean:
                out.append(f"{k} = {clean[k]}")
                seen.add(k)
                continue
        out.append(line)
    for k, v in clean.items():
        if k not in seen:
            out.append(f"{k} = {v}")
    content = "\n".join(out).rstrip("\n") + "\n"
    FAILLOCK_CONF.write_text(content, encoding="utf-8")
    os.chmod(FAILLOCK_CONF, 0o644)
    return faillock_get(req)


HOSTS_FILE = Path(os.environ.get("SHANI_HOSTS_FILE", "/etc/hosts"))
SYSTEM_HOST_IPS = {
    ipaddress.ip_address("127.0.0.1"),
    ipaddress.ip_address("127.0.1.1"),
    ipaddress.ip_address("::1"),
}


def _hosts_path() -> Path:
    return Path(str(HOSTS_FILE))


def _hosts_ips(text: str) -> set:
    ips = set()
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        try:
            ips.add(ipaddress.ip_address(s.split()[0]))
        except ValueError:
            continue
    return ips


def hosts_get(_req: dict) -> dict:
    try:
        text = _hosts_path().read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        return {"text": "", "error": str(e)}
    return {"text": text}


def hosts_set(req: dict) -> dict:
    text = req.get("text", "")
    if not isinstance(text, str) or len(text) > 65536:
        raise Refused("hosts text too large")
    _verify_digest(req, text, required=False)
    lines = text.splitlines()
    for i, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split()
        try:
            ipaddress.ip_address(parts[0])
        except Exception:
            raise Refused(f"line {i}: expected IP address")
        if len(parts) < 2:
            raise Refused(f"line {i}: expected at least one hostname")
    try:
        original = _hosts_path().read_text(encoding="utf-8", errors="replace")
    except OSError:
        original = ""
    missing = (_hosts_ips(original) & SYSTEM_HOST_IPS) - _hosts_ips(text)
    if missing:
        raise Refused(
            "system address must stay in hosts: "
            + ", ".join(sorted(str(ip) for ip in missing))
        )
    path = _hosts_path()
    path.write_text("\n".join(lines).rstrip("\n") + "\n", encoding="utf-8")
    os.chmod(path, 0o644)
    return hosts_get(req)


SUDOERS_DROPIN = Path("/etc/sudoers.d/50-shani-shell")
SUDOERS_TAGS = ("NOPASSWD", "PASSWD", "EXEC", "NOEXEC")
SUDOERS_PRINCIPAL = re.compile(r"^[%A-Za-z0-9._-]{1,64}$")
SUDOERS_RUNAS = re.compile(r"^[A-Za-z0-9._%:-]{0,64}$")
SUDOERS_BAD_COMMAND = re.compile(r"[;|&$`\\\n\r]")
SUDOERS_RULE = re.compile(
    r"^(?P<who>%?[A-Za-z0-9._-]+)\s+(?P<host>[A-Za-z0-9._-]+)"
    r"(?:=\((?P<runas>[^)]*)\))?\s*(?P<rest>.*)$"
)


def _sudoers_row(row: dict) -> dict:
    if not isinstance(row, dict):
        raise Refused("row must be an object")
    who = str(row.get("who") or "").strip()
    if not SUDOERS_PRINCIPAL.match(who):
        raise Refused("bad principal")
    runas = str(row.get("runas") or "").strip()
    if not SUDOERS_RUNAS.match(runas):
        raise Refused("bad runas")
    tags = row.get("tags") or []
    if isinstance(tags, str):
        tags = tags.replace(",", " ").split()
    if not isinstance(tags, list):
        raise Refused("bad tags")
    clean_tags = []
    for tag in tags:
        tag = str(tag).strip()
        if tag not in SUDOERS_TAGS:
            raise Refused("bad tag")
        if tag not in clean_tags:
            clean_tags.append(tag)
    clean_tags.sort(key=SUDOERS_TAGS.index)
    commands = row.get("commands") or []
    if isinstance(commands, str):
        commands = [commands]
    if not isinstance(commands, list) or not commands:
        raise Refused("bad commands")
    clean_commands = []
    for command in commands:
        command = str(command).strip()
        if not command or SUDOERS_BAD_COMMAND.search(command):
            raise Refused("bad command")
        head = command.split()[0]
        if head != "ALL" and not head.startswith("/"):
            raise Refused("bad command")
        clean_commands.append(command)
    out = {"who": who, "runas": runas, "tags": clean_tags, "commands": clean_commands}
    if any(c.split()[0] == "ALL" for c in clean_commands):
        out["warning"] = "all_commands"
    return out


def _sudoers_line(row: dict) -> str:
    line = f"{row['who']} ALL"
    if row["runas"]:
        line += f"=({row['runas']})"
    if row["tags"]:
        line += " " + ", ".join(row["tags"]) + ":"
    return line + " " + ", ".join(row["commands"])


def sudoers_rows_get(_req: dict) -> dict:
    """Parse the drop-in into stable row codes; anything odd goes to unreadable."""
    path = str(SUDOERS_DROPIN)
    try:
        text = SUDOERS_DROPIN.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        return {
            "rows": [],
            "other": [],
            "unreadable": [],
            "path": path,
            "text": "",
            "error": "unreadable",
        }
    rows, other, unreadable = [], [], []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            other.append(line)
            continue
        m = SUDOERS_RULE.match(s)
        if not m:
            unreadable.append(line)
            continue
        rest = m.group("rest").strip()
        if ":" in rest:
            tagpart, commandpart = rest.split(":", 1)
            tags = [t.strip() for t in tagpart.split(",") if t.strip()]
        else:
            tags, commandpart = [], rest
        commands = [c.strip() for c in commandpart.split(",") if c.strip()]
        try:
            row = _sudoers_row(
                {
                    "who": m.group("who"),
                    "runas": m.group("runas") or "",
                    "tags": tags,
                    "commands": commands,
                }
            )
        except Refused:
            unreadable.append(line)
            continue
        rows.append(row)
    return {
        "rows": rows,
        "other": other,
        "unreadable": unreadable,
        "path": path,
        "text": text,
        "error": "",
    }


def sudoers_get(_req: dict) -> dict:
    try:
        text = SUDOERS_DROPIN.read_text(encoding="utf-8", errors="replace")
    except OSError:
        text = ""
    return {"text": text, "path": str(SUDOERS_DROPIN)}


def sudoers_set(req: dict) -> dict:
    by_rows = "rows" in req
    if by_rows:
        given = req["rows"]
        if not isinstance(given, list):
            raise Refused("rows must be a list")
        rows = [_sudoers_row(item) for item in given]
        other = req.get("other") or []
        if not isinstance(other, list):
            raise Refused("other must be a list")
        other_lines = []
        for line in other:
            line = str(line)
            if "\n" in line or "\r" in line:
                raise Refused("bad other line")
            other_lines.append(line)
        content = "\n".join([*other_lines, *(_sudoers_line(r) for r in rows)]).rstrip(
            "\n"
        )
        content = content + "\n" if content else ""
    else:
        text = req.get("text", "")
        if not isinstance(text, str) or len(text) > 16384:
            raise Refused("sudoers text too large")
        _verify_digest(req, text, required=False)
        content = (
            "\n".join(text.splitlines()).rstrip("\n") + "\n" if text.strip() else ""
        )
        other_lines = []

    def precheck(tmp: str) -> None:
        r = subprocess.run(
            [VISUDO_TOOL, "-c", "-f", tmp], capture_output=True, text=True, timeout=10
        )
        if r.returncode != 0:
            raise Refused(_tool_error(r, "visudo rejected the drop-in"))

    if content:
        old = _install_atomic(SUDOERS_DROPIN, content, 0o440, precheck)
    else:
        old = SUDOERS_DROPIN.read_bytes() if SUDOERS_DROPIN.exists() else None
        SUDOERS_DROPIN.unlink(missing_ok=True)
    r = subprocess.run([VISUDO_TOOL, "-c"], capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        # rollback
        _restore(SUDOERS_DROPIN, old, 0o440)
        raise Refused("sudoers check failed after write; rolled back")
    out = sudoers_get(req)
    out.update(_file_meta(SUDOERS_DROPIN))
    if by_rows:
        out["rows"] = rows
        out["other"] = other_lines
    return out


EXPORTS_FILE = Path(
    os.environ.get("SHANI_EXPORTS_FILE", "/etc/exports.d/50-shani-shell.exports")
)
SMB_DROPIN = Path(
    os.environ.get("SHANI_SMB_DROPIN", "/etc/samba/smb.conf.d/50-shani-shell.conf")
)
PAM_U2F_CONF = Path(os.environ.get("SHANI_PAM_U2F_CONF", "/etc/security/pam_u2f.conf"))
PAM_YUBICO_CONF = Path(
    os.environ.get("SHANI_PAM_YUBICO_CONF", "/etc/security/pam_yubico.conf")
)
PKCS11_MAP_FILE = Path(
    os.environ.get("SHANI_PKCS11_MAP_FILE", "/etc/pam_pkcs11/subject_mapping")
)
EXPORTFS_TOOL = os.environ.get("SHANI_EXPORTFS", "exportfs")
TESTPARM_TOOL = os.environ.get("SHANI_TESTPARM", "testparm")


def _readback_check(path: Path, text: str):
    def check() -> None:
        if path.read_bytes() != text.encode("utf-8"):
            raise Refused("post-check failed")

    return check


def _staged_install(req: dict, path: Path, mode: int, postcheck=None) -> dict:
    """Digest-check staged text, install it, check it, roll it back on failure."""
    text = req.get("text")
    if not isinstance(text, str):
        raise Refused("text required")
    _verify_digest(req, text)
    old = _install_atomic(path, text, mode)
    check = postcheck(path, text) if postcheck is not None else None
    if check is not None:
        try:
            check()
        except BaseException:
            _restore(path, old, mode)
            raise
    out = {"text": text, "ok": True}
    out.update(_file_meta(path))
    return out


def _exportfs_check(path: Path, text: str):
    def check() -> None:
        run([EXPORTFS_TOOL, "-ra"])

    return check


def _testparm_check(path: Path, text: str):
    def check() -> None:
        run([TESTPARM_TOOL, "-s", str(path)])

    return check


def nfs_exports_set(req: dict) -> dict:
    return _staged_install(req, EXPORTS_FILE, 0o644, _exportfs_check)


def smb_share_set(req: dict) -> dict:
    return _staged_install(req, SMB_DROPIN, 0o644, _testparm_check)


def pam_config_set(req: dict) -> dict:
    target = req.get("target")
    if target == "fido2":
        path = PAM_U2F_CONF
    elif target == "yubico":
        path = PAM_YUBICO_CONF
    else:
        raise Refused("unknown PAM target")
    return _staged_install(req, path, 0o644, _readback_check)


def pkcs11_mapping_set(req: dict) -> dict:
    return _staged_install(req, PKCS11_MAP_FILE, 0o644, _readback_check)


def apparmor_set(req: dict) -> dict:
    profile = req.get("profile", "")
    mode = req.get("mode", "")
    if not isinstance(profile, str) or not re.match(
        r"^[A-Za-z0-9_./:-]{1,256}$", profile
    ):
        raise Refused("bad profile name")
    if mode not in ("enforce", "complain"):
        raise Refused("mode must be enforce or complain")
    cmd = "aa-enforce" if mode == "enforce" else "aa-complain"
    exe = shutil.which(cmd) or f"/usr/sbin/{cmd}"
    if not os.path.exists(exe):
        raise Refused(f"{cmd} is not installed")
    r = subprocess.run([exe, profile], capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        raise Refused(
            (r.stderr or r.stdout).strip().splitlines()[-1][:200] or f"{cmd} failed"
        )
    return {"profile": profile, "mode": mode}


MODPROBE_DROPIN = Path("/etc/modprobe.d/50-shani-shell.conf")
MODULES_LOAD_DROPIN = Path("/etc/modules-load.d/50-shani-shell.conf")
MOD_NAME = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


def modprobe_blacklist_get(_req: dict) -> dict:
    mods = []
    try:
        for line in MODPROBE_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if s.startswith("blacklist "):
                name = s.split(None, 1)[1].strip()
                if MOD_NAME.match(name):
                    mods.append(name)
    except OSError:
        pass
    return {"modules": mods, "path": str(MODPROBE_DROPIN)}


def modprobe_blacklist_set(req: dict) -> dict:
    mods = req.get("modules") or []
    if not isinstance(mods, list):
        raise Refused("modules must be a list")
    clean = []
    for m in mods:
        if not isinstance(m, str) or not MOD_NAME.match(m):
            raise Refused(f"bad module name: {m!r}")
        if m not in clean:
            clean.append(m)
    if clean:
        content = "# Managed by shani-shell\n" + "".join(
            f"blacklist {m}\ninstall {m} /bin/false\n" for m in clean
        )
        MODPROBE_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        MODPROBE_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(MODPROBE_DROPIN, 0o644)
    else:
        try:
            MODPROBE_DROPIN.unlink()
        except OSError:
            pass
    return modprobe_blacklist_get(req)


def modules_load_get(_req: dict) -> dict:
    mods = []
    try:
        for line in MODULES_LOAD_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if s and not s.startswith("#") and MOD_NAME.match(s):
                mods.append(s)
    except OSError:
        pass
    return {"modules": mods, "path": str(MODULES_LOAD_DROPIN)}


def modules_load_set(req: dict) -> dict:
    mods = req.get("modules") or []
    if not isinstance(mods, list):
        raise Refused("modules must be a list")
    clean = []
    for m in mods:
        if not isinstance(m, str) or not MOD_NAME.match(m):
            raise Refused(f"bad module name: {m!r}")
        if m not in clean:
            clean.append(m)
    if clean:
        content = "# Managed by shani-shell\n" + "".join(f"{m}\n" for m in clean)
        MODULES_LOAD_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        MODULES_LOAD_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(MODULES_LOAD_DROPIN, 0o644)
    else:
        try:
            MODULES_LOAD_DROPIN.unlink()
        except OSError:
            pass
    return modules_load_get(req)


JOURNALD_DROPIN = Path("/etc/systemd/journald.conf.d/50-shani-shell.conf")
JOURNALD_KEYS = {
    "Storage": {"persistent", "volatile", "auto", "none"},
    "SystemMaxUse": "size",
    "SystemKeepFree": "size",
    "RuntimeMaxUse": "size",
    "MaxRetentionSec": "size",
    "ForwardToSyslog": {"yes", "no"},
    "Compress": {"yes", "no"},
    "Seal": {"yes", "no"},
    "RateLimitIntervalSec": "rl_interval",
    "RateLimitBurst": "rl_burst",
}
SIZE_RE = re.compile(r"^\d+[KMGTP]?$")
RL_INTERVAL_RE = re.compile(r"^\d+s?$")


def journald_get(_req: dict) -> dict:
    settings = {}
    try:
        for line in JOURNALD_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("[") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in JOURNALD_KEYS:
                settings[k] = v
    except OSError:
        pass
    return {"settings": settings, "path": str(JOURNALD_DROPIN)}


def journald_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        if k not in JOURNALD_KEYS:
            raise Refused(f"unknown key: {k}")
        v = str(v).strip()
        spec = JOURNALD_KEYS[k]
        if isinstance(spec, set):
            if v not in spec:
                raise Refused(f"bad value for {k}")
        elif spec == "size":
            if not SIZE_RE.match(v):
                raise Refused(f"bad value for {k}")
        elif spec == "rl_interval":
            if not RL_INTERVAL_RE.match(v):
                raise Refused(f"bad value for {k}")
        elif spec == "rl_burst":
            if not re.match(r"^\d+$", v):
                raise Refused(f"bad value for {k}")
            n = int(v)
            if n < 0 or n > 100000:
                raise Refused(f"bad value for {k}")
        else:
            raise Refused(f"bad value for {k}")
        clean[k] = v
    if clean:
        content = "# Managed by shani-shell\n[Journal]\n" + "".join(
            f"{k}={v}\n" for k, v in clean.items()
        )
        JOURNALD_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        JOURNALD_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(JOURNALD_DROPIN, 0o644)
    else:
        try:
            JOURNALD_DROPIN.unlink()
        except OSError:
            pass
    subprocess.run(
        ["systemctl", "restart", "systemd-journald"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    return journald_get(req)


def journald_vacuum(req: dict) -> dict:
    mode = req.get("mode")
    value = str(req.get("value", "")).strip()
    if mode not in ("size", "time"):
        raise Refused("mode must be size or time")
    if mode == "size" and not SIZE_RE.match(value):
        raise Refused("bad size")
    if mode == "time" and not re.match(r"^\d+[smhdwMy]?$", value):
        raise Refused("bad time")
    flag = "--vacuum-size=" + value if mode == "size" else "--vacuum-time=" + value
    r = subprocess.run(["journalctl", flag], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise Refused(
            (r.stderr or r.stdout).strip().splitlines()[-1][:200] or "vacuum failed"
        )
    return {"ok": True, "output": (r.stdout or "").strip()[-400:]}


SYSCTL_DROPIN = Path("/etc/sysctl.d/50-shani-shell.conf")
SYSCTL_KEYS = {
    "vm.swappiness": (0, 200),
    "fs.inotify.max_user_watches": (8192, 1048576),
    "fs.inotify.max_user_instances": (128, 8192),
    "kernel.sysrq": (0, 511),
}


def sysctl_get(_req: dict) -> dict:
    settings = {}
    try:
        for line in SYSCTL_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in SYSCTL_KEYS:
                settings[k] = v
    except OSError:
        pass
    # also report live values
    live = {}
    for k in SYSCTL_KEYS:
        try:
            live[k] = (
                Path("/proc/sys/" + k.replace(".", "/"))
                .read_text(encoding="utf-8")
                .strip()
            )
        except OSError:
            pass
    return {"settings": settings, "live": live, "path": str(SYSCTL_DROPIN)}


def sysctl_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        if k not in SYSCTL_KEYS:
            raise Refused(f"unknown key: {k}")
        try:
            iv = int(v)
        except Exception:
            raise Refused(f"{k} must be integer")
        lo, hi = SYSCTL_KEYS[k]
        if iv < lo or iv > hi:
            raise Refused(f"{k} out of range {lo}-{hi}")
        clean[k] = str(iv)
    if clean:
        content = "# Managed by shani-shell\n" + "".join(
            f"{k} = {v}\n" for k, v in clean.items()
        )
        SYSCTL_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        SYSCTL_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(SYSCTL_DROPIN, 0o644)
        subprocess.run(
            ["sysctl", "--system"], capture_output=True, text=True, timeout=30
        )
    else:
        try:
            SYSCTL_DROPIN.unlink()
        except OSError:
            pass
    return sysctl_get(req)


TIMESYNCD_DROPIN = Path("/etc/systemd/timesyncd.conf.d/50-shani-shell.conf")
NTP_TOKEN = re.compile(r"^[A-Za-z0-9.:_-]{1,253}$")


def timesyncd_get(_req: dict) -> dict:
    vals = {"NTP": "", "FallbackNTP": ""}
    try:
        for line in TIMESYNCD_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("[") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in vals:
                vals[k] = v
    except OSError:
        pass
    return {"settings": vals, "path": str(TIMESYNCD_DROPIN)}


def timesyncd_set(req: dict) -> dict:
    settings = req.get("settings") or {}
    if not isinstance(settings, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k in ("NTP", "FallbackNTP"):
        raw = str(settings.get(k, "")).strip()
        if not raw:
            continue
        toks = raw.split()
        if len(toks) > 8:
            raise Refused(f"too many {k} servers")
        for t in toks:
            if not NTP_TOKEN.match(t):
                raise Refused(f"bad {k} server: {t!r}")
        clean[k] = " ".join(toks)
    if clean:
        content = "# Managed by shani-shell\n[Time]\n" + "".join(
            f"{k}={v}\n" for k, v in clean.items()
        )
        TIMESYNCD_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        TIMESYNCD_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(TIMESYNCD_DROPIN, 0o644)
    else:
        try:
            TIMESYNCD_DROPIN.unlink()
        except OSError:
            pass
    subprocess.run(
        ["systemctl", "restart", "systemd-timesyncd"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    return timesyncd_get(req)


def _resolved_server_token(tok: str) -> bool:
    if NTP_TOKEN.match(tok):
        return True
    try:
        ipaddress.ip_address(tok)
        return True
    except Exception:
        return False


def resolved_get(_req: dict) -> dict:
    settings = {k: "" for k in RESOLVED_KEYS}
    try:
        for line in RESOLVED_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("[") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in RESOLVED_KEYS:
                settings[k] = v
    except OSError:
        pass
    return {"settings": settings, "path": str(RESOLVED_DROPIN)}


def resolved_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        if k not in RESOLVED_KEYS:
            raise Refused(f"unknown key: {k}")
        spec = RESOLVED_KEYS[k]
        raw = str(v).strip()
        if spec == "servers":
            if not raw:
                continue
            toks = raw.split()
            if len(toks) > 8:
                raise Refused(f"too many {k} servers")
            for t in toks:
                if not _resolved_server_token(t):
                    raise Refused(f"bad {k} server: {t!r}")
            clean[k] = " ".join(toks)
        else:
            if raw not in spec:
                raise Refused(f"bad value for {k}")
            clean[k] = raw
    if clean:
        content = "# Managed by shani-shell\n[Resolve]\n" + "".join(
            f"{k}={v}\n" for k, v in clean.items()
        )
        RESOLVED_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        RESOLVED_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(RESOLVED_DROPIN, 0o644)
    else:
        try:
            RESOLVED_DROPIN.unlink()
        except OSError:
            pass
    subprocess.run(
        ["systemctl", "restart", "systemd-resolved"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    return resolved_get(req)


def login_defs_get(_req: dict) -> dict:
    settings = {}
    try:
        for line in LOGIN_DEFS.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            parts = s.split()
            if len(parts) >= 2 and parts[0] in LOGIN_DEFS_KEYS:
                settings[parts[0]] = parts[1]
    except OSError:
        pass
    return {"settings": settings, "path": str(LOGIN_DEFS)}


def login_defs_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        if k not in LOGIN_DEFS_KEYS:
            raise Refused(f"unknown key: {k}")
        try:
            iv = int(v)
        except Exception:
            raise Refused(f"{k} must be an integer")
        lo, hi = LOGIN_DEFS_KEYS[k]
        if iv < lo or iv > hi:
            raise Refused(f"{k} out of range {lo}-{hi}")
        clean[k] = str(iv)
    try:
        lines = LOGIN_DEFS.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as e:
        raise Refused(f"cannot read login.defs: {e}")
    seen = set()
    out = []
    for line in lines:
        s = line.strip()
        if s and not s.startswith("#"):
            parts = s.split()
            if parts and parts[0] in clean:
                out.append(f"{parts[0]}\t{clean[parts[0]]}")
                seen.add(parts[0])
                continue
        out.append(line)
    for k, v in clean.items():
        if k not in seen:
            out.append(f"{k}\t{v}")
    LOGIN_DEFS.write_text("\n".join(out).rstrip("\n") + "\n", encoding="utf-8")
    os.chmod(LOGIN_DEFS, 0o644)
    return login_defs_get(req)


def _unit_active(name: str) -> bool:
    try:
        r = subprocess.run(
            ["systemctl", "is-active", name], capture_output=True, text=True, timeout=5
        )
        return r.stdout.strip() == "active"
    except Exception:
        return False


def _unit_enabled(name: str) -> bool:
    try:
        r = subprocess.run(
            ["systemctl", "is-enabled", name], capture_output=True, text=True, timeout=5
        )
        return r.stdout.strip() in ("enabled", "static")
    except Exception:
        return False


def fstrim_get(_req: dict) -> dict:
    return {
        "enabled": _unit_enabled("fstrim.timer"),
        "active": _unit_active("fstrim.timer"),
    }


def fstrim_set(req: dict) -> dict:
    on = bool(req.get("enabled"))
    r = subprocess.run(
        ["systemctl", "enable" if on else "disable", "--now", "fstrim.timer"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    if r.returncode != 0:
        raise Refused(
            (r.stderr or r.stdout).strip().splitlines()[-1][:200]
            or "fstrim.timer change failed"
        )
    return fstrim_get(req)


def cups_browsed_get(_req: dict) -> dict:
    return {
        "enabled": _unit_enabled("cups-browsed.service"),
        "active": _unit_active("cups-browsed.service"),
    }


def cups_browsed_set(req: dict) -> dict:
    on = bool(req.get("enabled"))
    r = subprocess.run(
        ["systemctl", "enable" if on else "disable", "--now", "cups-browsed.service"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    if r.returncode != 0:
        raise Refused(
            (r.stderr or r.stdout).strip().splitlines()[-1][:200]
            or "cups-browsed change failed"
        )
    return cups_browsed_get(req)


def bluetooth_get(_req: dict) -> dict:
    return {
        "enabled": _unit_enabled("bluetooth.service"),
        "active": _unit_active("bluetooth.service"),
    }


def bluetooth_set(req: dict) -> dict:
    on = bool(req.get("enabled"))
    r = subprocess.run(
        ["systemctl", "enable" if on else "disable", "--now", "bluetooth.service"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    if r.returncode != 0:
        raise Refused(
            (r.stderr or r.stdout).strip().splitlines()[-1][:200]
            or "bluetooth.service change failed"
        )
    return bluetooth_get(req)


AUDIT_RULES_FILE = Path("/etc/audit/rules.d/50-shani-shell.rules")
AUDIT_PROFILE_NAMES = ("off", "minimal", "baseline")
AUDIT_PROFILE_MARKER = "# shani-shell-profile: "


def _audit_profile_dirs() -> list[Path]:
    here = Path(__file__).resolve().parent
    return [
        here / "../data/audit-profiles",
        Path("/usr/share/shani-shell/audit-profiles"),
    ]


def _audit_profile_path(name: str) -> Path:
    for d in _audit_profile_dirs():
        p = (d / f"{name}.rules").resolve()
        # only files inside the expected data dir
        try:
            p.relative_to(d.resolve())
        except Exception:
            continue
        if p.is_file():
            return p
    raise Refused(f"audit profile not found: {name}")


def _audit_profile_current() -> str:
    try:
        text = AUDIT_RULES_FILE.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return "off"
    for line in text.splitlines()[:5]:
        if line.startswith(AUDIT_PROFILE_MARKER):
            name = line[len(AUDIT_PROFILE_MARKER) :].strip()
            return name if name in AUDIT_PROFILE_NAMES else "unknown"
    return "unknown"


def _audit_reload(name: str) -> None:
    augenrules = shutil.which("augenrules")
    if augenrules:
        r = subprocess.run(
            [augenrules, "--load"], capture_output=True, text=True, timeout=30
        )
        if r.returncode != 0:
            raise Refused(
                (r.stderr or r.stdout).strip().splitlines()[-1][:200]
                or "augenrules --load failed"
            )
        return
    auditctl = shutil.which("auditctl")
    if auditctl:
        if name == "off":
            r = subprocess.run(
                [auditctl, "-D"], capture_output=True, text=True, timeout=30
            )
        else:
            r = subprocess.run(
                [auditctl, "-R", str(AUDIT_RULES_FILE)],
                capture_output=True,
                text=True,
                timeout=30,
            )
        if r.returncode != 0:
            raise Refused(
                (r.stderr or r.stdout).strip().splitlines()[-1][:200]
                or "auditctl failed"
            )
        return
    raise Refused("neither augenrules nor auditctl is available")


def auditd_get(_req: dict) -> dict:
    return {
        "enabled": _unit_enabled("auditd.service"),
        "active": _unit_active("auditd.service"),
    }


def auditd_set(req: dict) -> dict:
    on = bool(req.get("enabled"))
    r = subprocess.run(
        ["systemctl", "enable" if on else "disable", "--now", "auditd.service"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    if r.returncode != 0:
        raise Refused(
            (r.stderr or r.stdout).strip().splitlines()[-1][:200]
            or "auditd change failed"
        )
    return auditd_get(req)


def audit_profile_list(_req: dict) -> dict:
    return {"profiles": list(AUDIT_PROFILE_NAMES)}


def audit_profile_get(_req: dict) -> dict:
    return {"profile": _audit_profile_current(), "path": str(AUDIT_RULES_FILE)}


def audit_profile_set(req: dict) -> dict:
    name = req.get("profile", "")
    if not isinstance(name, str) or name not in AUDIT_PROFILE_NAMES:
        raise Refused("unknown audit profile")
    if name == "off":
        try:
            AUDIT_RULES_FILE.unlink()
        except FileNotFoundError:
            pass
        except OSError as e:
            raise Refused(f"could not remove audit rules: {e}")
        _audit_reload(name)
        return audit_profile_get(req)
    src = _audit_profile_path(name)
    content = src.read_text(encoding="utf-8", errors="replace")
    if not content.endswith("\n"):
        content += "\n"
    try:
        AUDIT_RULES_FILE.parent.mkdir(parents=True, exist_ok=True)
        AUDIT_RULES_FILE.write_text(content, encoding="utf-8")
        os.chmod(AUDIT_RULES_FILE, 0o640)
    except OSError as e:
        raise Refused(f"could not write audit rules: {e}")
    _audit_reload(name)
    return audit_profile_get(req)


LOGIND_DROPIN = Path("/etc/systemd/logind.conf.d/50-shani-shell.conf")
LOGIND_KEYS = {
    "HandleLidSwitch": {
        "ignore",
        "poweroff",
        "reboot",
        "halt",
        "kexec",
        "suspend",
        "hibernate",
        "hybrid-sleep",
        "suspend-then-hibernate",
        "lock",
    },
    "HandleLidSwitchExternalPower": {
        "ignore",
        "poweroff",
        "reboot",
        "halt",
        "kexec",
        "suspend",
        "hibernate",
        "hybrid-sleep",
        "suspend-then-hibernate",
        "lock",
    },
    "HandleLidSwitchDocked": {
        "ignore",
        "poweroff",
        "reboot",
        "halt",
        "kexec",
        "suspend",
        "hibernate",
        "hybrid-sleep",
        "suspend-then-hibernate",
        "lock",
    },
    "IdleAction": {
        "ignore",
        "poweroff",
        "reboot",
        "halt",
        "kexec",
        "suspend",
        "hibernate",
        "hybrid-sleep",
        "suspend-then-hibernate",
        "lock",
    },
}
LOGIND_INT_KEYS = {"IdleActionSec": (0, 86400)}


def logind_get(_req: dict) -> dict:
    settings = {}
    try:
        for line in LOGIND_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("[") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in LOGIND_KEYS or k in LOGIND_INT_KEYS:
                settings[k] = v
    except OSError:
        pass
    return {"settings": settings, "path": str(LOGIND_DROPIN)}


def logind_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        if k in LOGIND_KEYS:
            v = str(v).strip()
            if v not in LOGIND_KEYS[k]:
                raise Refused(f"bad value for {k}")
            clean[k] = v
        elif k in LOGIND_INT_KEYS:
            try:
                iv = int(v)
            except Exception:
                raise Refused(f"{k} must be integer")
            lo, hi = LOGIND_INT_KEYS[k]
            if iv < lo or iv > hi:
                raise Refused(f"{k} out of range")
            clean[k] = str(iv)
        else:
            raise Refused(f"unknown key: {k}")
    if clean:
        content = "# Managed by shani-shell\n[Login]\n" + "".join(
            f"{k}={v}\n" for k, v in clean.items()
        )
        LOGIND_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        LOGIND_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(LOGIND_DROPIN, 0o644)
    else:
        try:
            LOGIND_DROPIN.unlink()
        except OSError:
            pass
    subprocess.run(
        ["systemctl", "restart", "systemd-logind"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    return logind_get(req)


COREDUMP_DROPIN = Path("/etc/systemd/coredump.conf.d/50-shani-shell.conf")
COREDUMP_KEYS = {"Storage": {"none", "external", "journal"}, "Compress": {"yes", "no"}}
COREDUMP_SIZE_KEYS = {
    "ProcessSizeMax": None,
    "ExternalSizeMax": None,
    "JournalSizeMax": None,
    "MaxUse": None,
    "KeepFree": None,
}


def coredump_get(_req: dict) -> dict:
    settings = {}
    try:
        for line in COREDUMP_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("[") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in COREDUMP_KEYS or k in COREDUMP_SIZE_KEYS:
                settings[k] = v
    except OSError:
        pass
    return {"settings": settings, "path": str(COREDUMP_DROPIN)}


def coredump_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        v = str(v).strip()
        if k in COREDUMP_KEYS:
            if v not in COREDUMP_KEYS[k]:
                raise Refused(f"bad value for {k}")
            clean[k] = v
        elif k in COREDUMP_SIZE_KEYS:
            if not SIZE_RE.match(v):
                raise Refused(f"bad value for {k}")
            clean[k] = v
        else:
            raise Refused(f"unknown key: {k}")
    if clean:
        content = "# Managed by shani-shell\n[Coredump]\n" + "".join(
            f"{k}={v}\n" for k, v in clean.items()
        )
        COREDUMP_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        COREDUMP_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(COREDUMP_DROPIN, 0o644)
    else:
        try:
            COREDUMP_DROPIN.unlink()
        except OSError:
            pass
    return coredump_get(req)


SLEEP_DROPIN = Path("/etc/systemd/sleep.conf.d/50-shani-shell.conf")
SLEEP_STATE_KEYS = {
    "SuspendState": {"mem", "standby", "freeze", "disk"},
    "HibernateState": {"disk", "platform", "shutdown"},
    "HybridSleepState": {"disk", "platform", "shutdown"},
}
SLEEP_INT_KEYS = {"HibernateDelaySec": (0, 86400)}


def sleep_get(_req: dict) -> dict:
    settings = {}
    try:
        for line in SLEEP_DROPIN.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            line = line.strip()
            if (
                not line
                or line.startswith("#")
                or line.startswith("[")
                or "=" not in line
            ):
                continue
            k, v = line.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in SLEEP_STATE_KEYS or k in SLEEP_INT_KEYS:
                settings[k] = v
    except OSError:
        pass
    return {"settings": settings, "path": str(SLEEP_DROPIN)}


def sleep_set(req: dict) -> dict:
    updates = req.get("settings") or {}
    if not isinstance(updates, dict):
        raise Refused("settings must be an object")
    clean = {}
    for k, v in updates.items():
        if k in SLEEP_STATE_KEYS:
            v = str(v).strip()
            if v not in SLEEP_STATE_KEYS[k]:
                raise Refused(f"bad value for {k}")
            clean[k] = v
        elif k in SLEEP_INT_KEYS:
            try:
                iv = int(v)
            except Exception:
                raise Refused(f"{k} must be integer")
            lo, hi = SLEEP_INT_KEYS[k]
            if iv < lo or iv > hi:
                raise Refused(f"{k} out of range")
            clean[k] = str(iv)
        else:
            raise Refused(f"unknown key: {k}")
    if clean:
        content = "# Managed by shani-shell\n[Sleep]\n" + "".join(
            f"{k}={v}\n" for k, v in clean.items()
        )
        SLEEP_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        SLEEP_DROPIN.write_text(content, encoding="utf-8")
        os.chmod(SLEEP_DROPIN, 0o644)
    else:
        try:
            SLEEP_DROPIN.unlink()
        except OSError:
            pass
    return sleep_get(req)


COMMANDS = {
    "guest": guest,
    "wakeup": wakeup,
    "lighting": lighting,
    "power-limit": power_limit,
    "user-add": user_add,
    "user-remove": user_remove,
    "user-admin": user_admin,
    "user-password": user_password,
    "user-group": user_group,
    "autologin": autologin,
    "power-keys": power_keys,
    "battery-limit": battery_limit,
    "remote-access-get": remote_access_get,
    "remote-access-set": remote_access_set,
    "pwquality-get": pwquality_get,
    "pwquality-set": pwquality_set,
    "faillock-get": faillock_get,
    "faillock-set": faillock_set,
    "hosts-get": hosts_get,
    "hosts-set": hosts_set,
    "sudoers-get": sudoers_get,
    "sudoers-rows-get": sudoers_rows_get,
    "sudoers-set": sudoers_set,
    "nfs-exports-set": nfs_exports_set,
    "smb-share-set": smb_share_set,
    "pam-config-set": pam_config_set,
    "pkcs11-mapping-set": pkcs11_mapping_set,
    "apparmor-set": apparmor_set,
    "modprobe-blacklist-get": modprobe_blacklist_get,
    "modprobe-blacklist-set": modprobe_blacklist_set,
    "modules-load-get": modules_load_get,
    "modules-load-set": modules_load_set,
    "journald-get": journald_get,
    "journald-set": journald_set,
    "journald-vacuum": journald_vacuum,
    "sysctl-get": sysctl_get,
    "sysctl-set": sysctl_set,
    "timesyncd-get": timesyncd_get,
    "timesyncd-set": timesyncd_set,
    "resolved-get": resolved_get,
    "resolved-set": resolved_set,
    "login-defs-get": login_defs_get,
    "login-defs-set": login_defs_set,
    "fstrim-get": fstrim_get,
    "fstrim-set": fstrim_set,
    "cups-browsed-get": cups_browsed_get,
    "cups-browsed-set": cups_browsed_set,
    "bluetooth-get": bluetooth_get,
    "bluetooth-set": bluetooth_set,
    "auditd-get": auditd_get,
    "auditd-set": auditd_set,
    "audit-profile-list": audit_profile_list,
    "audit-profile-get": audit_profile_get,
    "audit-profile-set": audit_profile_set,
    "logind-get": logind_get,
    "logind-set": logind_set,
    "coredump-get": coredump_get,
    "coredump-set": coredump_set,
    "sleep-get": sleep_get,
    "sleep-set": sleep_set,
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
