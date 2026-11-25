#!/usr/bin/env python3
"""vpn — NetworkManager VPN connections for the shell's VPN panel.

One JSON answer per command, as every other bridge in this directory does:

    vpn.py list                      {ok, available, connections, error}
    vpn.py up <name>                 {ok, error}
    vpn.py down <name>               {ok, error}
    vpn.py autoconnect <name> <bool> {ok, error}
    vpn.py stats <name>              {ok, connected, rxBytes, txBytes, uptime, peer, state, error}
    vpn.py import <path>             {ok, name, error}
    vpn.py delete <name>             {ok, error}

Every nmcli call is an argv list, never a shell string: a name or a path with
spaces must not become a command, and a leading dash must not become an option.
A system-bus SecretAgent (VPN passwords/secrets) is deliberately out of scope
for this round — credentials still come from NetworkManager's own agent. nmcli
may be absent: ``list`` then answers with an empty list and available=false,
and the other commands answer with a clear error instead of a traceback.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# A leading letter/digit rules out nmcli options ("--clear-dummy"); the rest is
# conservative but covers the names NetworkManager shows (spaces, dots, dashes,
# "@", ":" in escaped form). Newlines and shell metacharacters never match.
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._@+=:/\\-]{0,127}$")
DEVICE_RE = re.compile(r"^[A-Za-z0-9_.-]{1,32}$")
UNSAFE_STEM_RE = re.compile(r"[^A-Za-z0-9._-]+")
VPN_TYPES = {"vpn", "wireguard", "tunnel", "openvpn"}
MAX_PROFILE = 2 * 1024 * 1024
TIMEOUT = 10
COMMANDS = {"list", "up", "down", "autoconnect", "stats", "import", "delete"}


class VpnError(Exception):
    """An expected failure that must reach the panel as JSON, not a traceback."""


def ok(**extra):
    return dict(ok=True, error="", **extra)


def fail(message, **extra):
    return dict(ok=False, error=str(message)[:200], **extra)


def nmcli_bin():
    """The nmcli to use. SHANI_VPN_NMCLI lets a test point at a stub."""
    return os.environ.get("SHANI_VPN_NMCLI") or shutil.which("nmcli")


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))


def vpn_dir() -> Path:
    return config_home() / "NetworkManager" / "VPN"


def run_nmcli(*args: str) -> subprocess.CompletedProcess:
    exe = nmcli_bin()
    if not exe:
        raise VpnError("nmcli is not installed")
    try:
        return subprocess.run(
            [exe, *args], capture_output=True, text=True, timeout=TIMEOUT
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise VpnError(str(exc)[:160]) from exc


def _result(proc):
    return proc.returncode, proc.stdout or "", (proc.stderr or "").strip()


def _detail(out: str, err: str) -> str:
    """nmcli's last line is the useful one; never leak the whole stderr."""
    text = (err or out or "").strip()
    return text.splitlines()[-1][:200] if text else ""


def _name(value) -> str:
    if not isinstance(value, str) or not NAME_RE.fullmatch(value):
        raise VpnError("invalid connection name")
    return value


def _bool(value) -> str:
    text = str(value).strip().lower()
    if text in ("true", "yes", "on", "1"):
        return "yes"
    if text in ("false", "no", "off", "0"):
        return "no"
    raise VpnError("autoconnect expects true or false")


def _fields(line: str):
    """nmcli -t separates fields with ':' and escapes a colon in a field as '\\:'."""
    out, cur, escaped = [], [], False
    for ch in line:
        if escaped:
            cur.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == ":":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if escaped:
        cur.append("\\")
    out.append("".join(cur))
    return out


def cmd_list() -> dict:
    out = {"ok": True, "error": "", "available": True, "connections": []}
    if not nmcli_bin():
        out.update(available=False, error="nmcli is not installed")
        return out
    try:
        proc = run_nmcli(
            "-t", "-f", "NAME,TYPE,STATE,AUTOCONNECT", "connection", "show"
        )
    except VpnError as exc:
        out.update(available=False, error=str(exc))
        return out
    code, text, err = _result(proc)
    if code != 0:
        out.update(
            available=False,
            error=_detail(text, err) or "nmcli could not list connections",
        )
        return out
    rows = []
    for line in text.splitlines():
        if not line.strip():
            continue
        f = _fields(line)
        if len(f) < 4 or f[1].strip().lower() not in VPN_TYPES:
            continue
        rows.append(
            {
                "name": f[0].strip(),
                "type": f[1].strip(),
                "state": f[2].strip(),
                "autoconnect": f[3].strip().lower() in ("yes", "true", "on", "1"),
            }
        )
    out["connections"] = rows
    return out


def _change(args) -> dict:
    try:
        proc = run_nmcli(*args)
    except VpnError as exc:
        return fail(exc)
    code, text, err = _result(proc)
    if code != 0:
        return fail(_detail(text, err) or "NetworkManager refused the change")
    return ok()


def cmd_up(name) -> dict:
    return _change(["connection", "up", _name(name)])


def cmd_down(name) -> dict:
    return _change(["connection", "down", _name(name)])


def cmd_delete(name) -> dict:
    return _change(["connection", "delete", _name(name)])


def cmd_autoconnect(name, flag) -> dict:
    return _change(
        ["connection", "modify", _name(name), "connection.autoconnect", _bool(flag)]
    )


def _profile(raw) -> Path:
    if not isinstance(raw, str) or not raw:
        raise VpnError("import needs a file path")
    path = Path(raw).expanduser()
    if not path.is_absolute():
        raise VpnError("import needs an absolute file path")
    try:
        path = path.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise VpnError("profile does not exist") from exc
    if not path.is_file():
        raise VpnError("profile is not a regular file")
    if path.suffix.lower() not in (".ovpn", ".conf"):
        raise VpnError("only .ovpn and .conf profiles can be imported")
    if path.stat().st_size > MAX_PROFILE:
        raise VpnError("profile is too large")
    return path


def _safe_stem(path: Path) -> str:
    stem = UNSAFE_STEM_RE.sub("-", path.stem[:64]).strip("-._")
    return stem or "imported"


def cmd_import(raw) -> dict:
    path = _profile(raw)
    suffix = path.suffix.lower()
    stem = _safe_stem(path)
    try:
        dest_dir = vpn_dir()
        dest_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        dest = dest_dir / (stem + suffix)
        n = 2
        while dest.exists():
            dest = dest_dir / (f"{stem}-{n}" + suffix)
            n += 1
        shutil.copyfile(path, dest)
        os.chmod(dest, 0o600)  # a profile can carry secrets: only its owner reads it
    except OSError as exc:
        return fail("could not install the profile: " + str(exc)[:160])

    # shortcut: NetworkManager reads .conf keyfiles from here after a reload;
    # newer nmcli versions prefer `connection import` for a raw .ovpn. Upgrade
    # to that when copied .ovpn files stop showing up.
    try:
        proc = run_nmcli("connection", "reload")
    except VpnError as exc:
        return fail(f"profile copied as {dest.name}, but {exc}")
    code, text, err = _result(proc)
    if code != 0:
        return fail(
            f"profile copied as {dest.name}, but reload failed: "
            + (_detail(text, err) or "nmcli error")
        )
    return ok(name=dest.stem)


def _counter(device: str, field: str) -> int:
    try:
        return int(
            (Path("/sys/class/net") / device / "statistics" / field).read_text().strip()
            or 0
        )
    except (OSError, ValueError):
        return 0


def _seconds(value: str) -> int:
    text = value.strip()
    if re.fullmatch(r"\d+", text):
        return int(text)
    m = re.fullmatch(r"(\d+):(\d{1,2}):(\d{1,2})", text)
    return int(m[1]) * 3600 + int(m[2]) * 60 + int(m[3]) if m else 0


def cmd_stats(name) -> dict:
    wanted = _name(name)
    out = {
        "ok": True,
        "error": "",
        "connected": False,
        "state": "disconnected",
        "device": "",
        "rxBytes": 0,
        "txBytes": 0,
        "uptime": 0,
        "peer": "",
    }
    try:
        proc = run_nmcli(
            "-t", "-f", "NAME,TYPE,STATE,DEVICE", "connection", "show", "--active"
        )
    except VpnError as exc:
        return fail(exc)
    code, text, err = _result(proc)
    if code != 0:
        return fail(_detail(text, err) or "nmcli could not read active connections")
    row = None
    for line in text.splitlines():
        f = _fields(line)
        if len(f) >= 4 and f[0].strip() == wanted and f[1].strip().lower() in VPN_TYPES:
            row = f
            break
    if row is None:
        return out
    out.update(connected=True, state=row[2].strip(), device=row[3].strip())
    device = row[3].strip()
    # a device name goes into a sysfs path and an argv: validate it first.
    # nmcli uses "--" while a connection is still coming up, not a device.
    if DEVICE_RE.fullmatch(device) and device not in ("", "--"):
        out["rxBytes"] = _counter(device, "rx_bytes")
        out["txBytes"] = _counter(device, "tx_bytes")
        try:
            det = run_nmcli(
                "-t",
                "-f",
                "GENERAL.CON-UPTIME,IP4.GATEWAY,IP6.GATEWAY",
                "device",
                "show",
                device,
            )
        except VpnError:
            det = None
        if det is not None and det.returncode == 0:
            for line in (det.stdout or "").splitlines():
                if ":" not in line:
                    continue
                key, value = line.split(":", 1)
                value = value.replace("\\:", ":").strip()
                key = key.strip().upper()
                if key.endswith("CON-UPTIME") or key == "CONNECTION-UPTIME":
                    out["uptime"] = _seconds(value)
                elif (
                    key.endswith("GATEWAY")
                    and not out["peer"]
                    and value not in ("", "--")
                ):
                    out["peer"] = value
    return out


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print(json.dumps(fail("usage: vpn.py <command> [args]")))
        return 2
    cmd, rest = args[0], args[1:]
    try:
        if cmd == "list":
            data = cmd_list()
        elif cmd in ("up", "down", "delete"):
            if len(rest) != 1:
                print(json.dumps(fail(f"usage: vpn.py {cmd} <name>")))
                return 2
            data = {"up": cmd_up, "down": cmd_down, "delete": cmd_delete}[cmd](rest[0])
        elif cmd == "autoconnect":
            if len(rest) != 2:
                print(json.dumps(fail("usage: vpn.py autoconnect <name> <true|false>")))
                return 2
            data = cmd_autoconnect(rest[0], rest[1])
        elif cmd == "stats":
            if len(rest) != 1:
                print(json.dumps(fail("usage: vpn.py stats <name>")))
                return 2
            data = cmd_stats(rest[0])
        elif cmd == "import":
            if len(rest) != 1:
                print(json.dumps(fail("usage: vpn.py import <path>")))
                return 2
            data = cmd_import(rest[0])
        else:
            print(json.dumps(fail("unknown command: " + cmd)))
            return 2
    except VpnError as exc:
        data = fail(exc)
    except Exception as exc:  # never send a traceback to the QML collector
        data = fail("VPN bridge failed: " + str(exc)[:160])
    print(json.dumps(data, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
