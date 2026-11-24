"""Static checks for the voice-recorder / video-trimmer competitive gaps.

Both surfaces are Quickshell QML windows, so the tests assert source wiring:
a later edit cannot silently drop a fix. The gaps were derived from GNOME
Sound Recorder (Vocalis), Apple Voice Memos, KDE Kdenlive and Apple iMovie.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECORDER = ROOT / "shani/Modules/VoiceRecorder/VoiceRecorderPanel.qml"
TRIMMER = ROOT / "shani/Modules/VideoTrimmer/VideoTrimmerPanel.qml"


def test_recorder_inline_playback_can_be_scrubbed():
    """Sound Recorder / Voice Memos let you drag the waveform to seek; ours
    only had play, pause and stop with no position or duration readout."""
    s = RECORDER.read_text(encoding="utf-8")
    assert (
        "value: playback.duration > 0 ? playback.position / playback.duration : 0" in s
    )
    assert (
        "onMoved: v => { if (playback.duration > 0) playback.setPosition(v * playback.duration); }"
        in s
    )
    assert (
        'VideoTrimmer.fmt(playback.position / 1000) + " / " + VideoTrimmer.fmt(playback.duration / 1000)'
        in s
    )
    assert 'label: Tr.t("Seek in recording")' in s


def test_recorder_trash_needs_confirmation():
    """Voice Memos moves a deleted note to Recently Deleted; a single click
    on our bin row used to trash the take irreversibly."""
    s = RECORDER.read_text(encoding="utf-8")
    assert "property string confirmingDelete:" in s
    assert "function trashTake(path) {" in s
    assert (
        "if (win.confirmingDelete === row.modelData.path) win.trashTake(row.modelData.path);"
        in s
    )
    assert 'Tr.t("Move %1 to trash?").arg(win.confirmingDelete.split("/").pop())' in s
    assert (
        'Button { text: Tr.t("Cancel"); flat: true; onClicked: win.confirmingDelete = "" }'
        in s
    )


def test_recorder_list_search_and_sort():
    """Voice Memos searches and re-sorts takes; ours showed a raw newest-first
    list with no way to find or reorder an old recording."""
    s = RECORDER.read_text(encoding="utf-8")
    assert "function visibleRows() {" in s
    assert 'String(r.name || "").toLowerCase().indexOf(needle) >= 0' in s
    assert "model: win.visibleRows()" in s
    assert "id: searchField" in s
    assert "onTextChanged: win.search = text" in s
    assert "win.sortMode = (win.sortMode + 1) % 3" in s
    assert 'Tr.t("No matching recordings")' in s


def test_voice_trim_has_exact_in_out_entry():
    """Kdenlive lets you type exact in/out timecodes; our take trim had only
    sliders and one-second buttons."""
    s = RECORDER.read_text(encoding="utf-8")
    assert "onAccepted: VoiceRecorder.setTrimStart(parseFloat(text))" in s
    assert "onAccepted: VoiceRecorder.setTrimEnd(parseFloat(text))" in s
    assert (
        'Button { text: "-0.1s"; onClicked: VoiceRecorder.setTrimStart(VoiceRecorder.trimStart - 0.1) }'
        in s
    )
    assert (
        'Button { text: "+0.1s"; onClicked: VoiceRecorder.setTrimEnd(VoiceRecorder.trimEnd + 0.1) }'
        in s
    )
    assert 'label: Tr.t("Trim start (seconds)")' in s
    assert 'label: Tr.t("Trim end (seconds)")' in s


def test_video_trimmer_shortcuts_survive_focus_changes():
    """Kdenlive keeps I/O/S working while any control has focus; our Keys
    handler lived on one focusable Item, so clicking a field killed it."""
    s = TRIMMER.read_text(encoding="utf-8")
    assert (
        "readonly property bool shortcutsOn: !pathField.activeFocus && !startField.activeFocus && !endField.activeFocus"
        in s
    )
    assert 'sequence: "I"' in s
    assert 'sequence: "O"' in s
    assert 'sequence: "S"' in s
    assert "enabled: win.shortcutsOn" in s
    assert "onActivated: VideoTrimmer.markIn()" in s
    assert "onActivated: VideoTrimmer.markOut()" in s
    assert "onActivated: VideoTrimmer.splitAtPlayhead()" in s
    assert "Esc closes · I in · O out · S split · ←/→ frame step" in s
