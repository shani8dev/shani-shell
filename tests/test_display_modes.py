"""The built-in panel's mode on battery (shani/Services/DisplayModes.js), run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Services" / "DisplayModes.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")

PANEL = {"name": "eDP-1", "mode": "2560x1600@165.000",
         "modes": [{"w": 2560, "h": 1600, "r": 165.0}, {"w": 2560, "h": 1600, "r": 60.0},
                   {"w": 2560, "h": 1600, "r": 48.0}, {"w": 1920, "h": 1200, "r": 165.0},
                   {"w": 1920, "h": 1200, "r": 59.95}]}


def battery_mode(output, configured=""):
    src = JS.read_text().replace(".pragma library", "")
    prog = src + "\nprocess.stdout.write(JSON.stringify(batteryMode(%s, %s)));" % (json.dumps(output), json.dumps(configured))
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def test_a_fast_panel_steps_down_to_60_not_below() -> None:
    assert battery_mode(PANEL) == "2560x1600@60.000"


def test_the_configured_resolution_is_kept() -> None:
    assert battery_mode(PANEL, "1920x1200@165.000") == "1920x1200@59.950"


def test_a_60hz_panel_is_left_alone() -> None:
    assert battery_mode({"name": "eDP-1", "mode": "1920x1080@60.000", "modes": [{"w": 1920, "h": 1080, "r": 60.0}]}) == ""


def test_an_external_monitor_is_never_touched() -> None:
    assert battery_mode(dict(PANEL, name="DP-2")) == ""
