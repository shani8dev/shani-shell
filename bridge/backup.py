#!/usr/bin/env python3
"""Thin bridge to the `shani-backup` command (../shani-backup/src/shani_backup/cli.py).

    backup.py <op> [args ...]        one JSON object per line on stdout

The command owns the backup logic. This file only parses argv, calls a plain
function that returns data, and prints that data. SHANI_BACKUP_TOOL and
SHANI_BACKUP_PKEXEC (shlex-split; empty means no pkexec) are for stand-ins.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys

BACKUP = shlex.split(os.environ.get("SHANI_BACKUP_TOOL", "shani-backup"))
PKEXEC = shlex.split(os.environ.get("SHANI_BACKUP_PKEXEC", "pkexec"))

USAGE = (
    "usage: backup.py list | backup | restore <target> <snapshot> | "
    "snapshot-list <path> | snapshot-create <source> <destination> [--readonly] | "
    "snapshot-delete <path> | home-list | home-snapshot | home-remove <name> | "
    "schedule on|off|at [HH:MM]"
)


def _error(r) -> str:
    lines = [line.strip() for line in (r.stderr or "").splitlines() if line.strip()]
    return lines[-1] if lines else f"exit {r.returncode}"


def run(args: list[str], privileged: bool = False, timeout: int = 120) -> dict:
    """Run shani-backup with args; return its JSON object or a failure dict."""
    cmd = [*BACKUP, *args]
    if privileged and PKEXEC:
        cmd = [*PKEXEC, *cmd]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return {"ok": False, "error": "shani-backup is not installed"}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    if "--json" in args:
        try:
            data = json.loads(r.stdout or "")
        except ValueError:
            data = None
        if isinstance(data, dict):
            return data
    if r.returncode == 0:
        return {"ok": True, "output": (r.stdout or "").strip()}
    return {"ok": False, "error": _error(r)}


def list_backups() -> dict:
    return run(["backups", "--json"])


def _progress(segment: str, state: dict) -> None:
    match = re.match(r"^\s*(\d{1,3})%\s+(.*)$", segment)
    if not match:
        return
    pct, name = int(match.group(1)), match.group(2).strip()
    if pct == state["last"]:
        return
    state["last"] = pct
    try:
        state["emit"]({"progress": pct, "file": name})
    except Exception:
        pass


def backup(emit=lambda d: None) -> dict:
    """Stream progress as the command runs, then return its final result."""
    out = {"ok": False, "snapshot": "", "restore_test": None, "error": ""}
    try:
        proc = subprocess.Popen(
            [*BACKUP, "backup"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        return {**out, "error": "shani-backup is not installed"}
    except Exception as exc:
        return {**out, "error": str(exc)}
    state, lines, buf = {"last": -1, "emit": emit}, [], ""
    try:
        while True:
            char = proc.stdout.read(1)
            if not char:
                break
            if char in "\r\n":
                _progress(buf, state)
                if buf.strip() and not re.match(r"^\s*\d{1,3}%", buf):
                    lines.append(buf.strip())
                buf = ""
            else:
                buf += char
        _progress(buf, state)
        if buf.strip() and not re.match(r"^\s*\d{1,3}%", buf):
            lines.append(buf.strip())
        proc.stderr.read()
        code = proc.wait()
    except Exception as exc:
        proc.kill()
        proc.wait()
        return {**out, "error": str(exc)}

    snapshot, error, restore = "", "", None
    for line in lines:
        if line.startswith("Backed up: "):
            snapshot = line[len("Backed up: ") :].strip()
        elif line.startswith("Error: "):
            error = line[len("Error: ") :].strip()
        elif line.startswith("Restore test: "):
            detail = line[len("Restore test: ") :].strip()
            if detail.startswith("FAILED - "):
                restore = {"ok": False, "detail": detail[len("FAILED - ") :].strip()}
            elif detail.startswith("restored "):
                restore = {"ok": True, "detail": detail[len("restored ") :].strip()}
    return {
        "ok": bool(snapshot) and not error and code in (0, 3),
        "snapshot": snapshot,
        "restore_test": restore,
        "error": error
        or (f"exit {code}" if not snapshot and code not in (0, 3) else ""),
    }


def restore(target: str, snapshot: str) -> dict:
    return run(["restore", target, "--snapshot", snapshot, "--json"])


def snapshot_list(path: str) -> dict:
    return run(["snapshot", "list", path, "--json"])


def snapshot_create(source: str, destination: str, readonly: bool = False) -> dict:
    return run(
        [
            "snapshot",
            "create",
            source,
            destination,
            *(["--readonly"] if readonly else []),
            "--json",
        ],
        privileged=True,
    )


def snapshot_delete(path: str) -> dict:
    return run(["snapshot", "delete", path, "--json"], privileged=True)


def home_list() -> dict:
    return run(["home", "list", "--json"])


def home_snapshot() -> dict:
    return run(["home", "snapshot", "--json"], privileged=True)


def home_remove(name: str) -> dict:
    return run(["home", "remove", name, "--json"], privileged=True)


def schedule(mode: str, value: str = "") -> dict:
    if mode == "on":
        return run(["schedule", "--enable"])
    if mode == "off":
        return run(["schedule", "--disable"])
    if mode == "at":
        if not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value or ""):
            return {"ok": False, "error": "Time must be HH:MM"}
        return run(["schedule", "--at", value])
    return {"ok": False, "error": "Unknown schedule mode"}


def _usage() -> int:
    print(USAGE, file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    rest = list(argv[1:])
    if not rest:
        return _usage()
    op, args = rest[0], rest[1:]
    if any(a.startswith("-") for a in args if a != "--readonly"):
        return _usage()
    if op == "list" and not args:
        result = list_backups()
    elif op == "backup" and not args:

        def emit(item: dict) -> None:
            print(json.dumps(item), flush=True)

        result = backup(emit=emit)
    elif op == "restore" and len(args) == 2:
        result = restore(args[0], args[1])
    elif op == "snapshot-list" and len(args) == 1:
        result = snapshot_list(args[0])
    elif (
        op == "snapshot-create"
        and len(args) in (2, 3)
        and (len(args) == 2 or args[2] == "--readonly")
    ):
        result = snapshot_create(args[0], args[1], readonly=len(args) == 3)
    elif op == "snapshot-delete" and len(args) == 1:
        result = snapshot_delete(args[0])
    elif op == "home-list" and not args:
        result = home_list()
    elif op == "home-snapshot" and not args:
        result = home_snapshot()
    elif op == "home-remove" and len(args) == 1:
        result = home_remove(args[0])
    elif (
        op == "schedule"
        and args
        and args[0] in ("on", "off", "at")
        and len(args) == (2 if args[0] == "at" else 1)
        or op == "schedule"
        and args == ["at"]
    ):
        result = schedule(args[0], args[1] if len(args) == 2 else "")
    else:
        return _usage()
    print(json.dumps(result))
    return 0 if result.get("ok") is True else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
