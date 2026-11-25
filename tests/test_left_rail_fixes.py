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


def test_left_rail_reserves_its_strip_and_is_one_per_screen():
    # a window is never tiled under it, and it does not hop between outputs
    assert "exclusionMode: ExclusionMode.Normal" in RAIL
    assert "exclusiveZone: implicitWidth" in RAIL
    assert "model: Quickshell.screens" in RAIL
    assert "mask: Region { item: card }" in RAIL


def test_the_dock_and_the_rail_never_both_show_workspaces():
    dock = (ROOT / "shani/Modules/Dock/Dock.qml").read_text()
    assert "readonly property bool spacesHere: !(Settings.data.leftRail && FormFactor.hasRail(output))" in dock
    assert "model: win.spacesHere ? win.spaces.concat([null]) : []" in dock
    niri = (ROOT / "shani/Services/Niri.qml").read_text()
    assert "function windowsOn(ws)" in niri and "function newWorkspaceOn(output)" in niri
    assert "Niri.newWorkspaceOn(" in RAIL and "Niri.windowsOn(" in RAIL


def test_left_rail_uses_existing_niri_workspace_apis():
    assert "Niri.workspacesOn(" in RAIL
    assert "Niri.focusWorkspace(" in RAIL
    assert "is_active || ws.is_focused" in RAIL


def test_left_rail_is_keyboard_and_at_reachable():
    assert "Accessible.role: Accessible.Button" in RAIL
    assert 'Tr.t("Workspace %1"' in RAIL and 'Tr.t("New workspace")' in RAIL
    assert "KeyFocus { onActivated: cell.activate() }" in RAIL


def test_left_rail_is_on_by_default_and_lazy_loaded():
    assert "visible: Settings.data.leftRail" in RAIL
    assert "property bool leftRail: true" in SETTINGS
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
