#!/usr/bin/env python3
"""system_health — the read-only checks behind Settings › System › System health.

    system_health.py list     {"have": bool, "checks": [{"key", "title",
                              "status", "detail"}], "error": ""}

Runs the person's own `shani-health --verify --json` as them: no root, no
password. The report can be a list of checks or an object with `checks` (or
`report`); each check's own words are mapped to one of pass, warn, fail, info.
An unusable or missing report is said, never filled in with invented checks.
A failing check still prints its JSON with exit 1; that report is used.
SHANI_SYSTEM_HEALTH / SHANI_SYSTEM_HEALTH_ARGS (tests and stand-ins).
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys

TOOL = shlex.split(os.environ.get("SHANI_SYSTEM_HEALTH", "shani-health"))
ARGS = shlex.split(os.environ.get("SHANI_SYSTEM_HEALTH_ARGS", "--verify --json"))

# The tool's own words, not a second opinion about their meaning. Anything
# unrecognised is info: never claim a check passed because we did not know its
# status word.
STATUS = {
    "pass": "pass",
    "passed": "pass",
    "ok": "pass",
    "good": "pass",
    "healthy": "pass",
    "success": "pass",
    "true": "pass",
    "warn": "warn",
    "warning": "warn",
    "degraded": "warn",
    "notice": "warn",
    "fail": "fail",
    "failed": "fail",
    "error": "fail",
    "critical": "fail",
    "bad": "fail",
    "false": "fail",
    "info": "info",
    "informational": "info",
    "unknown": "info",
    "skip": "info",
    "skipped": "info",
    "not run": "info",
    "none": "info",
}


def _text(check: dict, *names: str) -> str:
    for name in names:
        value = check.get(name)
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def _status(value) -> str:
    if isinstance(value, bool):
        return "pass" if value else "fail"
    word = str(value or "").strip().lower()
    return STATUS.get(word, "info")


def _rows(report):
    """Normalise a health report into check dicts; unknown shapes yield none."""
    if isinstance(report, dict):
        for key in ("checks", "report", "results"):
            if key in report:
                return _rows(report[key])
        if _text(report, "title", "name", "key", "id", "status"):
            return [report]
        return []
    if isinstance(report, list):
        return [c for c in report if isinstance(c, dict)]
    return []


def _check(check: dict) -> dict:
    title = _text(check, "title", "name", "label", "section")
    return {
        "key": _text(check, "key", "id", "name") or title,
        "title": title,
        "status": _status(
            check.get(
                "status", check.get("state", check.get("result", check.get("level")))
            )
        ),
        "detail": _text(check, "detail", "message", "description", "output", "note"),
    }


def listing() -> dict:
    out: dict = {"have": False, "checks": [], "error": ""}
    tool = TOOL[0] if TOOL else "shani-health"
    if not shutil.which(tool):
        out["error"] = f"{tool} is not available"
        return out
    try:
        r = subprocess.run(TOOL + ARGS, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        out["error"] = str(exc)
        return out
    # shani-health exits 1 when a check finds a problem and still prints its
    # JSON: the report on stdout wins over the exit code, or the fail rows are
    # lost just when they matter.
    try:
        report = json.loads(r.stdout or "")
    except ValueError as exc:
        out["error"] = (
            (r.stderr.strip().splitlines() or [f"exit {r.returncode}"])[-1]
            if r.returncode != 0
            else f"could not read the health report: {exc}"
        )
        return out
    out["have"] = True
    out["checks"] = [_check(c) for c in _rows(report)]
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] != "list":
        print("usage: system_health.py list", file=sys.stderr)
        return 2
    print(json.dumps(listing()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
