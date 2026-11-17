"""A pen on the board (shani/Common/Pen.js), run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Common" / "Pen.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def call(fn, *args):
    prog = JS.read_text().replace(".pragma library", "") + "\nprocess.stdout.write(JSON.stringify(%s(...%s)));" % (fn, json.dumps(list(args)))
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def test_pressure_makes_the_line_thicker():
    light, hard = call("width", 6, 0.1, True), call("width", 6, 1.0, True)
    assert light < 6 < hard
    assert abs(hard - 6 * 1.65) < 1e-9
    assert call("width", 6, 2.5, True) == hard            # past 1: as at 1


def test_the_mouse_and_fingers_draw_the_chosen_width():
    assert call("width", 6, 1.0, False) == 6
    assert call("width", 6, 0, True) == 6                  # a pen that reports nothing


def test_a_broad_contact_is_a_palm():
    assert call("isPalm", 120, 90, 60) is True
    assert call("isPalm", 25, 20, 60) is False
    assert call("isPalm", None, None, 60) is False         # a panel that does not say


def test_touch_is_ignored_while_the_pen_is_near():
    assert call("rejectTouch", True, 20, 20, 60) is True
    assert call("rejectTouch", False, 20, 20, 60) is False
    assert call("rejectTouch", False, 200, 150, 60) is True
