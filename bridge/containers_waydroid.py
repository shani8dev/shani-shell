#!/usr/bin/env python3
"""Waydroid/Android flows for the Containers window, kept apart from
containers.py so neither bridge imports the other. Every command prints its own
JSON: one object, or streamed {"line": ...} objects followed by {"ok": True}.

    waydroid-status              availability, helper, initialised, session
    waydroid-start|waydroid-stop start or stop the session
    waydroid-ui                  argv for the full Android UI, not launched here
    waydroid-init                waydroid-helper init through pkexec, streamed

`waydroid status` reports the session on a line starting "Status:" and the
fresh-install state with "not initialized". A missing or failing waydroid
command yields available False, never an error. Setup needs root, so init runs
the helper through pkexec; an empty SHANI_PKEXEC runs the helper directly (tests).

SHANI_WAYDROID, SHANI_WAYDROID_HELPER and SHANI_PKEXEC override the executables
(stand-ins in tests). All calls use a plain argument list, never a shell.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys

WAYDROID = shlex.split(os.environ.get("SHANI_WAYDROID", "waydroid"))
HELPER = shlex.split(os.environ.get("SHANI_WAYDROID_HELPER", "waydroid-helper"))
PKEXEC = shlex.split(os.environ.get("SHANI_PKEXEC", "pkexec"))

COMMANDS = (
    "waydroid-status",
    "waydroid-start",
    "waydroid-stop",
    "waydroid-ui",
    "waydroid-init",
)

_ACTIONS = {
    "waydroid-start": "start",
    "waydroid-stop": "stop",
}


def _has(cmd) -> bool:
    # A stand-in can be an absolute path that is not on PATH.
    return bool(cmd) and bool(shutil.which(cmd[0]) or os.path.exists(cmd[0]))


def _run(cmd, *args, timeout=60):
    return subprocess.run(
        cmd + list(args), capture_output=True, text=True, timeout=timeout
    )


def _status() -> dict:
    out = {
        "available": False,
        "helper": _has(HELPER),
        "initialised": False,
        "session": "unknown",
    }
    try:
        r = _run(WAYDROID, "status")
    except OSError:
        return out  # missing executable is not an error
    if r.returncode != 0:
        return out
    out["available"] = True
    text = r.stdout.lower()
    for line in r.stdout.splitlines():
        if line.startswith("Status:"):
            session = line[len("Status:") :].strip()
            if session:
                out["session"] = session
            break
    out["initialised"] = "not initialized" not in text
    return out


def _act(verb: str) -> dict:
    r = _run(WAYDROID, "session", verb)
    return (
        {"ok": True}
        if r.returncode == 0
        else {"error": "waydroid session %s failed" % verb}
    )


def _stream_init() -> int:
    cmd = PKEXEC + HELPER + ["init"]
    p = subprocess.Popen(
        cmd,
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
        json.dumps(
            {"ok": True} if rc == 0 else {"error": last or "waydroid init failed"}
        ),
        flush=True,
    )
    return 0 if rc == 0 else 1


def run(cmd: str, args: list[str]) -> int:
    try:
        if cmd == "waydroid-status" and not args:
            r = _status()
        elif cmd in _ACTIONS and not args:
            r = _act(_ACTIONS[cmd])
        elif cmd == "waydroid-ui" and not args:
            r = {"argv": ["waydroid", "show-full-ui"]}
        elif cmd == "waydroid-init" and not args:
            if not _has(HELPER):
                r = {"error": "the Waydroid setup helper is not installed"}
            else:
                return _stream_init()
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
