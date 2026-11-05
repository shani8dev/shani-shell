#!/usr/bin/env python3
"""gamepad — the game controllers connected, and one controller's buttons live.

  gamepad.py list           JSON: [{"name", "event", "uniq"}] - every joystick the
                            kernel has (/proc/bus/input/devices, "jsN" among its
                            handlers): USB and Bluetooth alike, unlike /dev/input/by-id
  gamepad.py nav            a controller moves around the desktop while it runs:
                            d-pad and left stick -> arrow keys (repeating while held),
                            A Return, B Escape (keys sent with wtype, as the screen
                            keyboard does); and one line per shell action on stdout:
                            menu (X), launcher (Y, Guide), sidebar (Start),
                            overview (Select), workspace-prev / workspace-next (LB / RB),
                            "used" once when a controller first drives the desktop.
                            The devices are read, never grabbed: a game still gets
                            every press. Services/GamepadNav runs it only while a
                            controller is connected and no game is fullscreen.
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
import select
import shlex
import struct
import subprocess
import sys
import time

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


# nav: what each button does on the desktop
NAV_KEYS = {0x130: "Return", 0x131: "Escape"}
NAV_ACTIONS = {0x134: "menu", 0x133: "launcher", 0x13c: "launcher", 0x13b: "sidebar", 0x13a: "overview",
               0x136: "workspace-prev", 0x137: "workspace-next"}
DPAD = {0x220: "Up", 0x221: "Down", 0x222: "Left", 0x223: "Right"}
REPEAT_DELAY, REPEAT_EVERY = 0.4, 0.12
STICK_ON, STICK_OFF = 0.55, 0.35          # hysteresis: a stick near the edge does not flicker


class Nav:
    """Controller events -> keys and shell actions; held directions repeat."""

    def __init__(self, key, say, now=time.monotonic):
        self.key, self.say, self.now = key, say, now
        self.held = {}                    # direction -> time of the next repeat
        self.sources = {}                 # (source) -> direction it holds
        self.used = False
        self.ranges = {}

    def _use(self):
        if not self.used:
            self.used = True
            self.say("used")

    def _hold(self, source, direction):
        old = self.sources.get(source)
        if old == direction:
            return
        if old:
            self.sources.pop(source)
            if old not in self.sources.values():
                self.held.pop(old, None)
        if direction:
            self.sources[source] = direction
            if direction not in self.held:
                self._use()
                self.key(direction)
                self.held[direction] = self.now() + REPEAT_DELAY

    def event(self, typ, code, value, rng=None):
        if typ == EV_KEY and value in (0, 1):
            if code in DPAD:
                self._hold(("btn", code), DPAD[code] if value else None)
            elif value == 1 and code in NAV_KEYS:
                self._use()
                self.key(NAV_KEYS[code])
            elif value == 1 and code in NAV_ACTIONS:
                self._use()
                self.say(NAV_ACTIONS[code])
        elif typ == EV_ABS and code in (0x10, 0x11):          # the hat: -1, 0, 1
            pair = ("Left", "Right") if code == 0x10 else ("Up", "Down")
            self._hold(("hat", code), pair[0] if value < 0 else pair[1] if value > 0 else None)
        elif typ == EV_ABS and code in (0x00, 0x01):          # the left stick
            lo, hi = rng or (-32768, 32767)
            x = (value - lo) / (hi - lo) * 2 - 1 if hi > lo else 0
            pair = ("Left", "Right") if code == 0x00 else ("Up", "Down")
            cur = self.sources.get(("stick", code))
            if abs(x) >= STICK_ON:
                self._hold(("stick", code), pair[0] if x < 0 else pair[1])
            elif abs(x) < STICK_OFF and cur:
                self._hold(("stick", code), None)

    def tick(self):
        """Repeats due now; returns seconds until the next one (None: nothing held)."""
        t = self.now()
        for d, due in list(self.held.items()):
            if t >= due:
                self.key(d)
                self.held[d] = t + REPEAT_EVERY
        return max(0.0, min(self.held.values()) - t) if self.held else None


def nav():
    wtype = shlex.split(os.environ.get("SHANI_WTYPE", "wtype"))

    def key(k):
        subprocess.run(wtype + ["-k", k], stdin=subprocess.DEVNULL)

    def say(s):
        print(s, flush=True)

    path = os.environ.get("SHANI_INPUT_DEVICES", "/proc/bus/input/devices")
    try:
        pads = devices(open(path).read())
    except OSError:
        pads = []
    root = os.environ.get("SHANI_INPUT_DIR", "/dev/input")
    fds = {}
    for p in pads:
        try:
            fds[os.open(os.path.join(root, p["event"]), os.O_RDONLY | os.O_NONBLOCK)] = {}
        except OSError:
            pass
    if not fds:
        return 1
    n = Nav(key, say)
    say("ready")
    while fds:
        wait = n.tick()
        ready, _, _ = select.select(list(fds), [], [], wait)
        for fd in ready:
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError:
                data = b""
            if not data:                          # unplugged (or the stream ended)
                os.close(fd)
                fds.pop(fd)
                continue
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _s, _us, typ, code, value = EVENT.unpack_from(data, i)
                if typ == EV_ABS and code in (0, 1) and code not in fds[fd]:
                    fds[fd][code] = absinfo(fd, code)
                n.event(typ, code, value, fds[fd].get(code) if typ == EV_ABS else None)
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "list":
        path = os.environ.get("SHANI_INPUT_DEVICES", "/proc/bus/input/devices")
        try:
            text = open(path).read()
        except OSError:
            text = ""
        print(json.dumps(devices(text)))
        return 0
    if len(argv) == 2 and argv[1] == "nav":
        return nav()
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
