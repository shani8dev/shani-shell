#!/usr/bin/env python3
"""Stands in for systemctl and ssh-keygen (tests/test_system_access.py).

Invoked by basename through a symlink; answers come from $FAKE_SYSTEM_ACCESS/
systemctl-<unit>.out or ssh-keygen.out when present, otherwise from small
fixtures here. Every call is logged in $FAKE_SYSTEM_ACCESS/calls.
"""

import os
import sys
import traceback

D = os.environ.get("FAKE_SYSTEM_ACCESS", "/tmp")


def _logged(t, v, tb):  # a stand-in failure, for the shell part to show
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
prog = os.path.basename(sys.argv[0])
a = sys.argv[1:]
with open(os.path.join(D, "calls"), "a") as f:
    f.write(prog + " " + " ".join(a) + "\n")


def _fixture():
    name = "ssh-keygen.out" if prog == "ssh-keygen" else prog + ".out"
    if prog == "systemctl" and a and a[-1].endswith(".service"):
        name = "systemctl-" + a[-1] + ".out"
    path = os.path.join(D, name)
    if os.path.exists(path):
        with open(path) as f:
            return f.read().rstrip("\n")
    return ""


def _default():
    if prog == "systemctl":
        return {"sssd.service": "active", "slapd.service": "inactive"}.get(
            a[-1] if a else "", "unknown"
        )
    if prog == "ssh-keygen":
        path = os.environ.get("SHANI_AUTHORIZED_KEYS", "")
        lines = []
        try:
            with open(path) as f:
                lines = [
                    l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")
                ]
        except OSError:
            pass
        return "\n".join(
            "256 SHA256:fake%d %s (ED25519)"
            % (i, line.split()[2] if len(line.split()) > 2 else "no comment")
            for i, line in enumerate(lines, 1)
        )
    return ""


out = _fixture() or _default()
if out:
    print(out)
