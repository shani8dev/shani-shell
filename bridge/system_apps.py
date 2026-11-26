#!/usr/bin/env python3
"""system_apps — the versions of installed apps and of the OS, read only.

    system_apps.py list   {"flatpak": [{"id", "name", "version"}],
                            "snap": [{"id", "name", "version"}],
                            "os": [{"id", "version"}],
                            "have": {"flatpak": bool, "snap": bool, "os": bool}}

Flatpak and snap report their own applications; the OS reports its deployment
through ostree, falling back to the machine's os-release file. These are three
different ways of numbering versions, so there is deliberately no total across
them. A tool that is not installed is reported in "have": false, not as an
empty list of healthy apps. SHANI_SYSTEM_FLATPAK, SHANI_SYSTEM_SNAP, SHANI_OSTREE and
SHANI_OS_RELEASE point at stand-ins in the tests. Every command has a 30-second
limit.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

TIMEOUT = 30
FLATPAK = shlex.split(os.environ.get("SHANI_SYSTEM_FLATPAK", "flatpak"))
SNAP = shlex.split(os.environ.get("SHANI_SYSTEM_SNAP", "snap"))
OSTREE = shlex.split(os.environ.get("SHANI_OSTREE", "ostree"))
OS_RELEASE = os.environ.get("SHANI_OS_RELEASE", "/etc/os-release")


def _have(cmd: list[str]) -> bool:
    return shutil.which(cmd[0]) is not None


def _run(cmd: list[str], *args: str) -> subprocess.CompletedProcess:
    """Run one read-only command. A timeout is a failure, never a blank answer."""
    try:
        return subprocess.run(
            cmd + list(args), capture_output=True, text=True, timeout=TIMEOUT
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 1, "", str(e))


def _flatpak() -> tuple[list[dict], bool]:
    if not _have(FLATPAK):
        return [], False
    r = _run(FLATPAK, "list", "--app", "--columns=application,application-name,version")
    if r.returncode != 0:
        return [], True
    out = []
    for line in r.stdout.splitlines():
        f = line.split("\t")
        if not f or not f[0].strip():
            continue
        ident = f[0].strip()
        out.append(
            {
                "id": ident,
                "name": (f[1].strip() if len(f) > 1 and f[1].strip() else ident),
                "version": f[2].strip() if len(f) > 2 else "",
            }
        )
    return out, True


def _snap() -> tuple[list[dict], bool]:
    if not _have(SNAP):
        return [], False
    r = _run(SNAP, "list")
    if r.returncode != 0:
        return [], True
    out = []
    for line in r.stdout.splitlines():
        f = re.split(r"\s{2,}", line.strip())
        if not f[0] or f[0] == "Name" or len(f) < 2:
            continue
        out.append({"id": f[0], "name": f[0], "version": f[1]})
    return out, True


def _ostree() -> tuple[list[dict], bool]:
    if not _have(OSTREE):
        return [], False
    r = _run(OSTREE, "admin", "deploy", "--json")
    if r.returncode != 0:
        return [], True
    try:
        data = json.loads(r.stdout or "[]")
    except ValueError:
        return [], True
    rows = (
        data
        if isinstance(data, list)
        else (data.get("deployments", []) if isinstance(data, dict) else [])
    )
    out = []
    for d in rows:
        if not isinstance(d, dict):
            continue
        ident = str(d.get("id") or d.get("ref") or d.get("checksum") or "")
        out.append({"id": ident, "version": str(d.get("version") or ident)})
    return out, True


def _os_release() -> list[dict]:
    vals = {}
    try:
        with open(OS_RELEASE, encoding="utf-8", errors="replace") as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    vals[k] = v.strip().strip('"').strip("'")
    except OSError:
        return []
    name = vals.get("PRETTY_NAME") or vals.get("ID") or ""
    version = vals.get("VERSION_ID") or ""
    if not name and not version:
        return []
    return [{"id": name or version, "version": version}]


def listing() -> dict:
    flatpak, have_flatpak = _flatpak()
    snap, have_snap = _snap()
    deployments, have_ostree = _ostree()
    if not deployments:
        deployments = _os_release()  # a machine without ostree still has a version
    return {
        "flatpak": flatpak,
        "snap": snap,
        "os": deployments,
        "have": {
            "flatpak": have_flatpak,
            "snap": have_snap,
            "os": have_ostree or bool(deployments),
        },
    }


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd != "list":
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    print(json.dumps(listing()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
