"""bridge/gamepad.py: the controllers the kernel has, and one's buttons read live."""
import json
import os
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge" / "gamepad.py"
EVENT = struct.Struct("llHHi")


def test_list_has_the_joysticks_not_their_motion_sensors():
    out = subprocess.run([sys.executable, str(BRIDGE), "list"], capture_output=True, text=True, check=True,
                         env=dict(os.environ, SHANI_INPUT_DEVICES=str(ROOT / "dev/input-devices.txt"))).stdout
    assert json.loads(out) == [
        {"name": "DualSense Wireless Controller", "event": "event21", "uniq": "7c:66:ef:12:34:56"},
        {"name": "Microsoft X-Box 360 pad", "event": "event23", "uniq": ""}]


def test_no_proc_file_is_no_controllers(tmp_path):
    out = subprocess.run([sys.executable, str(BRIDGE), "list"], capture_output=True, text=True, check=True,
                         env=dict(os.environ, SHANI_INPUT_DEVICES=str(tmp_path / "none"))).stdout
    assert json.loads(out) == []


def test_watch_reads_presses_and_sticks_and_ends_with_the_device(tmp_path):
    fifo = tmp_path / "event21"
    os.mkfifo(fifo)
    p = subprocess.Popen([sys.executable, str(BRIDGE), "watch", "event21"], stdout=subprocess.PIPE, text=True,
                         env=dict(os.environ, SHANI_INPUT_DIR=str(tmp_path)))
    lines = []
    t = threading.Thread(target=lambda: [lines.append(x.strip()) for x in p.stdout], daemon=True)
    t.start()
    with open(fifo, "wb") as w:
        w.write(EVENT.pack(0, 0, 1, 0x130, 1) + EVENT.pack(0, 0, 0, 0, 0))     # A down, SYN
        w.write(EVENT.pack(0, 0, 1, 0x130, 0))                                 # A up
        w.write(EVENT.pack(0, 0, 3, 0x00, 32767) + EVENT.pack(0, 0, 3, 0x00, 32767))   # right, twice: once
        w.write(EVENT.pack(0, 0, 1, 0x223, 1))                                 # d-pad right
    assert p.wait(timeout=5) == 0                                              # the device went: it ends
    t.join(2)
    assert lines == ["ready", "press A", "release A", "axis left-x 1.0", "press Right"]


def test_watch_takes_only_an_event_node_name():
    p = subprocess.run([sys.executable, str(BRIDGE), "watch", "../../etc/passwd"], capture_output=True, text=True)
    assert p.returncode == 2 and p.stdout == ""


# ---- nav: a controller moving around the desktop ----
sys.path.insert(0, str(BRIDGE.parent))
gamepad = __import__("gamepad")


class Clock:
    t = 0.0

    def __call__(self):
        return self.t


def nav_with_clock():
    keys, said, clock = [], [], Clock()
    return gamepad.Nav(keys.append, said.append, clock), keys, said, clock


def test_the_mapping():
    n, keys, said, _ = nav_with_clock()
    for code in (0x130, 0x131, 0x134, 0x133, 0x13b, 0x13a, 0x13c, 0x136, 0x137):
        n.event(1, code, 1)
        n.event(1, code, 0)
    assert keys == ["Return", "Escape"]
    assert said == ["used", "menu", "launcher", "sidebar", "overview", "launcher", "workspace-prev", "workspace-next"]


def test_a_held_direction_repeats_and_stops_on_release():
    n, keys, _, clock = nav_with_clock()
    n.event(1, 0x221, 1)                      # d-pad down, held
    assert keys == ["Down"]
    clock.t = 0.3; n.tick()
    assert keys == ["Down"]                   # not before the delay
    clock.t = 0.41; n.tick()
    clock.t = 0.54; n.tick()
    assert keys == ["Down", "Down", "Down"]
    n.event(1, 0x221, 0)
    clock.t = 2.0
    assert n.tick() is None and keys == ["Down", "Down", "Down"]


def test_the_hat_and_the_left_stick_are_arrows_too():
    n, keys, _, _ = nav_with_clock()
    n.event(3, 0x10, 1); n.event(3, 0x10, 0)              # hat right
    n.event(3, 0x01, -30000, (-32768, 32767))             # stick up
    n.event(3, 0x01, -20000, (-32768, 32767))             # still up (hysteresis): no repeat press
    n.event(3, 0x01, 0, (-32768, 32767))                  # centred
    n.event(3, 0x00, 255, (0, 255))                       # a 0..255 stick, right
    assert keys == ["Right", "Up", "Right"]


def test_the_right_stick_and_triggers_do_nothing():
    n, keys, said, _ = nav_with_clock()
    n.event(3, 0x03, 32767); n.event(3, 0x05, 255); n.event(1, 0x138, 1)
    assert keys == [] and said == []


def test_nav_reads_every_pad_and_sends_keys_with_wtype(tmp_path):
    (tmp_path / "devices").write_text((ROOT / "dev/input-devices.txt").read_text())
    for ev in ("event21", "event23"):
        os.mkfifo(tmp_path / ev)
    log = tmp_path / "wtype.log"
    fake = tmp_path / "wtype"
    fake.write_text(f"#!/bin/sh\necho \"$*\" >> {log}\n")
    fake.chmod(0o755)
    w21 = os.open(tmp_path / "event21", os.O_RDWR | os.O_NONBLOCK)   # writers first: a FIFO without one is at its end
    w23 = os.open(tmp_path / "event23", os.O_RDWR | os.O_NONBLOCK)
    p = subprocess.Popen([sys.executable, str(BRIDGE), "nav"], stdout=subprocess.PIPE, text=True,
                         env=dict(os.environ, SHANI_INPUT_DEVICES=str(tmp_path / "devices"),
                                  SHANI_INPUT_DIR=str(tmp_path), SHANI_WTYPE=str(fake)))
    assert p.stdout.readline().strip() == "ready"
    os.write(w21, EVENT.pack(0, 0, 1, 0x130, 1) + EVENT.pack(0, 0, 1, 0x130, 0))   # A on one pad
    os.write(w23, EVENT.pack(0, 0, 1, 0x13b, 1))                                   # Start on the other
    assert p.stdout.readline().strip() == "used"
    assert p.stdout.readline().strip() == "sidebar"
    os.close(w21); os.close(w23)
    assert p.wait(timeout=5) == 0                                                  # both gone: it ends
    assert log.read_text().split("\n")[0] == "-k Return"


def test_nav_never_grabs_a_controller():
    # EVIOCGRAB (0x40044590) would take the controller from a game: never used
    src = BRIDGE.read_text()
    assert "EVIOCGRAB" not in src and "0x40044590" not in src.lower()


# ---- the screen keyboard open: the pad drives its keys ----

def test_with_the_screen_keyboard_open_the_pad_types_on_it():
    n, keys, said, clock = nav_with_clock()
    n.set_osk(True)
    for code in (0x130, 0x131, 0x134, 0x133, 0x13b, 0x13a, 0x136):
        n.event(1, code, 1)
        n.event(1, code, 0)
    n.event(3, 0x10, 1)                   # hat right
    n.event(3, 0x10, 0)
    n.event(1, 0x220, 1)                  # d-pad up, held: repeats on the keyboard too
    clock.t = 0.45
    n.tick()
    n.event(1, 0x220, 0)
    assert keys == []                     # nothing typed into the app behind
    assert said == ["used", "osk-press", "osk-close", "osk-backspace", "osk-space", "osk-enter", "osk-shift",
                    "workspace-prev", "osk-right", "osk-up", "osk-up"]


def test_closing_the_keyboard_gives_the_pad_back_to_the_desktop():
    n, keys, said, _ = nav_with_clock()
    n.set_osk(True)
    n.event(1, 0x221, 1)                  # held down while the keyboard closes
    n.set_osk(False)
    n.event(1, 0x221, 0)
    n.event(1, 0x130, 1)
    n.event(1, 0x221, 1)
    assert keys == ["Return", "Down"] and said == ["used", "osk-down"]


def test_nav_listens_for_the_keyboard_on_stdin(tmp_path):
    (tmp_path / "devices").write_text((ROOT / "dev/input-devices.txt").read_text())
    fifo = tmp_path / "event21"
    os.mkfifo(fifo)
    os.mkfifo(tmp_path / "event23")
    typed = tmp_path / "typed"
    p = subprocess.Popen([sys.executable, str(BRIDGE), "nav"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
                         env=dict(os.environ, SHANI_INPUT_DIR=str(tmp_path), SHANI_INPUT_DEVICES=str(tmp_path / "devices"),
                                  SHANI_WTYPE=f"sh -c 'echo \"$*\" >> {typed}' wtype"))
    w = open(fifo, "wb", buffering=0)
    open(tmp_path / "event23", "wb").close()
    assert p.stdout.readline().strip() == "ready"
    w.write(EVENT.pack(0, 0, 1, 0x130, 1))                    # A: Return into the app
    p.stdin.write("osk on\n"); p.stdin.flush()
    time.sleep(0.3)
    w.write(EVENT.pack(0, 0, 1, 0x130, 0) + EVENT.pack(0, 0, 1, 0x130, 1))     # A: a key on the keyboard
    lines = [p.stdout.readline().strip() for _ in range(2)]
    w.close()
    p.wait(timeout=5)
    assert lines == ["used", "osk-press"]
    assert typed.read_text().split() == ["-k", "Return"]


# ---- the pointer: the right stick moves it, the triggers click ----

class FakePointer:
    def __init__(self):
        self.moves, self.buttons = [], []

    def move(self, dx, dy):
        self.moves.append((dx, dy))

    def button(self, code, down):
        self.buttons.append((code, down))


def nav_with_pointer():
    n, keys, said, clock = nav_with_clock()
    n.pointer = FakePointer()
    return n, keys, said, clock


def test_the_right_stick_moves_the_pointer_faster_the_further_it_goes():
    n, keys, _, clock = nav_with_pointer()
    n.event(3, 0x03, 16384)               # half right
    assert n.tick() == gamepad.FRAME      # moving: woken every frame
    for _ in range(60):                   # one second
        clock.t += gamepad.FRAME
        n.tick()
    half = sum(dx for dx, _ in n.pointer.moves)
    n.pointer.moves.clear()
    n.event(3, 0x03, 32767)               # all the way
    for _ in range(60):
        clock.t += gamepad.FRAME
        n.tick()
    full = sum(dx for dx, _ in n.pointer.moves)
    assert 200 < half < 400 and 1400 < full <= 1500 and all(dy == 0 for _, dy in n.pointer.moves)
    assert keys == []                     # the pointer is not the arrows


def test_the_dead_zone_and_rest_stop_it():
    n, _, _, clock = nav_with_pointer()
    n.event(3, 0x04, 3000)                # a worn stick resting slightly off centre
    assert n.tick() is None and n.pointer.moves == []
    n.event(3, 0x04, -32768)
    clock.t += 0.5
    n.tick()
    n.event(3, 0x04, 0)
    n.pointer.moves.clear()
    clock.t += 0.5
    assert n.tick() is None and n.pointer.moves == []


def test_triggers_click_as_buttons_and_as_axes():
    n, _, _, _ = nav_with_pointer()
    n.event(1, 0x139, 1); n.event(1, 0x139, 0)           # RT, digital
    n.event(1, 0x138, 1); n.event(1, 0x138, 0)           # LT
    n.event(1, 0x13e, 1); n.event(1, 0x13e, 0)           # right stick click
    n.event(3, 0x05, 200, (0, 255)); n.event(3, 0x05, 120, (0, 255)); n.event(3, 0x05, 10, (0, 255))
    L, R = gamepad.BTN_LEFT, gamepad.BTN_RIGHT
    assert n.pointer.buttons == [(L, True), (L, False), (R, True), (R, False), (L, True), (L, False),
                                 (L, True), (L, False)]      # an analog trigger: down past half, held until let go


def test_a_pad_without_a_right_stick_axis_pair_never_clicks_from_z():
    n, _, _, _ = nav_with_pointer()
    n.event(3, 0x05, 255, (0, 255), right_stick=False)   # a DirectInput pad's right stick, not a trigger
    assert n.pointer.buttons == []


def test_no_uinput_no_pointer_and_nothing_breaks():
    n, keys, said, _ = nav_with_clock()                  # pointer None
    n.event(3, 0x03, 32767)
    n.event(1, 0x139, 1)
    assert n.tick() is None and keys == [] and said == []


def test_pointer_device_setup_is_what_the_kernel_expects(tmp_path):
    calls = []
    node = tmp_path / "uinput"
    node.write_bytes(b"")
    p = gamepad.Pointer(str(node), ioctl=lambda fd, req, arg=0: calls.append((req, arg)))
    p.move(3, -2)
    p.close()
    setup = [a for r, a in calls if r == gamepad.UI_DEV_SETUP][0]
    assert len(setup) == 92 and setup[8:8 + len(gamepad.POINTER_NAME)] == gamepad.POINTER_NAME
    assert (gamepad.UI_SET_EVBIT, gamepad.EV_REL) in calls and (gamepad.UI_SET_KEYBIT, gamepad.BTN_LEFT) in calls
    assert [r for r, _ in calls][-2:] == [gamepad.UI_DEV_CREATE, gamepad.UI_DEV_DESTROY]
    data = node.read_bytes()
    events = [EVENT.unpack_from(data, i)[2:] for i in range(0, len(data), EVENT.size)]
    assert events == [(2, 0, 3), (2, 1, -2), (0, 0, 0)]
