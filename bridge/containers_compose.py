#!/usr/bin/env python3
"""Compose folders and user Quadlet services for the Containers window.

Standalone bridge: every command prints its own JSON, either one object or a
stream of {"line": ...} objects followed by {"ok": True}/{"error": ...}.

    compose-up|compose-down|compose-logs FOLDER
    service-create NAME IMAGE [--ports P] [--volumes V] [--env E] [--gpu]
    service-status NAME
    service-remove NAME

SHANI_COMPOSE, SHANI_SYSTEMCTL and SHANI_QUADLET_DIR override the executables
and the unit directory. Podlet, when found on PATH, is only reported as
hasPodlet by service-status; it is never required.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

COMPOSE = shlex.split(os.environ.get("SHANI_COMPOSE", "podman-compose"))
SYSTEMCTL = shlex.split(os.environ.get("SHANI_SYSTEMCTL", "systemctl"))
QUADLET_DIR = os.environ.get(
    "SHANI_QUADLET_DIR", os.path.expanduser("~/.config/containers/systemd")
)

COMMANDS = (
    "compose-up",
    "compose-down",
    "compose-logs",
    "service-create",
    "service-status",
    "service-remove",
)

_COMPOSE_FILES = (
    "compose.yaml",
    "compose.yml",
    "docker-compose.yml",
    "docker-compose.yaml",
)
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
IMAGE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,200}$")
_PORT = re.compile(r"^[A-Za-z0-9._:-]+$")
_PATH = re.compile(r"^(?:[A-Za-z0-9][A-Za-z0-9_.-]*|/[A-Za-z0-9_./@+-]*)$")
_ENV = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=[^\s,;]*$")


def _run(cmd, *args, timeout=60):
    return subprocess.run(
        cmd + list(args), capture_output=True, text=True, timeout=timeout
    )


def _err(r, fallback):
    return {"error": (r.stderr.strip().splitlines() or [fallback])[-1]}


def _stream(cmd) -> int:
    p = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
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
        json.dumps({"ok": True} if rc == 0 else {"error": last or "failed"}), flush=True
    )
    return 0 if rc == 0 else 1


def _compose_file(folder):
    if not os.path.isdir(folder):
        return None, {"error": "not a folder: %s" % folder}
    for name in _COMPOSE_FILES:
        path = os.path.join(folder, name)
        if os.path.isfile(path):
            return path, None
    return None, {"error": "no compose file in %s" % folder}


def _service_create(args: list[str]):
    if len(args) < 2:
        return {"error": "service-create needs a name and an image"}
    name, image = args[0], args[1]
    if not NAME.match(name) or not IMAGE.match(image):
        return {"error": "a name of letters, digits, - and _; and an image"}
    tail = list(args[2:])
    opts = {}
    bad = None
    while tail:
        k = tail.pop(0)
        if k == "--gpu":
            opts[k] = "yes"
            continue
        if k not in ("--ports", "--volumes", "--env") or not tail:
            bad = "create options: --ports --volumes --env --gpu"
            break
        opts[k] = tail.pop(0)
    ports = [p for p in opts.get("--ports", "").split(",") if p]
    vols = [v for v in opts.get("--volumes", "").split(",") if v]
    envs = [e for e in opts.get("--env", "").split(",") if e]
    if any(not _PORT.match(p) for p in ports):
        bad = "not a port"
    for v in vols:
        bits = v.split(":")
        if len(bits) < 2 or len(bits) > 3 or not all(_PATH.match(b) for b in bits):
            bad = "not a volume: %s" % v
    if any(not _ENV.match(e) for e in envs):
        bad = "not an environment value"
    if bad:
        return {"error": bad}

    try:
        os.makedirs(QUADLET_DIR, exist_ok=True)
        path = os.path.join(QUADLET_DIR, name + ".container")
        lines = [
            "[Container]",
            "Image=" + image,
            "ContainerName=" + name,
            "AutoUpdate=registry",
        ]
        lines += ["PublishPort=" + p for p in ports]
        lines += ["Volume=" + v for v in vols]
        lines += ["Environment=" + e for e in envs]
        if opts.get("--gpu"):
            lines += ["Device=nvidia.com/gpu=all", "SecurityOpt=label=disable"]
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
    except OSError as e:
        return {"error": str(e)}
    print(json.dumps({"line": "Wrote %s.container" % name}), flush=True)

    rr = _run(SYSTEMCTL, "--user", "daemon-reload")
    if rr.returncode != 0:
        return _err(rr, "not reloaded")
    print(json.dumps({"line": "Reloaded user services"}), flush=True)
    rr = _run(SYSTEMCTL, "--user", "start", name + ".service")
    if rr.returncode != 0:
        return _err(rr, "not started")
    print(json.dumps({"line": "Started %s.service" % name}), flush=True)
    return {"ok": True}


def _service_status(name: str):
    if not NAME.match(name):
        return {"error": "not a service name"}
    rr = _run(
        SYSTEMCTL,
        "--user",
        "show",
        "-p",
        "ActiveState",
        "-p",
        "SubState",
        "-p",
        "Description",
        name + ".service",
    )
    props = {}
    for line in rr.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            props[k] = v
    return {
        "active": props.get("ActiveState") == "active",
        "sub": props.get("SubState", ""),
        "description": props.get("Description", ""),
        "hasPodlet": bool(shutil.which("podlet")),
    }


def _service_remove(name: str):
    if not NAME.match(name):
        return {"error": "not a service name"}
    path = os.path.join(QUADLET_DIR, name + ".container")
    if not os.path.isfile(path):
        return {"error": "no service: %s" % name}
    rr = _run(SYSTEMCTL, "--user", "stop", name + ".service")
    if rr.returncode != 0:
        return _err(rr, "not stopped")
    try:
        os.remove(path)
    except OSError as e:
        return {"error": str(e)}
    rr = _run(SYSTEMCTL, "--user", "daemon-reload")
    return {"ok": True} if rr.returncode == 0 else _err(rr, "not reloaded")


def run(cmd: str, args: list[str]) -> int:
    try:
        if cmd in ("compose-up", "compose-down", "compose-logs") and len(args) == 1:
            f, err = _compose_file(args[0])
            if err:
                r = err
            else:
                verb = {
                    "compose-up": ["up", "-d"],
                    "compose-down": ["down"],
                    "compose-logs": ["logs"],
                }[cmd]
                return _stream(COMPOSE + ["-f", f] + verb)
        elif cmd == "service-create":
            r = _service_create(args)
        elif cmd == "service-status" and len(args) == 1:
            r = _service_status(args[0])
        elif cmd == "service-remove" and len(args) == 1:
            r = _service_remove(args[0])
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
