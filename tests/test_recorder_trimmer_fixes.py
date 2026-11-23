"""Static guards for the pass-20 recorder/trimmer bugs: the trimmed save never
reported success, renaming could change a take's format, and the frame-step
buttons were permanently disabled."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECORDER = ROOT / "shani/Services/VoiceRecorder.qml"
TRIMMER = ROOT / "shani/Services/VideoTrimmer.qml"
PANEL = ROOT / "shani/Modules/VideoTrimmer/VideoTrimmerPanel.qml"


def test_trimmed_save_matches_the_actual_timestamped_output():
    trimmer = TRIMMER.read_text()
    assert "cutProc.out = out" in trimmer
    assert "return out;" in trimmer  # cut hands back the exact name used
    assert "return cut();" in trimmer  # not a freshly stamped outputFor()

    recorder = RECORDER.read_text()
    assert "trimOutput" in recorder
    assert 'trimOutput = VideoTrimmer.trimAudio(trimFile, s, e) || ""' in recorder
    assert "VideoTrimmer.result === root.trimOutput" in recorder
    assert "trimmedPathFor" not in recorder  # the stale fixed-name matcher is gone


def test_rename_keeps_the_takes_own_extension():
    t = RECORDER.read_text()
    assert "function cleanName(name, path)" in t
    assert 'String(path || "").split(".").pop()' in t
    assert 'ext === "flac" || ext === "opus"' in t
    assert "const to = cleanName(name, path)" in t


def test_frame_step_buttons_are_live_when_a_duration_is_known():
    t = PANEL.read_text()
    assert 'text: "◀"' in t and 'text: "▶"' in t
    assert "enabled: false" not in t
    assert t.count("enabled: VideoTrimmer.inputDuration > 0") == 2
    assert "VideoTrimmer.nudgePlayhead(-VideoTrimmer.frameStep)" in t
    assert "VideoTrimmer.nudgePlayhead(VideoTrimmer.frameStep)" in t
