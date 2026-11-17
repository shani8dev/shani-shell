"""Which edge swipe a finger made (shani/Common/Gestures.js), run in node."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Common" / "Gestures.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(
    node is None or not JS.exists(), reason="node is not installed"
)


def swipe(edge, dx, dy, min_px=60):
    prog = JS.read_text().replace(
        ".pragma library", ""
    ) + "\nprocess.stdout.write(JSON.stringify(classify(...%s)));" % json.dumps(
        [edge, dx, dy, min_px]
    )
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


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
    assert swipe("bottom", 0, 200) == ""  # away from the screen
    assert swipe("left", -100, 0) == ""
    assert (
        swipe("bottom", 300, -80) == ""
    )  # mostly along the edge: scrolling the dock, not a swipe
    assert swipe("top", 0, 100, 160) == ""  # a bigger screen wants a longer swipe


def test_an_unknown_edge_is_nothing():
    assert swipe("middle", 100, 100) == ""


def holds(*calls):
    """run a press/hold/click sequence the way QML calls it"""
    prog = (
        JS.read_text().replace(".pragma library", "")
        + "\nvar s = state();\n"
        + "\n".join(calls)
        + "\nprocess.stdout.write(JSON.stringify([s.long, swallowed(s)]));"
    )
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def test_a_long_press_is_a_click_that_is_swallowed():
    assert holds("press(s)", "hold(s)") == [
        True,
        True,
    ]  # the click that ends it is swallowed
    assert holds("press(s)", "hold(s)", "swallowed(s)") == [False, False]  # ... once


def test_a_plain_click_is_left_alone():
    assert holds("press(s)", "swallowed(s)") == [False, False]
    assert holds("swallowed(s)") == [False, False]


def pinch(scale, base):
    prog = JS.read_text().replace(
        ".pragma library", ""
    ) + "\nprocess.stdout.write(JSON.stringify(pinchSteps(%s, %s)));" % (scale, base)
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def test_a_pinch_zooms_the_map_a_level_per_doubling():
    assert pinch(1.5, 1) == {"steps": 0, "base": 1}  # not yet
    assert pinch(2.0, 1) == {"steps": 1, "base": 2}  # twice as far apart: one level in
    assert pinch(3.9, 2) == {"steps": 0, "base": 2}  # the next level needs 4
    assert pinch(0.5, 1) == {"steps": -1, "base": 0.5}  # half: one level out


def test_a_broken_pinch_does_nothing():
    assert pinch(0, 1)["steps"] == 0
    assert pinch(2, 0)["steps"] == 0


def away(d, dx, dy, min_px=80):
    prog = JS.read_text().replace(
        ".pragma library", ""
    ) + "\nprocess.stdout.write(JSON.stringify(dismissed(...%s)));" % json.dumps(
        [d, dx, dy, min_px]
    )
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def test_a_panel_is_swiped_away_toward_its_edge():
    assert away("right", 120, 10) is True  # Quick Settings, back to the right
    assert away("down", 0, 150) is True  # the launcher, down
    assert away("right", 50, 0) is False  # not far enough
    assert away("right", -120, 0) is False  # the wrong way
    assert away("down", 30, 100) is True
    assert away("down", 120, 100) is False  # more across than down: a sideways scroll
    assert away("sideways", 100, 0) is False


def hold(edge, dx, dy, ms, min_px=60):
    prog = JS.read_text().replace(
        ".pragma library", ""
    ) + "\nprocess.stdout.write(JSON.stringify(classifyHold(...%s)));" % json.dumps(
        [edge, dx, dy, min_px, ms]
    )
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def test_a_swipe_that_waits_at_the_bottom_is_the_overview():
    assert hold("bottom", 0, -200, 500) == "overview"
    assert hold("bottom", 0, -200, 100) == "launcher"  # a flick is still the launcher
    assert hold("left", 120, 0, 900) == "back"  # a hold changes only the bottom's


def test_a_hold_that_is_not_a_swipe_is_still_nothing():
    assert hold("bottom", 0, -10, 900) == ""


def tracked_swipe(points, edge="bottom", cancelled=False):
    """Feed movement and release timestamps, not a precomputed hold duration."""
    prog = (
        JS.read_text().replace(".pragma library", "")
        + """
const points = %s;
let s = startSwipe(points[0][0], points[0][1]);
for (const [x, y, t] of points.slice(1, -1))
    moveSwipe(s, %s, x, y, 60, 8, t);
if (%s) s = null;
const [x, y, t] = points[points.length - 1];
process.stdout.write(JSON.stringify(finishSwipe(s, %s, x, y, 60, 8, t)));
"""
        % (
            json.dumps(points),
            json.dumps(edge),
            json.dumps(cancelled),
            json.dumps(edge),
        )
    )
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def test_only_stationary_time_after_the_threshold_counts_as_a_hold():
    assert tracked_swipe([[0, 0, 0], [0, -80, 100], [0, -83, 500]]) == "overview"
    assert tracked_swipe([[0, 0, 0], [0, -80, 100], [0, -83, 499]]) == "launcher"
    # A slow moving finger and a long wait before moving are not a hold.
    assert tracked_swipe([[0, 0, 0], [0, -70, 500], [0, -150, 1000]]) == "launcher"
    assert tracked_swipe([[0, 0, 0], [0, 0, 900], [0, -150, 1000]]) == "launcher"


def test_moving_again_or_retracting_resets_the_hold():
    assert (
        tracked_swipe([[0, 0, 0], [0, -80, 100], [0, -110, 550], [0, -110, 600]])
        == "launcher"
    )
    assert (
        tracked_swipe([[0, 0, 0], [0, -80, 100], [0, -20, 550], [0, -80, 900]])
        == "launcher"
    )
    assert (
        tracked_swipe([[0, 0, 0], [0, -80, 100], [0, -80, 900]], cancelled=True) == ""
    )
    assert tracked_swipe([[0, 0, 0], [80, 0, 100], [80, 0, 900]], edge="left") == "back"
