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
