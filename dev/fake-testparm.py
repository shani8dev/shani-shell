#!/usr/bin/env python3
"""Strict stand-in for testparm: -s <path> only."""

import os
import sys


def fail(message):
    print(f"fake testparm: {message}", file=sys.stderr)
    raise SystemExit(2)


def main(argv):
    if len(argv) != 2 or argv[0] != "-s":
        fail("unsupported option: " + (" ".join(argv) or "none"))
    if not os.path.isfile(argv[1]):
        fail("config file not found")
    if os.environ.get("FAKE_TESTPARM_FAIL") == "1":
        fail("forced failure")
    return 0


if __name__ == "__main__":
    main(sys.argv[1:])
