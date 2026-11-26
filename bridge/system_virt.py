#!/usr/bin/env python3
"""system_virt — read-only virtualization facts: KVM readiness and an inventory.

    system_virt.py kvm         {"device", "modules", "usable", "detail"}
    system_virt.py inventory   {"have": {"virsh", "lxc", "lxd", "machinectl"},
                                "libvirt", "lxc", "lxd", "nspawn", "error"}

No lifecycle verb exists here: starting, stopping or creating anything stays in
the shell's Containers window. Missing tools and absent sockets give empty
lists, never invented machines. All reads run as the person; one JSON answer.

Test overrides: SHANI_KVM_PATH, SHANI_MODULES_FILE, SHANI_VIRSH, SHANI_LXC,
SHANI_LXD, SHANI_LXD_SOCKET, SHANI_MACHINECTL.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys


def _cmd(env: str, default: str) -> list[str]:
    return shlex.split(os.environ.get(env, default))


def _text(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def _run(cmd: list[str], *args: str, timeout: int = 15):
    try:
        return subprocess.run(
            cmd + list(args), capture_output=True, text=True, timeout=timeout
        ), ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)


def kvm() -> dict:
    """KVM device, kvm* kernel modules and whether the two agree."""
    path = os.environ.get("SHANI_KVM_PATH", "/dev/kvm")
    device = os.path.exists(path)
    text = _text(os.environ.get("SHANI_MODULES_FILE", "/proc/modules"))
    if text is None:
        return {
            "device": device,
            "modules": [],
            "usable": False,
            "detail": "kernel module list is not readable",
        }
    modules = []
    for line in text.splitlines():
        parts = line.split()
        if parts and parts[0].startswith("kvm") and parts[0] not in modules:
            modules.append(parts[0])
    if not device:
        detail = "KVM device is not present"
    elif not modules:
        detail = "KVM device is present; the module list does not name it"
    else:
        detail = "KVM device and modules are present"
    return {
        "device": device,
        "modules": modules,
        "usable": device and bool(modules),
        "detail": detail,
    }


def _virsh(text: str) -> list[dict]:
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3 and (parts[0].isdigit() or parts[0] == "-"):
            rows.append({"name": parts[1], "state": " ".join(parts[2:])})
    return rows


def _lxc(text: str) -> list[dict]:
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] != "NAME" and not parts[0].startswith("-"):
            rows.append({"name": parts[0], "state": parts[1]})
    return rows


def _lxd(text: str) -> list[dict]:
    rows = []
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("|"):
            continue
        cols = [c.strip() for c in s.strip("|").split("|")]
        if len(cols) < 2 or cols[0] in ("NAME", "") or set(cols[0]) <= {"-"}:
            continue
        rows.append({"name": cols[0], "state": cols[1]})
    return rows


def _machinectl(text: str) -> list[dict]:
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if not parts or parts[0] in ("MACHINE",) or set(parts[0]) <= {"-"}:
            continue
        rows.append({"name": parts[0], "state": "running"})
    return rows


def inventory() -> dict:
    """What the three runtimes report, each in its own command's words."""
    tools = {
        "virsh": _cmd("SHANI_VIRSH", "virsh"),
        "lxc": _cmd("SHANI_LXC", "lxc-ls"),
        "lxd": _cmd("SHANI_LXD", "lxc"),
        "machinectl": _cmd("SHANI_MACHINECTL", "machinectl"),
    }
    out = {
        "have": {
            name: bool(cmd and shutil.which(cmd[0])) for name, cmd in tools.items()
        },
        "libvirt": [],
        "lxc": [],
        "lxd": [],
        "nspawn": [],
        "error": "",
    }
    plans = (
        ("virsh", ("list", "--all"), "libvirt", _virsh),
        ("lxc", ("-f",), "lxc", _lxc),
        ("machinectl", ("list",), "nspawn", _machinectl),
    )
    for name, args, key, parse in plans:
        if not out["have"][name]:
            continue
        r, err = _run(tools[name], *args)
        if err:
            out["error"] = out["error"] or err
        elif r.returncode != 0:
            out["error"] = (
                out["error"]
                or (r.stderr.strip().splitlines() or ["%s failed" % name])[-1]
            )
        else:
            out[key] = parse(r.stdout)
    # LXD is the same lxc command, but only speaks to a local daemon socket.
    socket = os.environ.get("SHANI_LXD_SOCKET", "/var/lib/lxd/unix.socket")
    if out["have"]["lxd"] and os.path.exists(socket):
        r, err = _run(tools["lxd"], "list")
        if err:
            out["error"] = out["error"] or err
        elif r.returncode != 0:
            out["error"] = (
                out["error"]
                or (r.stderr.strip().splitlines() or ["lxc list failed"])[-1]
            )
        else:
            out["lxd"] = _lxd(r.stdout)
    return out


VERBS = {"kvm": kvm, "inventory": inventory}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if cmd not in VERBS or args:
        print(json.dumps({"error": "usage: system_virt.py <kvm|inventory>; read only"}))
        return 2
    result = VERBS[cmd]()
    print(json.dumps(result))
    return 1 if result.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
