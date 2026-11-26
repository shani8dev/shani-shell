#!/usr/bin/env python3
"""Strict stand-in for exportfs: -ra only."""

import os
import sys


def fail(message):
    print(f"fake exportfs: {message}", file=sys.stderr)
    raise SystemExit(2)


def main(argv):
    if argv != ["-ra"]:
        fail("unsupported option: " + (" ".join(argv) or "none"))
    if os.environ.get("FAKE_EXPORTFS_FAIL") == "1":
        fail("forced failure")
    return 0


if __name__ == "__main__":
    main(sys.argv[1:])
