#!/usr/bin/env python3
"""Stand-in for `systemctl --user` that knows one unit: Chronoa's engine.

Only `start`, `stop` and `show` for shani-chronoa-engine.service. Anything else
fails the way the real command fails, so a harness cannot hide a bad call.
Calls go to $SHANI_CHRONOA_SYSTEMCTL_LOG (default /tmp/fake-chronoa-systemctl/calls);
the active state is kept in state.json beside that log.
"""

from __future__ import annotations

import json
import os
import sys

UNIT = "shani-chronoa-engine.service"

LOG = (
    os.environ.get("SHANI_CHRONOA_SYSTEMCTL_LOG") or "/tmp/fake-chronoa-systemctl/calls"
)
DIR = os.path.dirname(os.path.abspath(LOG))
STATE = os.path.join(DIR, "state.json")


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def log_call(args: list[str]) -> None:
    rest = args[1:] if args and args[0] == "--user" else args
    verb = rest[0] if rest else ""
    tail = rest[1:]
    unit = tail[-1] if tail else ""
    extra = tail[:-1]
    line = " ".join([verb, unit] + extra) if verb else "(no command)"
    with open(LOG, "a") as fh:
        fh.write(line + "\n")


def active() -> bool:
    try:
        with open(STATE) as fh:
            return bool(json.load(fh).get("active"))
    except (OSError, ValueError):
        return False


def store(online: bool) -> None:
    with open(STATE, "w") as fh:
        json.dump({"active": online}, fh)


def main(argv: list[str]) -> int:
    os.makedirs(DIR, exist_ok=True)
    args = list(argv)
    log_call(args)
    if not args or args[0] != "--user":
        return fail("systemctl: only --user is supported")
    rest = args[1:]
    if not rest:
        return fail("systemctl: missing command")
    verb, tail = rest[0], rest[1:]
    if verb in ("start", "stop"):
        if tail != [UNIT]:
            return fail(f"systemctl: unsupported unit: {' '.join(tail)}")
        store(verb == "start")
        return 0
    if verb == "show":
        if tail == [UNIT]:
            print("ActiveState=" + ("active" if active() else "inactive"))
            return 0
        if tail == ["-p", "ActiveState", "--value", UNIT]:
            print("active" if active() else "inactive")
            return 0
        return fail("systemctl: unsupported show arguments")
    return fail(f"systemctl: unknown command: {verb}")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
