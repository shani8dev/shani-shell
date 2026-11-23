"""Fixes from the third-pass audit of unaudited apps and accessibility."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text()


def test_pdf_signer_preserves_all_pages():
    s = read("shani/Services/PdfSigner.qml")
    assert "pdftoppm -png -r 150 -f" not in s  # the one-page command is gone
    assert 'pdftoppm -png -r 150 "$1" "$work/page"' in s
    assert "pdfunite" in s
    assert '"bash", "-c", script' in s  # mapfile needs bash, not sh


def test_archive_appends_jar_and_apk_as_zip():
    s = read("shani/Services/Archive.qml")
    assert '["zip", "jar", "apk"].indexOf(root.appendExt) >= 0' in s


def test_disk_usage_clears_marks_on_navigation():
    s = read("shani/Services/DiskUsage.qml")
    assert s.count("marked = []") >= 2


def test_font_install_decodes_path():
    s = read("shani/Modules/Fonts/FontsPanel.qml")
    assert "decodeURIComponent(selectedFile.toString()" in s


def test_maps_route_uses_typed_start():
    s = read("shani/Modules/Maps/MapsPanel.qml")
    assert 'win.fromOk ? (win.fromLat + "," + win.fromLon)' in s


def test_converter_wires_fade_artist_speed():
    s = read("shani/Modules/Converter/ConverterWindow.qml")
    for name in ("artistField", "fadeField", "speedField"):
        assert name in s
    assert 'add("fade", fadeField)' in s and 'add("speed", speedField)' in s


def test_nearby_cancel_is_exposed():
    svc = read("shani/Services/Nearby.qml")
    win = read("shani/Modules/Nearby/NearbyWindow.qml")
    assert "function cancel(session)" in svc
    assert 'op: "cancel"' in svc
    assert "Nearby.cancel(tr.modelData.session)" in win


def test_accessibility_wins():
    toast = read("shani/Common/Toast.qml")
    slider = read("shani/Common/SliderRow.qml")
    shell = read("shani/shell.qml")
    assert "Qt.accessibleAnnounce(message" in toast
    assert "Accessible.role: Accessible.Slider" in slider
    # the slider now exposes a human-readable name, falling back to the icon-derived
    # one only when no label was supplied (pass-18 a11y fix)
    assert "Accessible.name: root.readableName" in slider
    assert "property string label" in slider
    assert 'sequences: ["Meta+Alt+S"]' in shell
