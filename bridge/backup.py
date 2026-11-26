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
from datetime import datetime

BACKUP = shlex.split(os.environ.get("SHANI_BACKUP_TOOL", "shani-backup"))
PKEXEC = shlex.split(os.environ.get("SHANI_BACKUP_PKEXEC", "pkexec"))
# A user timer needs no root. SHANI_SYSTEMCTL_USER names that tool; the harness
# already points SHANI_SYSTEMCTL at its stand-in, so it works there too.
SYSTEMCTL_USER = shlex.split(
    os.environ.get("SHANI_SYSTEMCTL_USER")
    or os.environ.get("SHANI_SYSTEMCTL", "systemctl")
)
HOME_TIMER = "shani-backup-home.timer"
STALE_AFTER_DAYS = 3
FIND_LIMIT = 60

USAGE = (
    "usage: backup.py list | backup | restore <target> <snapshot> | "
    "snapshot-list <path> | snapshot-create <source> <destination> [--readonly] | "
    "snapshot-delete <path> | home-list | home-snapshot | home-remove <name> | "
    "home-timer state|on|off | disk-usage <path> | find-file <name> | "
    "schedule on|off|at [HH:MM]"
)


def _error(r) -> str:
    lines = [line.strip() for line in (r.stderr or "").splitlines() if line.strip()]
    return lines[-1] if lines else f"exit {r.returncode}"


def backup_call(args: list[str], privileged: bool = False, timeout: int = 120) -> dict:
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


def backup_status(backups: list, now=None) -> dict:
    """Plain codes from backup times: is the newest one old, and when was it."""
    stamps = []
    for item in backups or []:
        text = item.get("time") if isinstance(item, dict) else ""
        if not text:
            continue
        try:
            when = datetime.fromisoformat(str(text).replace("Z", "+00:00"))
        except ValueError:
            continue
        stamps.append((when, str(text)))
    if not stamps:
        return {"stale": True, "newest": ""}
    newest_when, newest = max(stamps, key=lambda pair: pair[0])
    reference = now or datetime.now(newest_when.tzinfo)
    age = (reference - newest_when).total_seconds() / 86400
    return {"stale": age >= STALE_AFTER_DAYS, "newest": newest}


def list_backups() -> dict:
    data = backup_call(["backups", "--json"])
    if data.get("ok") is not False:
        data.update(backup_status(data.get("backups")))
    return data


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
    return backup_call(["restore", target, "--snapshot", snapshot, "--json"])


def snapshot_list(path: str) -> dict:
    return backup_call(["snapshot", "list", path, "--json"])


def snapshot_create(source: str, destination: str, readonly: bool = False) -> dict:
    return backup_call(
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
    return backup_call(["snapshot", "delete", path, "--json"], privileged=True)


def home_list() -> dict:
    return backup_call(["home", "list", "--json"])


def home_snapshot() -> dict:
    return backup_call(["home", "snapshot", "--json"], privileged=True)


def home_remove(name: str) -> dict:
    return backup_call(["home", "remove", name, "--json"], privileged=True)


def schedule(mode: str, value: str = "") -> dict:
    if mode == "on":
        return backup_call(["schedule", "--enable"])
    if mode == "off":
        return backup_call(["schedule", "--disable"])
    if mode == "at":
        if not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value or ""):
            return {"ok": False, "error": "Time must be HH:MM"}
        return backup_call(["schedule", "--at", value])
    return {"ok": False, "error": "Unknown schedule mode"}


def systemctl_user(args: list[str], timeout: int = 20) -> dict:
    """Run `systemctl --user <args>`; return its output as plain data."""
    prefix = list(SYSTEMCTL_USER)
    if "--user" not in prefix:
        prefix.append("--user")
    try:
        r = subprocess.run(
            [*prefix, *args], capture_output=True, text=True, timeout=timeout
        )
    except FileNotFoundError:
        return {"ok": False, "error": "systemctl is not available", "output": ""}
    except Exception as exc:
        return {"ok": False, "error": str(exc), "output": ""}
    return {
        "ok": r.returncode == 0,
        "output": (r.stdout or "").strip(),
        "error": _error(r) if r.returncode != 0 else "",
        "code": r.returncode,
    }


def home_timer_state() -> dict:
    """Read the daily snapshot timer: enabled, active and its next run."""
    r = systemctl_user(["show", HOME_TIMER])
    if not r["ok"]:
        return {"ok": False, "error": r["error"] or "Could not read the timer"}
    props = {}
    for line in r["output"].splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            props[key.strip()] = value.strip()
    unit_state = props.get("UnitFileState", "")
    active_state = props.get("ActiveState", "")
    next_run = ""
    for key in ("NextElapseUSecRealtime", "NextElapseUSecMonotonic"):
        try:
            micros = int(props.get(key, "0") or 0)
        except ValueError:
            continue
        if micros > 0:
            next_run = datetime.fromtimestamp(micros / 1_000_000).strftime(
                "%Y-%m-%d %H:%M"
            )
            break
    return {
        "ok": True,
        "enabled": unit_state.split("-")[0] == "enabled",
        "active": active_state == "active",
        "next": next_run,
    }


def home_timer(on: bool) -> dict:
    """Enable or disable the daily snapshot timer for this user."""
    verb = "enable" if on else "disable"
    r = systemctl_user([verb, "--now", HOME_TIMER])
    if not r["ok"]:
        return {"ok": False, "error": r["error"] or f"Could not {verb} the timer"}
    return {"ok": True, "output": r["output"] or verb + "d"}


def disk_usage(path: str, statvfs=os.statvfs) -> dict:
    """Space on the filesystem that holds the snapshots, in bytes."""
    if not path or not isinstance(path, str):
        return {"ok": False, "error": "Give a folder to check"}
    try:
        v = statvfs(path)
    except OSError as exc:
        return {"ok": False, "error": str(exc)}
    total = v.f_blocks * v.f_frsize
    free = v.f_bavail * v.f_frsize
    used = (v.f_blocks - v.f_bfree) * v.f_frsize
    return {
        "ok": True,
        "total": total,
        "free": free,
        "used": used,
        "low": bool(total and free / total < 0.10),
    }


def find_in_snapshots(query: str, paths=None, walk=os.walk, stat=os.lstat) -> dict:
    """Names in any snapshot, newest first, one row per size/mtime signature."""
    needle = (query or "").strip().lower()
    if len(needle) < 2:
        return {"ok": False, "error": "Type at least two letters", "results": []}
    if paths is None:
        listed = home_list()
        if listed.get("ok") is False:
            return {**listed, "results": []}
        paths = [
            s.get("path", "")
            for s in listed.get("snapshots", [])
            if isinstance(s, dict)
        ]
    results, seen, truncated = [], set(), False
    # shortcut: different files with one size and mtime collapse, add the inode
    # and relative path to the key when that matters
    for base in paths:
        if not base:
            continue
        for root, dirs, files in walk(base):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for name in files + dirs:
                if needle not in name.lower():
                    continue
                path = os.path.join(root, name)
                try:
                    info = stat(path)
                except OSError:
                    continue
                signature = (info.st_size, int(info.st_mtime))
                if signature in seen:
                    continue
                seen.add(signature)
                results.append(
                    {
                        "name": name,
                        "path": path,
                        "size": info.st_size,
                        "mtime": int(info.st_mtime),
                    }
                )
                if len(results) >= FIND_LIMIT:
                    truncated = True
                    break
            if truncated:
                break
        if truncated:
            break
    return {"ok": True, "results": results, "truncated": truncated}


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
    elif op == "home-timer" and args in (["state"], ["on"], ["off"]):
        result = (
            home_timer_state() if args[0] == "state" else home_timer(args[0] == "on")
        )
    elif op == "disk-usage" and len(args) == 1:
        result = disk_usage(args[0])
    elif op == "find-file" and len(args) == 1:
        result = find_in_snapshots(args[0])
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
