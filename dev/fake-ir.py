#!/usr/bin/env python3
"""Tiny infrared stand-in for dev/shell-parts/devices.sh.

Speaks `irsend` as well as the short action form, so either bridge shape works:

  fake-ir.py LIST "" ""                the remote's name, one per line
  fake-ir.py LIST <remote> ""          "<code> <button>" lines
  fake-ir.py SEND_ONCE <remote> <key>  "Sent <key> of <remote>."
  fake-ir.py list [remote]             aliases of the first two
  fake-ir.py send <remote:key|remote key>

Env:
  SHANI_IR_LOG   call log (default /tmp/fake-ir-calls)
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

REMOTE = "tv"
KEYS = {"power": "0001", "on": "0002", "volume-up": "0003"}


def log(argv: list[str]) -> None:
    path = Path(os.environ.get("SHANI_IR_LOG", "/tmp/fake-ir-calls"))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(" ".join(argv) + "\n")


def main() -> int:
    argv = sys.argv[1:]
    log(argv)
    upper = [a.upper() for a in argv]
    if upper[:1] == ["LIST"]:
        if len(argv) > 1 and argv[1] and argv[1] != REMOTE:
            return 0
        if len(argv) > 1 and argv[1] == REMOTE:
            for key, code in KEYS.items():
                print("%s %s" % (code, key))
        else:
            print(REMOTE)
        return 0
    if upper[:1] == ["SEND_ONCE"] and len(argv) >= 3:
        remote, key = argv[1], argv[2]
        if remote == REMOTE and key in KEYS:
            print("Sent %s of %s." % (key, remote))
        return 0
    if argv and argv[0].lower() == "list":
        if len(argv) > 1 and argv[1] == REMOTE:
            for key, code in KEYS.items():
                print("%s %s" % (code, key))
        else:
            print(REMOTE)
    elif argv and argv[0].lower() == "send" and len(argv) > 1:
        remote, _, key = argv[1].partition(":")
        if not key and len(argv) > 2:
            key = argv[2]
        if remote == REMOTE and key in KEYS:
            print("Sent %s of %s." % (key, remote))
    return 0


if __name__ == "__main__":
    sys.exit(main())
