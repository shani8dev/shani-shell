"""Audiobook mode: sleep timer, bookmarks and resume in the Media Player.

GAPS asks for "bookmarks, chapters and a sleep timer in Media Player (no new
app)". This is all QML: PlayQueue owns the bookmarks/sleep/resume data and the
window shows it in one additive panel. QML is compiled by the render harness,
so these read the sources as text (the style used by the other large-fix
tests) - no QML runtime needed.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / "shani/Services/PlayQueue.qml").read_text()
WINDOW = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text()


def _panel() -> str:
    """Only the additive Audiobook block, so counts are not from other cards."""
    a = WINDOW.index("Audiobook mode - part of this player")
    return WINDOW[a:]


# ---- it is a mode of the Media Player, not a new app ----------------------


def test_audiobook_is_a_mode_of_the_media_player():
    assert 'appName: "Media Player"' in WINDOW
    assert 'appName: "Audiobook"' not in WINDOW
    assert "property bool audiobookShown: false" in WINDOW
    assert 'Tr.t("Audiobook")' in WINDOW
    assert "No app id and no bridge were added" in WINDOW
    # the data lives in the player's own queue service
    assert "Audiobook mode: part of this player, not another app" in QUEUE


# ---- named bookmarks, persisted like resume points -----------------------


def test_bookmarks_are_persisted_json_like_resume_at():
    assert "property var bookmarks: ({})" in QUEUE
    assert 'Quickshell.statePath("media-bookmarks.json")' in QUEUE
    assert "id: bookmarkStore" in QUEUE
    assert "JSON.stringify(root.bookmarks)" in QUEUE
    assert "JSON.parse(text()) || {}" in QUEUE
    # the same debounced-save shape as resumeSave
    assert "id: bookmarkSave" in QUEUE and "bookmarkSave.restart()" in QUEUE


def test_bookmark_actions_are_in_the_service():
    for fn in ("bookmarksFor(", "addBookmark(", "deleteBookmark("):
        assert f"function {fn}" in QUEUE, fn
    assert 'Tr.t("Bookmark %1", list.length + 1)' in QUEUE  # unnamed gets a name
    assert "list.sort((a, b) => a.at - b.at)" in QUEUE  # ordered by time
    assert "list.splice(index, 1)" in QUEUE  # delete one
    # the window never writes the map itself; it calls the service
    assert "PlayQueue.addBookmark(" in WINDOW
    assert "PlayQueue.deleteBookmark(" in WINDOW


# ---- sleep timer: minutes or end of chapter ------------------------------


def test_sleep_timer_has_both_arms_and_cancel():
    for fn in ("armSleepMinutes(", "armSleepChapter(", "cancelSleep(", "checkSleep("):
        assert f"function {fn}" in QUEUE, fn
    assert "property bool sleepArmed: false" in QUEUE
    assert "property bool sleepAtChapterEnd: false" in QUEUE
    assert "property real sleepDeadline: 0" in QUEUE
    assert "property real sleepChapterEnd: -1" in QUEUE
    # both arms only ask the window to pause
    assert QUEUE.count("root.pauseRequested()") >= 2


def test_sleep_timer_uses_a_qml_timer_and_wall_clock():
    assert "Date.now() + n * 60000" in QUEUE
    assert "Date.now() >= sleepDeadline" in QUEUE
    assert "root.chapterAt(root.position)" in QUEUE
    assert "Number(pos) >= sleepChapterEnd - 1" in QUEUE  # chapter end reached
    assert (
        "running: root.sleepArmed && !root.sleepAtChapterEnd && root.playing" in QUEUE
    )
    assert "root.sleepNow = Date.now(); root.checkSleep(root.position)" in QUEUE
    assert "property real sleepMinutesLeft" in QUEUE


def test_window_drives_the_chapter_arm_from_the_playhead():
    panel = _panel()
    assert "target: player" in panel
    assert (
        "function onPositionChanged() { PlayQueue.checkSleep(player.position / 1000); }"
        in panel
    )
    assert "PlayQueue.armSleepMinutes(modelData)" in panel
    assert "PlayQueue.armSleepChapter()" in panel
    assert "PlayQueue.cancelSleep()" in panel


# ---- continue listening, skips and speed ---------------------------------


def test_continue_listening_uses_resume_points():
    assert "readonly property var continueRows:" in QUEUE
    assert "root.resumeRecent.map(" in QUEUE
    assert "at: root.resumePoint(p)" in QUEUE
    assert ".filter(x => x.at > 0)" in QUEUE
    panel = _panel()
    assert 'Tr.t("Continue listening")' in panel
    assert "win.openContinue(contRow.modelData.path)" in panel
    assert "PlayQueue.playRecent(path)" in panel  # opens and resumes
    assert 'Tr.t("Nothing to continue yet")' in panel


def test_fifteen_second_skip_buttons():
    panel = _panel()
    assert "win.skip(-15)" in panel and "win.skip(15)" in panel
    assert 'tip: Tr.t("Back 15 seconds")' in panel
    assert 'tip: Tr.t("Forward 15 seconds")' in panel


def test_full_audiobook_speed_presets():
    assert "readonly property var speedPresets: [0.75, 1, 1.25, 1.5, 2, 3]" in QUEUE
    assert "function setRate(r)" in QUEUE
    assert "Math.max(0.25, Math.min(4, n))" in QUEUE
    panel = _panel()
    assert "model: PlayQueue.speedPresets" in panel
    assert "PlayQueue.setRate(modelData)" in panel
    assert 'Tr.t("Playback speed %1 times", modelData)' in panel


# ---- one chapter + bookmark list, with jump and delete -------------------


def test_chapters_and_bookmarks_share_one_time_ordered_list():
    panel = _panel()
    assert "readonly property var timelineRows:" in panel
    assert "chapter: true" in panel and "chapter: false" in panel
    assert "out.sort((a, b) => a.at - b.at)" in panel
    assert "model: win.timelineRows" in panel
    assert 'Tr.t("Chapters & bookmarks")' in panel


def test_bookmark_rows_jump_and_delete():
    panel = _panel()
    assert "function audiobookJump(at)" in panel
    assert "win.audiobookJump(tlRow.modelData.at)" in panel
    assert (
        "PlayQueue.deleteBookmark(PlayQueue.current, tlRow.modelData.bookmarkIndex)"
        in panel
    )
    assert 'tip: Tr.t("Delete bookmark")' in panel


# ---- names for assistive tech, and empty / error states ------------------


def test_new_controls_have_accessible_names():
    panel = _panel()
    assert panel.count("Accessible.name") >= 10
    assert 'Accessible.name: Tr.t("Skip back 15 seconds")' in panel
    assert 'Accessible.name: Tr.t("Sleep timer off")' in panel
    assert 'Accessible.name: Tr.t("Add a bookmark at the current position")' in panel
    assert 'Accessible.name: Tr.t("Delete bookmark %1", tlRow.modelData.title)' in panel


def test_empty_and_error_states():
    panel = _panel()
    assert "visible: win.timelineRows.length === 0" in panel
    assert 'icon: "bookmark-new"' in panel
    assert 'Tr.t("No chapters or bookmarks yet")' in panel
    assert 'Tr.t("Nothing to continue yet")' in panel
    assert 'visible: PlayQueue.error !== "" || win.bookmarkError !== ""' in panel
    assert "color: Theme.danger" in panel
    assert 'Tr.t("Open a book first")' in panel


def test_no_new_bridge_was_added():
    # bookmarks are a FileView in the service; chapters stay with ffprobe
    bridges = [b.stem.lower() for b in (ROOT / "bridge").glob("*.py")]
    assert not any("audiobook" in b or "sleep" in b or "bookmark" in b for b in bridges)
