"""Cross-wires between the media surfaces.

Integration only: a recorded take is handed to the existing player entry point,
and a frame the Media Player saves is offered through the existing Screenshots
notification (which already carries share / annotate / pin actions). No new
capture tool, player or annotation API is introduced here.

Static hooks pin the wires; the path-to-player mapping and the media-type check
are the real functions from PlayQueue.qml, run in node with tiny stubs - the
same technique the media-key tests use, so the tested code is the shipped code.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / "shani/Services/PlayQueue.qml").read_text(encoding="utf-8")
RECORDER = (ROOT / "shani/Modules/VoiceRecorder/VoiceRecorderPanel.qml").read_text(
    encoding="utf-8"
)
SCREENSHOTS = (ROOT / "shani/Services/Screenshots.qml").read_text(encoding="utf-8")
PLAYER = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text(
    encoding="utf-8"
)
PIN = (ROOT / "shani/Modules/Screenshots/PinCapture.qml").read_text(encoding="utf-8")
ANNOTATE = (ROOT / "shani/Modules/Annotate/Annotate.qml").read_text(encoding="utf-8")
TEMPLATE = json.loads((ROOT / "shani/i18n/template.json").read_text(encoding="utf-8"))

NODE = shutil.which("node") or shutil.which("nodejs")


def js_function(text, name):
    """One whole, brace-free function body, extracted verbatim from the QML."""
    m = re.search(r"function " + re.escape(name) + r"\([^)]*\) \{[^}]*\}", text)
    assert m, f"no function {name} in the QML"
    return m.group(0)


def js_array(text, name):
    m = re.search(r"readonly property var " + name + r": (\[[^\]]*\])", text)
    assert m, f"no {name} list in the QML"
    return m.group(1)


def node_json(program):
    out = subprocess.run(
        [NODE, "-e", program], capture_output=True, text=True, timeout=30
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


def function_body(text, signature):
    assert signature in text, signature
    return text.split(signature, 1)[1].split("\n    }", 1)[0]


# ---- static hooks ----------------------------------------------------------


def test_recorder_take_has_an_open_in_player_action():
    fn = function_body(RECORDER, "function openInPlayer(path) {")
    assert "if (!path) return;" in fn
    assert "Ui.voiceRecorder = false" in fn  # the player must not open behind the panel
    assert "PlayQueue.open(path)" in fn  # the player's own entry point

    # the row passes the take's own path, with a keyed, named control
    at = RECORDER.index("win.openInPlayer(row.modelData.path)")
    button = RECORDER[at - 300 : at]
    assert 'icon: "applications-multimedia"' in button
    assert "size: Theme.px(30)" in button  # a Theme token, not a raw pixel value
    assert 'tip: Tr.t("Open in %1", "Media Player")' in button
    assert 'Accessible.name: Tr.t("Open in %1", "Media Player")' in button
    assert "Open in %1" in TEMPLATE  # no new, untranslated catalog key


def test_wave6_waveform_and_media_keys_are_untouched_by_the_wire():
    # the recorder's inline waveform and the player's key handler keep working
    assert "win.loadPeaks(path)" in RECORDER
    assert "Accessible.role: Accessible.Slider" in RECORDER
    assert "onStep: dir =>" in RECORDER and "dir * 5000" in RECORDER
    assert PLAYER.count("function key(e)") == 1
    assert "Qt.Key_Space || e.key === Qt.Key_K" in PLAYER


def test_saved_frame_is_offered_to_screenshots():
    # the frame is already captured by the player into Ui.mediaFrameSaved; the
    # Screenshots service picks it up instead of capturing or copying it again
    assert "Ui.mediaFrameSaved = win.frameSaved" in PLAYER
    assert "target: Ui" in SCREENSHOTS
    assert "function onMediaFrameSavedChanged()" in SCREENSHOTS
    assert 'Ui.mediaFrameSaved !== ""' in SCREENSHOTS
    assert "root.offer(Ui.mediaFrameSaved)" in SCREENSHOTS
    assert "function offer(path)" in SCREENSHOTS
    # the offer's actions are the existing share / annotate / pin ones
    assert '"-A", "share=Share…"' in SCREENSHOTS
    assert '"-A", "annotate=Annotate"' in SCREENSHOTS
    assert "Share.open(root.last)" in SCREENSHOTS
    assert (
        "Viewer.open(root.last)" in SCREENSHOTS and "Viewer.startEdit()" in SCREENSHOTS
    )


def test_pin_capture_keeps_its_share_actions():
    # screenshot -> pin -> share already flows through the service's real APIs
    assert "Screenshots.shareImage(Screenshots.pinnedPath)" in PIN
    assert "Screenshots.copyImage(Screenshots.pinnedPath)" in PIN
    assert "Screenshots.saveImage(Screenshots.pinnedPath)" in PIN
    assert "function shareImage(path)" in SCREENSHOTS and "Share.open(p)" in SCREENSHOTS


def test_annotate_has_no_open_from_path_api_to_wire():
    # Annotate is a live overlay: it captures the screen with grim on save and
    # has no open(path). Image-file markup is Screenshots.annotate() -> Viewer.
    if re.search(r"function open\s*\(", ANNOTATE):
        pytest.skip("Annotate gained an open(path) API - wire PinCapture to it")
    assert "function save()" in ANNOTATE and "grim" in ANNOTATE
    assert "function annotate()" in SCREENSHOTS


# ---- pure logic, run from the shipped QML ----------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
@pytest.mark.parametrize(
    "arg,want",
    [
        ("/home/test/Voice Recorder/take.opus", "/home/test/Voice Recorder/take.opus"),
        ("  take.flac  ", "/home/test/take.flac"),
        ("file:///home/test/A%20B/One%23Two.wav", "/home/test/A B/One#Two.wav"),
        ("", ""),
        ("   ", ""),
        ("null", "/home/test/null"),
    ],
)
def test_path_to_player_open_mapping(arg, want):
    # open() uses this exact function, so the mapping tested here is the one a
    # recorder take (or any other caller) actually reaches the player with
    assert "const path = root.playerPath(arg);" in QUEUE
    program = (
        'const Quickshell = { env: () => "/home/test" };\n'
        + js_function(QUEUE, "playerPath")
        + f"\nconsole.log(JSON.stringify(playerPath({json.dumps(arg)})));\n"
    )
    assert node_json(program) == want


@pytest.mark.skipif(NODE is None, reason="node is not installed")
@pytest.mark.parametrize(
    "path,want",
    [
        ("/home/test/take.opus", "audio"),
        ("/home/test/take.flac", "audio"),
        ("/home/test/take.wav", "audio"),
        ("/home/test/song.mp3", "audio"),
        ("/home/test/film.mp4", "video"),
        ("/home/test/film.mkv", "video"),
        ("/home/test/notes.txt", ""),
    ],
)
def test_media_type_detection_recognises_recordings_as_audio(path, want):
    program = (
        "const videoTypes = "
        + js_array(QUEUE, "videoTypes")
        + ";\n"
        + "const audioTypes = "
        + js_array(QUEUE, "audioTypes")
        + ";\n"
        + js_function(QUEUE, "kind")
        + f"\nconsole.log(JSON.stringify(kind({json.dumps(path)})));\n"
    )
    assert node_json(program) == want
