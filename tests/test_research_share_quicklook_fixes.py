"""Static guards for five low-risk share / quick-look / pin fixes.

These surfaces need live services (Bluetooth targets, a file list, grim) that
the suite cannot start, so each test pins the wiring in the QML source.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHARE = "shani/Modules/Share/ShareSheet.qml"
QUICK = "shani/Modules/QuickLook/QuickLookSheet.qml"
PIN = "shani/Modules/Screenshots/PinCapture.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_share_sheet_caps_height_and_scrolls_targets():
    """Many Bluetooth targets pushed the last rows off-screen: the card now has
    a height cap and its target list lives in a clipping Flickable."""
    q = read(SHARE)
    assert "implicitHeight: Math.min(col.implicitHeight + 32, parent.height - 80)" in q
    assert "id: targetFlick" in q
    assert "implicitHeight: Math.min(targetsCol.implicitHeight, win.height - 160)" in q
    assert "contentHeight: targetsCol.implicitHeight" in q
    assert "clip: true" in q
    # the Repeater is nested in the Flickable's column, not laid out by col
    assert q.index("id: targetFlick") < q.index("Repeater {")


def test_share_sheet_home_end_jump_to_first_last():
    """Up/Down only walked one target at a time; Home/End now reach the ends."""
    q = read(SHARE)
    assert "Qt.Key_Home" in q and "Qt.Key_End" in q
    assert "win.sel = 0" in q
    assert "win.sel = Share.targets.length - 1" in q


def test_quicklook_text_preview_scrolls_from_the_keyboard():
    """A long text/code preview could not be scrolled without a pointer; the
    arrow and page keys now move the text Flickable's contentY."""
    q = read(QUICK)
    assert "id: listingFlick" in q
    assert 'QuickLook.kind !== "text"' in q
    for key in ("Qt.Key_Up", "Qt.Key_Down", "Qt.Key_PageUp", "Qt.Key_PageDown"):
        assert key in q
    assert "listingFlick.contentY" in q


def test_quicklook_home_end_jump_to_ends_of_list():
    """The header counts '3 / 12' but there was no first/last jump; Home/End
    drive QuickLook.step with the offset to either end of the sibling list."""
    q = read(QUICK)
    assert "function jumpTo(i)" in q
    assert "QuickLook.step(i - cur)" in q
    assert "Qt.Key_Home" in q and "Qt.Key_End" in q
    assert "jumpTo(0)" in q
    assert "jumpTo(QuickLook.list.length - 1)" in q


def test_pin_capture_percent_encodes_the_path():
    """A '#', '?' or '%' in a screenshot filename broke the raw 'file://' + path,
    showing 'Screenshot not found'; encode each segment like Quick Look does."""
    q = read(PIN)
    assert (
        'function fileUrl(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }'
        in q
    )
    assert (
        'source: Screenshots.pinnedPath !== "" ? fileUrl(Screenshots.pinnedPath) : ""'
        in q
    )
    assert '"file://" + Screenshots.pinnedPath' not in q
