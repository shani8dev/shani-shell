#!/usr/bin/env python3
"""services — the person's own units and scheduled jobs, with real writes.
No root: everything here is `systemctl --user` or the person's own crontab.

    services.py services                [{"unit", "active", "enabled", "description"}]
    services.py timers                  [{"unit", "next", "left", "description"}]
    services.py cron                    [{"index", "line"}]
    services.py unit <action> <name>    start | stop | restart | enable | disable
    services.py cron-add <schedule> <command>
    services.py cron-remove <index>

Unit names are matched strictly: only letters, digits and @._- are accepted,
and no command is ever built with a shell. A new cron line cannot contain a
newline. One JSON answer per call, as every other bridge.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

CRONTAB = os.environ.get("SHANI_CRONTAB", "crontab")
UNIT = re.compile(r"^[A-Za-z0-9@._-]+$")
TIMEOUT = 10


def run(*argv, timeout=TIMEOUT):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.stdout.strip(), p.stderr.strip(), p.returncode
    except FileNotFoundError:
        return "", "not installed", 127
    except subprocess.TimeoutExpired:
        return "", "timed out", 124


def ok(err="", code=0):
    return {"ok": code == 0 and not err, "error": err.strip()[:200]}


def cmd_services():
    out, _e, _c = run("systemctl", "--user", "list-units", "--type=service", "--all",
                      "--no-pager", "--plain")
    out2, _e2, _c2 = run("systemctl", "--user", "list-unit-files", "--type=service", "--no-pager", "--plain")
    enabled = {}
    for line in out2.splitlines()[1:]:
        p = line.split()
        if p:
            enabled[p[0]] = p[1] if len(p) > 1 else ""
    rows = []
    for line in out.splitlines()[1:]:
        p = line.split(None, 4)
        if len(p) >= 4 and p[0].endswith(".service"):
            rows.append({"unit": p[0], "active": p[2], "enabled": enabled.get(p[0], ""),
                         "description": p[4] if len(p) > 4 else ""})
    return rows


def cmd_timers():
    out, _e, _c = run("systemctl", "--user", "list-timers", "--all", "--no-pager", "--plain")
    rows = []
    for line in out.splitlines()[1:]:
        p = line.split()
        if len(p) >= 2 and p[-1].endswith(".timer"):
            rows.append({"unit": p[-1], "next": p[0] + " " + p[1],
                         "left": p[2] if len(p) > 2 else "", "description": " ".join(p[3:-1])})
    return rows


def crontab_lines():
    out, _e, code = run(CRONTAB, "-l")
    if code != 0:
        return []
    return [l for l in out.splitlines() if l.strip() and not l.lstrip().startswith("#")]


def cmd_cron():
    return [{"index": i, "line": l} for i, l in enumerate(crontab_lines())]


def cron_write(lines):
    text = "\n".join(lines) + ("\n" if lines else "")
    try:
        p = subprocess.run([CRONTAB, "-"], input=text, capture_output=True, text=True, timeout=10)
        return ok(p.stderr, p.returncode)
    except Exception as exc:  # noqa: BLE001
        return ok(str(exc))


def cmd_cron_add(schedule, command):
    schedule, command = (schedule or "").strip(), (command or "").strip()
    if not schedule or not command:
        return ok("a schedule and a command are both needed")
    if "\n" in schedule or "\n" in command:
        return ok("one entry cannot contain a newline")
    line = f"{schedule} {command}"
    lines = crontab_lines()
    if line in lines:
        return ok("that entry is already there")
    return cron_write(lines + [line])


def cmd_cron_remove(index):
    try:
        i = int(index)
    except Exception:
        return ok("which entry?")
    lines = crontab_lines()
    if i < 0 or i >= len(lines):
        return ok("no such entry")
    return cron_write([l for j, l in enumerate(lines) if j != i])


def cmd_unit(action, name):
    if action not in ("start", "stop", "restart", "enable", "disable"):
        return ok("unknown action")
    if not UNIT.match(name or ""):
        return ok("that is not a unit name")
    _o, err, code = run("systemctl", "--user", action, name)
    return ok(err, code)


def main():
    a = sys.argv[1:]
    if not a:
        print(json.dumps(cmd_services(), ensure_ascii=False))
    elif a[0] == "services":
        print(json.dumps(cmd_services(), ensure_ascii=False))
    elif a[0] == "timers":
        print(json.dumps(cmd_timers(), ensure_ascii=False))
    elif a[0] == "cron":
        print(json.dumps(cmd_cron(), ensure_ascii=False))
    elif a[0] == "cron-add" and len(a) > 2:
        print(json.dumps(cmd_cron_add(a[1], a[2]), ensure_ascii=False))
    elif a[0] == "cron-remove" and len(a) > 1:
        print(json.dumps(cmd_cron_remove(a[1]), ensure_ascii=False))
    elif a[0] == "unit" and len(a) > 2:
        print(json.dumps(cmd_unit(a[1], a[2]), ensure_ascii=False))
    else:
        print(json.dumps({"error": "usage: services.py services|timers|cron|unit|cron-add|cron-remove"}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
