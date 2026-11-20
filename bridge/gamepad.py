#!/usr/bin/env python3
"""gamepad — the game controllers connected, and one controller's buttons live.

  gamepad.py list           JSON: [{"name", "event", "uniq"}] - every joystick the
                            kernel has (/proc/bus/input/devices, "jsN" among its
                            handlers): USB and Bluetooth alike, unlike /dev/input/by-id
  gamepad.py nav            a controller moves around the desktop while it runs:
                            d-pad and left stick -> arrow keys (repeating while held),
                            A Return, B Escape (keys sent with wtype, as the screen
                            keyboard does); and one line per shell action on stdout:
                            menu (X), launcher (Y), guide (Guide: the assistant), sidebar (Start),
                            overview (Select), workspace-prev / workspace-next (LB / RB),
                            "used" once when a controller first drives the desktop,
                            "active" at most every 5 s while one does.
                            While the screen keyboard is open (the shell writes
                            "osk on" / "osk off" to stdin) the pad drives its keys
                            instead, as lines: osk-up/down/left/right (repeating),
                            osk-press (A), osk-close (B), osk-backspace (X),
                            osk-space (Y), osk-enter (Start), osk-shift (Select).
                            The right stick moves the pointer (with LB held: scrolls,
                            LB's own action then on its release only if it did not)
                            and the triggers click
                            (RT, or a click of the right stick: left; LT: right), for
                            whatever arrows cannot reach - a web page, a canvas - on
                            a virtual mouse made through /dev/uinput (game-devices-udev
                            gives the seat's person that node, as Steam needs it too).
                            "pointer" on stdout once it exists; without it, none.
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

EVENT = struct.Struct("llHHi")  # struct input_event: timeval, type, code, value
EV_KEY, EV_ABS = 1, 3

# the kernel's gamepad codes (linux/input-event-codes.h), by the face a person sees
BUTTONS = {
    0x130: "A",
    0x131: "B",
    0x132: "C",
    0x133: "Y",
    0x134: "X",
    0x135: "Z",
    0x136: "LB",
    0x137: "RB",
    0x138: "LT",
    0x139: "RT",
    0x13A: "Select",
    0x13B: "Start",
    0x13C: "Home",
    0x13D: "Left stick",
    0x13E: "Right stick",
    0x220: "Up",
    0x221: "Down",
    0x222: "Left",
    0x223: "Right",
    # older joysticks: BTN_TRIGGER … BTN_BASE6
    0x120: "Trigger",
    0x121: "Thumb",
    0x122: "Thumb 2",
    0x123: "Top",
    0x124: "Top 2",
    0x125: "Pinkie",
    0x126: "Base",
    0x127: "Base 2",
    0x128: "Base 3",
    0x129: "Base 4",
    0x12A: "Base 5",
    0x12B: "Base 6",
}
AXES = {
    0x00: "left-x",
    0x01: "left-y",
    0x02: "left-trigger",
    0x03: "right-x",
    0x04: "right-y",
    0x05: "right-trigger",
    0x10: "dpad-x",
    0x11: "dpad-y",
}


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
        fcntl.ioctl(
            fd, 0x80184540 + code, buf
        )  # _IOR('E', 0x40 + code, struct input_absinfo)
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
                if last.get(code) != x:  # a stick at rest jitters: only changes
                    last[code] = x
                    print(f"axis {AXES[code]} {x}", flush=True)


# nav: what each button does on the desktop
NAV_KEYS = {0x130: "Return", 0x131: "Escape"}
NAV_ACTIONS = {
    0x134: "menu",
    0x133: "launcher",
    0x13C: "guide",
    0x13B: "sidebar",
    0x13A: "overview",
    0x136: "workspace-prev",
    0x137: "workspace-next",
}
# the screen keyboard open: its own meaning for the buttons (Steam's keyboard's, by position)
OSK_BUTTONS = {
    0x130: "osk-press",
    0x131: "osk-close",
    0x134: "osk-backspace",
    0x133: "osk-space",
    0x13B: "osk-enter",
    0x13A: "osk-shift",
}
DPAD = {0x220: "Up", 0x221: "Down", 0x222: "Left", 0x223: "Right"}
REPEAT_DELAY, REPEAT_EVERY = 0.4, 0.12
STICK_ON, STICK_OFF = 0.55, 0.35  # hysteresis: a stick near the edge does not flicker


class Nav:
    """Controller events -> keys and shell actions; held directions repeat."""

    def __init__(self, key, say, now=time.monotonic):
        self.key, self.say, self.now = key, say, now
        self.held = {}  # direction -> time of the next repeat
        self.sources = {}  # (source) -> direction it holds
        self.used = False
        self.ranges = {}
        self.osk = False  # the screen keyboard is open: the pad drives it
        self.pointer = None  # a Pointer, when uinput gave one
        self.aim = [0.0, 0.0]  # the right stick, -1 … 1
        self.carry = [0.0, 0.0]  # sub-pixel motion not sent yet
        self.last_move = None
        self.clicks = {}  # source -> the button it holds down
        # LB held, the right stick scrolls instead (a web page, a long list): LB's own
        # action waits for its release, and is dropped when it scrolled meanwhile
        self.scroll_hold = False
        self.scrolled = False
        self.wheel_carry = [0.0, 0.0]
        self.last_active = None

    def set_osk(self, on):
        self.osk = on
        self.held.clear()  # a direction held across the switch stops
        self.sources.clear()

    def _direction(self, d):
        if self.osk:
            self.say("osk-" + d.lower())
        else:
            self.key(d)

    def _use(self):
        if not self.used:
            self.used = True
            self.say("used")
        # now and then while it is used (a field it reaches brings the screen keyboard)
        t = self.now()
        if self.last_active is None or t - self.last_active >= ACTIVE_EVERY:
            self.last_active = t
            self.say("active")

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
                self._direction(direction)
                self.held[direction] = self.now() + REPEAT_DELAY

    def _click(self, source, button, down):
        if not self.pointer:
            return
        if down and source not in self.clicks:
            self._use()
            self.clicks[source] = button
            self.pointer.button(button, True)
        elif not down and source in self.clicks:
            self.pointer.button(self.clicks.pop(source), False)

    def event(self, typ, code, value, rng=None, right_stick=True):
        """right_stick: the device has ABS_RX/RY. Without them ABS_Z/RZ are its
        right stick (DirectInput pads), not triggers, and click nothing."""
        if typ == EV_KEY and code in (0x139, 0x13E, 0x138) and value in (0, 1):
            # RT and a click of the right stick: left; LT: right
            self._click(
                ("key", code), BTN_RIGHT if code == 0x138 else BTN_LEFT, value == 1
            )
            return
        if typ == EV_ABS and code in (0x03, 0x04):  # the right stick: the pointer
            lo, hi = rng or (-32768, 32767)
            self.aim[code - 3] = (value - lo) / (hi - lo) * 2 - 1 if hi > lo else 0.0
            if self.pointer and any(abs(a) > DEAD for a in self.aim):
                self._use()
            return
        if typ == EV_ABS and code in (0x02, 0x05):  # the triggers, as axes
            if right_stick:
                lo, hi = rng or (0, 255)
                x = (value - lo) / (hi - lo) if hi > lo else 0
                held = ("abs", code) in self.clicks
                if x >= 0.5 or (held and x > 0.3):
                    self._click(
                        ("abs", code), BTN_RIGHT if code == 0x02 else BTN_LEFT, True
                    )
                elif held:
                    self._click(("abs", code), None, False)
            return
        if typ == EV_KEY and value in (0, 1):
            if code in DPAD:
                self._hold(("btn", code), DPAD[code] if value else None)
            elif value == 1 and self.osk and code in OSK_BUTTONS:
                self._use()
                self.say(OSK_BUTTONS[code])
            elif value == 1 and code in NAV_KEYS:
                self._use()
                self.key(NAV_KEYS[code])
            elif code == SCROLL_BUTTON and self.pointer and not self.osk:
                if value == 1:
                    self.scroll_hold, self.scrolled = True, False
                else:
                    if self.scroll_hold and not self.scrolled:
                        self._use()
                        self.say(NAV_ACTIONS[code])
                    self.scroll_hold = False
                    self.wheel_carry = [0.0, 0.0]
            elif value == 1 and code in NAV_ACTIONS:
                self._use()
                self.say(NAV_ACTIONS[code])
        elif typ == EV_ABS and code in (0x10, 0x11):  # the hat: -1, 0, 1
            pair = ("Left", "Right") if code == 0x10 else ("Up", "Down")
            self._hold(
                ("hat", code), pair[0] if value < 0 else pair[1] if value > 0 else None
            )
        elif typ == EV_ABS and code in (0x00, 0x01):  # the left stick
            lo, hi = rng or (-32768, 32767)
            x = (value - lo) / (hi - lo) * 2 - 1 if hi > lo else 0
            pair = ("Left", "Right") if code == 0x00 else ("Up", "Down")
            cur = self.sources.get(("stick", code))
            if abs(x) >= STICK_ON:
                self._hold(("stick", code), pair[0] if x < 0 else pair[1])
            elif abs(x) < STICK_OFF and cur:
                self._hold(("stick", code), None)

    def tick(self):
        """Repeats and pointer motion due now; returns seconds until the next
        (None: nothing held, the stick at rest)."""
        t = self.now()
        for d, due in list(self.held.items()):
            if t >= due:
                self._direction(d)
                self.held[d] = t + REPEAT_EVERY
        waits = [max(0.0, min(self.held.values()) - t)] if self.held else []
        if self.pointer and any(abs(a) > DEAD for a in self.aim):
            dt = min(t - self.last_move, 0.1) if self.last_move is not None else FRAME
            self.last_move = t
            if self.scroll_hold:
                # notches of the wheel: up on the stick scrolls up (the wheel's +), right scrolls right
                self.scrolled = True
                self.wheel_carry[0] += (
                    stick_speed(self.aim[0]) / TOP_SPEED * TOP_NOTCHES * dt
                )
                self.wheel_carry[1] -= (
                    stick_speed(self.aim[1]) / TOP_SPEED * TOP_NOTCHES * dt
                )
                h, v = int(self.wheel_carry[0]), int(self.wheel_carry[1])
                if h or v:
                    self.wheel_carry[0] -= h
                    self.wheel_carry[1] -= v
                    self.pointer.wheel(h, v)
            else:
                for i in (0, 1):
                    self.carry[i] += stick_speed(self.aim[i]) * dt
                dx, dy = int(self.carry[0]), int(self.carry[1])
                if dx or dy:
                    self.carry[0] -= dx
                    self.carry[1] -= dy
                    self.pointer.move(dx, dy)
            waits.append(FRAME)
        else:
            self.last_move = None
            self.carry = [0.0, 0.0]
        return min(waits) if waits else None


# ---- the pointer: a virtual mouse through uinput (linux/uinput.h) ----
EV_SYN, EV_REL = 0, 2
REL_X, REL_Y, REL_HWHEEL, REL_WHEEL = 0, 1, 6, 8
BTN_LEFT, BTN_RIGHT = 0x110, 0x111
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT = 0x40045564, 0x40045565, 0x40045566
UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = (
    0x405C5503,
    0x5501,
    0x5502,
)  # struct uinput_setup: 92 bytes
POINTER_NAME = b"Shani controller pointer"


class Pointer:
    """A mouse the desktop sees like any other: move(dx, dy), button(code, down)."""

    def __init__(self, path=None, ioctl=fcntl.ioctl):
        self.fd = os.open(
            path or os.environ.get("SHANI_UINPUT", "/dev/uinput"),
            os.O_WRONLY | os.O_NONBLOCK,
        )
        try:
            ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
            ioctl(self.fd, UI_SET_EVBIT, EV_REL)
            for b in (BTN_LEFT, BTN_RIGHT):
                ioctl(self.fd, UI_SET_KEYBIT, b)
            for r in (REL_X, REL_Y, REL_HWHEEL, REL_WHEEL):
                ioctl(self.fd, UI_SET_RELBIT, r)
            # struct input_id (bustype BUS_VIRTUAL, vendor, product, version), name[80], ff_effects_max
            ioctl(
                self.fd,
                UI_DEV_SETUP,
                struct.pack("4H80sI", 0x06, 0x5348, 0x0001, 1, POINTER_NAME, 0),
            )
            ioctl(self.fd, UI_DEV_CREATE)
        except OSError:
            os.close(self.fd)
            raise
        self.ioctl = ioctl

    def _emit(self, events):
        data = b"".join(
            EVENT.pack(0, 0, t, c, v) for t, c, v in events + [(EV_SYN, 0, 0)]
        )
        try:
            os.write(self.fd, data)
        except OSError:
            pass

    def move(self, dx, dy):
        self._emit([(EV_REL, REL_X, dx), (EV_REL, REL_Y, dy)])

    def button(self, code, down):
        self._emit([(EV_KEY, code, 1 if down else 0)])

    def wheel(self, h, v):
        self._emit([(EV_REL, c, n) for c, n in ((REL_HWHEEL, h), (REL_WHEEL, v)) if n])

    def close(self):
        try:
            self.ioctl(self.fd, UI_DEV_DESTROY)
        except OSError:
            pass
        os.close(self.fd)


# the right stick's travel past the dead zone -> pixels a second (squared: fine
# aim near the centre, across a television at the edge)
DEAD, TOP_SPEED, FRAME = 0.15, 1500.0, 1 / 60
ACTIVE_EVERY = 5.0  # "active" at most this often, seconds
TOP_NOTCHES = 15.0  # LB held: the wheel's notches a second, the stick all the way
SCROLL_BUTTON = 0x136  # LB


def stick_speed(x):
    a = abs(x)
    if a <= DEAD:
        return 0.0
    v = ((a - DEAD) / (1 - DEAD)) ** 2 * TOP_SPEED
    return v if x > 0 else -v


def nav():
    wtype = shlex.split(os.environ.get("SHANI_WTYPE", "wtype"))

    def key(k):
        subprocess.run(wtype + ["-k", k], stdin=subprocess.DEVNULL)

    def say(s):
        print(s, flush=True)

    path = os.environ.get("SHANI_INPUT_DEVICES", "/proc/bus/input/devices")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            pads = devices(fh.read())
    except OSError:
        pads = []
    root = os.environ.get("SHANI_INPUT_DIR", "/dev/input")
    fds = {}
    for p in pads:
        try:
            fds[
                os.open(os.path.join(root, p["event"]), os.O_RDONLY | os.O_NONBLOCK)
            ] = {}
        except OSError:
            pass
    if not fds:
        return 1
    n = Nav(key, say)
    try:
        n.pointer = Pointer()
    except OSError:
        n.pointer = None  # no uinput: arrows and buttons only
    say("ready")
    if n.pointer:
        say("pointer")
    control = sys.stdin.fileno()  # "osk on" / "osk off" from the shell
    listen = True
    while fds:
        wait = n.tick()
        ready, _, _ = select.select(
            list(fds) + ([control] if listen else []), [], [], wait
        )
        for fd in ready:
            if fd == control:
                line = sys.stdin.readline()
                if not line:
                    listen = False  # no shell on the other end: plain navigation
                elif line.strip() in ("osk on", "osk off"):
                    n.set_osk(line.strip() == "osk on")
                continue
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError:
                data = b""
            if not data:  # unplugged (or the stream ended)
                os.close(fd)
                fds.pop(fd)
                continue
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _s, _us, typ, code, value = EVENT.unpack_from(data, i)
                if typ == EV_ABS and code in (0, 1, 2, 3, 4, 5) and code not in fds[fd]:
                    fds[fd][code] = absinfo(fd, code)
                if "rx" not in fds[fd]:
                    fds[fd]["rx"] = (
                        absinfo(fd, 0x03) is not None
                        or os.environ.get("SHANI_PAD_RIGHT_STICK") == "1"
                    )
                n.event(
                    typ,
                    code,
                    value,
                    fds[fd].get(code) if typ == EV_ABS else None,
                    fds[fd]["rx"],
                )
    if n.pointer:
        n.pointer.close()
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "list":
        path = os.environ.get("SHANI_INPUT_DEVICES", "/proc/bus/input/devices")
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            text = ""
        print(json.dumps(devices(text)))
        return 0
    if len(argv) == 2 and argv[1] == "nav":
        return nav()
    if (
        len(argv) == 3
        and argv[1] == "watch"
        and argv[2].startswith("event")
        and "/" not in argv[2]
    ):
        return watch(
            os.path.join(os.environ.get("SHANI_INPUT_DIR", "/dev/input"), argv[2])
        )
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
