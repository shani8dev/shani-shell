"""The light/dark cross-fade (shani/Common/ThemeFade.js + Theme.qml), run in node.

The fade is a 300 ms walk of `darkT` from 0 to 1 when the style flips, 0 with
reduce motion; every palette token blends light<->dark by it, so the shell
cross-fades instead of snapping. Nothing animates while idle (the Behavior
only runs while darkT moves), so the idle-frames budget is untouched.
"""
import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
JS = ROOT / "shani" / "Common" / "ThemeFade.js"
THEME = ROOT / "shani" / "Common" / "Theme.qml"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def call(fn, *args):
    prog = JS.read_text().replace(".pragma library", "") + "\nprocess.stdout.write(JSON.stringify(%s));" % fn
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def blend(light, dark, t):
    return call("blendC(%s, %s, %s)" % (json.dumps(light), json.dumps(dark), json.dumps(t)))


def test_blend_endpoints_are_exact():
    light, dark = [1, 1, 1, 1], [0, 0, 0, 1]
    assert blend(light, dark, 0) == light
    assert blend(light, dark, 1) == dark


def test_blend_midpoint_is_halfway_on_every_channel():
    assert blend([1, 0, 0, 0], [0, 1, 1, 1], 0.5) == [0.5, 0.5, 0.5, 0.5]


def test_blend_clamps_out_of_range_t():
    light, dark = [0.2, 0.2, 0.2, 1], [0.8, 0.8, 0.8, 1]
    assert blend(light, dark, -1) == light
    assert blend(light, dark, 2) == dark


def test_fade_is_300ms_and_zero_with_reduce_motion():
    assert call("fadeMs(false)") == 300
    assert call("fadeMs(true)") == 0


def test_theme_walks_darkT_with_a_behavior_and_blends_tokens():
    t = THEME.read_text()
    assert "property real darkT: Settings.data.darkMode ? 1 : 0" in t
    assert "Behavior on darkT" in t and "fadeMs(Settings.data.reduceMotion)" in t
    for token in ("bg", "text", "glass", "card", "surface1"):
        assert re.search(r"readonly property color %s:.*\bmix\(" % token, t), token


def test_theme_keeps_no_snapping_dark_branch_on_core_tokens():
    t = THEME.read_text()
    # the wallpaper choice still switches discretely (it is a picture, not a
    # colour) but the core colour tokens no longer branch on `dark` directly
    for bad in ("readonly property color bg: contrast ? (dark ?", "readonly property color text: contrast ? (dark ?"):
        assert bad not in t
