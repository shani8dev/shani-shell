"""Hover previews: window capture on dock hover, file peek on path hover."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
peek = (ROOT / "shani/Common/HoverPeek.qml").read_text()
wp = (ROOT / "shani/Services/WindowPreview.qml").read_text()
dock = (ROOT / "shani/Modules/Dock/Dock.qml").read_text()
files = (ROOT / "shani/Modules/Files/FilesPanel.qml").read_text()


def test_window_preview_uses_grim_geometry():
    assert "grim -g" in wp
    assert "tile_pos_in_workspace_view" in wp and "tile_size" in wp
    assert (
        "Math.max(x, ox)" in wp and "Math.min(x + w, ox + ow)" in wp
    )  # clipped to output


def test_hover_peek_is_nonfocusing_popup():
    assert "PopupWindow" in peek
    assert "anchor.item" in peek
    assert "Timer" in peek and "interval: root.delay" in peek
    assert "HoverHandler" in peek
    assert "WindowPreview.capture" in peek
    assert "head -c 4096" in peek


def test_dock_and_files_wired():
    assert dock.count("HoverPeek") >= 1
    assert "onEntered: hoverPeek.forceActive()" in dock
    assert "onExited: hoverPeek.cancel()" in dock
    assert files.count("HoverPeek") >= 2
    assert files.count("onEntered: hoverPeek.forceActive()") >= 2


def test_launcher_already_has_selected_preview():
    q = (ROOT / "shani/Modules/Launcher/Launcher.qml").read_text()
    assert "lookPath" in q and "lookPdfImage" in q
