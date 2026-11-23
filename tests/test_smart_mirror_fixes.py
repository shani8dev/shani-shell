"""Static regressions for the Smart/Mirror singleton fixes.

QML cannot run under pytest here, so each test pins the source binding that
carries one fix: a failed adb scan must not keep stale phones, a vanished
serial must not stay "mirrored", mirror() must refuse a device it cannot see,
a URL chip must not print its password, and dates/cards must not be dialled.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MIRROR = "shani/Services/Mirror.qml"
SMART = "shani/Services/Smart.qml"


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def list_process(text):
    return text[text.index("id: list") :]


def mirror_function(text):
    start = text.index("function mirror(")
    return text[start : text.index("Process {", start)]


def test_failed_adb_scan_drops_stale_devices():
    block = list_process(source(MIRROR))
    assert "onExited: code =>" in block
    assert "code !== 0" in block
    assert "root.devices = []" in block


def test_vanished_serial_clears_mirrored_state():
    block = list_process(source(MIRROR))
    assert "const found =" in block
    assert "root.devices = found;" in block
    assert "!found.some(d => d.serial === root.last)" in block
    assert 'root.last = "";' in block


def test_mirror_rejects_unavailable_or_stale_serial():
    fn = mirror_function(source(MIRROR))
    assert "!root.available" in fn
    assert "devices.length > 0 && !devices.some" in fn
    assert "return false;" in fn
    assert "last = serial;" in fn  # a real device is still recorded


def test_url_chip_hides_embedded_password():
    text = source(SMART)
    assert 'replace(/^[^@/]+@/, "***@")' in text
    assert "run: () => Qt.openUrlExternally(t)" in text  # the real URL still opens


def test_date_and_card_are_not_offered_as_calls():
    text = source(SMART)
    assert r"!/^(\d{1,4}[-/.]){2}\d{1,4}$|^\d{16}$/.test(t)" in text
