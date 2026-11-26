#!/usr/bin/env python3
"""Tiny NFC stand-in for dev/shell-parts/devices.sh.

Two shapes, so it works whether the bridge asks for an action or speaks to it
as it would to `nfc-list`:

  fake-nfc.py read                     the tag's text (what devices.py reads)
  fake-nfc.py write <text>             remember new text, "Written to the tag"
  fake-nfc.py -n -1                    a libnfc dump of a valid NDEF text record

Env:
  SHANI_NFC_STATE   the tag's text (default /tmp/fake-nfc-tag.txt)
  SHANI_NFC_LOG     call log (default /tmp/fake-nfc-calls)
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

DEFAULT = "Asha Patil 9844444444"


def state_path() -> Path:
    return Path(os.environ.get("SHANI_NFC_STATE", "/tmp/fake-nfc-tag.txt"))


def tag_text() -> str:
    try:
        return state_path().read_text(encoding="utf-8").strip() or DEFAULT
    except OSError:
        return DEFAULT


def log(argv: list[str]) -> None:
    path = Path(os.environ.get("SHANI_NFC_LOG", "/tmp/fake-nfc-calls"))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(" ".join(argv) + "\n")


def ndef_dump(text: str) -> None:
    """An NDEF text record as libnfc's `nfc-list -n` prints it."""
    payload = bytes([0x02, 0x65, 0x6E]) + text.encode("utf-8")
    if len(payload) >= 128:
        payload = payload[:124]
    # 0xE1 = MB | ME | SR | TNF well-known; 0xD1 would set IL and shift parsing.
    record = bytes([0xE1, 0x01, len(payload), 0x54]) + payload
    print("NFC device found: fake tag")
    print(" ".join("%02x" % b for b in record))


def main() -> int:
    argv = sys.argv[1:]
    log(argv)
    if argv == ["-n", "-1"]:
        ndef_dump(tag_text())
    elif argv and argv[0].lower() == "read":
        print("The tag says:")
        print(tag_text())
    elif argv and argv[0].lower() == "write" and len(argv) > 1:
        path = state_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(" ".join(argv[1:]), encoding="utf-8")
        print("Written to the tag")
    return 0


if __name__ == "__main__":
    sys.exit(main())
