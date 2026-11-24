"""First-run gesture hints in the overview.

The overview teaches the five pointer/key gestures that reach its window tools,
once, and the × writes a dismissal flag the shell reads back on next start.
These tests check the static wiring and evaluate the tip list as plain data: a
hint that teaches a binding the shell does not have is worse than no hint.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCH = ROOT / "shani/Modules/Overview/OverviewSearch.qml"
SOURCE = SEARCH.read_text(encoding="utf-8")
TEMPLATE = json.loads((ROOT / "shani/i18n/template.json").read_text(encoding="utf-8"))

# the strip is a short block under the search field, not a second tour
TIP_LIMIT = 5
EXPECTED_KEYS = {
    "Super+Alt+←/→",
    "Hold zoom",
    "Hover",
    "Right-click dock",
    "Middle-click dock",
}


def block(text, needle, open_="{", close="}"):
    """The balanced block that follows the first occurrence of `needle`."""
    start = text.index(needle)
    i = text.index(open_, start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == open_:
            depth += 1
        elif text[j] == close:
            depth -= 1
            if depth == 0:
                return text[i : j + 1]
    raise AssertionError(f"unterminated block after {needle!r}")


def hints_block():
    return block(SOURCE, "Glass {\n        id: hints\n")


def tips():
    """Evaluate the declarative tip list as data (no QML runtime needed)."""
    raw = block(SOURCE, "readonly property var gestureTips", "[", "]")
    # Tr.t() only marks the string for the catalog; the value is the literal
    raw = re.sub(r'Tr\.t\(("(?:[^"\\]|\\.)*")\)', r"\1", raw)
    raw = re.sub(r"([A-Za-z_]\w*):", r'"\1":', raw)
    raw = re.sub(r",\s*([}\]])", r"\1", raw)
    return json.loads(raw)


# ---- static wiring ---------------------------------------------------------


def test_hint_is_dismissed_once_and_remembered():
    assert "JsonAdapter { id: hintsPrefs; property bool dismissed: false }" in SOURCE
    assert "visible: !hintsPrefs.dismissed" in SOURCE
    dismiss = block(SOURCE, "function dismissHints()")
    assert "hintsPrefs.dismissed = true" in dismiss
    assert "hintsFile.writeAdapter()" in dismiss
    assert 'Quickshell.execDetached(["mkdir", "-p", win.hintsDir])' in dismiss
    assert "gesture-hints.json" in SOURCE
    # Common/Settings.qml does not own this key; it lives beside settings.json
    assert "Settings.data" not in block(SOURCE, "path: win.hintsDir")
    assert "Common/Settings.qml" in SOURCE


def test_dismiss_button_is_accessible_and_keyboard_reachable():
    hints = hints_block()
    # translucent card, not an opaque Rectangle
    assert "Glass {\n        id: hints\n" in SOURCE
    assert 'elevation: "none"' in hints
    assert "IconButton {" in hints
    button = block(hints, "IconButton {")
    assert 'icon: "window-close"' in button
    assert 'tip: Tr.t("Hide the navigation hints")' in button
    assert 'accessibleName: Tr.t("Hide the navigation hints")' in button
    assert "onClicked: win.dismissHints()" in button
    # Tab can reach the button and get back to the search field; Esc still leaves
    assert "activeFocusOnTab: true" in SOURCE
    assert 'Keys.onEscapePressed: Niri.action("close-overview")' in hints


def test_key_badges_read_the_delegate_not_the_rectangle():
    # the badge's Text sits inside a Rectangle: one `parent` up is the Rectangle,
    # two up is the Repeater delegate that owns modelData
    assert "text: parent.parent.modelData.keys" in hints_block()
    assert "text: parent.modelData.what" in hints_block()


def test_hint_uses_theme_tokens_and_scales_with_text():
    hints = hints_block()
    for token in (
        "Theme.radiusSmall",
        "Theme.alpha",
        "Theme.text",
        "Theme.font",
        "Theme.px",
        "Theme.fontScale",
    ):
        assert token in hints, token
    # no hard-coded colour makes an opaque card that ignores Reduce transparency
    assert not re.search(r'color:\s*"#|color:\s*"white"|color:\s*"black"', hints)


def test_hint_does_not_break_the_search_handover():
    # the strip adds a row below the field; typing still hands over once
    assert "handOver.stop()" in block(SOURCE, "function search(text)")
    keys = block(SOURCE, "Keys.onPressed")
    assert "Qt.Key_Backspace" in keys and "win.typed.slice(0, -1)" in keys
    assert "Qt.Key_Escape" in keys


# ---- pure logic over the tip data -----------------------------------------


def test_tips_are_compact_and_translated():
    data = tips()
    assert 0 < len(data) <= TIP_LIMIT
    assert len(data) == len(EXPECTED_KEYS)
    for tip in data:
        assert set(tip) == {"keys", "what"}
        assert tip["keys"] and tip["what"]
        assert len(tip["keys"]) <= 18, tip  # short enough for a two-column grid
        assert tip["what"] in TEMPLATE, tip["what"]  # every label is in the catalog
    assert {tip["keys"] for tip in data} == EXPECTED_KEYS


def test_the_middle_click_claim_is_the_real_one():
    data = {tip["keys"]: tip["what"] for tip in tips()}
    # the dock's middle click launches a new app instance (Dock.qml, onClicked),
    # while its window list is under the right-click menu - never teach the reverse
    assert data["Middle-click dock"] == "New window"
    assert data["Right-click dock"] == "Switch windows"
    assert "window list" not in json.dumps(data, ensure_ascii=False).lower()


# ---- the bindings the tips name really exist -------------------------------


def test_taught_bindings_exist_in_source():
    cfg = (
        ROOT.parent / "shani-pkgbuilds/shani-desktop-niri/etc/niri/config.kdl"
    ).read_text()
    assert "Mod+Alt+Left" in cfg and "Mod+Alt+Right" in cfg
    bar = (ROOT / "shani/Modules/Bar/Bar.qml").read_text()
    assert "onPressAndHold: Ui.toggleWindowLayouts()" in bar
    dock = (ROOT / "shani/Modules/Dock/Dock.qml").read_text()
    assert "HoverPeek {" in dock
    assert "e.button === Qt.MiddleButton" in dock and "Launch.app(" in dock
    assert "win.setMenu(" in dock and "cell.modelData.windows" in dock
