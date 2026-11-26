#!/usr/bin/env python3
"""Stands in for testparm, pdbedit, ss, systemctl and pkexec.

Invoked by basename through a symlink. Every call is logged in
$FAKE_SYSTEM_SMB/calls; a pkexec call also logs the exact stdin it received in
$FAKE_SYSTEM_SMB/stdin and returns {"ok": true, "mode", "owner"}. Option tables
are strict: anything the real tool would reject exits 2 with stderr. Answers
come from <prog>.out / <prog>.err (or systemctl-<unit>.out) in $FAKE_SYSTEM_SMB.
Set FAKE_SYSTEM_SMB_FAIL to a tool name to force a failure.
"""

import os
import sys

D = os.environ.get("FAKE_SYSTEM_SMB", "/tmp")
prog = os.path.basename(sys.argv[0])
args = sys.argv[1:]

TABLES = {
    "testparm": {"-s", "-d", "0"},
    "pdbedit": {"-L", "-v"},
    "ss": {"-tulpn"},
    "systemctl": {"is-active", "smb.service", "nmb.service", "winbind.service"},
}


def log(name, text):
    with open(os.path.join(D, name), "a") as fh:
        fh.write(text + "\n")


def fixture(name, ext):
    try:
        with open(os.path.join(D, f"{name}.{ext}")) as fh:
            return fh.read().rstrip("\n")
    except OSError:
        return ""


def forced():
    names = os.environ.get("FAKE_SYSTEM_SMB_FAIL", "").replace(",", " ").split()
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

if prog not in TABLES:
    sys.stderr.write(f"{prog}: not a stand-in tool\n")
    sys.exit(2)

if not args or any(arg not in TABLES[prog] for arg in args):
    sys.stderr.write(f"{prog}: invalid option\n")
    sys.exit(2)
if prog == "systemctl" and (len(args) != 2 or args[0] != "is-active"):
    sys.stderr.write("systemctl: invalid option\n")
    sys.exit(2)
if prog == "testparm" and args != ["-s", "-d", "0"]:
    sys.stderr.write("testparm: invalid option\n")
    sys.exit(2)
if forced():
    sys.stderr.write(f"{prog}: forced failure\n")
    sys.exit(1)

name = prog
if prog == "systemctl" and len(args) == 2:
    name = "systemctl-" + args[1]
out = fixture(name, "out")
err = fixture(name, "err")
if out:
    print(out)
if err:
    sys.stderr.write(err + "\n")
try:
    with open(os.path.join(D, f"{name}.code")) as fh:
        code = int(fh.read().strip())
except (OSError, ValueError):
    code = 0
sys.exit(code)
