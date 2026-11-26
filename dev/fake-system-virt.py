#!/usr/bin/env python3
"""Stands in for virsh, lxc-ls, lxc and machinectl (tests/test_system_virt.py).

Invoked by basename through a symlink; answers come from $FAKE_SYSTEM_VIRT/
<program>.out when present, otherwise from small read-only tables here. Calls
are logged in $FAKE_SYSTEM_VIRT/calls. No lifecycle verb is offered.
"""

import os
import sys
import traceback

D = os.environ.get("FAKE_SYSTEM_VIRT", "/tmp")


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
prog = os.path.basename(sys.argv[0])
a = sys.argv[1:]
with open(os.path.join(D, "calls"), "a") as f:
    f.write(prog + " " + " ".join(a) + "\n")

path = os.path.join(D, prog + ".out")
if os.path.exists(path):
    with open(path) as f:
        out = f.read().rstrip("\n")
else:
    out = {
        "virsh": " Id   Name                  State\n-------------------------------\n 1    web                   running\n -    old-box               shut off",
        "lxc-ls": "NAME    STATE    AUTOSTART    GROUPS    IPV4    IPV6\nweb     RUNNING  1            -         10.0.0.2 -",
        "lxc": "+-------+---------+\n| NAME  | STATE   |\n+-------+---------+\n| db    | RUNNING |\n+-------+---------+",
        "machinectl": "MACHINE    CLASS   SERVICE   OS        VERSION   ADDRESSES\ndev-vm     vm      systemd   example   1         10.0.0.3",
    }.get(prog, "")
if out:
    print(out)
