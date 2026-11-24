"""Regressions for TvHome.qml fixes the gap catalogues do not cover: a stale
keysActivated flag, Settings closing to a bare desktop, cards a screen reader
cannot open, and two TVs fighting over the remote's keys.

Static checks only - Quickshell's QML cannot run under pytest.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "shani/Modules/TvHome/TvHome.qml"


def _source():
    return SRC.read_text(encoding="utf-8")


def test_keys_activated_is_cleared_after_a_tv_home_key():
    """KeyFocus clears the flag after activation; TvHome used to set it on every
    key and never clear it, so a later OSK toggle opened in remote mode."""
    handler = _source().split("Keys.onPressed: e => {", 1)[1].split("\n        }", 1)[0]
    assert "Ui.keysActivated = true;" in handler
    assert "Qt.callLater(() => Ui.keysActivated = false);" in handler
    # set after the switch so keys we do not handle (default: return) do not arm it
    assert handler.index("default: return;") < handler.index("Ui.keysActivated = true;")


def test_settings_opened_from_home_returns_to_home_on_close():
    src = _source()
    assert (
        "win.settingsFromHome = true; Ui.tvHome = false; Ui.openSettings(cat);" in src
    )
    assert "property bool settingsFromHome: false" in src
    assert "function onSettingsOpenChanged()" in src
    assert "if (Ui.settingsOpen || !win.settingsFromHome) return;" in src
    assert '&& !Niri.mru().some(w => w.app_id && w.app_id !== "org.quickshell"))' in src


def test_cards_can_be_activated_by_a_screen_reader():
    src = _source()
    assert "Accessible.role: Accessible.Button" in src
    assert "Accessible.name:" in src
    assert "modelData.label" in src
    assert "Accessible.onPressAction: { card.choose(); win.activate(); }" in src
    # the reader and the mouse share one path, so they cannot drift apart
    assert "function choose() {" in src
    assert "onEntered: card.choose()" in src
    assert "onClicked: { card.choose(); win.activate(); }" in src


def test_only_the_focused_tv_takes_the_remote_keys():
    src = _source()
    assert (
        "readonly property bool keysHere: !Niri.focusedOutput || Niri.focusedOutput === modelData.name"
        in src
    )
    assert "WlrLayershell.keyboardFocus: visible && keysHere && !Ui.launcher" in src
    assert "if (keysHere) Qt.callLater(() => keys.forceActiveFocus());" in src
