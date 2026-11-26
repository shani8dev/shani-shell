#!/usr/bin/env python3
"""Machines for the Containers window: systemd-nspawn machines and images through
machinectl/importctl, and boot of a disk image with systemd-vmspawn. Kept apart
from containers.py so neither bridge imports the other. Every command prints its
own JSON: one object, or streamed {"line": ...} objects followed by {"ok": True}.

    machines-list
    machine-start|machine-poweroff|machine-reboot|machine-remove NAME
    machine-shell NAME            argv for xdg-terminal-exec, not launched here
    machine-image-pull URL NAME tar|raw    importctl progress, streamed
    machine-image-clone|machine-image-rename OLD NEW
    machine-image-remove NAME
    vmspawn-boot FILE             argv for xdg-terminal-exec, not launched here

A machine's state comes from `machinectl show NAME -p State`; when that is not
reported the state is "unknown" - the tables have no state column. Opening a
shell and booting an image only hand back argv: QML runs execDetached.

SHANI_MACHINECTL, SHANI_IMPORTCTL and SHANI_VMSPAWN override the executables
(a stand-in in tests).
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

MACHINECTL = shlex.split(os.environ.get("SHANI_MACHINECTL", "machinectl"))
IMPORTCTL = shlex.split(os.environ.get("SHANI_IMPORTCTL", "importctl"))
VMSPAWN = shlex.split(os.environ.get("SHANI_VMSPAWN", "systemd-vmspawn"))
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
URL = re.compile(r"^https?://[^\s]+$")
DISK = (".raw", ".qcow2")

COMMANDS = (
    "machines-list",
    "machine-start",
    "machine-poweroff",
    "machine-reboot",
    "machine-remove",
    "machine-shell",
    "machine-image-pull",
    "machine-image-clone",
    "machine-image-rename",
    "machine-image-remove",
    "vmspawn-boot",
)

_ACTIONS = {
    "machine-start": ("start", 1),
    "machine-poweroff": ("poweroff", 1),
    "machine-reboot": ("reboot", 1),
    "machine-remove": ("remove", 1),
    "machine-image-clone": ("clone", 2),
    "machine-image-rename": ("rename", 2),
    "machine-image-remove": ("remove", 1),
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


def _rows(text, headers):
    out = []
    for line in text.splitlines():
        fields = line.split()
        if fields and fields[0] not in headers:
            out.append(fields)
    return out


def _state(name: str) -> str:
    r = _run(MACHINECTL, "show", name, "-p", "State")
    if r.returncode == 0:
        for line in r.stdout.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                if key.strip() == "State" and value.strip():
                    return value.strip()
    return "unknown"


def _listing() -> dict:
    out = {
        "machines": [],
        "images": [],
        "machinectl": _has(MACHINECTL),
        "importctl": _has(IMPORTCTL),
        "vmspawn": _has(VMSPAWN),
    }
    if not out["machinectl"]:
        return out
    r = _run(MACHINECTL, "list", "--no-pager", "--no-legend")
    if r.returncode == 0:
        for f in _rows(r.stdout, ("MACHINE", "NAME")):
            out["machines"].append(
                {
                    "name": f[0],
                    "class": f[1] if len(f) > 1 else "",
                    "service": f[2] if len(f) > 2 else "",
                    "state": _state(f[0]),
                }
            )
    r = _run(MACHINECTL, "list-images", "--no-pager", "--no-legend")
    if r.returncode == 0:
        for f in _rows(r.stdout, ("NAME", "MACHINE")):
            out["images"].append(
                {
                    "name": f[0],
                    "type": f[1] if len(f) > 1 else "",
                    "size": f[2] if len(f) > 2 else "",
                    "created": f[3] if len(f) > 3 else "",
                }
            )
    return out


def _act(verb: str, names: list[str]) -> dict:
    if not names or not all(NAME.match(n) for n in names):
        return {"error": "not a machine or image name"}
    r = _run(MACHINECTL, verb, *names, timeout=120)
    return {"ok": True} if r.returncode == 0 else _err(r, "machinectl %s failed" % verb)


def _shell(name: str) -> dict:
    if not NAME.match(name):
        return {"error": "not a machine name"}
    return {
        "argv": [
            "xdg-terminal-exec",
            "sudo",
            MACHINECTL[0] if MACHINECTL else "machinectl",
            "shell",
            name,
            "/bin/bash",
        ]
    }


def _stream_pull(url: str, name: str, kind: str) -> int:
    p = subprocess.Popen(
        IMPORTCTL + ["pull-" + kind, url, name],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    last = ""
    for raw in p.stdout:
        for line in raw.replace("\r", "\n").splitlines():
            line = line.strip()
            if line:
                last = line
                print(json.dumps({"line": line[:200]}), flush=True)
    rc = p.wait()
    print(
        json.dumps({"ok": True} if rc == 0 else {"error": last or "importctl failed"}),
        flush=True,
    )
    return 0 if rc == 0 else 1


def _vmspawn_boot(path: str) -> dict:
    if os.path.splitext(path)[1].lower() not in DISK or not os.path.isfile(path):
        return {"error": "not an image file: %s" % path}
    return {
        "argv": [
            "xdg-terminal-exec",
            VMSPAWN[0] if VMSPAWN else "systemd-vmspawn",
            "--image",
            path,
        ]
    }


def run(cmd: str, args: list[str]) -> int:
    try:
        if cmd == "machines-list" and not args:
            r = _listing()
        elif cmd in _ACTIONS and len(args) == _ACTIONS[cmd][1]:
            r = _act(_ACTIONS[cmd][0], args)
        elif cmd == "machine-shell" and len(args) == 1:
            r = _shell(args[0])
        elif cmd == "machine-image-pull" and len(args) == 3:
            url, name, kind = args
            if not URL.match(url) or not NAME.match(name) or kind not in ("tar", "raw"):
                r = {"error": "an http(s) URL, a name, and tar or raw"}
            else:
                return _stream_pull(url, name, kind)
        elif cmd == "vmspawn-boot" and len(args) == 1:
            r = _vmspawn_boot(args[0])
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
