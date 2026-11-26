#!/usr/bin/env python3
"""Extra toolbox (Distrobox) flows for the Containers window: install a package
file with the distro's own tool, copy a toolbox, create one with home/GPU/start-up
choices, and read its details. Wired into bridge/containers.py; each command
prints its own JSON (progress lines for the long ones) and returns 0 or 1.
SHANI_PODMAN / SHANI_DISTROBOX point at the tools (tests).
"""

from __future__ import annotations

import datetime
import json
import os
import re
import shlex
import subprocess
import sys

COMMANDS = ("box-install", "box-clone", "box-create-options", "box-details")

PODMAN = shlex.split(os.environ.get("SHANI_PODMAN", "podman"))
DISTROBOX = shlex.split(os.environ.get("SHANI_DISTROBOX", "distrobox"))
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
IMAGE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,200}$")


def _run(cmd, *args, timeout=60):
    return subprocess.run(
        cmd + list(args), check=False, capture_output=True, text=True, timeout=timeout
    )


def _json(cmd, *args):
    r = _run(cmd, *args)
    try:
        return json.loads(r.stdout or "[]")
    except ValueError:
        return []


def _inspect(name):
    d = _json(PODMAN, "inspect", name)
    return d[0] if isinstance(d, list) and d and isinstance(d[0], dict) else {}


def _note(line):
    print(json.dumps({"line": line[:200]}), flush=True)


def _stream(cmd):
    """Run with progress as JSON lines; return (status, last line)."""
    p = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
    )
    last = ""
    for raw in p.stdout:
        for line in raw.replace("\r", "\n").splitlines():
            line = line.strip()
            if line:
                last = line
                _note(line)
    return p.wait(), last


def _finish(rc, last=""):
    ok = rc == 0
    print(
        json.dumps({"ok": True} if ok else {"error": last or "not completed"}),
        flush=True,
    )
    return 0 if ok else 1


def _error(text):
    print(json.dumps({"error": text}), flush=True)
    return 1


def _tool(image):
    s = (image or "").lower()
    if "fedora" in s:
        return ["sudo", "dnf", "install", "-y"]
    if "arch" in s:
        return ["sudo", "pacman", "-U", "--noconfirm"]
    return ["sudo", "apt", "install", "-y"]  # Debian, Ubuntu and anything else


def _distro(image):
    s = (image or "").lower()
    for key, label in (
        ("ubuntu", "Ubuntu"),
        ("debian", "Debian"),
        ("fedora", "Fedora"),
        ("arch", "Arch Linux"),
        ("alpine", "Alpine"),
    ):
        if key in s:
            return label
    return image or ""


def _date(value):
    try:
        when = float(value)
    except (TypeError, ValueError):
        return str(value or "")
    try:
        return datetime.datetime.fromtimestamp(when, datetime.timezone.utc).strftime(
            "%Y-%m-%d %H:%M UTC"
        )
    except (ValueError, OverflowError, OSError):
        return str(value)


def box_install(box, path):
    if not NAME.match(box):
        return _error("not a toolbox name")
    if not os.path.isfile(path) or not path.lower().endswith((".deb", ".rpm")):
        return _error("not a package file")
    image = _inspect(box).get("Image", "")
    file = path if os.path.isabs(path) else "./" + path  # one argv, never expanded
    rc, last = _stream(DISTROBOX + ["enter", box, "--"] + _tool(image) + [file])
    return _finish(rc, last)


def box_clone(box, new):
    if not NAME.match(box) or not NAME.match(new):
        return _error("not a toolbox name")
    image = _inspect(box).get("Image", "")
    _note("Copying " + box)
    rc, last = _stream(DISTROBOX + ["clone", box, new])
    if rc != 0:  # distrobox without clone: make the same box from its image
        _note("Making a new toolbox instead")
        rc, last = _stream(
            DISTROBOX + ["create", "--yes", "--name", new, "--image", image]
        )
    return _finish(rc, last)


def box_create_options(name, image, flags):
    if not NAME.match(name) or not IMAGE.match(image):
        return _error("a name of letters, digits, - and _; and an image")
    home = nvidia = False
    hooks = None
    for flag in flags:
        if flag == "home":
            home = True
        elif flag == "nvidia":
            nvidia = True
        elif flag.startswith("hooks="):
            hooks = flag.split("=", 1)[1]
        else:
            return _error("not a toolbox option: " + flag)
    cmd = DISTROBOX + ["create", "--yes", "--name", name, "--image", image]
    if home:
        cmd += ["--home", os.path.join(os.path.expanduser("~"), name)]
    if nvidia:
        cmd += ["--nvidia"]
    if hooks is not None:
        cmd += ["--init-hooks", hooks]
    rc, last = _stream(cmd)
    return _finish(rc, last)


def box_details(name):
    if not NAME.match(name):
        return _error("not a toolbox name")
    info = _inspect(name)
    image = info.get("Image", "")
    state = info.get("State", "")
    if isinstance(state, dict):
        state = state.get("Status", "")
    size = 0
    for im in _json(PODMAN, "images", "--format", "json"):
        tags = im.get("Names") or im.get("RepoTags") or []
        if image and image in tags:
            try:
                size = int(im.get("Size") or 0)
            except (TypeError, ValueError):
                size = 0
            break
    print(
        json.dumps(
            {
                "image": image,
                "distro": _distro(image),
                "size": size,
                "created": _date(info.get("Created")),
                "state": str(state).lower(),
            }
        ),
        flush=True,
    )
    return 0


def run(cmd: str, args: list[str]) -> int:
    try:
        if cmd == "box-install" and len(args) == 2:
            return box_install(*args)
        if cmd == "box-clone" and len(args) == 2:
            return box_clone(*args)
        if cmd == "box-create-options" and len(args) >= 2:
            return box_create_options(args[0], args[1], args[2:])
        if cmd == "box-details" and len(args) == 1:
            return box_details(args[0])
    except (OSError, subprocess.TimeoutExpired) as e:
        return _error(str(e))
    return _error("not a toolbox command")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(_error("no toolbox command"))
    sys.exit(run(sys.argv[1], sys.argv[2:]))
