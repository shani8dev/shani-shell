#!/usr/bin/env python3
"""Stands in for exportfs and pkexec (tests/test_system_nfs.py).

Invoked by basename through a symlink. Every call is logged in
$FAKE_SYSTEM_NFS/calls; a pkexec call also logs the exact stdin it received in
$FAKE_SYSTEM_NFS/stdin and returns {"ok": true, "mode", "owner"}. Option tables
are strict: anything the real tool would reject exits 2 with stderr. Answers
come from <prog>.out and <prog>.err in $FAKE_SYSTEM_NFS when present. Set
FAKE_SYSTEM_NFS_FAIL to a tool name to force a failure.
"""

import os
import sys

D = os.environ.get("FAKE_SYSTEM_NFS", "/tmp")
prog = os.path.basename(sys.argv[0])
args = sys.argv[1:]


def log(name, text):
    with open(os.path.join(D, name), "a") as fh:
        fh.write(text + "\n")


def fixture(ext):
    path = os.path.join(D, f"{prog}.{ext}")
    try:
        with open(path) as fh:
            return fh.read().rstrip("\n")
    except OSError:
        return ""


def forced():
    names = os.environ.get("FAKE_SYSTEM_NFS_FAIL", "").replace(",", " ").split()
    return prog in names


log("calls", prog + " " + " ".join(args))

if prog == "pkexec":
    stdin = sys.stdin.read(65536)
    log("stdin", stdin)
    verb = args[-1] if args else ""
    if verb not in ("nfs-exports-set", "smb-share-set"):
        sys.stderr.write(f"pkexec: unknown verb {verb}\n")
        sys.exit(2)
    print('{"ok": true, "mode": "0644", "owner": "0:0"}')
    sys.exit(0)

if prog == "exportfs":
    allowed = {"-r", "-a", "-ra", "-v", "-s", "-f"}
    if not args or any(arg not in allowed for arg in args):
        sys.stderr.write("exportfs: invalid option\n")
        sys.exit(2)
    if forced():
        sys.stderr.write("exportfs: forced failure\n")
        sys.exit(1)
    out = fixture("out")
    if out:
        print(out)
    err = fixture("err")
    if err:
        sys.stderr.write(err + "\n")
    try:
        with open(os.path.join(D, "exportfs.code")) as fh:
            code = int(fh.read().strip())
    except (OSError, ValueError):
        code = 0
    sys.exit(code)

sys.stderr.write(f"{prog}: not a stand-in tool\n")
sys.exit(2)
