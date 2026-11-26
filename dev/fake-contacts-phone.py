#!/usr/bin/env python3
"""Stand-in for the phone's contact reader behind bridge/contacts.py.

    SHANI_CONTACTS_PHONE_TOOL="python3 .../fake-contacts-phone.py"

The bridge passes no arguments; the real reader rejects unknown options, so
this one does too (exit 3). SHANI_CONTACTS_PHONE_MODE picks the answer:
`rows` (default), `empty` (no phone connected), or `error` (read failed).
Every call is appended to SHANI_CONTACTS_PHONE_LOG when that is set.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROWS = [
    {
        "uid": "phone:Alice Smith",
        "name": "Alice Smith",
        "numbers": ["+15550100"],
        "emails": ["alice@example.com"],
    },
    {
        "uid": "phone:Bob Patil",
        "name": "Bob Patil",
        "numbers": ["+15550101", "+15550102"],
        "emails": [],
    },
]


def main() -> int:
    log = os.environ.get("SHANI_CONTACTS_PHONE_LOG", "")
    if log:
        with Path(log).open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({"argv": sys.argv[1:]}) + "\n")
    if len(sys.argv) > 1:
        print("Invalid argument: the phone reader takes no options", file=sys.stderr)
        return 3
    mode = os.environ.get("SHANI_CONTACTS_PHONE_MODE", "rows")
    if mode == "empty":
        print(json.dumps({"contacts": [], "error": "no phone is connected"}))
        return 0
    if mode == "error":
        print("no phone is connected", file=sys.stderr)
        return 3
    print(json.dumps({"contacts": ROWS}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
