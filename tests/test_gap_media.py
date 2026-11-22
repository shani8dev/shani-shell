"""Media Player gaps: go-to-time, recent media, network stream, A→B loop, Stop, chapters."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / "shani/Services/PlayQueue.qml").read_text()
WINDOW = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text()


def test_go_to_time_field_parses_mmss():
    assert "function goToTime(" in WINDOW
    # splits on ':' and rejects non-numeric parts
    assert 'split(":")' in WINDOW and r"/^\d+$/" in WINDOW
    assert "id: goField" in WINDOW
    assert "onAccepted:" in WINDOW and "win.goToTime(" in WINDOW


def test_recent_media_comes_from_resume_points():
    assert "readonly property var recent:" in QUEUE and "Object.keys(resumeAt)" in QUEUE
    assert "function playRecent(" in QUEUE and "open(path)" in QUEUE
    assert "PlayQueue.recent" in WINDOW and "PlayQueue.playRecent(" in WINDOW
    assert "document-open-recent" in WINDOW


def test_network_stream_uses_playstream():
    assert "function playStreamUrl(" in WINDOW
    assert r"/^https?:\/\//" in WINDOW and "PlayQueue.playStream(" in WINDOW
    assert "id: streamField" in WINDOW and "network-workgroup" in WINDOW
    assert "SHANI_TRANSLATE_URL" not in QUEUE  # sanity: no cross-wiring


def test_ab_loop_jumps_back():
    for fn in ("setLoopA(", "setLoopB(", "clearLoop(", "loopJump("):
        assert f"function {fn}" in QUEUE, fn
    assert "loopActive" in QUEUE and "pos >= loopB" in QUEUE
    # the window applies the jump after each position update
    assert "PlayQueue.loopJump(PlayQueue.position)" in WINDOW
    assert 'text: "A"' in WINDOW and 'text: "B"' in WINDOW


def test_stop_button_and_chapters():
    assert "function stop(" in QUEUE and "pauseRequested(); seekRequested(0)" in QUEUE
    assert '"media-playback-stop"' in WINDOW and "PlayQueue.stop()" in WINDOW
    # chapters via ffprobe in the service, listed in the window
    assert '"-show_chapters"' in QUEUE and "property var chapters" in QUEUE
    assert "PlayQueue.chapters" in WINDOW
