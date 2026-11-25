"""Static checks for the left workspace rail and the uniformity round."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAIL = (ROOT / "shani/Modules/LeftRail/LeftRail.qml").read_text()
SHELL = (ROOT / "shani/shell.qml").read_text()
SETTINGS = (ROOT / "shani/Common/Settings.qml").read_text()


def test_left_rail_uses_the_left_edge_only():
    assert "anchors { top: true; bottom: true; left: true }" in RAIL
    assert 'WlrLayershell.namespace: "shani-left-rail"' in RAIL
    assert "WlrLayershell.layer: WlrLayer.Top" in RAIL
    assert "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None" in RAIL


def test_left_rail_uses_existing_niri_workspace_apis():
    assert "Niri.workspacesOn(" in RAIL
    assert "Niri.focusWorkspace(" in RAIL
    assert "is_active || ws.is_focused" in RAIL


def test_left_rail_is_keyboard_and_at_reachable():
    assert "Accessible.role: Accessible.Button" in RAIL
    assert 'Accessible.name: Tr.t("Workspace %1"' in RAIL
    assert "KeyFocus { onActivated: Niri.focusWorkspace(ws) }" in RAIL


def test_left_rail_is_opt_in_and_lazy_loaded():
    assert "visible: Settings.data.leftRail" in RAIL
    assert "property bool leftRail: false" in SETTINGS
    assert (
        'LazyLoader { active: Settings.data.leftRail; source: "Modules/LeftRail/LeftRail.qml" }'
        in SHELL
    )


def test_no_invalid_wlr_or_accessible_enum():
    assert "WlrLayer.layer" not in RAIL
    for bad in (
        "Accessible.Image",
        "Accessible.Menu",
        "Accessible.ListHeader",
        "Accessible.Text",
    ):
        assert bad not in RAIL
