#!/usr/bin/env python3
"""Apptainer (.sif image) flows for the Containers window, kept apart from
containers.py so neither bridge imports the other. Every command prints its own
JSON: one object, or streamed {"line": ...} objects followed by {"ok": True}.

    apptainer-list FOLDER       .sif images in a folder picked in the UI
    apptainer-pull REF NAME [FOLDER]  pull into FOLDER (default ~/Apptainer)
    apptainer-run FILE          argv for xdg-terminal-exec, not launched here
    apptainer-shell FILE        same, with "shell"
    apptainer-remove FILE       delete a .sif from the image folder

SHANI_APPTAINER overrides the executable. FAKE_APPTAINER names the stand-in's
image folder. The default image folder is ~/Apptainer; callers pass the folder
explicitly because the UI picks it. Standard library only.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

APPTAINER = shlex.split(os.environ.get("SHANI_APPTAINER", "apptainer"))
DEFAULT_FOLDER = os.path.expanduser("~/Apptainer")
REF = re.compile(r"^(?:docker|oras)://\S+$")
NAME = re.compile(r"^[A-Za-z0-9._-]+$")

COMMANDS = (
    "apptainer-list",
    "apptainer-pull",
    "apptainer-run",
    "apptainer-shell",
    "apptainer-remove",
)


def _has(cmd) -> bool:
    # A stand-in can be an absolute path that is not on PATH.
    return bool(shutil.which(cmd[0]) or os.path.exists(cmd[0]))


def _list(folder: str) -> dict:
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        names = []
    images = []
    for n in names:
        if not n.endswith(".sif"):
            continue
        path = os.path.join(folder, n)
        if not os.path.isfile(path):
            continue
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        images.append({"name": n, "path": path, "size": size})
    return {"images": images, "hasApptainer": _has(APPTAINER)}


def _stream_pull(ref: str, name: str, folder: str) -> int:
    p = subprocess.Popen(
        APPTAINER + ["pull", "--name", name + ".sif", ref],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        cwd=folder if os.path.isdir(folder) else None,
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
        json.dumps({"ok": True} if rc == 0 else {"error": last or "pull failed"}),
        flush=True,
    )
    return 0 if rc == 0 else 1


def _argv(verb: str, path: str) -> dict:
    if not os.path.isfile(path) or not path.lower().endswith(".sif"):
        return {"error": "not an image file: %s" % path}
    exe = APPTAINER[0] if APPTAINER else "apptainer"
    return {"argv": ["xdg-terminal-exec", exe, verb, path]}


def _inside(path: str, root: str) -> bool:
    try:
        real = os.path.realpath(root)
        return os.path.commonpath([os.path.realpath(path), real]) == real
    except ValueError:
        return False


def _remove(path: str) -> dict:
    if not path.lower().endswith(".sif"):
        return {"error": "not an image file: %s" % path}
    roots = [DEFAULT_FOLDER]
    fake = os.environ.get("FAKE_APPTAINER")
    if fake:
        roots.append(fake)
    if not any(_inside(path, root) for root in roots):
        return {"error": "not inside the image folder: %s" % path}
    os.remove(path)
    return {"ok": True}


def run(cmd: str, args: list[str]) -> int:
    try:
        if cmd == "apptainer-list" and len(args) == 1:
            r = _list(args[0])
        elif cmd == "apptainer-pull" and len(args) in (2, 3):
            ref, name = args[:2]
            folder = args[2] if len(args) == 3 else DEFAULT_FOLDER
            if not REF.match(ref):
                r = {"error": "a docker:// or oras:// reference"}
            elif not NAME.match(name) or name in (".", ".."):
                r = {"error": "not an image name"}
            else:
                return _stream_pull(ref, name, folder)
        elif cmd in ("apptainer-run", "apptainer-shell") and len(args) == 1:
            r = _argv("run" if cmd == "apptainer-run" else "shell", args[0])
        elif cmd == "apptainer-remove" and len(args) == 1:
            r = _remove(args[0])
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
