"""Static checks for the camera / voice-recorder panel fixes.

These panels are QML surfaces driven by singletons (Camera, VoiceRecorder);
the assertions pin the wiring that makes capture feedback, empty states and
keyboard/AT reach real rather than decorative.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAM = (ROOT / "shani/Modules/Camera/CameraPanel.qml").read_text()
REC = (ROOT / "shani/Modules/VoiceRecorder/VoiceRecorderPanel.qml").read_text()


def test_camera_shutter_is_gated_and_capture_is_reported():
    # the shutter cannot be pressed while no camera is ready or a shot is in
    # flight: the visual, mouse and keyboard paths are all gated the same way
    assert 'enabled: Camera.available && Camera.phase === "idle"' in CAM
    assert CAM.count("enabled: parent.enabled") == 2
    assert "opacity: enabled ? 1 : 0.5" in CAM
    # the header says what is happening, including the otherwise silent
    # "capturing" phase, and exposes it to assistive technology
    assert 'Camera.phase === "capturing" ? Tr.t("Saving photo…")' in CAM
    assert "Accessible.name: text" in CAM


def test_camera_gallery_has_an_empty_state():
    assert "visible: Camera.gallery.length === 0" in CAM
    assert 'text: Tr.t("No captures yet")' in CAM


def test_camera_gallery_rows_are_keyboard_and_at_reachable():
    # clicking a row opened the viewer, but a keyboard user could only reach
    # the delete button; name the row and give it the same activation
    assert "Accessible.role: Accessible.ListItem" in CAM
    assert 'Accessible.name: modelData.name + ", " + modelData.when' in CAM
    assert "KeyFocus { onActivated: Viewer.open(modelData.path) }" in CAM


def test_recorder_rename_escape_cancels_only_the_edit():
    # without an accepted Escape on the field, the window handler closed the
    # whole panel and left win.renaming pointing at the old path
    line = 'Keys.onEscapePressed: { event.accepted = true; win.renaming = ""; }'
    assert line in REC
    assert "Keys.onEscapePressed: Ui.voiceRecorder = false" in REC


def test_recorder_inline_playback_has_no_stale_bar():
    # end of media, closing the panel, renaming and trashing a playing take
    # all clear the inline playback bar
    assert "playback.mediaStatus === MediaPlayer.EndOfMedia" in REC
    assert 'else { playback.stop(); win.inlinePlay = ""; }' in REC
    # the play/pause and trash controls check inlinePlay against the row path;
    # helpers use a `path` argument after the search/sort refactor
    assert REC.count("win.inlinePlay === row.modelData.path") >= 2
    assert REC.count('win.inlinePlay = "";') >= 4
