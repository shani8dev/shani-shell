"""The Applications folder (AppGrid) + right detail panel fixes.

Both components are QML, so most checks read the sources — the pattern in
test_large_launcher_search_fixes.py. What each fix asserts: the grid is a
soft-wrap, categorised grid; search-all covers name/keywords/tags/folders;
per-app tags with a tag cloud; drag reorder; the detail panel's details,
Open and tag editing, all with accessible names and translated labels.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPGRID = (ROOT / "shani/Modules/Launcher/AppGrid.qml").read_text(encoding="utf-8")
PANEL = (ROOT / "shani/Modules/Launcher/AppDetailPanel.qml").read_text(encoding="utf-8")


def block(src, start, end):
    return src.split(start, 1)[1].split(end, 1)[0]


# --------------------------------------------------------------------------
# 1. the grid: soft-wrap columns and folders (categorisation)
# --------------------------------------------------------------------------
def test_appgrid_is_a_soft_wrap_grid():
    assert "GridLayout" in APPGRID
    cols = APPGRID.split("columns: ", 1)[1].split("\n", 1)[0]
    assert "Math.floor(grid.width / Theme.px(" in cols
    assert "Math.max(1, " in cols  # at least one column
    assert "narrow ? 1" in cols  # narrow = one column at a time
    assert "columnSpacing" in APPGRID and "rowSpacing" in APPGRID


def test_appgrid_folders_soft_categorisation():
    assert "readonly property var folders: [" in APPGRID
    for f in [
        "Internet",
        "Office",
        "Graphics",
        "AudioVideo",
        "Development",
        "Utility",
        "System",
        "Game",
        "Other",
    ]:
        assert '"' + f + '"' in APPGRID
    assert "function folderOf(a)" in APPGRID
    fn = block(APPGRID, "function folderOf(a) {", "\n    }")
    assert 'return "Other"' in fn


# --------------------------------------------------------------------------
# 2. the grid: search-all
# --------------------------------------------------------------------------
def test_appgrid_search_all_covers_name_keywords_tags_and_folders():
    fn = block(APPGRID, "function matches(a, t) {", "\n    }")
    for needle in [
        "a.name",
        "a.genericName",
        "a.comment",
        "a.keywords",
        "root.tagsOf(a)",
    ]:
        assert needle in fn, needle
    assert "function searchAll(" in APPGRID
    # the folder chip filters through folderOf
    va = block(APPGRID, "readonly property var visibleApps:", "\n    }")
    assert "root.folderOf(a) === root.category" in va
    assert "root.filter.trim().toLowerCase()" in APPGRID


def test_appgrid_tags_and_tag_cloud():
    assert "function tagsOf(a)" in APPGRID
    fn = block(APPGRID, "function tagCloud() {", "\n    }")
    assert "root.visibleApps" in fn
    assert "counts[t] = (counts[t] || 0) + 1" in fn
    assert "Object.keys(counts).sort(" in fn


# --------------------------------------------------------------------------
# 3. the grid: drag reorder, model from the shell
# --------------------------------------------------------------------------
def test_appgrid_drag_reorder():
    assert "property var order: []" in APPGRID
    assert "function moveItem(" in APPGRID
    assert "DragHandler" in APPGRID and "root.dragFrom = tile.index" in APPGRID
    assert "arr.splice(at, 1)" in APPGRID


def test_appgrid_model_uses_the_shell_apps():
    assert (
        "readonly property var model: DesktopEntries.applications.values.filter("
        "a => !a.noDisplay && AppFilter.allowed(a.id))"
    ) in APPGRID


# --------------------------------------------------------------------------
# 4. the detail panel: details, Open, tag editing
# --------------------------------------------------------------------------
def test_panel_shows_the_selected_app_details():
    for needle in [
        "property var selected: null",
        "root.selected.name",
        "root.selected.genericName || root.selected.comment",
        "Quickshell.iconPath(root.selected ? root.selected.icon",
        '[].concat(root.selected ? root.selected.keywords || [] : []).join(" ")',
    ]:
        assert needle in PANEL, needle


def test_panel_opens_the_selected_app():
    assert "function open(" in PANEL
    assert "Launch.app((a || root.selected || {}).id)" in PANEL
    assert "onClicked: root.open()" in PANEL


def test_panel_edits_tags():
    for needle in [
        "function addTag()",
        "function removeTag(",
        "function tagsOf(",
        'property string newTag: ""',
        "id: tagField",
        'Tr.t("New tag…")',
        "onClicked: root.addTag()",
        'root.newTag = ""',
    ]:
        assert needle in PANEL, needle
    assert "root.tags[e.id] = mine.concat([t])" in PANEL
    assert "root.tagsOf(e).filter(x => x !== t)" in PANEL


# --------------------------------------------------------------------------
# 5. house conventions: accessible names, translated labels
# --------------------------------------------------------------------------
def test_accessible_names_and_roles():
    assert "Accessible.role: Accessible.ListItem" in APPGRID
    assert "Accessible.name: (tile.modelData.name" in APPGRID
    assert "Accessible.name: root.selected ? root.selected.name" in PANEL


def test_labels_are_translated():
    assert "Tr.t(" in PANEL
    for t in ['Tr.t("New tag…")', 'Tr.t("Add tag")', 'Tr.t("Open")']:
        assert t in PANEL, t


def test_no_invalid_accessible_roles():
    """Qt has Accessible.ListItem but no ListHeader/Image/Menu; an unknown enum
    assigns undefined and warns at render."""
    import re as _re

    invalid = {"ListHeader", "Image", "Menu", "PaneItem", "Widget"}
    found = set(_re.findall(r"Accessible\.(\w+)", APPGRID + PANEL))
    assert not (found & invalid), found & invalid
