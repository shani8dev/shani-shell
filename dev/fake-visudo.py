#!/usr/bin/env python3
"""Strict stand-in for visudo: -c and -c -f <path> only."""

import os
import sys


def fail(message):
    print(f"fake visudo: {message}", file=sys.stderr)
    raise SystemExit(2)


def main(argv):
    if not argv or argv[0] != "-c":
        fail("unsupported option: " + (" ".join(argv) or "none"))
    if len(argv) == 1:
        if os.environ.get("FAKE_VISUDO_FAIL_POST") == "1":
            fail("forced post-check failure")
        return 0
    if argv[1] == "-f" and len(argv) == 3:
        if not os.path.isfile(argv[2]):
            fail("config file not found")
        if os.environ.get("FAKE_VISUDO_FAIL_PRE") == "1":
            fail("forced pre-check failure")
        return 0
    fail("unsupported option: " + " ".join(argv[1:]))


if __name__ == "__main__":
    main(sys.argv[1:])
