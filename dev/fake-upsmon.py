#!/usr/bin/env python3
"""Stands in for shani-cassini-save when saving upsmon.conf (tests/test_ups.py).

Reach it by symlink named `shani-cassini-save`; other basenames are refused.
Accepts only `--target nut_upsmon_conf --expect-sha256 <64-hex>` and reads the
new full content from stdin, like the real helper. Every call is logged to
$FAKE_UPMON/calls as argv only; stdin is never logged or echoed. The content is
written to $SHANI_UPSMON_CONF with mode 0644. FAKE_UPMON_REFUSE=1 stands in for
a cancelled authentication and writes nothing.
"""

import hashlib
import os
import sys

MAX_BYTES = 16384


def usage() -> int:
    print(
        "usage: shani-cassini-save --target nut_upsmon_conf "
        "--expect-sha256 <64-hex> < content",
        file=sys.stderr,
    )
    return 2


def main(argv: list[str]) -> int:
    if os.path.basename(sys.argv[0]) != "shani-cassini-save":
        return usage()
    target, digest = "", ""
    args = list(argv)
    while args:
        option = args.pop(0)
        if option == "--target" and args:
            target = args.pop(0)
        elif option == "--expect-sha256" and args:
            digest = args.pop(0)
        else:
            return usage()
    if target != "nut_upsmon_conf" or not digest:
        return usage()
    folder = os.environ.get("FAKE_UPMON", "/tmp/fake-upsmon")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "calls"), "a") as fh:
        fh.write("shani-cassini-save " + " ".join(argv) + "\n")
    if os.environ.get("FAKE_UPMON_REFUSE") == "1":
        print("shani-cassini-save: authentication cancelled", file=sys.stderr)
        return 1
    path = os.environ.get("SHANI_UPSMON_CONF", "")
    if not path or not os.path.isdir(os.path.dirname(path)):
        print("shani-cassini-save: no target directory", file=sys.stderr)
        return 1
    content = sys.stdin.buffer.read()
    if len(content) > MAX_BYTES:
        print("shani-cassini-save: content too large", file=sys.stderr)
        return 1
    if len(digest) != 64 or any(c not in "0123456789abcdefABCDEF" for c in digest):
        print("shani-cassini-save: bad --expect-sha256", file=sys.stderr)
        return 1
    if hashlib.sha256(content).hexdigest() != digest.lower():
        print(
            "shani-cassini-save: content does not match --expect-sha256",
            file=sys.stderr,
        )
        return 1
    with open(path, "wb") as fh:
        fh.write(content)
    os.chmod(path, 0o644)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
