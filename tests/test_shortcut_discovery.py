"""Static checks for the in-app shortcut discoverability fixes.

Only the fixes owned by this pass are asserted: IconButton's keys channel and
the shortcut conflict banner. The Qt ToolTip system lives in SwitchRow.qml
(not owned here) and the coverage counter in Ui.qml, so neither is covered.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_iconbutton_forwards_keys_to_hint():
    src = read("shani/Common/IconButton.qml")
    assert re.search(r"property string keys:\s*\"\"", src)
    hint = re.search(r"Hint \{[^\n]*\}", src)
    assert hint, "IconButton must still instantiate Hint"
    assert "keys: root.keys" in hint.group(0)
    # text-only callers keep working: keys defaults to empty and text is unchanged
    assert 'text: root.tip !== "" ? root.tip : root.Accessible.name' in hint.group(0)


def test_shortcut_conflict_banner_names_owner_and_key():
    src = read("shani/Modules/Settings/SettingsShortcuts.qml")
    banner = next(line for line in src.splitlines() if "already taken" in line)
    # the owner/app from takenBy() and the exact key sequence are both shown
    assert "page.conflict" in banner
    assert "page.pretty(page.combo)" in banner
    # reuse the existing translated catalog string, no new i18n key
    assert 'Tr.t("That one is already taken: %1. Try another.")' in banner
