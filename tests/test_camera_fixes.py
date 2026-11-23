"""Static checks for the camera capture fixes: selected camera for video,
gallery timestamps, and viewfinder lifetime."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVC = (ROOT / "shani/Services/Camera.qml").read_text()
PANEL = (ROOT / "shani/Modules/Camera/CameraPanel.qml").read_text()


def test_video_uses_selected_camera_pipewire_node():
    # the picker's libcamera index is not a PipeWire id: resolve it via nodes
    assert "import Quickshell.Services.Pipewire" in SVC
    assert "Pipewire.nodes.values" in SVC and "PwNodeType.VideoSource" in SVC
    assert "function selectedPwNodeId()" in SVC
    # pipewiresrc gets path=<id>; an unknown camera keeps the plain default
    assert '"pipewiresrc path=" + id' in SVC
    assert 'return id > 0 ? "pipewiresrc path=" + id : "pipewiresrc"' in SVC
    # the resolved source is what the recorder argv receives
    assert "const videoSource = root.videoSrc()" in SVC
    assert '"sh", last, videoSource, venc, muxer, audioSource, aenc' in SVC


def test_gallery_timestamps_parse_the_capture_name():
    assert "function isoOf(path)" in SVC
    assert r"(\d{4})-(\d{2})-(\d{2})[ -](\d{2})-(\d{2})-(\d{2})" in SVC
    assert "new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])" in SVC
    assert 'Qt.formatDateTime(d, "yyyy-MM-dd hh:mm:ss")' in SVC
    assert "new Date(path.split" not in SVC


def test_viewfinder_lifetime_follows_open_and_selection():
    assert "Process { id: viewfinder }" in SVC
    assert "function stopViewfinder()" in SVC
    block = SVC.split("function openViewfinder()", 1)[1].split("\n    }", 1)[0]
    assert "viewfinder.command" in block and "execDetached" not in block
    # retarget on a new selection, stop on close; panel close paths call closeCamera
    assert "onOpenChanged: if (root.open) openViewfinder()" in SVC
    assert "onSelectedChanged: if (root.open) openViewfinder()" in SVC
    assert "closeCamera() { open = false; stopViewfinder(); }" in SVC
    assert "Camera.selected = modelData.index" in PANEL
    assert "Camera.closeCamera()" in PANEL
