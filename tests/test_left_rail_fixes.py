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
    assert "readonly property bool spacesHere: !(Settings.data.leftRail && Settings.data.railContent !== \"apps\" && FormFactor.hasRail(output))" in dock
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


def test_every_kind_of_screen_has_a_layout_made_for_it():
    """Screen and layout: each kind (FormFactor.js PROFILES) has exactly one
    layout made for it, which tryKind picks, and a line saying what it is."""
    import re
    # the layouts are Services/Layouts' (the switcher, the situations' memory and these share it)
    switcher = (ROOT / "shani/Services/Layouts.qml").read_text()
    ui = (ROOT / "shani/Modules/LayoutSwitcher/LayoutSwitcher.qml").read_text()
    ff = (ROOT / "shani/Common/FormFactor.js").read_text()
    kinds = re.findall(r'"(\w+)"', re.search(r"var PROFILES = \[(.*?)\]", ff).group(1))
    made = re.findall(r'\{ id: "(\w+)", made: "(\w+)", suits: \[(.*?)\]', switcher)
    by_kind = {}
    for pid, kind, suits in made:
        by_kind.setdefault(kind, []).append(pid)
        assert '"%s"' % kind in suits, pid            # made for it, so it suits it
    assert by_kind == {"computer": ["default"], "laptop": ["laptop"], "tablet": ["tablet"], "phone": ["phone"],
                       "tv": ["tv"], "projector": ["focus"], "handheld": ["handheld"], "board": ["classroom"]}
    # no two layouts alike, and none named after another product
    sets = re.findall(r"set: Object\.assign\(\{ (.*?) \}, cornersAll\(\"(\w+)\"\)\)", switcher)
    assert len(sets) == len(set(sets)) == len(re.findall(r'\{ id: "(\w+)"', switcher))
    names = " ".join(re.findall(r'name: Tr\.t\("([^"]+)"\)', switcher) + re.findall(r'desc: Tr\.t\("([^"]+)"\)', switcher))
    for brand in ("Windows", "macOS", "Ubuntu", "Unity", "GNOME", "KDE", "ChromeOS", "Steam", "Cortana"):
        assert brand not in names, brand
    assert sorted(by_kind) == sorted(kinds)
    assert "x.made === now" in ui                       # tryKind takes the one made for it first
    for k in kinds:
        assert re.search(r"\b%s: Tr\.t\(" % k, ui), k
    # the render matrix shows each kind in its own layout, and every layout on a computer
    render = (ROOT / "dev/render.sh").read_text()
    ids = re.findall(r'\{ id: "(\w+)"', switcher)
    listed = re.search(r'MATRIX_LAYOUTS="([^"]+)"', render).group(1).split()
    assert sorted(listed) == sorted(ids)
