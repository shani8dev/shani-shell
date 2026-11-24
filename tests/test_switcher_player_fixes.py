"""Static regressions for Switcher and Player gaps.

QML needs a live session, so these assert the source carries each fix.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_switcher_card_eats_clicks():
    """Clicking empty card space must not fall through to the background closer."""
    qml = read("shani/Modules/Switcher/Switcher.qml")
    glass = qml.split("Glass {", 1)[1].split("ListView {", 1)[0]
    assert "MouseArea { anchors.fill: parent }" in glass


def test_switcher_prunes_stale_windows_and_closes_when_empty():
    """Windows closed externally must be dropped; an empty switcher closes itself."""
    qml = read("shani/Modules/Switcher/Switcher.qml")
    assert "function pruneStale()" in qml
    assert "win.list = win.list.filter(w => Niri.windows[w.id]);" in qml
    assert "function onWindowsChanged()" in qml
    assert "win.pruneStale();" in qml
    # closing the last tile should not leave an empty overlay open
    close = qml.split("function close(w) {", 1)[1].split("\n    function", 1)[0]
    close_app = qml.split("function closeApp() {", 1)[1].split("\n    function", 1)[0]
    assert "Ui.switcher = false" in close
    assert "Ui.switcher = false" in close_app


def test_switcher_home_end_keyboard_navigation():
    """Home/End jump to the first/last tile for keyboard users."""
    qml = read("shani/Modules/Switcher/Switcher.qml")
    assert "Qt.Key_Home" in qml
    assert "Qt.Key_End" in qml
    assert "win.sel = 0;" in qml
    assert "win.sel = Math.max(0, win.count() - 1);" in qml


def test_player_global_play_pause_and_seek_keys():
    """Space/Left/Right work at panel level, not only on the seek KeyFocus."""
    qml = read("shani/Modules/Player/Player.qml")
    keys = qml.split("Keys.onEscapePressed: Ui.player = false", 1)[1].split(
        "Glass {", 1
    )[0]
    assert "Qt.Key_Space" in keys
    assert "togglePlaying()" in keys
    assert "Qt.Key_Left" in keys
    assert "Qt.Key_Right" in keys
    assert "win.seekTo(" in keys
    assert "Space play/pause" in qml


def test_player_queue_path_encodes_special_characters():
    """File URIs must encode # and ? so queue items with them open correctly."""
    qml = read("shani/Modules/Player/Player.qml")
    assert 'path.split("/").map(s => encodeURIComponent(s)).join("/")' in qml
    assert "encodeURI(path)" not in qml
