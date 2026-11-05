"""bridge/input-kinds.py on udev databases recorded in dev/udev-db/: a real keyboard
is told from the power button, the lid, the video bus and virtual keyboards."""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "bridge" / "input-kinds.py"


def kinds(db):
    out = subprocess.run([sys.executable, str(TOOL)], capture_output=True, text=True, check=True,
                         env=dict(os.environ, SHANI_UDEV_DB=str(db))).stdout
    return json.loads(out)


def test_a_laptop_has_a_keyboard():
    assert kinds(ROOT / "dev/udev-db/laptop.txt") == {"keyboard": True, "touchscreen": False, "tabletSwitch": False}


def test_buttons_and_virtual_keyboards_are_not_a_keyboard():
    k = kinds(ROOT / "dev/udev-db/tablet-no-keyboard.txt")
    assert k == {"keyboard": False, "touchscreen": True, "tabletSwitch": True}


def test_nothing_known_is_no_keyboard(tmp_path):
    (tmp_path / "db").write_text("")
    assert kinds(tmp_path / "db")["keyboard"] is False
