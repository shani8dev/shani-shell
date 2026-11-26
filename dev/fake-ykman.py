#!/usr/bin/env python3
"""Stand-in for yubikey-manager's `ykman` (tests/test_u2f_config.py).

Accepts only `--version`; everything else is usage + exit 2, as the real tool
does for an unknown option. FAKE_YKMAN_FAIL=1 makes the version call fail.
"""

import os
import sys


def main(args):
    if args != ["--version"]:
        print("usage: fake-ykman.py --version", file=sys.stderr)
        return 2
    if os.environ.get("FAKE_YKMAN_FAIL") == "1":
        print("ykman: simulated failure", file=sys.stderr)
        return 1
    print("ykman version 5.4.1")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
