"""Static checks for Chronoa surface and Control Centre sidebar fixes.

These QML surfaces are not instantiated in this suite, so each fix is asserted
against its source: the sidebar keeps its dismiss animation, clears stale state,
and stays reachable by keyboard and assistive tech; the Chronoa surface ignores
empty turn payloads instead of rendering "undefined".
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SIDEBAR = (ROOT / "shani/Modules/ControlCenter/Sidebar.qml").read_text(encoding="utf-8")
CHRONOA = (ROOT / "shani/Modules/Chronoa/ChronoaSurface.qml").read_text(
    encoding="utf-8"
)


def test_sidebar_narrow_close_keeps_window_visible_for_slide_animation():
    """A phone shade must stay mounted until its slide-down animation finishes."""
    # the phone's shade slides down from the top, so it is on screen while its
    # top edge is still above the screen top (not below the screen bottom)
    assert (
        "visible: Ui.controlCenter || (!narrow && slide.x < width) || (narrow && slide.y > -slide.height + 1)"
        in SIDEBAR
    )


def test_sidebar_clears_stale_power_confirm_on_close():
    """A two-click power confirmation must not survive closing the sidebar."""
    assert (
        'win.confirm = "";      // stale two-click power confirm must not survive a close'
        in SIDEBAR
    )
    changed = SIDEBAR.split("function onControlCenterChanged()", 1)[1]
    changed = changed.split("Connections", 1)[0]
    assert "if (Ui.controlCenter)" in changed
    assert "win.confirm" in changed
    assert "else {" in changed


def test_sidebar_exposes_accessible_name_and_nav_window():
    """The overlay needs an AT name and nav registration for keyboard reach."""
    assert "Accessible.role: Accessible.Pane" in SIDEBAR
    assert 'Accessible.name: Tr.t("Control centre")' in SIDEBAR
    assert "NavWindow {}" in SIDEBAR


def test_sidebar_home_end_scroll_the_panel():
    """Keyboard users can jump to the top or bottom of the long sidebar."""
    assert "Qt.Key_Home" in SIDEBAR and "flick.contentY = 0" in SIDEBAR
    assert "Qt.Key_End" in SIDEBAR and "flick.contentHeight - flick.height" in SIDEBAR


def test_chronoa_surface_ignores_empty_turn_payloads():
    """Empty bridge payloads must not become undefined transcript rows."""
    assert "if (!e || !e.event)" in CHRONOA
    assert 'const text = String(e.text || "");' in CHRONOA
    assert 'const t = String(text || "").trim();' in CHRONOA
    assert 'if (t !== "")\n                panel.addUser(t);' in CHRONOA
    assert 'if (t !== "")\n                panel.addSystem(t);' in CHRONOA
    assert 'if (text !== "")\n                    panel.addTool(text);' in CHRONOA
    assert 'if (text !== "")\n                    panel.appendReply(text);' in CHRONOA
    assert 'if (text !== "")\n                    panel.addSystem(text);' in CHRONOA
