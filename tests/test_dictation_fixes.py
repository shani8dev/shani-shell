"""Static guards for the pass-20/21 voice + IME fixes.

Each test maps to one fix: a muted mic must block recording, a failed recorder
must not run STT over a stale WAV, recording is bounded with a countdown, and a
text field can ask the OSK for a numeric/mail/URL layout. Runtime QML behaviour
is not exercised here.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DICTATION = (ROOT / "shani/Services/Dictation.qml").read_text(encoding="utf-8")
TEXT_FIELD = (ROOT / "shani/Common/TextField.qml").read_text(encoding="utf-8")


def _object(src, anchor):
    """The brace-balanced object starting at `anchor` (nested blocks included)."""
    pos = src.index(anchor)
    start = src.index("{", pos)
    depth = 0
    for j in range(start, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[pos : j + 1]
    raise AssertionError(f"unbalanced block at {anchor}")


def _line(src, anchor):
    pos = src.index(anchor)
    return src[pos : src.index("\n", pos)]


def test_muted_mic_refuses_to_start():
    # fix 1: Audio.micMuted is consulted before pw-record is launched.
    start = _object(DICTATION, "function start()")
    assert "if (Audio.micMuted)" in start
    assert 'Tr.t("Unmute the microphone first")' in start
    muted = (
        start[: start.index("rec.running = true")]
        if "rec.running = true" in start
        else start
    )
    by_mute = muted[muted.index("if (Audio.micMuted)") :]
    assert "return;" in by_mute  # the muted path bails out
    assert "rec.running" not in by_mute  # and never starts the recorder


def test_recorder_failure_does_not_run_stt():
    # fix 2: only a clean exit may reach transcribing; a stale WAV is dropped.
    exited = _object(DICTATION, "onExited: (code, status)")
    failure = exited[
        exited.index("if (code !== 0)") : exited.index('root.phase = "transcribing"')
    ]
    assert "root.dropWav()" in failure
    assert 'root.phase = "idle"' in failure
    assert "notify-send" in failure
    assert "stt.running" not in failure


def test_recording_is_bounded_and_exposes_a_countdown():
    # fix 2b: pw-record is wrapped in a 60 s timeout and secondsLeft ticks down.
    rec = _object(DICTATION, 'command: ["timeout"')
    assert '"timeout"' in rec and '"-s", "INT", "60"' in rec
    assert "--preserve-status" in rec  # a clean stop still exits 0, so fix 2 holds
    assert 'command: ["pw-record"' not in DICTATION
    assert "property int secondsLeft" in DICTATION
    assert (
        "onTriggered: root.secondsLeft = Math.max(0, root.secondsLeft - 1)" in DICTATION
    )


def test_text_field_mode_maps_to_input_method_hints():
    # fix 3: a mode picks the OSK hint, while the default and secret paths stay.
    assert 'property string mode: ""' in TEXT_FIELD
    hints = _line(TEXT_FIELD, "inputMethodHints:")
    assert "root.secret" in hints
    assert "Qt.ImhSensitiveData" in hints
    assert "Qt.ImhDigitsOnly" in hints
    assert "Qt.ImhEmailCharactersOnly" in hints
    assert "Qt.ImhUrlCharactersOnly" in hints
    assert "Qt.ImhNone" in hints  # unchanged default for existing callers
