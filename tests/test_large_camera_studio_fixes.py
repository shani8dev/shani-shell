"""The camera studio: twelve fixes benchmarked against GNOME Cheese / Camera,
KDE Kamoso and Apple Photo Booth.

Cheese and Kamoso both give a photo/video switch, a countdown and a strip of
last captures; Photo Booth adds a three-shot burst and share from the strip.
Our shell already had capture machinery but no visible mode state, overlays,
burst, metadata or quick actions. The QML is checked statically (there is no
QML runtime in the suite) and the two Python branches embedded in the service
are actually executed here.
"""

import json
import re
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVC = (ROOT / "shani/Services/Camera.qml").read_text(encoding="utf-8")
PANEL = (ROOT / "shani/Modules/Camera/CameraPanel.qml").read_text(encoding="utf-8")


def qml_string(text, name):
    """Unescape a single-quoted QML string so Python can execute it."""
    m = re.search(r"property string " + name + r": '(.*?)'\n", text, re.S)
    assert m, name
    return m.group(1).replace("\\n", "\n")


def still_code():
    m = re.search(r'python3 - "\$f" "\$3" "\$4" "\$5" <<"PY"\n(.*?)\nPY', SVC, re.S)
    assert m, "still pipeline not found"
    return m.group(1).replace("\\\\", "\\")


def png_pixels(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat = 8, b""
    w = h = 0
    while pos < len(data):
        size = struct.unpack(">I", data[pos : pos + 4])[0]
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + size]
        pos += 12 + size
        if kind == b"IHDR":
            w, h = struct.unpack(">II", body[:8])
        elif kind == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    rows = []
    for y in range(h):
        row = raw[y * (w * 3 + 1) : (y + 1) * (w * 3 + 1)]
        assert row[0] == 0
        rows.append([tuple(row[1 + x * 3 : 4 + x * 3]) for x in range(w)])
    return rows


def run_still(tmp, pixels, ev, zoom):
    h, w = len(pixels), len(pixels[0])
    src = tmp / "in.ppm"
    src.write_bytes(
        f"P6\n{w} {h}\n255\n".encode()
        + bytes(channel for row in pixels for pixel in row for channel in pixel)
    )
    out = tmp / "out.png"
    code = still_code()
    subprocess.run(
        ["python3", "-c", code, str(src), str(out), str(ev), str(zoom)], check=True
    )
    return png_pixels(out)


# ---- 1. photo / video switch has a visible, named state -----------------------


def test_mode_switch_has_visible_state():
    assert 'property string mode: "photo"' in SVC
    assert (
        'text: Camera.mode === "video" ? Tr.t("Video mode") : Tr.t("Photo mode")'
        in PANEL
    )
    assert 'color: Camera.mode === "video" ? Theme.red : Theme.accent' in PANEL
    assert "Accessible.name: modeLabel.text" in PANEL
    assert 'Choice { text: Tr.t("Photo"); selected: Camera.mode === "photo"' in PANEL
    assert 'Choice { text: Tr.t("Video"); selected: Camera.mode === "video"' in PANEL
    assert (
        'k === Qt.Key_C) Camera.mode = Camera.mode === "photo" ? "video" : "photo"'
        in PANEL
    )


# ---- 2. timer / recording overlays --------------------------------------------


def test_timer_and_recording_overlays_are_seen_and_named():
    assert 'visible: Camera.phase === "counting"' in PANEL
    assert "text: String(Camera.countdown)" in PANEL
    assert 'Accessible.name: Tr.t("Photo in %1 seconds", Camera.countdown)' in PANEL
    assert 'visible: Camera.phase === "recording"' in PANEL
    assert 'Accessible.name: Tr.t("Recording") + " " + Camera.elapsed' in PANEL
    assert (
        "const s = [0, 3, 5, 10]; Camera.selfTimer = s[(s.indexOf(Camera.selfTimer) + 1) % s.length];"
        in PANEL
    )


# ---- 3. composition grid ------------------------------------------------------


def test_grid_is_a_visible_overlay_only_when_asked_for():
    assert "property bool grid: false" in SVC
    assert "visible: Camera.grid" in PANEL
    # two vertical + two horizontal third lines, drawn over the preview
    assert PANEL.count("model: 2") >= 2
    assert "preview.width * (index + 1) / 3" in PANEL
    assert "preview.height * (index + 1) / 3" in PANEL
    assert 'Choice { text: Tr.t("Grid"); selected: Camera.grid' in PANEL
    assert "k === Qt.Key_G) Camera.grid = !Camera.grid" in PANEL


# ---- 4. flash cue -------------------------------------------------------------


def test_flash_cue_is_driven_by_each_capture():
    assert "property bool flash: false" in SVC
    assert "property int flashTick: 0" in SVC
    assert "root.flashTick++" in SVC
    assert (
        "function onFlashTickChanged() { if (Camera.flash) flashAnim.restart(); }"
        in PANEL
    )
    assert 'id: flashLayer; anchors.fill: parent; color: "white"; opacity: 0' in PANEL
    assert (
        'NumberAnimation { target: flashLayer; property: "opacity"; from: 0.85; to: 0'
        in PANEL
    )
    assert 'Choice { text: Tr.t("Flash"); selected: Camera.flash' in PANEL
    assert "k === Qt.Key_F) Camera.flash = !Camera.flash" in PANEL


# ---- 5. exposure / zoom (executed) --------------------------------------------


def test_still_exposure_and_zoom_are_applied_by_the_pipeline(tmp_path):
    # cam exposes no CLI for these, so the existing PNG step applies them to
    # the still itself; the EV and zoom travel as argv slots, never shell text
    assert "property real exposure: 0" in SVC
    assert "property int zoom: 100" in SVC
    assert 'python3 - "$f" "$3" "$4" "$5" <<"PY"' in SVC
    assert "root.last, String(root.exposure), String(root.zoom)" in SVC
    code = still_code()
    assert "float(sys.argv[3])" in code and "float(sys.argv[4])" in code

    plain = [[(10, 20, 30), (100, 100, 100)], [(200, 90, 40), (7, 8, 9)]]
    assert run_still(tmp_path, plain, 0, 100) == plain
    assert run_still(tmp_path, plain, 1, 100) == [
        [(20, 40, 60), (200, 200, 200)],
        [(255, 180, 80), (14, 16, 18)],
    ]
    zoomed = run_still(tmp_path, plain, 0, 200)
    assert zoomed == [[plain[0][0], plain[0][0]], [plain[0][0], plain[0][0]]]
    assert 'Choice { text: "-"; onClicked: Camera.exposure = Math.max(-2' in PANEL
    assert 'Choice { text: "+"; onClicked: Camera.zoom = Math.min(400' in PANEL


# ---- 6. burst -----------------------------------------------------------------


def test_burst_takes_a_numbered_strip_without_ending_the_phase():
    assert "property bool burst: false" in SVC
    assert "burstLeft = root.burst ? root.burstCount : 1" in SVC
    assert (
        'const seq = root.burstLeft > 1 ? " " + (root.burstCount - root.burstLeft + 1) : ""'
        in SVC
    )
    assert "root.burstLeft--" in SVC
    assert "if (root.burstLeft > 0) { burstGap.restart(); return; }" in SVC
    assert (
        "Timer { id: burstGap; interval: 350; onTriggered: root.captureStill() }" in SVC
    )
    assert 'Choice { text: Tr.t("Burst"); selected: Camera.burst' in PANEL
    assert "k === Qt.Key_B) Camera.burst = !Camera.burst" in PANEL
    # the failure path cannot leave a half-finished strip running
    assert 'root.burstLeft = 0;\n                root.phase = "idle";' in SVC


# ---- 7. ratings / favourites / recents (executed) ------------------------------


def test_gallery_metadata_survives_a_rescan_and_filters(tmp_path):
    assert 'property string galleryFilter: "all"' in SVC
    assert 'root.galleryFilter === "favorites"' in SVC
    assert "root.gallery.slice(0, 10)" in SVC
    assert "root.gallery = root.decorate(out)" in SVC
    assert "function ratingOf(path)" in SVC and "function favoriteOf(path)" in SVC
    assert (
        "function rate(path, stars)" in SVC and "function toggleFavorite(path)" in SVC
    )
    assert "Math.max(0, Math.min(5, Math.round(stars)))" in SVC
    assert "root.gallery = root.decorate(root.gallery)" in SVC
    # the file really is written with argv slots, not an interpolated shell line
    assert (
        'metaWrite.command = ["python3", "-c", root.metaWriteCode, root.metaFile, JSON.stringify(root.meta)]'
        in SVC
    )
    write_code = qml_string(SVC, "metaWriteCode")
    load = re.search(
        r'running: true\n\s+command: \["python3", "-c", \'(.*?)\', root\.metaFile\]',
        SVC,
        re.S,
    )
    assert load
    load_code = load.group(1).replace("\\n", "\n")
    target = tmp_path / "camera.json"
    payload = {"/p/a.jpg": {"rating": 4, "favorite": True}}
    subprocess.run(
        ["python3", "-c", write_code, str(target), json.dumps(payload)], check=True
    )
    assert json.loads(target.read_text()) == payload
    read = subprocess.run(
        ["python3", "-c", load_code, str(target)],
        check=True,
        capture_output=True,
        text=True,
    )
    assert json.loads(read.stdout) == payload
    missing = subprocess.run(
        ["python3", "-c", load_code, str(tmp_path / "none.json")],
        check=True,
        capture_output=True,
        text=True,
    )
    assert json.loads(missing.stdout) == {}
    for chip in (
        'text: Tr.t("Recents")',
        'text: Tr.t("Favorites")',
        "model: Camera.galleryView",
    ):
        assert chip in PANEL
    assert (
        'Camera.galleryFilter === "favorites" ? Tr.t("No favorites yet") : Tr.t("No recent captures")'
        in PANEL
    )


# ---- 8. quick actions ---------------------------------------------------------


def test_last_capture_has_open_share_copy_and_reveal():
    for action in (
        "Camera.openCapture(Camera.last)",
        "Share.open(Camera.last)",
        "Camera.copyPath(Camera.last)",
        "Camera.reveal(Camera.last)",
    ):
        assert action in PANEL, action
    assert (
        "function copyPath(path) { if (path) Quickshell.clipboardText = path; }" in SVC
    )
    assert (
        'function reveal(path) { if (path) Files.show(path.substring(0, path.lastIndexOf("/"))); }'
        in SVC
    )
    assert "if (/\\.(png|jpg|jpeg|webp)$/i.test(path)) Viewer.open(path);" in SVC
    assert 'else Qt.openUrlExternally("file://" + path)' in SVC
    assert "Share.open(captureRow.modelData.path)" in PANEL


# ---- 9. device selection error ------------------------------------------------


def test_no_device_and_scan_error_have_an_actionable_state():
    assert 'property string error: ""' in SVC
    assert 'root.error = found.length === 0 ? Tr.t("No camera found") : ""' in SVC
    assert (
        'onExited: code => { if (code !== 0) root.error = Tr.t("Camera check failed"); }'
        in SVC
    )
    assert "readonly property bool privacyOff: !Privacy.cameraEnabled" in SVC
    assert 'visible: Camera.privacyOff || Camera.error !== ""' in PANEL
    assert (
        'title: Camera.privacyOff ? Tr.t("Camera is switched off") : Camera.error'
        in PANEL
    )
    assert 'actionText: Tr.t("Try again")' in PANEL
    assert "onAction: Camera.refresh()" in PANEL
    assert "Camera.selected = modelData.index" in PANEL
    # opening a camera now scans the gallery too (it used to stay empty)
    assert "function openCamera() { refresh(); scanGallery(); open = true; }" in SVC


# ---- 10. keyboard and assistive technology ------------------------------------


def test_shortcuts_do_not_double_fire_and_controls_are_named():
    assert "Keys.onPressed: e => { if (!e.accepted) win.shortcut(e); }" in PANEL
    for key in (
        "Qt.Key_Space",
        "Qt.Key_C",
        "Qt.Key_G",
        "Qt.Key_F",
        "Qt.Key_B",
        "Qt.Key_T",
        "Qt.Key_X",
        "Qt.Key_Z",
    ):
        assert key in PANEL, key
    assert "e.accepted = true;" in PANEL
    assert "Space shoot · C mode · G grid" in PANEL
    assert "Accessible.role: Accessible.Button" in PANEL  # the shutter's own role
    for label in (
        "Less exposure",
        "More exposure",
        "Zoom out",
        "Zoom in",
        "Favorite capture",
        "Share capture",
    ):
        assert 'Tr.t("' + label + '")' in PANEL, label
    assert "accessibleName: tip" in PANEL
    assert "Accessible.ignored: true" in PANEL


# ---- 11. gallery row actions ---------------------------------------------------


def test_gallery_rows_rate_favorite_share_copy_and_open():
    assert "Camera.rate(captureRow.modelData.path, index + 1)" in PANEL
    assert "Camera.toggleFavorite(captureRow.modelData.path)" in PANEL
    assert "Camera.copyPath(captureRow.modelData.path)" in PANEL
    assert "Camera.trash(modelData.path)" in PANEL
    assert "KeyFocus { onActivated: Viewer.open(modelData.path) }" in PANEL
    assert "Accessible.role: Accessible.ListItem" in PANEL
    assert 'Accessible.name: modelData.name + ", " + modelData.when' in PANEL
    assert (
        'icon: captureRow.modelData.rating > index ? "starred" : "non-starred"' in PANEL
    )


# ---- 12. original capture path still intact -----------------------------------


def test_existing_capture_contract_is_not_broken():
    assert 'enabled: Camera.available && Camera.phase === "idle"' in PANEL
    assert "visible: Camera.gallery.length === 0" in PANEL
    assert 'text: Tr.t("No captures yet")' in PANEL
    assert "function selectedPwNodeId()" in SVC
    assert "function isoOf(path)" in SVC
    assert '["gio", "trash", "--", path]' in SVC
    assert SVC.count('SystemSounds.play("camera-shutter")') >= 2
    assert "closeCamera() { open = false; stopViewfinder(); }" in SVC
