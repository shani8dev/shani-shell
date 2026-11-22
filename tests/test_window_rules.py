"""Per-app window rules (Services/WindowRules.qml) produce valid, rich niri KDL.

The function is plain JS, so we lift it out of the QML file and run it in node.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QML = (ROOT / "shani/Services/WindowRules.qml").read_text()
node = shutil.which("node")
import pytest

pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def kdl(app, rule):
    m = re.search(r"function kdlRule\(std, r\) \{(.*?)\n    \}", QML, re.S)
    assert m, "kdlRule not found"
    src = "function kdlRule(std, r) {" + m.group(1) + "\n}\n"
    prog = src + "\nprocess.stdout.write(JSON.stringify(kdlRule(%s, %s)));" % (
        json.dumps(app),
        json.dumps(rule),
    )
    return json.loads(subprocess.run(
        [node, "-e", prog], capture_output=True, text=True, check=True
    ).stdout)


def test_modes_and_match():
    out = kdl("org.mozilla.firefox", {"mode": "fullscreen", "title": "Some window"})
    assert 'match app-id="^org\\\\.mozilla\\\\.firefox$" title="Some window"' in out
    assert "open-fullscreen true" in out
    assert "open-floating" not in out
    assert "default-column-width" not in out  # fullscreen has no initial size


def test_output_height_and_fixed_size():
    out = kdl(
        "foot", {"mode": "floating", "output": "DP-1", "width": 900, "height": 800}
    )
    assert 'open-on-output "DP-1"' in out
    assert "open-floating true" in out
    assert "default-column-width { fixed 900; }" in out
    assert "default-window-height { fixed 800; }" in out


def test_plain_tiled_rule_unchanged():
    out = kdl("foot", {"workspace": "chat", "width": 0.5})
    assert 'open-on-workspace "chat"' in out
    assert "default-column-width { proportion 0.5000; }" in out
    assert "open-floating" not in out
