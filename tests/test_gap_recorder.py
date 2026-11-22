"""Voice Recorder gaps: format/channels, sequential names + durations, cancel, export, in-app playback."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVC = (ROOT / "shani/Services/VoiceRecorder.qml").read_text()
PANEL = (ROOT / "shani/Modules/VoiceRecorder/VoiceRecorderPanel.qml").read_text()


def test_format_and_channels_choice_keeps_default_contract():
    assert 'property string format: "opus"' in SVC and "property int channels: 1" in SVC
    assert "function recordScript()" in SVC
    # the documented default command is kept verbatim for the existing contract
    assert "pw-record --rate 48000 --channels 1 --format opus" in SVC
    assert "--channels ' + channels + ' --format ' + format" in SVC
    for label in ("Opus", "FLAC", "Mono", "Stereo"):
        assert f'text: "{label}"' in PANEL or f'Tr.t("{label}")' in PANEL, label
    assert (
        'VoiceRecorder.format = "flac"' in PANEL
        and "VoiceRecorder.channels = 2" in PANEL
    )


def test_sequential_names_and_per_row_duration():
    assert "property int nextNumber: 1" in SVC
    assert '"/Recording " + nextNumber + " "' in SVC
    assert "voice-recorder-number.json" in SVC and "numberSave.restart()" in SVC
    assert "function probeDurations(" in SVC and "ffprobe" in SVC
    assert "duration: root.durations[p] || 0" in SVC
    assert "VideoTrimmer.fmt(row.modelData.duration)" in PANEL


def test_cancel_discards_the_take():
    assert "function cancel(" in SVC
    assert "discarding = true" in SVC and "discardFile = file" in SVC
    assert '["gio", "trash", "--", doomed]' in SVC
    assert "VoiceRecorder.cancel()" in PANEL and 'Tr.t("Discard take")' in PANEL


def test_export_to_chosen_path():
    assert "function exportTo(path, source)" in SVC
    assert '"ffmpeg"' in SVC and '"-c:a", codec' in SVC
    assert "exported = out" in SVC and "exportError" in SVC
    assert 'mode: "save"' in PANEL and "VoiceRecorder.exportTo(paths[0], path)" in PANEL
    assert "VoiceRecorder.exported" in PANEL


def test_in_app_playback():
    assert "MediaPlayer {" in PANEL and "audioOutput: AudioOutput" in PANEL
    assert "function playInline(path)" in PANEL
    assert "win.playInline(row.modelData.path)" in PANEL
    assert 'playback.stop(); win.inlinePlay = ""' in PANEL
