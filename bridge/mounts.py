#!/usr/bin/env python3
"""mounts — open a camera's, a phone's or an iPhone's files in Files, through gvfs.

  mounts.py open gphoto2|mtp|afc

gvfs's volume monitors (gphoto2, mtp, afc) list such a device as a volume the
moment it is plugged in; `gio mount -li` shows its activation root
(gphoto2://…, mtp://…, afc://…). It is mounted if it is not yet, and opened
with the default file manager (`gio open`). Exit 1 when no such device is there.
SHANI_GIO replaces gio (the tests).
"""
import os
import re
import shlex
import subprocess
import sys


def gio(*args):
    return subprocess.run(shlex.split(os.environ.get("SHANI_GIO", "gio")) + list(args), capture_output=True, text=True, timeout=30)


def roots(listing, scheme):
    """(activation roots of volumes, roots of mounts) for one scheme, in listing order."""
    vols, mounts = [], []
    for m in re.finditer(r"(activation_root|default_location)=(\S+)", listing):
        if m.group(2).startswith(scheme + "://"):
            (vols if m.group(1) == "activation_root" else mounts).append(m.group(2))
    for m in re.finditer(r"^Mount\(\d+\): .*?-> (\S+)$", listing, re.M):
        if m.group(1).startswith(scheme + "://"):
            mounts.append(m.group(1))
    return vols, mounts


def main(argv):
    if len(argv) != 3 or argv[1] != "open" or argv[2] not in ("gphoto2", "mtp", "afc"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    vols, mounts = roots(gio("mount", "-li").stdout, argv[2])
    if mounts:
        target = mounts[0]
    elif vols:
        target = vols[0]
        if gio("mount", target).returncode != 0:
            return 1
    else:
        return 1
    return gio("open", target).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv))
