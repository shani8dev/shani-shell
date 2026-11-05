"""The slow-charger rule (shani/Services/Charger.js), run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Services" / "Charger.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def slow(*args):
    prog = JS.read_text().replace(".pragma library", "") + "\nprocess.stdout.write(JSON.stringify(tooSlow(%s)));" % ", ".join(map(json.dumps, args))
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def test_plugged_in_and_still_running_down_for_a_while():
    assert slow(False, True, 120, 0) is True


def test_a_moment_dip_is_not_a_slow_charger():
    assert slow(False, True, 10, 0.5) is False


def test_a_real_draw_says_it_at_once():
    assert slow(False, True, 5, 6.5) is True


def test_on_battery_or_charging_never():
    assert slow(True, True, 999, 20) is False
    assert slow(False, False, 999, 20) is False
