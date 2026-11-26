#!/usr/bin/env python3
"""Stands in for systemctl and ausearch (tests/test_system_background.py).

Invoked by basename through a symlink; answers come from $FAKE_SYSTEM_BG/
systemctl-<unit>.out or ausearch.out when present, otherwise from short
fixtures here. Calls are logged in $FAKE_SYSTEM_BG/calls. Nothing is changed.
"""

import os
import sys
import traceback

D = os.environ.get("FAKE_SYSTEM_BG", "/tmp")


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
prog = os.path.basename(sys.argv[0])
a = sys.argv[1:]
with open(os.path.join(D, "calls"), "a") as f:
    f.write(prog + " " + " ".join(a) + "\n")

name = (
    "systemctl-" + a[-1] + ".out"
    if prog == "systemctl" and a and a[-1].endswith(".service")
    else prog + ".out"
)
path = os.path.join(D, name)
if os.path.exists(path):
    with open(path) as f:
        out = f.read().rstrip("\n")
else:
    out = {
        "systemctl": "active" if a and a[-1] == "ananicy-cpp.service" else "unknown",
        "ausearch": 'type=USER_LOGIN msg=audit(1710000000.100:42): pid=100 uid=0 auid=1000 msg=\'op=login id="alice" exe="/usr/bin/login"\'\n'
        "type=USER_ACCT msg=audit(1710000000.101:43): pid=100 uid=0 auid=1000 msg='op=adding user id=\"bob\"'",
    }.get(prog, "")
if out:
    print(out)
