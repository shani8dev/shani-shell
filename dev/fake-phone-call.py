#!/usr/bin/env python3
"""Incoming-call stand-in for dev/shell-parts/calls.sh.

Only thing it does is write the caller card bridge/link.py's `incoming`
command reads, atomically, where the shell looks for it:
  $SHANI_PHONE_STATE_HOME/incoming-call.json            (when set)
  $XDG_STATE_HOME/shani-shell/incoming-call.json        (default)
  ~/.local/state/shani-shell/incoming-call.json         (XDG fallback)

No socket, no D-Bus, no phone: the card is a file. The shell's
`callAction <id> answer|decline` clears it and appends to the actions log;
this tool only reads that log back so a live check can see the answer.

Usage:
  fake-phone-call.py post [name] [number] [id] [line] [when]
  fake-phone-call.py clear
  fake-phone-call.py state
  fake-phone-call.py actions
  fake-phone-call.py incoming          (alias of state, link.py's verb)
  fake-phone-call.py log ACTION [ID]   (append, same shape as the shell)

Env:
  SHANI_PHONE_STATE_HOME  directory for incoming-call.json
  SHANI_PHONE_CALL_LOG    actions log (default /tmp/phone-call-actions)
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from pathlib import Path

CARD = "incoming-call.json"


def state_dir() -> Path:
    override = os.environ.get("SHANI_PHONE_STATE_HOME", "").strip()
    if override:
        return Path(override)
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return Path(base) / "shani-shell"


def card() -> Path:
    return state_dir() / CARD


def log_path() -> Path:
    return Path(os.environ.get("SHANI_PHONE_CALL_LOG", "/tmp/phone-call-actions"))


def atomic_write(path: Path, text: str) -> None:
    """Same-directory temp then os.replace: a reader never sees a half card."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        dir=str(path.parent), prefix="." + path.stem + "-", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def post(argv: list[str]) -> None:
    name = argv[0] if len(argv) > 0 and argv[0] else "Asha Patil"
    number = argv[1] if len(argv) > 1 and argv[1] else "9844444444"
    ident = argv[2] if len(argv) > 2 and argv[2] else "c1"
    line = argv[3] if len(argv) > 3 and argv[3] else "phone"
    when = (
        int(argv[4])
        if len(argv) > 4 and argv[4].lstrip("-").isdigit()
        else int(time.time())
    )
    atomic_write(
        card(),
        json.dumps(
            {"id": ident, "name": name, "number": number, "line": line, "when": when},
            ensure_ascii=False,
        ),
    )
    print(str(card()))


def clear(_argv: list[str]) -> None:
    try:
        card().unlink()
    except FileNotFoundError:
        pass


def state(_argv: list[str]) -> None:
    try:
        data = json.loads(card().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    print(json.dumps(data, ensure_ascii=False))


def actions(_argv: list[str]) -> None:
    try:
        sys.stdout.write(log_path().read_text(encoding="utf-8"))
    except OSError:
        pass


def log(argv: list[str]) -> None:
    if not argv:
        raise SystemExit("usage: fake-phone-call.py log ACTION [ID]")
    action, ident = argv[0], (argv[1] if len(argv) > 1 else "")
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(("{} {}\n".format(ident, action)).strip() + "\n")


def main() -> int:
    argv = sys.argv[1:]
    cmd = argv[0] if argv else ""
    handlers = {
        "post": post,
        "clear": clear,
        "state": state,
        "incoming": state,
        "actions": actions,
        "log": log,
    }
    if cmd not in handlers:
        sys.stderr.write(__doc__ + "\n")
        return 2
    handlers[cmd](argv[1:])
    return 0


if __name__ == "__main__":
    sys.exit(main())
