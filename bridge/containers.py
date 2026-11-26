#!/usr/bin/env python3
"""containers — the shell's Containers window (Pods' and BoxBuddy's jobs, as Ananta
Dev does them): your rootless Podman containers and images, and Distrobox
toolboxes - a whole Linux (Ubuntu, Fedora, Arch, Debian...) per project, sharing
your home folder, its apps in your menu.

    containers.py list                  {"podman", "distrobox", "containers": [{"id", "name", "image",
                                         "state", "box", "created", "ports"}], "images": [...]}
    containers.py start|stop|restart|remove <name>
    containers.py logs <name>           its last 300 lines
    containers.py image-remove <id>     an image no container uses
    containers.py prune                 images nothing uses, gone (podman image prune)
    containers.py box-create <name> <image>   prints flatpak-style progress lines, then {"ok"}
    containers.py box-apps <name>       [{"id", "name"}]: the apps inside that could join the menu
    containers.py box-export <name> <app-id>   that app in your menu (distrobox-export)
    containers.py box-unexport <name> <app-id> that app gone from your menu (--delete)
    containers.py box-upgrade <name>    its own packages updated (distrobox upgrade)
    containers.py box-remove <name>     the toolbox and what it put in the menu

    containers.py container-run <name> <image> [--ports P] [--volumes V] [--env E] [--command C] [--gpu]
    containers.py gpu-status      can a Podman container use the graphics card
    containers.py container-shell <name>       a terminal command for a shell inside
    containers.py logs-follow <name>           log lines as they arrive (JSON lines)
    containers.py container-pause|container-resume|container-kill <name>
    containers.py container-rename <name> <new> / container-commit <name> <image>
    containers.py container-stats <name> / container-inspect <name>   readable details
    containers.py image-search <term> / image-pull <image>
    containers.py pod-list / pod-start|pod-stop|pod-remove <name>
    containers.py volume-list / volume-create|volume-remove <name> / volume-prune
    containers.py box-install <box> <file> / box-clone <box> <new>
    containers.py box-create-options <name> <image> [home] [nvidia] [hooks=TEXT]
    containers.py box-details <name>
    containers.py machines-list
    containers.py machine-start|machine-poweroff|machine-reboot|machine-remove <name>
    containers.py machine-shell <name>         a terminal command for a machine shell
    containers.py machine-image-pull <url> <name> <tar|raw>
    containers.py machine-image-clone|machine-image-rename|machine-image-remove <name> [new]
    containers.py vmspawn-boot <file>          a terminal command to boot a disk image

    containers.py lxd-list / lxd-init / lxd-launch <image> <name>
    containers.py lxd-start|lxd-stop|lxd-restart|lxd-delete <name>
    containers.py lxd-shell <name>             a terminal command into a system
    containers.py apptainer-list <folder> / apptainer-pull <ref> <name> [folder]
    containers.py apptainer-run|apptainer-shell <file>   terminal commands
    containers.py apptainer-remove <file>
    containers.py virt-list / virt-start|virt-shutdown|virt-force-off|virt-reboot NAME URI
    containers.py virt-console <name> <uri> / virt-open-boxes
    containers.py virt-remove <name> <uri> / virt-remove-disks <name> <uri>
    containers.py waydroid-status / waydroid-start / waydroid-stop / waydroid-ui / waydroid-init
    containers.py compose-up|compose-down|compose-logs <folder>
    containers.py service-create <name> <image> [--ports P] [--volumes V] [--env E] [--gpu]
    containers.py service-status <name> / service-remove <name>

All as you (rootless) where possible: no administrator password for your own
containers. Opening one in a terminal is the shell's. SHANI_PODMAN, SHANI_DISTROBOX,
SHANI_MACHINECTL, SHANI_IMPORTCTL, SHANI_VMSPAWN, SHANI_LXC, SHANI_LXD,
SHANI_APPTAINER, SHANI_VIRSH, SHANI_VIRT_VIEWER, SHANI_WAYDROID,
SHANI_WAYDROID_HELPER, SHANI_COMPOSE and SHANI_SYSTEMCTL point at the tools (tests).
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

from containers_apptainer import COMMANDS as SIF_COMMANDS, run as sif_run
from containers_boxes import COMMANDS as BOX_COMMANDS, run as box_run
from containers_compose import COMMANDS as COMPOSE_COMMANDS, run as compose_run
from containers_lxd import COMMANDS as LXD_COMMANDS, run as lxd_run
from containers_machines import COMMANDS as MACHINE_COMMANDS, run as machine_run
from containers_podman import COMMANDS as POD_COMMANDS, run as pod_run
from containers_virt import COMMANDS as VIRT_COMMANDS, run as virt_run
from containers_waydroid import COMMANDS as WAYDROID_COMMANDS, run as waydroid_run

PODMAN = shlex.split(os.environ.get("SHANI_PODMAN", "podman"))
DISTROBOX = shlex.split(os.environ.get("SHANI_DISTROBOX", "distrobox"))
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
IMAGE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,200}$")


def _has(cmd) -> bool:
    return bool(shutil.which(cmd[0]))


def _run(cmd, *args, timeout=60):
    return subprocess.run(
        cmd + list(args), capture_output=True, text=True, timeout=timeout
    )


def _err(r, fallback):
    return {"error": (r.stderr.strip().splitlines() or [fallback])[-1]}


def listing() -> dict:
    out = {
        "podman": _has(PODMAN),
        "distrobox": _has(DISTROBOX),
        "containers": [],
        "images": [],
    }
    if not out["podman"]:
        return out
    r = _run(PODMAN, "ps", "-a", "--format", "json")
    try:
        cs = json.loads(r.stdout or "[]")
    except ValueError:
        cs = []
    for c in cs:
        labels = c.get("Labels") or {}
        names = c.get("Names") or [c.get("Name", "")]
        out["containers"].append(
            {
                "id": (c.get("Id") or "")[:12],
                "name": names[0] if names else "",
                "image": c.get("Image", ""),
                "state": (c.get("State") or "").lower(),
                "created": c.get("Created", 0),
                "box": labels.get("manager") == "distrobox",
                "ports": ", ".join(
                    "%s→%s" % (p.get("host_port"), p.get("container_port"))
                    for p in (c.get("Ports") or [])
                    if p.get("host_port")
                ),
            }
        )
    out["containers"].sort(key=lambda c: (not c["box"], c["name"].lower()))
    r = _run(PODMAN, "images", "--format", "json")
    try:
        ims = json.loads(r.stdout or "[]")
    except ValueError:
        ims = []
    used = {c["image"] for c in out["containers"]}
    for i in ims:
        tags = i.get("Names") or i.get("RepoTags") or []
        out["images"].append(
            {
                "id": (i.get("Id") or "")[:12],
                "name": tags[0] if tags else "<none>",
                "size": i.get("Size", 0),
                "created": i.get("Created", 0),
                "used": any(t in used for t in tags),
            }
        )
    return out


def act(verb: str, name: str) -> dict:
    if not NAME.match(name or ""):
        return {"error": "not a container name: %s" % name}
    args = {
        "start": ["start"],
        "stop": ["stop", "-t", "10"],
        "restart": ["restart"],
        "remove": ["rm", "-f"],
    }[verb]
    r = _run(PODMAN, *args, name, timeout=120)
    return {"ok": True} if r.returncode == 0 else _err(r, "podman %s failed" % verb)


def logs(name: str) -> dict:
    if not NAME.match(name or ""):
        return {"error": "not a container name"}
    r = _run(PODMAN, "logs", "--tail", "300", name)
    return {"text": (r.stdout + r.stderr)[-60000:]}


def stream(cmd) -> int:
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
    return rc


def box_apps(name: str) -> list[dict]:
    """The .desktop files inside the toolbox (read with podman exec - no distrobox
    start-up), the ones a person would open: not hidden, not NoDisplay."""
    r = _run(
        PODMAN,
        "exec",
        name,
        "sh",
        "-c",
        'for f in /usr/share/applications/*.desktop; do [ -f "$f" ] || continue; '
        'grep -qi "^NoDisplay=true" "$f" && continue; printf "%s\\t%s\\n" "${f##*/}" "$(sed -n "s/^Name=//p" "$f" | head -1)"; done',
        timeout=60,
    )
    out = []
    for line in r.stdout.splitlines():
        if "\t" in line:
            i, n = line.split("\t", 1)
            out.append({"id": i.removesuffix(".desktop"), "name": n or i})
    return sorted(out, key=lambda a: a["name"].lower())


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    try:
        if cmd == "list":
            r = listing()
        elif cmd in ("start", "stop", "restart", "remove") and len(args) == 1:
            r = act(cmd, args[0])
        elif cmd == "logs" and len(args) == 1:
            r = logs(args[0])
        elif cmd == "image-remove" and len(args) == 1:
            rr = (
                _run(PODMAN, "rmi", args[0])
                if re.match(r"^[0-9a-f]{6,64}$", args[0])
                else None
            )
            r = (
                {"ok": True}
                if rr and rr.returncode == 0
                else (_err(rr, "not removed") if rr else {"error": "not an image id"})
            )
        elif cmd == "prune":
            rr = _run(PODMAN, "image", "prune", "-f", timeout=300)
            r = (
                {
                    "ok": True,
                    "removed": len([l for l in rr.stdout.splitlines() if l.strip()]),
                }
                if rr.returncode == 0
                else _err(rr, "not pruned")
            )
        elif cmd == "box-create" and len(args) == 2:
            if not NAME.match(args[0]) or not IMAGE.match(args[1]):
                r = {"error": "a name of letters, digits, - and _; and an image"}
            else:
                return (
                    0
                    if stream(
                        DISTROBOX
                        + ["create", "--yes", "--name", args[0], "--image", args[1]]
                    )
                    == 0
                    else 1
                )
        elif cmd == "box-apps" and len(args) == 1:
            r = box_apps(args[0]) if NAME.match(args[0]) else {"error": "not a name"}
        elif cmd in ("box-export", "box-unexport") and len(args) == 2:
            if not NAME.match(args[0]) or not re.match(r"^[A-Za-z0-9_.+-]+$", args[1]):
                r = {"error": "not a name"}
            else:
                unexport = cmd == "box-unexport"
                tail = ["--delete"] if unexport else []
                rr = _run(
                    DISTROBOX,
                    "enter",
                    args[0],
                    "--",
                    "distrobox-export",
                    "--app",
                    args[1],
                    *tail,
                    timeout=300,
                )
                r = (
                    {"ok": True}
                    if rr.returncode == 0
                    else _err(
                        rr,
                        "not removed from the menu"
                        if unexport
                        else "not added to the menu",
                    )
                )
        elif cmd == "box-upgrade" and len(args) == 1:
            return (
                0
                if NAME.match(args[0]) and stream(DISTROBOX + ["upgrade", args[0]]) == 0
                else 1
            )
        elif cmd == "box-remove" and len(args) == 1:
            rr = (
                _run(DISTROBOX, "rm", "--force", args[0], timeout=180)
                if NAME.match(args[0])
                else None
            )
            r = (
                {"ok": True}
                if rr and rr.returncode == 0
                else (_err(rr, "not removed") if rr else {"error": "not a name"})
            )
        elif cmd in POD_COMMANDS:
            return pod_run(cmd, args)
        elif cmd in BOX_COMMANDS:
            return box_run(cmd, args)
        elif cmd in MACHINE_COMMANDS:
            return machine_run(cmd, args)
        elif cmd in LXD_COMMANDS:
            return lxd_run(cmd, args)
        elif cmd in SIF_COMMANDS:
            return sif_run(cmd, args)
        elif cmd in VIRT_COMMANDS:
            return virt_run(cmd, args)
        elif cmd in WAYDROID_COMMANDS:
            return waydroid_run(cmd, args)
        elif cmd in COMPOSE_COMMANDS:
            return compose_run(cmd, args)
        else:
            print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
            return 2
    except (OSError, subprocess.TimeoutExpired) as e:
        r = {"error": str(e)}
    print(json.dumps(r))
    return 1 if isinstance(r, dict) and "error" in r else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
