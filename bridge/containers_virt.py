#!/usr/bin/env python3
"""libvirt/QEMU VMs for the Containers window, kept apart from containers.py so
neither bridge imports the other. Every command prints its own JSON: one object.

    virt-list
    virt-start|virt-shutdown|virt-force-off|virt-reboot NAME [URI]
    virt-console NAME [URI]   argv for a viewer or a terminal, not launched here
    virt-remove NAME [URI]    undefine, disks kept
    virt-remove-disks NAME [URI]   undefine --remove-all-storage
    virt-open-boxes           argv for GNOME Boxes, not launched here

URIs are qemu:///session (default) or qemu:///system. A VM's state comes from the
`virsh -c URI list --all` table when it has a state column; otherwise "unknown".
SHANI_VIRSH and SHANI_VIRT_VIEWER override the executables (stand-ins in tests).
SHANI_KVM=1 stands in for /dev/kvm.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

VIRSH = shlex.split(os.environ.get("SHANI_VIRSH", "virsh"))
VIEWER = shlex.split(os.environ.get("SHANI_VIRT_VIEWER", "virt-viewer"))
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
URIS = ("qemu:///session", "qemu:///system")

COMMANDS = (
    "virt-list",
    "virt-start",
    "virt-shutdown",
    "virt-force-off",
    "virt-reboot",
    "virt-console",
    "virt-remove",
    "virt-remove-disks",
    "virt-open-boxes",
)

_ACTIONS = {
    "virt-start": "start",
    "virt-shutdown": "shutdown",
    "virt-force-off": "destroy",
    "virt-reboot": "reboot",
}


def _has(cmd) -> bool:
    # A stand-in can be an absolute path that is not on PATH.
    return bool(shutil.which(cmd[0]) or os.path.exists(cmd[0]))


def _run(cmd, *args, timeout=60):
    return subprocess.run(
        cmd + list(args), capture_output=True, text=True, timeout=timeout
    )


def _err(r, fallback):
    return {"error": (r.stderr.strip().splitlines() or [fallback])[-1]}


def _check(name: str, uri: str):
    if not NAME.match(name):
        return {"error": "not a VM name"}
    if uri not in URIS:
        return {"error": "not a libvirt URI"}
    return None


def _domains(uri: str):
    r = _run(VIRSH, "-c", uri, "list", "--all", "--name")
    if r.returncode != 0:
        return [], False
    names = [l.strip() for l in r.stdout.splitlines() if l.strip()]
    states = {}
    t = _run(VIRSH, "-c", uri, "list", "--all")
    if t.returncode == 0:
        for line in t.stdout.splitlines():
            f = line.split()
            if len(f) >= 3:
                states[f[1]] = f[2]
            elif len(f) == 2:
                states[f[0]] = f[1]
    return (
        [{"name": n, "state": states.get(n, "unknown"), "uri": uri} for n in names],
        True,
    )


def _listing() -> dict:
    out = {
        "domains": [],
        "kvm": os.path.exists("/dev/kvm") or os.environ.get("SHANI_KVM") == "1",
        "hasVirsh": _has(VIRSH),
        "hasViewer": _has(VIEWER),
        "systemAllowed": False,
        "hasBoxes": bool(shutil.which("flatpak")),
    }
    if not out["hasVirsh"]:
        return out
    for uri in URIS:
        domains, ok = _domains(uri)
        out["domains"].extend(domains)
        if uri == URIS[1]:
            out["systemAllowed"] = ok
    return out


def _act(verb: str, name: str, uri: str, extra=()) -> dict:
    bad = _check(name, uri)
    if bad:
        return bad
    r = _run(VIRSH, "-c", uri, verb, name, *extra, timeout=120)
    return {"ok": True} if r.returncode == 0 else _err(r, "virsh %s failed" % verb)


def _console(name: str, uri: str) -> dict:
    bad = _check(name, uri)
    if bad:
        return bad
    if _has(VIEWER):
        return {"argv": [VIEWER[0] if VIEWER else "virt-viewer", name]}
    return {"argv": ["xdg-terminal-exec", "virsh", "-c", uri, "console", name]}


def _boxes() -> dict:
    if not shutil.which("flatpak"):
        return {"error": "Boxes is not installed"}
    return {"argv": ["flatpak", "run", "org.gnome.Boxes"]}


def run(cmd: str, args: list[str]) -> int:
    try:
        if cmd == "virt-list" and not args:
            r = _listing()
        elif cmd in _ACTIONS and len(args) in (1, 2):
            r = _act(
                _ACTIONS[cmd],
                args[0],
                args[1] if len(args) == 2 else URIS[0],
            )
        elif cmd == "virt-console" and len(args) in (1, 2):
            r = _console(args[0], args[1] if len(args) == 2 else URIS[0])
        elif cmd in ("virt-remove", "virt-remove-disks") and len(args) in (1, 2):
            extra = ("--remove-all-storage",) if cmd == "virt-remove-disks" else ()
            r = _act(
                "undefine",
                args[0],
                args[1] if len(args) == 2 else URIS[0],
                extra,
            )
        elif cmd == "virt-open-boxes" and not args:
            r = _boxes()
        else:
            r = {
                "error": "unknown command or wrong arguments: %s %s"
                % (cmd, " ".join(args))
            }
    except (OSError, subprocess.TimeoutExpired, ValueError, IndexError) as e:
        r = {"error": str(e)}
    print(json.dumps(r))
    return 1 if isinstance(r, dict) and "error" in r else 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1], sys.argv[2:]))
