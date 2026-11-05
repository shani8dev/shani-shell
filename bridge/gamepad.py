#!/usr/bin/env python3
"""gamepad — the game controllers connected, and one controller's buttons live.

  gamepad.py list           JSON: [{"name", "event", "uniq"}] - every joystick the
                            kernel has (/proc/bus/input/devices, "jsN" among its
                            handlers): USB and Bluetooth alike, unlike /dev/input/by-id
  gamepad.py watch event5   one line per change while it runs:
                              press A / release A
                              axis left-x 0.42      (-1 … 1; triggers 0 … 1)
                            Settings' "Test the buttons" view runs it while open and
                            stops it when it closes: nothing reads the controller otherwise.

The device node is readable by the person at the seat (systemd's 70-uaccess
gives joysticks to the active session). Plain os.read on the event node - no
python-evdev in the image. SHANI_INPUT_DEVICES and SHANI_INPUT_DIR replace
/proc/bus/input/devices and /dev/input (the tests).
"""

import fcntl
import json
import os
import struct
import sys

EVENT = struct.Struct("llHHi")              # struct input_event: timeval, type, code, value
EV_KEY, EV_ABS = 1, 3

# the kernel's gamepad codes (linux/input-event-codes.h), by the face a person sees
BUTTONS = {0x130: "A", 0x131: "B", 0x132: "C", 0x133: "Y", 0x134: "X", 0x135: "Z",
           0x136: "LB", 0x137: "RB", 0x138: "LT", 0x139: "RT",
           0x13a: "Select", 0x13b: "Start", 0x13c: "Home", 0x13d: "Left stick", 0x13e: "Right stick",
           0x220: "Up", 0x221: "Down", 0x222: "Left", 0x223: "Right",
           # older joysticks: BTN_TRIGGER … BTN_BASE6
           0x120: "Trigger", 0x121: "Thumb", 0x122: "Thumb 2", 0x123: "Top", 0x124: "Top 2", 0x125: "Pinkie",
           0x126: "Base", 0x127: "Base 2", 0x128: "Base 3", 0x129: "Base 4", 0x12a: "Base 5", 0x12b: "Base 6"}
AXES = {0x00: "left-x", 0x01: "left-y", 0x02: "left-trigger", 0x03: "right-x", 0x04: "right-y",
        0x05: "right-trigger", 0x10: "dpad-x", 0x11: "dpad-y"}


def devices(text):
    out = []
    for block in text.split("\n\n"):
        f = {}
        for line in block.splitlines():
            if len(line) > 3 and line[1] == ":":
                k, v = line[0], line[3:]
                f.setdefault(k, []).append(v)
        handlers = " ".join(f.get("H", [])).replace("Handlers=", "").split()
        if not any(h.startswith("js") for h in handlers):
            continue
        name = uniq = ""
        for v in f.get("N", []):
            if v.startswith("Name="):
                name = v[5:].strip('"')
        for v in f.get("U", []):
            if v.startswith("Uniq="):
                uniq = v[5:]
        ev = next((h for h in handlers if h.startswith("event")), "")
        if ev:
            out.append({"name": name, "event": ev, "uniq": uniq})
    return out


def absinfo(fd, code):
    """EVIOCGABS: the axis's min and max (a FIFO in the tests has none: raw values)."""
    buf = bytearray(24)
    try:
        fcntl.ioctl(fd, 0x80184540 + code, buf)          # _IOR('E', 0x40 + code, struct input_absinfo)
    except OSError:
        return None
    _value, lo, hi, *_ = struct.unpack("6i", buf)
    return (lo, hi) if hi > lo else None


def watch(node):
    fd = os.open(node, os.O_RDONLY)
    ranges = {}
    last = {}
    print("ready", flush=True)
    while True:
        data = os.read(fd, EVENT.size * 64)
        if not data:
            return 0
        for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _s, _us, typ, code, value = EVENT.unpack_from(data, i)
            if typ == EV_KEY and code in BUTTONS and value in (0, 1):
                print(("press " if value else "release ") + BUTTONS[code], flush=True)
            elif typ == EV_ABS and code in AXES:
                if code not in ranges:
                    ranges[code] = absinfo(fd, code)
                r = ranges[code]
                if r:
                    lo, hi = r
                    x = (value - lo) / (hi - lo)
                    x = x if "trigger" in AXES[code] else x * 2 - 1
                else:
                    x = max(-1.0, min(1.0, value / 32767))
                x = round(x, 2)
                if last.get(code) != x:          # a stick at rest jitters: only changes
                    last[code] = x
                    print(f"axis {AXES[code]} {x}", flush=True)


def main(argv):
    if len(argv) >= 2 and argv[1] == "list":
        path = os.environ.get("SHANI_INPUT_DEVICES", "/proc/bus/input/devices")
        try:
            text = open(path).read()
        except OSError:
            text = ""
        print(json.dumps(devices(text)))
        return 0
    if len(argv) == 3 and argv[1] == "watch" and argv[2].startswith("event") and "/" not in argv[2]:
        return watch(os.path.join(os.environ.get("SHANI_INPUT_DIR", "/dev/input"), argv[2]))
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
    except OSError as e:
        print(f"gamepad: {e}", file=sys.stderr)
        sys.exit(1)
