"""Static + unit checks for the Tour / What's new fixes.

Tour.qml and WhatsNew.qml are QML singletons/panels, so their wiring is checked
from source; the pure rules in WhatsNew.js are executed in node, as in
tests/test_whatsnew.py.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOUR = ROOT / "shani/Modules/Tour/Tour.qml"
NOTES = ROOT / "shani/Services/WhatsNew.qml"
LOGIC = ROOT / "shani/Services/WhatsNew.js"
NODE = shutil.which("node")


def call_js(expr):
    prog = (
        LOGIC.read_text().replace(".pragma library", "")
        + "\nprocess.stdout.write(JSON.stringify(%s));" % expr
    )
    result = subprocess.run([NODE, "-e", prog], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_tour_back_button_reachable_without_a_keyboard():
    src = TOUR.read_text()
    back = next(l for l in src.splitlines() if 'Tr.t("Back")' in l)
    assert "visible: win.step > 0" in back
    assert "win.step--" in back
    # the keyboard path stays too
    assert "Keys.onLeftPressed: if (win.step > 0) win.step--" in src


def test_tour_card_is_named_for_screen_readers():
    src = TOUR.read_text()
    card = src.split("id: blurCard", 1)[1].split("anchors.centerIn", 1)[0]
    assert "Accessible.role: Accessible.Dialog" in card
    assert "Accessible.name: win.cards[win.step].title" in card


def test_whatsnew_reads_the_version_only_after_the_state_is_known():
    src = NOTES.read_text()
    proc = src.split("id: versionProc", 1)[1].split("stdout:", 1)[0]
    assert "running: root.stateLoaded" in proc
    assert "running: true" not in proc
    assert "if (stateLoaded && !versionProc.running)" in src
    # both load outcomes must open the gate
    assert "root.stateLoaded = true;" in src


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_version_token_with_markup_is_not_used_as_a_notification_title():
    # a number inside markup is already safe (the regex extracts "1.0")
    assert call_js('parseVersion("<b>1.0</b>")') == "1.0"
    # a markup-only token falls through to the fallback and must be dropped
    assert call_js('parseVersion("<script>bad</script>")') == ""
    assert call_js('parseVersion("1.4.2\\n")') == "1.4.2"
    assert call_js('parseVersion("shani 2.0\\n")') == "2.0"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_a_rollback_is_not_announced_as_whats_new():
    assert call_js('shouldShow("1.4.2", "1.5.0")') == "none"
    assert call_js('shouldShow("1.6.0", "1.5.0")') == "show"
    assert call_js('shouldShow("1.5.0", "1.5.0")') == "none"
