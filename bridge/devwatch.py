#!/usr/bin/env python3
"""devwatch — cameras coming and going, and being opened, without polling.

One line on stdout per event, for the shell (Services/Privacy, Services/Camera):

  devices          a /dev/video* node appeared or went (a camera plugged in or out)
  open video0      something opened a camera
  close video0     something closed it

inotify does it: IN_CREATE/IN_DELETE on /dev, IN_OPEN/IN_CLOSE on each
/dev/video* node (device nodes report opens like any file). The shell then
looks once - which process holds it - instead of scanning every process's
open files every three seconds. ctypes, because the image has no
inotify-tools and the shell already runs Python bridges.

DEVWATCH_DIR replaces /dev (the tests).
"""

import ctypes
import ctypes.util
import os
import struct
import sys

IN_OPEN, IN_CLOSE_WRITE, IN_CLOSE_NOWRITE = 0x20, 0x08, 0x10
IN_CREATE, IN_DELETE, IN_IGNORED = 0x100, 0x200, 0x8000
EVENT = struct.Struct("iIII")

libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)


def main() -> int:
    root = os.environ.get("DEVWATCH_DIR", "/dev")
    fd = libc.inotify_init1(os.O_CLOEXEC)
    if fd < 0:
        print(f"devwatch: inotify: {os.strerror(ctypes.get_errno())}", file=sys.stderr)
        return 1
    nodes = {}                                    # watch descriptor -> name

    def watch(name):
        wd = libc.inotify_add_watch(fd, os.path.join(root, name).encode(), IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE)
        if wd >= 0:
            nodes[wd] = name

    top = libc.inotify_add_watch(fd, root.encode(), IN_CREATE | IN_DELETE)
    for name in sorted(os.listdir(root)):
        if name.startswith("video"):
            watch(name)
    print("ready", flush=True)
    while True:
        data = os.read(fd, 65536)
        out = []
        i = 0
        while i < len(data):
            wd, mask, _cookie, size = EVENT.unpack_from(data, i)
            name = data[i + EVENT.size:i + EVENT.size + size].rstrip(b"\0").decode(errors="replace")
            i += EVENT.size + size
            if wd == top and name.startswith("video"):
                if mask & IN_CREATE:
                    watch(name)
                out.append("devices")
            elif wd in nodes:
                if mask & IN_IGNORED:
                    nodes.pop(wd, None)
                elif mask & IN_OPEN:
                    out.append("open " + nodes[wd])
                elif mask & (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE):
                    out.append("close " + nodes[wd])
        # a burst (an app probing every format) is one line per kind
        for line in dict.fromkeys(out):
            print(line, flush=True)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
