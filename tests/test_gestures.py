"""Which edge swipe a finger made (shani/Common/Gestures.js), run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Common" / "Gestures.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None or not JS.exists(), reason="node is not installed")


def swipe(edge, dx, dy, min_px=60):
    prog = JS.read_text().replace(".pragma library", "") + "\nprocess.stdout.write(JSON.stringify(classify(...%s)));" % json.dumps([edge, dx, dy, min_px])
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def test_each_edge_inward_is_its_action():
    assert swipe("bottom", 0, -200) == "launcher"
    assert swipe("top", 10, 150) == "quick-settings"
    assert swipe("left", 120, -20) == "back"
    assert swipe("right", -120, 30) == "overview"


def test_a_tap_or_a_short_slip_is_no_swipe():
    assert swipe("bottom", 0, 0) == ""
    assert swipe("bottom", 0, -40) == ""
    assert swipe("left", 59, 0) == ""


def test_outward_or_along_the_edge_is_no_swipe():
    assert swipe("bottom", 0, 200) == ""          # away from the screen
    assert swipe("left", -100, 0) == ""
    assert swipe("bottom", 300, -80) == ""        # mostly along the edge: scrolling the dock, not a swipe
    assert swipe("top", 0, 100, 160) == ""        # a bigger screen wants a longer swipe


def test_an_unknown_edge_is_nothing():
    assert swipe("middle", 100, 100) == ""


def holds(*calls):
    """run a press/hold/click sequence the way QML calls it"""
    prog = (JS.read_text().replace(".pragma library", "")
            + "\nvar s = state();\n"
            + "\n".join(calls)
            + "\nprocess.stdout.write(JSON.stringify([s.long, swallowed(s)]));")
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def test_a_long_press_is_a_click_that_is_swallowed():
    assert holds("press(s)", "hold(s)") == [True, True]          # the click that ends it is swallowed
    assert holds("press(s)", "hold(s)", "swallowed(s)") == [False, False]   # ... once


def test_a_plain_click_is_left_alone():
    assert holds("press(s)", "swallowed(s)") == [False, False]
    assert holds("swallowed(s)") == [False, False]
