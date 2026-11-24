"""Static checks for five low-risk Media Player gaps closed in this pass.

QML is compiled by the render harness, so these read MediaPlayerWindow.qml as
text: an arbitrary subtitle file, chapter ticks on the seek bar, chapter keys,
shuffle/repeat keys, and a fading title overlay over video.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text()


def test_arbitrary_subtitle_file_can_be_opened():
    # only a .srt/.vtt beside the video was found; a downloaded one must be pickable
    assert 'Tr.t("Open subtitle…")' in WINDOW
    assert 'filters: ["srt", "vtt"]' in WINDOW
    assert "PlayQueue.subtitleFile = paths[0]" in WINDOW
    # the window already turns whatever the service publishes into cues
    assert "function onSubtitleFileChanged()" in WINDOW
    assert "cueReader.command" in WINDOW


def test_chapter_ticks_on_the_seek_bar():
    # the chapter list lived in the tracks card; the timeline gave no hint
    assert "model: player.duration > 0 ? PlayQueue.chapters : []" in WINDOW
    assert "modelData.start / player.duration" in WINDOW
    # the ticks sit on the same bar as the playhead and the drag area
    assert "id: track" in WINDOW and "id: seekArea" in WINDOW


def test_chapter_navigation_keys():
    assert "function stepChapter(dir)" in WINDOW
    assert "Qt.Key_Comma" in WINDOW and "Qt.Key_Period" in WINDOW
    assert "win.stepChapter(-1)" in WINDOW and "win.stepChapter(1)" in WINDOW
    # the index is clamped: no undefined chapter at either end
    assert "cs.length - 1" in WINDOW


def test_shuffle_and_repeat_keys():
    assert "Qt.Key_S" in WINDOW
    assert "Qt.Key_R && big" in WINDOW
    assert "function cycleRepeat()" in WINDOW
    assert "PlayQueue.shuffle = !PlayQueue.shuffle" in WINDOW
    # the toolbar cycles repeat through the same function as Shift+R
    assert "onClicked: win.cycleRepeat()" in WINDOW


def test_video_title_overlay():
    assert "id: titleNote" in WINDOW and "Timer {" in WINDOW
    assert "function onCurrentChanged() { titleNote.restart(); }" in WINDOW
    assert "id: videoHover" in WINDOW
    assert "player.hasVideo && !win.mini" in WINDOW
    assert "titleNote.running || videoHover.hovered" in WINDOW
