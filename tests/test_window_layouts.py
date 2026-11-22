"""Window layouts: arrange many windows at once, with a real snapshot undo."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
svc = (ROOT / "shani/Services/WindowLayouts.qml").read_text()
ui = (ROOT / "shani/Modules/WindowLayouts/WindowLayouts.qml").read_text()


def test_snapshot_and_arrange_all():
    assert "function snapshot()" in svc
    assert "function arrangeAll(layoutId)" in svc
    assert "function restore(snap)" in svc
    assert "function undo()" in svc
    assert "snapshot: snap" in svc


def test_ui_toggle():
    assert "arrangeAllMode" in ui
    assert "All windows" in ui
    assert "WindowLayouts.arrangeAll" in ui


def test_drag_to_edge_is_keyboard_backed():
    # niri exposes no drag events to the shell; the keyboard snap is the
    # supported path and is documented as such
    assert "function snapToEdge" in svc
    assert "move-column-to-side" in svc
    cfg = (
        ROOT.parent / "shani-pkgbuilds/shani-desktop-niri/etc/niri/config.kdl"
    ).read_text()
    assert "Mod+Alt+Left" in cfg and "Mod+Alt+Right" in cfg
