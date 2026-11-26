#!/usr/bin/env python3
"""Podman-only flows for the Containers window, kept apart from containers.py so
neither bridge imports the other. Every command prints its own JSON: one object or
list, or streamed {"line": ...} objects followed by {"ok": True}/{"error": ...}.

    container-run NAME IMAGE [--ports P] [--volumes V] [--env E] [--command C] [--gpu]
    gpu-status                 whether a CDI spec lets Podman use the graphics card
    container-shell NAME       argv for xdg-terminal-exec, not launched here
    logs-follow NAME           stream podman logs --follow
    container-pause|container-resume|container-kill NAME
    container-rename NAME NEW / container-commit NAME IMAGE
    container-stats NAME / container-inspect NAME
    image-search TERM / image-pull IMAGE
    image-build TAG PATH dir|file        stream a build from a Dockerfile or folder
    container-files NAME [PATH]          dir listing inside a running container
    container-file-copy NAME SRC DEST    podman cp SRC out to a host path
    pod-list / pod-start|pod-stop|pod-remove NAME
    volume-list / volume-create|volume-remove NAME / volume-prune

SHANI_PODMAN overrides the executable (a stand-in in tests).
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys

PODMAN = shlex.split(os.environ.get("SHANI_PODMAN", "podman"))
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
IMAGE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,200}$")

COMMANDS = (
    "container-run",
    "container-shell",
    "logs-follow",
    "container-pause",
    "container-resume",
    "container-kill",
    "container-rename",
    "container-commit",
    "container-stats",
    "container-inspect",
    "image-search",
    "image-pull",
    "image-build",
    "container-files",
    "container-file-copy",
    "pod-list",
    "pod-start",
    "pod-stop",
    "pod-remove",
    "volume-list",
    "volume-create",
    "volume-remove",
    "volume-prune",
    "gpu-status",
)

CDI_DIR = os.environ.get("SHANI_CDI_DIR", "/etc/cdi")

_PORT = re.compile(r"^[A-Za-z0-9._:-]+$")
_PATH = re.compile(r"^(?:[A-Za-z0-9][A-Za-z0-9_.-]*|/[A-Za-z0-9_./@+-]*)$")
_ENV = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=[^\s,;]*$")
_PATHARG = re.compile(r"^/(?:[A-Za-z0-9_ .@+,=-]+/?)*$")
_SHELLS = ("ubuntu", "debian", "fedora", "arch")


def _run(cmd, *args, timeout=60):
    return subprocess.run(
        cmd + list(args), capture_output=True, text=True, timeout=timeout
    )


def _err(r, fallback):
    return {"error": (r.stderr.strip().splitlines() or [fallback])[-1]}


def _stream(args) -> int:
    p = subprocess.Popen(
        PODMAN + args,
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
        json.dumps({"ok": True} if rc == 0 else {"error": last or "failed"}), flush=True
    )
    return 0 if rc == 0 else 1


def _json(r, fallback):
    try:
        return json.loads(r.stdout or fallback)
    except ValueError:
        return json.loads(fallback)


def _gpu_status() -> dict:
    try:
        cdi = any(f.endswith((".yaml", ".yml")) for f in os.listdir(CDI_DIR))
    except OSError:
        cdi = False
    return {"cdi": cdi, "directory": CDI_DIR}


def _container_run(args: list[str]):
    if len(args) < 2:
        return {"error": "container-run needs a name and an image"}
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
        if k not in ("--ports", "--volumes", "--env", "--command") or not tail:
            bad = "run options: --ports --volumes --env --command --gpu"
            break
        opts[k] = tail.pop(0)
    ports = [p for p in opts.get("--ports", "").split(",") if p]
    vols = [v for v in opts.get("--volumes", "").split(",") if v]
    envs = [e for e in opts.get("--env", "").split(",") if e]
    for p in ports:
        if not _PORT.match(p):
            bad = "not a port: %s" % p
    for v in vols:
        bits = v.split(":")
        if len(bits) < 2 or len(bits) > 3 or not all(_PATH.match(b) for b in bits):
            bad = "not a volume: %s" % v
    for e in envs:
        if not _ENV.match(e):
            bad = "not an environment value: %s" % e
    try:
        cmdtail = shlex.split(opts.get("--command", ""))
    except ValueError:
        return {"error": "not a command"}
    if bad:
        return {"error": bad}
    if opts.get("--gpu") and not _gpu_status()["cdi"]:
        return {
            "error": "The graphics card needs a CDI spec at %s/nvidia.yaml; "
            "nvidia-container-toolkit is not in the image. Use a toolbox with "
            "the graphics card instead." % CDI_DIR
        }
    av = ["run", "-d", "--name", name]
    if opts.get("--gpu"):
        av += ["--device", "nvidia.com/gpu=all", "--security-opt", "label=disable"]
    for p in ports:
        av += ["-p", p]
    for v in vols:
        av += ["-v", v]
    for e in envs:
        av += ["-e", e]
    rr = _run(PODMAN, *(av + [image] + cmdtail), timeout=180)
    return {"ok": True} if rr.returncode == 0 else _err(rr, "not run")


def _container_shell(name: str):
    if not NAME.match(name):
        return {"error": "not a container name"}
    rr = _run(PODMAN, "inspect", name)
    try:
        docs = json.loads(rr.stdout or "[]")
    except ValueError:
        docs = []
    image = str((docs[0] if docs else {}).get("Image", "")).lower()
    shell = "bash" if any(s in image for s in _SHELLS) else "sh"
    return {
        "argv": [
            "xdg-terminal-exec",
            PODMAN[0] if PODMAN else "podman",
            "exec",
            "-it",
            name,
            shell,
        ]
    }


def _container_inspect(name: str):
    rr = _run(PODMAN, "inspect", name)
    if rr.returncode != 0:
        return _err(rr, "not inspected")
    docs = _json(rr, "[]")
    d = docs[0] if docs else {}
    cfg = d.get("Config") or {}
    cmd = cfg.get("Cmd") or d.get("Cmd") or []
    cmd = " ".join(str(x) for x in cmd) if isinstance(cmd, list) else str(cmd)
    ports = d.get("Ports") or []
    if not ports:
        nd = (d.get("NetworkSettings") or {}).get("Ports") or {}
        ports = [
            {"HostPort": (v[0] or {}).get("HostPort"), "ContainerPort": k.split("/")[0]}
            for k, v in nd.items()
            if v
        ]
    portstr = ", ".join(
        "%s→%s" % (p.get("HostPort"), p.get("ContainerPort"))
        for p in ports
        if p.get("HostPort")
    )
    mounts = ", ".join(
        "%s→%s" % (m.get("Source"), m.get("Destination"))
        for m in (d.get("Mounts") or [])
        if m.get("Source")
    )
    state = d.get("State") or {}
    state = state.get("Status", "") if isinstance(state, dict) else state
    return {
        "name": (d.get("Name") or "").lstrip("/"),
        "id": (d.get("Id") or "")[:12],
        "state": state,
        "image": d.get("Image", ""),
        "created": d.get("Created", 0),
        "command": cmd,
        "ports": portstr,
        "mounts": mounts,
    }


def _container_stats(name: str):
    rr = _run(
        PODMAN,
        "stats",
        "--no-stream",
        "--format",
        "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}",
        name,
    )
    if rr.returncode != 0:
        return _err(rr, "no stats")
    line = next((l for l in rr.stdout.splitlines() if "|" in l), "")
    fields = [f.strip() for f in line.split("|")]
    if len(fields) >= 3:
        return {"cpu": fields[1], "mem": fields[2]}
    if len(fields) == 2:
        return {"cpu": fields[0], "mem": fields[1]}
    return {"error": "no stats"}


def _image_search(term: str):
    rr = _run(PODMAN, "search", "--format", "json", "--limit", "8", term)
    if rr.returncode != 0:
        return _err(rr, "not searched")
    rows = _json(rr, "[]")
    out = [
        {
            "name": x.get("name") or x.get("Name", ""),
            "description": x.get("description") or x.get("Description", ""),
            "stars": x.get("stars", 0),
            "official": bool(x.get("official", False)),
        }
        for x in rows
    ]
    out.sort(key=lambda x: (not x["official"], -x["stars"]))
    return out


def _pod_list():
    rr = _run(PODMAN, "pod", "ps", "--format", "json")
    if rr.returncode != 0:
        return _err(rr, "no pods")
    pods = _json(rr, "[]")
    return {
        "pods": [
            {
                "name": p.get("Name", ""),
                "status": p.get("Status", ""),
                "containers": p.get("Containers", 0),
                "created": p.get("Created", 0),
            }
            for p in pods
        ]
    }


def _volume_list():
    rr = _run(PODMAN, "volume", "ls", "--format", "json")
    if rr.returncode != 0:
        return _err(rr, "no volumes")
    vols = _json(rr, "[]")
    return {
        "volumes": [
            {
                "name": v.get("Name", ""),
                "driver": v.get("Driver", ""),
                "size": v.get("Size", 0),
                "created": v.get("Created", 0),
            }
            for v in vols
        ]
    }


def _act(verb, name: str, timeout=120):
    if not NAME.match(name):
        return {"error": "not a name"}
    rr = _run(PODMAN, *verb, name, timeout=timeout)
    return (
        {"ok": True} if rr.returncode == 0 else _err(rr, "podman %s failed" % verb[0])
    )


def _container_files(name: str, path: str) -> dict:
    """A directory inside a running container, read with podman exec - no shell
    on the host and no mount of the container's filesystem needed."""
    if not NAME.match(name):
        return {"error": "not a container name"}
    if not _PATHARG.match(path):
        return {"error": "not a path"}
    rr = _run(PODMAN, "exec", name, "ls", "-lA", path)
    if rr.returncode != 0:
        return _err(rr, "not listed")
    entries = []
    for line in rr.stdout.splitlines():
        f = line.split(None, 8)  # mode links owner group size month day time name
        if len(f) < 9 or f[8] in (".", ".."):
            continue
        try:
            size = int(f[4])
        except ValueError:
            size = 0
        entries.append({"name": f[8], "dir": f[0].startswith("d"), "size": size})
    return {"path": path, "entries": entries}


def _container_file_copy(name: str, src: str, dest: str) -> dict:
    if not NAME.match(name) or not _PATHARG.match(src):
        return {"error": "not a container name or path"}
    if not _PATHARG.match(dest):
        return {"error": "not a destination path"}
    rr = _run(PODMAN, "cp", "%s:%s" % (name, src), dest, timeout=120)
    return {"ok": True} if rr.returncode == 0 else _err(rr, "not copied")


def run(cmd: str, args: list[str]) -> int:
    try:
        if cmd == "container-run":
            r = _container_run(args)
        elif cmd == "container-shell" and len(args) == 1:
            r = _container_shell(args[0])
        elif cmd == "logs-follow" and len(args) == 1:
            if not NAME.match(args[0]):
                r = {"error": "not a container name"}
            else:
                return _stream(["logs", "--follow", args[0]])
        elif (
            cmd in ("container-pause", "container-resume", "container-kill")
            and len(args) == 1
        ):
            verb = {
                "container-pause": "pause",
                "container-resume": "unpause",
                "container-kill": "kill",
            }[cmd]
            r = _act([verb], args[0])
        elif cmd == "container-rename" and len(args) == 2:
            r = (
                _act(["rename", args[0]], args[1])
                if NAME.match(args[0]) and NAME.match(args[1])
                else {"error": "not a name"}
            )
        elif cmd == "container-commit" and len(args) == 2:
            if NAME.match(args[0]) and IMAGE.match(args[1]):
                rr = _run(PODMAN, "commit", args[0], args[1], timeout=180)
                r = {"ok": True} if rr.returncode == 0 else _err(rr, "not committed")
            else:
                r = {"error": "not a name or image"}
        elif cmd == "container-stats" and len(args) == 1:
            r = (
                _container_stats(args[0])
                if NAME.match(args[0])
                else {"error": "not a container name"}
            )
        elif cmd == "container-inspect" and len(args) == 1:
            r = (
                _container_inspect(args[0])
                if NAME.match(args[0])
                else {"error": "not a container name"}
            )
        elif cmd == "image-search" and len(args) == 1:
            r = (
                _image_search(args[0])
                if NAME.match(args[0]) or IMAGE.match(args[0])
                else {"error": "not a search term"}
            )
        elif cmd == "image-pull" and len(args) == 1:
            if not IMAGE.match(args[0]):
                r = {"error": "not an image"}
            else:
                return _stream(["pull", args[0]])
        elif cmd == "image-build" and len(args) == 3:
            tag, path, kind = args
            if not IMAGE.match(tag):
                r = {"error": "not an image tag"}
            elif not _PATHARG.match(path):
                r = {"error": "not a path"}
            elif kind == "dir":
                return _stream(["build", "-t", tag, path])
            elif kind == "file":
                return _stream(
                    ["build", "-t", tag, "-f", path, os.path.dirname(path) or "."]
                )
            else:
                r = {"error": "not a source kind"}
        elif cmd == "container-files" and len(args) in (1, 2):
            r = _container_files(args[0], args[1] if len(args) == 2 else "/")
        elif cmd == "container-file-copy" and len(args) == 3:
            r = _container_file_copy(*args)
        elif cmd == "pod-list":
            r = _pod_list()
        elif cmd in ("pod-start", "pod-stop", "pod-remove") and len(args) == 1:
            verb = {
                "pod-start": ["pod", "start"],
                "pod-stop": ["pod", "stop"],
                "pod-remove": ["pod", "rm", "-f"],
            }[cmd]
            r = _act(verb, args[0])
        elif cmd == "volume-list":
            r = _volume_list()
        elif cmd == "volume-create" and len(args) == 1:
            r = (
                _act(["volume", "create"], args[0])
                if NAME.match(args[0])
                else {"error": "not a name"}
            )
        elif cmd == "volume-remove" and len(args) == 1:
            r = (
                _act(["volume", "rm"], args[0])
                if NAME.match(args[0])
                else {"error": "not a name"}
            )
        elif cmd == "gpu-status":
            r = _gpu_status()
        elif cmd == "volume-prune":
            rr = _run(PODMAN, "volume", "prune", "-f", timeout=120)
            r = (
                {
                    "ok": True,
                    "removed": len([l for l in rr.stdout.splitlines() if l.strip()]),
                }
                if rr.returncode == 0
                else _err(rr, "not pruned")
            )
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
