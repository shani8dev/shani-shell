"""Static guards for the QML compile fixes in MediaPlayerWindow and ClocksWindow."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml"
CLOCKS = ROOT / "shani/Modules/Clocks/ClocksWindow.qml"


def test_media_audiobook_button_has_no_stray_semicolon():
    src = MEDIA.read_text()
    assert 'Accessible.name: Tr.t("Audiobook mode") }; Accessible.name' not in src
    assert "win.streamShown = false; } }; Accessible.name" not in src
    # The AT name is still assigned, on its own line, inside the IconButton.
    assert 'Accessible.name: Tr.t("Audiobook mode")' in src
    button = src.split('icon: "book"', 1)[1].split("\n                    }", 1)[0]
    assert "on: win.audiobookShown" in button
    assert "onClicked:" in button


def test_clocks_no_unsupported_page_handlers():
    src = CLOCKS.read_text()
    assert "onPageDownPressed" not in src
    assert "onPageUpPressed" not in src
    assert "onHomePressed" not in src
    assert "onEndPressed" not in src
    assert src.count("Keys.onPressed: e => {") >= 2


def test_clocks_page_navigation_behavior_preserved():
    src = CLOCKS.read_text()
    assert "e.key === Qt.Key_PageUp" in src
    assert "e.key === Qt.Key_PageDown" in src
    assert "currentIndex = Math.max(0, currentIndex - 8)" in src
    assert "currentIndex = Math.min(count - 1, currentIndex + 8)" in src
    assert "currentIndex = 0" in src
    assert "currentIndex = count - 1" in src
