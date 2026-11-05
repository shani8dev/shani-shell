"""bridge/tablet-mode.py: the SW_TABLET_MODE switch, through a FIFO standing in for its node."""
import os
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "bridge" / "tablet-mode.py"
EVENT = struct.Struct("llHHi")
DEVICES = """I: Bus=0019 Vendor=0000 Product=0000 Version=0000
N: Name="Lid Switch"
H: Handlers=event1
B: EV=21
B: SW=1

I: Bus=0019 Vendor=0000 Product=0000 Version=0000
N: Name="Intel Virtual Switches"
H: Handlers=event13
B: EV=21
B: SW=2
"""


def test_folding_and_unfolding(tmp_path):
    (tmp_path / "devices").write_text(DEVICES)
    os.mkfifo(tmp_path / "event13")
    p = subprocess.Popen([sys.executable, str(TOOL)], stdout=subprocess.PIPE, text=True,
                         env=dict(os.environ, SHANI_INPUT_DEVICES=str(tmp_path / "devices"), SHANI_INPUT_DIR=str(tmp_path)))
    w = os.open(tmp_path / "event13", os.O_WRONLY)          # waits for the reader to open its end
    os.write(w, EVENT.pack(0, 0, 5, 1, 1) + EVENT.pack(0, 0, 0, 0, 0) + EVENT.pack(0, 0, 5, 0, 1))   # tablet; the lid is not it
    os.write(w, EVENT.pack(0, 0, 5, 1, 1) + EVENT.pack(0, 0, 5, 1, 0))                              # again (no news), then laptop
    os.close(w)
    out, _ = p.communicate(timeout=5)
    assert out.split() == ["tablet", "laptop"]


def test_no_switch_no_reader(tmp_path):
    (tmp_path / "devices").write_text(DEVICES.split("\n\n")[0])
    p = subprocess.run([sys.executable, str(TOOL)], capture_output=True, text=True,
                       env=dict(os.environ, SHANI_INPUT_DEVICES=str(tmp_path / "devices"), SHANI_INPUT_DIR=str(tmp_path)))
    assert p.returncode == 1 and p.stdout == ""
