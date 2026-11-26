#!/usr/bin/env python3
"""LXD/LXC flows for the Containers window, kept apart from containers.py so
neither bridge imports the other. Every command prints its own JSON: one object,
or streamed {"line": ...} objects followed by {"ok": True}/{"error": ...}.

    lxd-list                  instances and whether LXD is initialised
    lxd-init                  lxd init --auto progress, streamed
    lxd-launch IMAGE NAME     launch a container from a remote:image
    lxd-start|lxd-stop|lxd-restart|lxd-delete NAME
    lxd-shell NAME            argv for xdg-terminal-exec, not launched here

`lxc list --format json` is parsed when LXD is initialised; a non-zero status
means the daemon is not set up yet, which the window shows as an empty list with
ready False, not as an error. A shell and all state changes run lxc with a plain
argument list (no shell), with names and images checked first.

SHANI_LXC and SHANI_LXD override the executables (stand-ins in tests).
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

LXC = shlex.split(os.environ.get("SHANI_LXC", "lxc"))
LXD = shlex.split(os.environ.get("SHANI_LXD", "lxd"))
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
IMAGE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,200}$")

COMMANDS = (
    "lxd-list",
    "lxd-init",
    "lxd-launch",
    "lxd-start",
    "lxd-stop",
    "lxd-restart",
    "lxd-delete",
    "lxd-shell",
)

_ACTIONS = {
    "lxd-start": "start",
    "lxd-stop": "stop",
    "lxd-restart": "restart",
}


def _has(cmd) -> bool:
    # A stand-in can be an absolute path that is not on PATH.
    return bool(cmd) and bool(shutil.which(cmd[0]) or os.path.exists(cmd[0]))


def _run(cmd, *args, timeout=60):
    return subprocess.run(
        cmd + list(args), capture_output=True, text=True, timeout=timeout
    )


def _err(r, fallback):
    return {"error": (r.stderr.strip().splitlines() or [fallback])[-1]}


def _stream(args) -> int:
    p = subprocess.Popen(
        LXD + args,
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
        json.dumps({"ok": True} if rc == 0 else {"error": last or "lxd init failed"}),
        flush=True,
    )
    return 0 if rc == 0 else 1


def _listing() -> dict:
    out = {"instances": [], "ready": False, "hasLxc": _has(LXC)}
    r = _run(LXC, "list", "--format", "json")
    if r.returncode != 0:
        return out
    try:
        rows = json.loads(r.stdout or "[]")
    except ValueError:
        return out
    if not isinstance(rows, list):
        return out
    out["instances"] = [
        {
            "name": x.get("name", ""),
            "status": x.get("status", ""),
            "image": x.get("image", ""),
            "type": x.get("type", ""),
            "address": x.get("address", ""),
        }
        for x in rows
        if isinstance(x, dict)
    ]
    out["ready"] = True
    return out


def _launch(image: str, name: str) -> dict:
    if not IMAGE.match(image) or not NAME.match(name):
        return {"error": "a remote:image and a name of letters, digits, - and _"}
    rr = _run(LXC, "launch", image, name, timeout=180)
    return {"ok": True} if rr.returncode == 0 else _err(rr, "not launched")


def _act(verb: str, name: str, tail=()) -> dict:
    if not NAME.match(name):
        return {"error": "not an instance name"}
    rr = _run(LXC, verb, name, *tail, timeout=120)
    return {"ok": True} if rr.returncode == 0 else _err(rr, "lxc %s failed" % verb)


def _shell(name: str) -> dict:
    if not NAME.match(name):
        return {"error": "not an instance name"}
    return {
        "argv": [
            "xdg-terminal-exec",
            LXC[0] if LXC else "lxc",
            "exec",
            name,
            "--",
            "bash",
        ]
    }


def run(cmd: str, args: list[str]) -> int:
    try:
        if cmd == "lxd-list" and not args:
            r = _listing()
        elif cmd == "lxd-init" and not args:
            return _stream(["init", "--auto"])
        elif cmd == "lxd-launch" and len(args) == 2:
            r = _launch(args[0], args[1])
        elif cmd in _ACTIONS and len(args) == 1:
            r = _act(_ACTIONS[cmd], args[0])
        elif cmd == "lxd-delete" and len(args) == 1:
            r = _act("delete", args[0], ("--force",))
        elif cmd == "lxd-shell" and len(args) == 1:
            r = _shell(args[0])
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
