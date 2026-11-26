#!/usr/bin/env python3
"""Stand-in for one neutral systemd unit state, used by the system pages' harness.

Invoked by basename as `systemctl`; only `is-active UNIT` and `is-enabled UNIT`
are accepted, everything else exits 2. The answer comes from
FAKE_UNIT_<UPPER_NAME> (dashes become underscores), defaulting to active.
"""

import os
import sys

a = sys.argv[1:]
if len(a) != 2 or a[0] not in ("is-active", "is-enabled"):
    sys.exit(2)
key = "FAKE_UNIT_" + a[1].split(".")[0].upper().replace("-", "_")
print(os.environ.get(key, "active"))
