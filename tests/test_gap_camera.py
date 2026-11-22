"""Camera gaps: self-timer, shutter sound, H.264/MP4, picture format, gallery delete."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVC = (ROOT / "shani/Services/Camera.qml").read_text()
PANEL = (ROOT / "shani/Modules/Camera/CameraPanel.qml").read_text()


def test_self_timer_is_a_choice_not_a_fixed_three():
    assert "property int selfTimer: 3" in SVC
    assert "countdown = selfTimer > 0 ? selfTimer : 0" in SVC
    assert "function captureStill()" in SVC and "root.captureStill()" in SVC
    for sec in ("[0,", "[3,", "[5,", "[10,"):
        assert sec in PANEL, sec
    assert "Camera.selfTimer = modelData[0]" in PANEL


def test_shutter_sound_uses_existing_system_sounds():
    assert 'SystemSounds.play("camera-shutter")' in SVC
    # both a still and a video start make the shutter sound
    assert SVC.count('SystemSounds.play("camera-shutter")') >= 2


def test_video_format_h264_mp4_option():
    assert 'property string videoFormat: "webm"' in SVC
    assert 'videoFormat === "mp4"' in SVC
    assert "x264enc" in SVC and "mp4mux" in SVC and "avenc_aac" in SVC
    assert "vp8enc" in SVC and "webmmux" in SVC
    # encoders pass through argv slots, never built into the shell string
    assert '"sh", last, videoSource, venc, muxer, audioSource, aenc' in SVC
    assert '.mp4"' in SVC
    assert 'text: "MP4"' in PANEL and 'Camera.videoFormat = "mp4"' in PANEL


def test_picture_format_choice_with_conversion():
    assert 'property string photoFormat: "png"' in SVC
    assert "ffmpeg" in SVC and "-q:v" in SVC and ".jpg" in SVC
    assert r"\.png$" in SVC
    assert 'text: "JPG"' in PANEL and 'Camera.photoFormat = "jpg"' in PANEL
    assert r"/\.(png|jpg)$/i.test(Camera.last)" in PANEL


def test_gallery_delete():
    assert "function trash(" in SVC and '["gio", "trash", "--", path]' in SVC
    assert "root.scanGallery()" in SVC
    assert "Camera.trash(modelData.path)" in PANEL
    assert "edit-delete" in PANEL
