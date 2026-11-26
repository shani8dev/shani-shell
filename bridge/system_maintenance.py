#!/usr/bin/env python3
"""system_maintenance — clean-up, a saved report and reset behind Settings › System › Maintenance.

    system_maintenance.py clean            {"ok", "output", "error"}
    system_maintenance.py report           {"ok", "path", "error"}
    system_maintenance.py reset            {"ok", "error"}   (JSON on stdin:
                                            {"home": bool, "keepDownloads": bool})

These three need root, so each runs through pkexec: the shell's polkit agent
asks why before it asks for a password. The calling page says what will happen;
this script never reads the bundle it asks shani-health to write, only reports
the folder it was written to. Reset accepts exactly two booleans on stdin:
unknown keys and values that are not booleans are refused before any command
runs. SHANI_PKEXEC / SHANI_DEPLOY / SHANI_HEALTH / SHANI_RESET / SHANI_REPORT_DIR.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

PKEXEC = shlex.split(os.environ.get("SHANI_PKEXEC", "pkexec"))
DEPLOY = os.environ.get("SHANI_DEPLOY", "/usr/local/bin/shani-deploy")
HEALTH = os.environ.get("SHANI_HEALTH", "/usr/local/bin/shani-health")
RESET = os.environ.get("SHANI_RESET", "/usr/local/bin/shani-reset")
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
REPORT_DIR = Path(os.environ.get("SHANI_REPORT_DIR", CACHE / "shani-shell" / "reports"))
RESET_KEYS = {"home", "keepDownloads"}


def _run(args: list[str], timeout: int = 300):
    if not PKEXEC or not shutil.which(PKEXEC[0]):
        return None, f"{PKEXEC[0] if PKEXEC else 'pkexec'} is not available"
    try:
        return subprocess.run(
            PKEXEC + args, capture_output=True, text=True, timeout=timeout
        ), ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)


def _failure(r, error: str) -> str:
    """One line of why: a runner failure or the tool's own last error line."""
    if r is None:
        return error
    return (r.stderr.strip().splitlines() or [f"exit {r.returncode}"])[-1]


def _result(r, fallback: str) -> dict:
    if r is None:
        return {"ok": False, "output": "", "error": fallback}
    lines = [
        line.strip()
        for line in (r.stdout + "\n" + r.stderr).replace("\r", "\n").splitlines()
        if line.strip()
    ]
    ok = r.returncode == 0
    return {
        "ok": ok,
        "output": "\n".join(lines[-20:])[:4000],
        "error": "" if ok else _failure(r, fallback),
    }


def clean() -> dict:
    r, error = _run([DEPLOY, "--cleanup", "--optimize", "--yes"])
    return _result(r, error)


def _bundle_path(r, folder: str) -> str:
    """The file the helper says it wrote; only its path, never its contents."""
    for line in reversed((r.stdout or "").splitlines() if r else []):
        path = line.strip()
        if path.startswith("/") and path.startswith(folder + os.sep):
            return path
    return folder


def report() -> dict:
    try:
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return {"ok": False, "path": str(REPORT_DIR), "error": str(exc)}
    r, error = _run([HEALTH, "--export-logs", str(REPORT_DIR)], timeout=120)
    ok = r is not None and r.returncode == 0
    return {
        "ok": ok,
        "path": _bundle_path(r, str(REPORT_DIR)) if ok else str(REPORT_DIR),
        "error": "" if ok else _failure(r, error),
    }


def reset(body: bytes) -> dict:
    try:
        options = json.loads(body or b"")
    except (ValueError, UnicodeDecodeError):
        return {"ok": False, "error": 'expected {"home": true, "keepDownloads": false}'}
    if (
        not isinstance(options, dict)
        or set(options) != RESET_KEYS
        or any(type(options[k]) is not bool for k in RESET_KEYS)
    ):
        return {
            "ok": False,
            "error": "expected only home and keepDownloads as true or false",
        }
    args = [RESET, "--yes"]
    if options["home"]:
        args.append("--home")
    if options["keepDownloads"]:
        args.append("--keep-downloads")
    r, error = _run(args)
    ok = r is not None and r.returncode == 0
    return {"ok": ok, "error": "" if ok else _failure(r, error)}


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in ("clean", "report", "reset"):
        print("usage: system_maintenance.py clean|report|reset", file=sys.stderr)
        return 2
    if argv[1] == "clean":
        result = clean()
    elif argv[1] == "report":
        result = report()
    else:
        result = reset(sys.stdin.buffer.read())
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
