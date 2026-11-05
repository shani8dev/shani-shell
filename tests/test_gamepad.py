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
