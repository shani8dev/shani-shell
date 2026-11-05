#!/usr/bin/env python3
"""face.py - Settings' side of face sign-in (linux-hello), one JSON line out.

    face.py probe          {"installed", "camera", "on", "saved", "views"}
    face.py enroll LABEL   {"ok", "views", "message"}   (one look: center, left, ...)

linux-hello's daemon answers on a Unix socket; it serves a request naming a
user only for root or that same user (ShaniOS' peer-check patch), so this runs
as the person, for themselves. Turning the service on or off and removing a
saved face need an administrator, and go through pkexec from the shell.

$SHANI_FACE_SOCK replaces the socket (tests); $SHANI_FACE_CAMERAS replaces
`linux-hello cameras` (its output, for a machine without the camera).
"""
from __future__ import annotations

import getpass
import json
import os
import shutil
import socket
import subprocess
import sys

SOCK = os.environ.get("SHANI_FACE_SOCK", "/run/linux-hello.sock")


def ask(request: dict, timeout: float) -> dict:
    """One request, one reply line; {} when the daemon is not there."""
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(timeout)
            s.connect(SOCK)
            s.sendall((json.dumps(request) + "\n").encode())
            data = b""
            while not data.endswith(b"\n"):
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
        return json.loads(data or b"{}")
    except (OSError, ValueError):
        return {}


def has_ir_camera() -> bool:
    out = os.environ.get("SHANI_FACE_CAMERAS")
    if out is None:
        if not shutil.which("linux-hello"):
            return False
        try:
            out = subprocess.run(["linux-hello", "cameras"], capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.TimeoutExpired):
            return False
    return "IR CAMERA" in out


def probe() -> dict:
    installed = bool(os.environ.get("SHANI_FACE_SOCK")) or shutil.which("linux-hellod") is not None
    status = ask({"action": "status"}, 3) if installed else {}
    user = getpass.getuser()
    return {
        "installed": installed,
        "camera": installed and has_ir_camera(),
        "on": bool(status),
        "saved": user in (status.get("enrolled_users") or []),
    }


def enroll(label: str) -> dict:
    reply = ask({"action": "enroll", "username": getpass.getuser(), "label": label}, 20)
    if not reply:
        return {"ok": False, "views": 0, "message": "Face sign-in is not running"}
    if reply.get("type") == "error":
        return {"ok": False, "views": 0, "message": reply.get("message", "")}
    return {"ok": bool(reply.get("success")), "views": int(reply.get("total_enrolled") or 0),
            "message": reply.get("message", "")}


def main(argv: "list[str]") -> int:
    if len(argv) >= 2 and argv[1] == "probe":
        print(json.dumps(probe()))
        return 0
    if len(argv) >= 3 and argv[1] == "enroll":
        result = enroll(argv[2])
        print(json.dumps(result))
        return 0 if result["ok"] else 1
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
