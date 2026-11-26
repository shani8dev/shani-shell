#!/usr/bin/env python3
"""system_background — scheduled jobs, process priority, IRQs and audit, read only.

    system_background.py schedules  {"files": [{"file", "lines": [...]}], "error"}
    system_background.py priority   {"installed", "active", "detail", "error"}
    system_background.py irq        {"balanced", "cpus", "lines", "error"}
    system_background.py audit      {"events": [{"type", "time", "detail"}], "error"}

No grading and no changes: these are the machine's own words. Schedules keep
the extra user field in /etc/crontab; IRQ lines are a sample of the counters;
audit records are parsed, not judged. All reads run as the person; ausearch is
called through pkexec only because the audit log needs root to be read.

Test overrides: SHANI_CRONTAB_ROOT, SHANI_ANANICY, SHANI_SYSTEMCTL,
SHANI_INTERRUPTS, SHANI_AUSEARCH.
"""

from __future__ import annotations

import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys


def _cmd(env: str, default: str) -> list[str]:
    return shlex.split(os.environ.get(env, default))


def _text(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def _run(cmd: list[str], *args: str, timeout: int = 10):
    try:
        return subprocess.run(
            cmd + list(args), capture_output=True, text=True, timeout=timeout
        ), ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)


def schedules() -> dict:
    """System-wide cron files, one row per job line, comments and blanks gone."""
    out = {"files": [], "error": ""}
    root = os.environ.get("SHANI_CRONTAB_ROOT", "/etc")
    paths = [os.path.join(root, "crontab")]
    for folder in ("cron.d", "cron.hourly", "cron.daily"):
        paths.extend(sorted(glob.glob(os.path.join(root, folder, "*"))))
    for path in paths:
        if not os.path.isfile(path):
            continue
        text = _text(path) or ""
        lines = [
            s
            for line in text.splitlines()
            if (s := line.strip()) and not s.startswith("#")
        ]
        if lines:
            out["files"].append({"file": path, "lines": lines})
    return out


def priority() -> dict:
    """Whether the priority daemon is installed and running, in plain words."""
    name = os.environ.get("SHANI_ANANICY", "ananicy-cpp")
    installed = bool(shutil.which(name))
    out = {
        "installed": installed,
        "active": False,
        "detail": "not installed",
        "error": "",
    }
    if not installed:
        return out
    r, err = _run(
        _cmd("SHANI_SYSTEMCTL", "systemctl"), "is-active", "ananicy-cpp.service"
    )
    if err:
        out["error"] = err
        out["detail"] = "service state is not available"
        return out
    state = r.stdout.strip().splitlines()
    state = state[-1].strip() if state else ""
    out["active"] = state == "active"
    out["detail"] = state or "not running"
    return out


def irq() -> dict:
    """CPU count from the header, whether IRQs reach more than one CPU, 3 samples."""
    out = {"balanced": False, "cpus": 0, "lines": [], "error": ""}
    text = _text(os.environ.get("SHANI_INTERRUPTS", "/proc/interrupts"))
    if text is None:
        out["error"] = "interrupt counters are not readable"
        return out
    rows = text.splitlines()
    if not rows:
        out["error"] = "interrupt counters are empty"
        return out
    out["cpus"] = len(re.findall(r"CPU\d+", rows[0]))
    if not out["cpus"]:
        out["error"] = "interrupt counters have no CPU header"
        return out
    for line in rows[1:]:
        parts = line.split()
        if len(parts) < 2:
            continue
        counts = [
            int(p.replace(",", "")) for p in parts[1:] if p.replace(",", "").isdigit()
        ]
        if sum(1 for n in counts if n) > 1:
            out["balanced"] = True
        if len(out["lines"]) < 3:
            out["lines"].append(line.rstrip())
    return out


def audit() -> dict:
    """Today's audit events, word for word, with no opinion about the rules."""
    out = {"events": [], "error": ""}
    cmd = _cmd("SHANI_AUSEARCH", "pkexec ausearch")
    if not cmd or not shutil.which(cmd[0]):
        out["error"] = "ausearch is not available"
        return out
    r, err = _run(cmd, "-m", "ALL", "-ts", "today", timeout=20)
    if err:
        out["error"] = err
        return out
    if r.returncode != 0:
        out["error"] = (r.stderr or r.stdout).strip().splitlines() or [
            "audit search failed"
        ]
        out["error"] = out["error"][-1][:200]
        return out
    for line in r.stdout.splitlines():
        kind = re.search(r"type=(\S+)", line)
        stamp = re.search(r"msg=audit\(([^)]*)\)", line)
        if not kind or not stamp:
            continue
        out["events"].append(
            {
                "type": kind.group(1),
                "time": stamp.group(1),
                "detail": line[stamp.end() :].lstrip(":) ").strip()[:300],
            }
        )
    return out


VERBS = {"schedules": schedules, "priority": priority, "irq": irq, "audit": audit}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if cmd not in VERBS or args:
        print(
            json.dumps(
                {"error": "usage: system_background.py <" + "|".join(VERBS) + ">"}
            )
        )
        return 2
    result = VERBS[cmd]()
    print(json.dumps(result))
    return 1 if result.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
