#!/usr/bin/env python3
"""tablet-mode — a convertible folded into a tablet and back: "tablet" / "laptop" lines.

The kernel's SW_TABLET_MODE switch (EV_SW code 1), on whichever input device
reports it (/proc/bus/input/devices: a "B: SW=" bitmask with bit 1 set - Intel
virtual switches, a 2-in-1's hinge sensor). The state now first (EVIOCGSW), then
one line each time it moves; blocking reads, so it wakes only then.
Services/TabletMode shows and hides the screen keyboard with it.
SHANI_INPUT_DEVICES and SHANI_INPUT_DIR replace /proc/bus/input/devices and /dev/input.
"""
import fcntl
import os
import struct
import sys

EVENT = struct.Struct("llHHi")
EV_SW, SW_TABLET_MODE = 5, 1


def switch_nodes(text):
    out = []
    for block in text.split("\n\n"):
        sw, handlers = 0, []
        for line in block.splitlines():
            if line.startswith("B: SW="):
                words = line[6:].split()
                sw = int(words[-1], 16) if words else 0          # the lowest word holds bit 1
            if line.startswith("H: Handlers="):
                handlers = line[12:].split()
        if sw & (1 << SW_TABLET_MODE):
            out += [h for h in handlers if h.startswith("event")]
    return out


def main():
    try:
        text = open(os.environ.get("SHANI_INPUT_DEVICES", "/proc/bus/input/devices")).read()
    except OSError:
        return 1
    nodes = switch_nodes(text)
    if not nodes:
        return 1
    fd = os.open(os.path.join(os.environ.get("SHANI_INPUT_DIR", "/dev/input"), nodes[0]), os.O_RDONLY)
    buf = bytearray(8)
    try:
        fcntl.ioctl(fd, 0x8008451B, buf)                  # EVIOCGSW(8): the switches' state now
        print("tablet" if buf[0] & (1 << SW_TABLET_MODE) else "laptop", flush=True)
    except OSError:
        pass
    last = None
    while True:
        data = os.read(fd, EVENT.size * 16)
        if not data:
            return 0
        for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _s, _us, typ, code, value = EVENT.unpack_from(data, i)
            if typ == EV_SW and code == SW_TABLET_MODE and value != last:
                last = value
                print("tablet" if value else "laptop", flush=True)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
