#!/usr/bin/env python3
"""Stands in for ausearch and systemctl (tests/test_system_health.py). Symlink
this file as `ausearch`, `systemctl` or `pkexec`; every call, including argv
behind pkexec, lands in $FAKE_AUDIT/calls. Unknown options are refused with
exit 2, like the real tools. FAKE_AUDIT_EMPTY / FAKE_AUDIT_REFUSE /
FAKE_AUDIT_COUNT / FAKE_AUDIT_DOC / FAKE_AUDIT_ACTIVE / FAKE_AUDIT_ENABLED
shape the answer; the log path itself comes from SHANI_AUDIT_LOG."""

import json
import os
import sys

D = os.environ.get("FAKE_AUDIT", "/tmp")


def _log(prog, args):
    try:
        with open(os.path.join(D, "calls"), "a") as f:
            f.write(prog + " " + " ".join(args) + "\n")
    except OSError:
        pass


def _record(n):
    if n == 0:
        return {
            "type": "USER_START",
            "time": "11/26/2026 12:00:01",
            "items": [
                {
                    "sub": [
                        {"name": "a0", "value": "/usr/bin/su"},
                        {"name": "a1", "value": "-"},
                    ]
                }
            ],
        }
    if n == 1:
        return {
            "type": "EXECVE",
            "time": "11/26/2026 12:00:02",
            "items": [{"sub": [{"name": "a0", "value": "/usr/bin/id"}]}],
        }
    if n == 2:
        return {
            "type": "SYSCALL",
            "time": "11/26/2026 12:00:03",
            "items": [{"output": "raw audit line 3"}],
        }
    return {
        "type": "SYSCALL",
        "time": "11/26/2026 12:00:%02d" % (n % 60),
        "items": [{"sub": [{"name": "a0", "value": "/usr/bin/cmd%d" % n}]}],
    }


def _valid_ausearch(args):
    i = 0
    while i < len(args):
        word = args[i]
        if word in ("--output=json", "-i"):
            i += 1
        elif word == "-n":
            i += 1
            if i >= len(args) or not args[i].isdigit():
                return False
            i += 1
        elif word == "--start":
            i += 1
            if i >= len(args) or args[i].startswith("-"):
                return False
            i += 1
        else:
            return False
    return True


def ausearch(args):
    if not _valid_ausearch(args):
        print("ausearch: invalid option", file=sys.stderr)
        return 2
    if os.environ.get("FAKE_AUDIT_REFUSE"):
        print("pkexec: permission denied", file=sys.stderr)
        return 255
    if os.environ.get("FAKE_AUDIT_MALFORMED"):
        print("not json at all")
        return 0
    if os.environ.get("FAKE_AUDIT_EMPTY"):
        count = 0
    else:
        try:
            count = int(os.environ.get("FAKE_AUDIT_COUNT", "3"))
        except ValueError:
            count = 3
    records = [_record(n) for n in range(max(count, 0))]
    key = "items" if os.environ.get("FAKE_AUDIT_DOC") == "items" else "records"
    print(json.dumps({key: records}))
    return 0


def systemctl(args):
    if (
        len(args) != 2
        or args[0] not in ("is-active", "is-enabled")
        or args[1] != "auditd"
    ):
        print("systemctl: invalid option", file=sys.stderr)
        return 2
    name, default = (
        ("FAKE_AUDIT_ACTIVE", "active")
        if args[0] == "is-active"
        else ("FAKE_AUDIT_ENABLED", "enabled")
    )
    print(os.environ.get(name, default))
    return 0


prog = os.path.basename(sys.argv[0])
args = sys.argv[1:]
_log(prog, args)
if prog == "pkexec":
    if not args:
        sys.exit(2)
    prog = os.path.basename(args[0])
    args = args[1:]
if prog == "ausearch":
    sys.exit(ausearch(args))
if prog == "systemctl":
    sys.exit(systemctl(args))
print("%s: not a supported stand-in" % prog, file=sys.stderr)
sys.exit(2)
