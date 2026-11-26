#!/usr/bin/env python3
"""system_net — read-only answers about the machine's network services.

One JSON object per call, for the shell's network pages. Nothing here writes a
file, sends a packet or asks for a password: every command is a status query,
run as the person. Config files are read only for the fields shown below; a
token, key or password is never copied into an answer.

    system_net.py resolver      {"conf","target","servers","search","resolved",
                                 "links": [interface names], "error"}
    system_net.py inbound       {"ports":[{"proto","port","address","process"}],
                                 "sshd","forwarding","error"}
    system_net.py avahi         {"installed","active",
                                 "services":[{"type","name","host","port"}],
                                 "error"}
    system_net.py caddy         {"installed","file","valid","sites":[...],"error"}
    system_net.py cloudflared   {"installed","config","credentials",
                                 "tunnels":[{"id","name"}],"error"}
    system_net.py mail          {"relay","host","detail","error"}

Every external tool, file and directory has a SHANI_* override for tests:
SHANI_RESOLV_CONF, SHANI_RESOLVECTL, SHANI_SYSTEMCTL, SHANI_SS, SHANI_SYSCTL_FILE,
SHANI_AVAHI_BROWSE, SHANI_CADDYFILE, SHANI_CADDY, SHANI_CLOUDFLARED_DIR,
SHANI_CLOUDFLARED and SHANI_EXIM_CONF. Status queries get five seconds each.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

TIMEOUT = 5

RESOLV_CONF = os.environ.get("SHANI_RESOLV_CONF", "/etc/resolv.conf")
RESOLVECTL = shlex.split(os.environ.get("SHANI_RESOLVECTL", "resolvectl"))
SYSTEMCTL = shlex.split(os.environ.get("SHANI_SYSTEMCTL", "systemctl"))
SS = shlex.split(os.environ.get("SHANI_SS", "ss"))
SYSCTL_FILE = os.environ.get("SHANI_SYSCTL_FILE", "/proc/sys/net/ipv4/ip_forward")
AVAHI_BROWSE = shlex.split(os.environ.get("SHANI_AVAHI_BROWSE", "avahi-browse"))
CADDYFILE = os.environ.get("SHANI_CADDYFILE") or "/etc/caddy/Caddyfile"
CADDY = shlex.split(os.environ.get("SHANI_CADDY", "caddy"))
CLOUDFLARED_DIR = os.path.expanduser(
    os.environ.get("SHANI_CLOUDFLARED_DIR", "~/.cloudflared")
)
CLOUDFLARED = shlex.split(os.environ.get("SHANI_CLOUDFLARED", "cloudflared"))
EXIM_CONF = os.environ.get("SHANI_EXIM_CONF", "/etc/mail/exim.conf")

HOSTNAME = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$")
LINK = re.compile(r"^Link\s+\d+\s+\(([^)]+)\)")


def _run(cmd: list[str], *args: str, timeout: int = TIMEOUT):
    """A completed process even when the tool is missing or too slow."""
    try:
        return subprocess.run(
            cmd + list(args), capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", "timed out")
    except OSError as exc:
        return subprocess.CompletedProcess(cmd, 127, "", str(exc))


def _unique(values):
    return list(dict.fromkeys(v for v in values if v))


def _unit(name: str) -> str:
    r = _run(SYSTEMCTL, "is-active", name)
    state = r.stdout.strip()
    return state if state in ("active", "inactive") else "unknown"


def _text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8", errors="replace")


def resolver() -> dict:
    """What answers name lookups, and where resolv.conf points."""
    out = {
        "conf": RESOLV_CONF,
        "target": "",
        "servers": [],
        "search": [],
        "resolved": _unit("systemd-resolved"),
        "links": [],
        "error": "",
    }
    try:
        out["target"] = os.readlink(RESOLV_CONF)
    except OSError:
        pass  # a plain file is a valid resolv.conf too
    try:
        text = _text(RESOLV_CONF)
    except OSError as exc:
        out["error"] = str(exc)
        text = ""

    servers, search = [], []
    for line in text.splitlines():
        parts = line.split()
        if not parts or parts[0].startswith("#"):
            continue
        if parts[0] == "nameserver" and len(parts) > 1:
            servers.append(parts[1])
        elif parts[0] in ("search", "domain"):
            search.extend(parts[1:])

    r = _run(RESOLVECTL, "status")
    if r.returncode == 0:
        current, listed, domains = [], [], []
        for line in r.stdout.splitlines():
            m = LINK.match(line.strip())
            if m:
                out["links"].append(m.group(1))
            s = line.strip()
            for label, dest in (
                ("Current DNS Server:", current),
                ("DNS Servers:", listed),
                ("DNS Domain:", domains),
            ):
                if s.startswith(label):
                    dest.extend(s[len(label) :].split())
        # The server in use first, then the rest of the resolver's own list.
        out["servers"] = _unique(current + listed + servers)
        out["search"] = _unique(domains + search)
    else:
        out["servers"] = _unique(servers)
        out["search"] = _unique(search)
    return out


def inbound() -> dict:
    """Listening TCP ports, remote sign-in and IP forwarding."""
    out = {
        "ports": [],
        "sshd": _unit("sshd.service"),
        "forwarding": "unknown",
        "error": "",
    }
    r = _run(SS, "-ltnp")
    if r.returncode != 0:
        out["error"] = "could not list listening ports"
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) < 4 or not parts[0].startswith("LISTEN"):
            continue
        local = parts[3]
        if local.startswith("["):
            end = local.find("]")
            if end < 0 or local[end + 1 : end + 2] != ":":
                continue
            address, port = local[1:end], local[end + 2 :]
        else:
            address, sep, port = local.rpartition(":")
            if not sep:
                continue
        if not port.isdigit():
            continue
        m = re.search(r'users:\(\("([^"]+)"', line)
        out["ports"].append(
            {
                "proto": "tcp",
                "port": int(port),
                "address": address,
                "process": m.group(1) if m else "",
            }
        )
    out["ports"].sort(key=lambda p: (p["port"], p["address"]))
    try:
        value = _text(SYSCTL_FILE).strip()
        out["forwarding"] = (
            "on" if value == "1" else "off" if value == "0" else "unknown"
        )
    except OSError:
        pass
    return out


def avahi() -> dict:
    """Services this machine hears on the local network; nothing is published."""
    out = {
        "installed": bool(shutil.which(AVAHI_BROWSE[0])),
        "active": _unit("avahi-daemon.service"),
        "services": [],
        "error": "",
    }
    if not out["installed"]:
        return out
    r = _run(AVAHI_BROWSE, "-art")
    if r.returncode != 0:
        out["error"] = "service discovery did not answer"
        return out
    seen = set()
    for line in r.stdout.splitlines():
        if not line.startswith("+"):
            continue
        fields = line.split(";")
        if len(fields) < 9:
            continue
        service = {
            "type": fields[4],
            "name": fields[3],
            "host": fields[6],
            "port": int(fields[8]) if fields[8].isdigit() else fields[8],
        }
        key = tuple(service.values())
        if key not in seen:
            seen.add(key)
            out["services"].append(service)
    return out


def caddy() -> dict:
    """Which config file exists, whether it parses, and the sites it declares."""
    out = {
        "installed": bool(shutil.which(CADDY[0])),
        "file": "",
        "valid": False,
        "sites": [],
        "error": "",
    }
    for path in _unique([CADDYFILE, "/etc/caddy/Caddyfile"]):
        if os.path.isfile(path):
            out["file"] = path
            break
    if not out["file"]:
        return out
    if out["installed"]:
        r = _run(CADDY, "validate", "--config", out["file"], "--adapter", "caddyfile")
        out["valid"] = r.returncode == 0
        if not out["valid"]:
            out["error"] = "configuration did not validate"
    try:
        text = _text(out["file"])
    except OSError as exc:
        out["error"] = str(exc)
        return out
    sites = []
    for line in text.splitlines():
        if not line or line[0].isspace() or line.lstrip().startswith("#"):
            continue  # only top-level blocks declare an address
        s = line.strip()
        if not s.endswith("{"):
            continue
        tokens = s[:-1].split()
        if not tokens:
            continue
        for address in tokens[0].split(","):
            address = address.strip()
            if "." in address or address.split(":", 1)[0] == "localhost":
                sites.append(address)
    out["sites"] = _unique(sites)
    return out


def cloudflared() -> dict:
    """Whether a tunnel is set up; only file existence and tunnel names are read."""
    out = {
        "installed": bool(shutil.which(CLOUDFLARED[0])),
        "config": (Path(CLOUDFLARED_DIR) / "config.yml").is_file(),
        "credentials": False,
        "tunnels": [],
        "error": "",
    }
    try:
        out["credentials"] = any(Path(CLOUDFLARED_DIR).glob("*.json"))
    except OSError:
        pass
    if not out["installed"]:
        return out
    r = _run(CLOUDFLARED, "tunnel", "list")
    if r.returncode != 0:
        out["error"] = "tunnel list did not answer"
        return out
    for line in r.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and re.match(r"^[A-Za-z0-9_-]{8,}$", parts[0]):
            out["tunnels"].append({"id": parts[0], "name": parts[1]})
    return out


def mail() -> dict:
    """Whether outgoing mail uses a smart host or goes straight to the MX."""
    out = {"relay": "unknown", "host": "", "detail": "", "error": ""}
    try:
        text = _text(EXIM_CONF)
    except OSError as exc:
        out["error"] = str(exc)
        return out
    smart = any(
        re.match(r"^\.ifdef\s+ROUTER_SMARTHOST\b", line.strip())
        for line in text.splitlines()
    )
    if not smart:
        out["relay"] = "direct"
        out["detail"] = "Mail goes straight to the receiving server."
        return out
    out["relay"] = "smart host"
    out["detail"] = "A smart host is set in the mail configuration."
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("#"):
            continue
        m = re.search(r"(?:\broute_list\s*=\s*\*?\s*|\bhost\s*=\s*)(\S+)", s)
        if not m:
            continue
        candidate = m.group(1)
        if HOSTNAME.match(candidate) and "." in candidate:
            out["host"] = candidate
            break
    return out


VERBS = {
    "resolver": resolver,
    "inbound": inbound,
    "avahi": avahi,
    "caddy": caddy,
    "cloudflared": cloudflared,
    "mail": mail,
}


def main(argv: list[str]) -> int:
    verb = argv[1] if len(argv) > 1 else ""
    if verb not in VERBS:
        print(json.dumps({"error": "not a known verb"}))
        return 2
    print(json.dumps(VERBS[verb]()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
