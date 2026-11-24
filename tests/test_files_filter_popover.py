"""The finer Files filter popover: type (reusing the chips), date, size and content.

The QML is checked as text (no QML runner here); the predicate composition and
active-filter count are lifted out of FilesPanel.qml and really executed in node
with a small stand-in for `win`. Content needs no new bridge command: files.py's
deep search already runs a bounded ripgrep over file text.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/Files/FilesPanel.qml").read_text(encoding="utf-8")
BRIDGE = (ROOT / "bridge/files.py").read_text(encoding="utf-8")

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")


def js_func(src, name):
    """One whole function body, braces balanced, ready for node."""
    m = re.search(r"(?m)^[ \t]*function %s\(" % re.escape(name), src)
    assert m, name
    i = src.index("{", m.start())
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[m.start() : j + 1]
    raise AssertionError("unbalanced function " + name)


FUNCS = [
    js_func(PANEL, n)
    for n in (
        "filterDateCutoff",
        "filterSizeBounds",
        "entryPassesFilters",
        "computeActiveFilterCount",
    )
]
PRELUDE = """
const win = { dateFilter: "any", sizeFilter: "any", activeCategory: "all", contentQuery: "" };
"""


def run_js(result, setup="", statements=""):
    names = re.findall(r"function\s+(\w+)\s*\(", "\n".join(FUNCS))
    attach = "\n".join("win.%s = %s;" % (n, n) for n in names)
    prog = (
        PRELUDE
        + "\n"
        + setup
        + "\n"
        + "\n".join(FUNCS)
        + "\n"
        + attach
        + "\n"
        + statements
        + "\nprocess.stdout.write(JSON.stringify("
        + result
        + "));\n"
    )
    r = subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def filter_box():
    """The filter popover object only, brace-balanced."""
    start = PANEL.index("    Glass {\n        id: filterBox")
    i = PANEL.index("{", start)
    depth = 0
    for j in range(i, len(PANEL)):
        if PANEL[j] == "{":
            depth += 1
        elif PANEL[j] == "}":
            depth -= 1
            if depth == 0:
                return PANEL[start : j + 1]
    raise AssertionError("unbalanced filterBox")


# ---- static wiring: a button beside the chips, a popover, a count and Clear --------


def test_filter_button_lives_beside_the_category_chips():
    chips = PANEL.split(
        "// search categories: the chips feed the listing's extension filters", 1
    )[1]
    chips = chips.split("// split pane toolbar", 1)[0]
    for line in (
        "id: filterBtn",
        'icon: "view-filter"',
        "on: win.filterShown || win.activeFilterCount > 0",
        'accessibleName: win.activeFilterCount ? Tr.t("Filters, %1 active").arg(win.activeFilterCount) : Tr.t("Filters")',
        "onClicked: win.toggleFilters()",
        "text: String(win.activeFilterCount)",
    ):
        assert line in chips
    assert chips.index("model: win.searchCategories") < chips.index("id: filterBtn")
    # the other controls the prior agents put in the toolbar are still there
    for line in (
        "Files.searchPath(win.deepWords)",
        "win.typed += event.text.toLowerCase()",
        'tip: Tr.t("Keyboard shortcuts (Ctrl+/)")',
    ):
        assert line in PANEL


def test_popover_is_a_translucent_glass_dialog_with_keyboard_and_a11y_names():
    box = filter_box()
    for line in (
        "strong: true",
        "focus: visible",
        "Accessible.role: Accessible.Dialog",
        'Accessible.name: Tr.t("File filters")',
        "Keys.onPressed: event => {",
        "if (event.key === Qt.Key_Escape) { win.toggleFilters(); event.accepted = true; }",
        'tip: Tr.t("Close filters")',
        'text: Tr.t("Done"); kind: "primary"; onClicked: win.toggleFilters()',
    ):
        assert line in box
    assert "solid: true" not in box  # never an opaque card
    assert "filterBtn.mapToItem(win.contentItem" in box
    # every colour comes from the Theme, not a hard-coded swatch
    assert "Theme.glassStrong" not in box  # Glass supplies the surface colour
    assert "color: Theme." in box or "color: Theme" in box
    assert "#" not in box.replace("Theme.", "")


def test_active_count_and_clear_filters_are_always_visible():
    for line in (
        "function computeActiveFilterCount(category, date, size, content)",
        "property int activeFilterCount: win.computeActiveFilterCount(",
        'text: win.activeFilterCount ? Tr.t("Filters · %1 active").arg(win.activeFilterCount) : Tr.t("Filters")',
        'text: Tr.t("Clear filters")',
        "enabled: win.hasAnyFilter",
        "onClicked: win.clearAllFilters()",
        "visible: win.activeFilterCount > 0",
    ):
        assert line in PANEL
    for line in (
        'win.dateFilter = "any";',
        'win.sizeFilter = "any";',
        "Files.setSearchDeep(false);",
        'win.applyCategory("all");',
    ):
        assert line in PANEL
    # the empty state clears the new filters too, and keeps its useful next click
    empty = PANEL.split("// nothing here", 1)[1]
    empty = empty.split(
        "Text {\n                            anchors.centerIn: parent", 1
    )[0]
    assert 'win.hasAnyFilter ? Tr.t("Clear filters")' in empty
    assert 'win.dateFilter = "any";' in empty
    assert 'win.sizeFilter = "any";' in empty


def test_type_in_the_popover_reuses_the_chips_model_and_action():
    box = filter_box()
    assert "model: win.searchCategories" in box
    assert "selected: Files.activeCategory === modelData.id" in box
    assert "onClicked: win.applyCategory(modelData.id)" in box
    # no second type definition: the category list is still declared exactly once
    assert PANEL.count("readonly property var searchCategories: [") == 1
    assert "function applyCategory(id)" in PANEL
    assert 'Tr.t("Type · choose with the chips above")' in box


def test_date_size_and_content_controls_are_wired():
    box = filter_box()
    for label in ("Any time", "Today", "Last 7 days", "Last 30 days"):
        assert 'Tr.t("%s")' % label in box
    for label in ("Any size", "Under 1 MB", "1-100 MB", "Over 100 MB"):
        assert 'Tr.t("%s")' % label in box
    assert "onClicked: win.setDateFilter(modelData[0])" in box
    assert "onClicked: win.setSizeFilter(modelData[0])" in box
    assert (
        "function setDateFilter(which)" in PANEL
        and "function setSizeFilter(which)" in PANEL
    )
    for line in (
        "id: contentField",
        "text: searchBox.text",
        'if (text.trim() !== "" && !Files.searchDeep) Files.setSearchDeep(true);',
        "searchBox.text = text;",
        'dir.query = Files.searchDeep ? "" : text;',
        "deepTimer.restart();",
        'Tr.t("Content contains")',
    ):
        assert line in box
    assert (
        'readonly property string contentQuery: Files.searchDeep ? searchBox.text.trim() : ""'
        in PANEL
    )


def test_bridge_already_has_a_safe_bounded_content_search():
    # why files.py was not touched: the rg -l path is already argv-only, bounded
    # in time and count and capped in file size, with a grep fallback.
    assert (
        '["rg", "-l", "-i", "-F", "--max-filesize", "20M", "--max-count", "1"]'
        in BRIDGE
    )
    assert '["--", q, root]' in BRIDGE
    assert (
        "subprocess.run(cmd, capture_output=True, text=True, timeout=seconds)" in BRIDGE
    )
    assert "[:limit]" in BRIDGE
    assert "shell=True" not in BRIDGE
    # the deep search the popover drives still merges those content hits
    assert "for p in inside(root, query, hidden" in BRIDGE
    assert 'e["inside"] = True' in BRIDGE


def test_shortcut_and_escape_do_not_shadow_existing_keys():
    assert (
        "if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_F)"
        in PANEL
    )
    assert "win.toggleFilters();" in PANEL
    assert '{ key: "Ctrl+Shift+F", label: Tr.t("The finer filters") },' in PANEL
    assert "if (win.filterShown) { win.toggleFilters(); return; }" in PANEL
    # selection, type-to-search and both views still use the same filtered model
    for line in (
        "Files.setPaths(entries.map(e => e.path))",
        "Files.setEntries(entries)",
        "model: win.visibleEntries",
        "model: win.splitVisibleEntries",
    ):
        assert line in PANEL


# ---- pure logic: date / size / type composition and the active count ----------------


@node_mark
def test_date_cutoff_presets():
    now = 1700000000000
    out = run_js(
        "({any:win.filterDateCutoff('any',NOW), w:win.filterDateCutoff('7days',NOW),"
        " m:win.filterDateCutoff('30days',NOW), today:win.filterDateCutoff('today',NOW)})",
        setup="const NOW = %d;" % now,
    )
    assert out["any"] == 0
    assert out["w"] == now - 7 * 86400000
    assert out["m"] == now - 30 * 86400000
    midnight = run_js(
        "({t:win.filterDateCutoff('today',NOW),h:new Date(win.filterDateCutoff('today',NOW)).getHours(),"
        "mi:new Date(win.filterDateCutoff('today',NOW)).getMinutes()})",
        setup="const NOW = %d;" % now,
    )
    assert midnight["t"] <= now and midnight["h"] == 0 and midnight["mi"] == 0


@node_mark
def test_size_bounds_have_exact_byte_boundaries():
    out = run_js(
        "({any:win.filterSizeBounds('any'),s:win.filterSizeBounds('small'),"
        "m:win.filterSizeBounds('medium'),l:win.filterSizeBounds('large')})"
    )
    assert out == {
        "any": [-1, -1],
        "s": [0, 1024 * 1024 - 1],
        "m": [1024 * 1024, 100 * 1024 * 1024],
        "l": [100 * 1024 * 1024 + 1, -1],
    }


@node_mark
def test_no_filters_keep_everything_and_folders_only_keeps_folders():
    files = [
        {"name": "a.png", "isDir": False, "mtime": 1, "size": 10},
        {"name": "note.txt", "isDir": False, "mtime": 1, "size": 10},
        {"name": "Pictures", "isDir": True, "mtime": 1, "size": 10},
    ]
    out = run_js(
        "ENTRIES.map(e => win.entryPassesFilters(e, NOW, [], false))",
        setup="const ENTRIES = %s; const NOW = 1700000000000;" % json.dumps(files),
    )
    assert out == [True, True, True]
    out = run_js(
        "ENTRIES.map(e => win.entryPassesFilters(e, NOW, [], true))",
        setup="const ENTRIES = %s; const NOW = 1700000000000;" % json.dumps(files),
    )
    assert out == [False, False, True]


@node_mark
def test_type_predicate_is_case_insensitive_and_keeps_folders():
    entries = [
        {"name": "a.PNG", "isDir": False, "mtime": 1, "size": 10},
        {"name": "b.jpg", "isDir": False, "mtime": 1, "size": 10},
        {"name": "noext", "isDir": False, "mtime": 1, "size": 10},
        {"name": "Pics", "isDir": True, "mtime": 1, "size": 10},
    ]
    out = run_js(
        "ENTRIES.map(e => win.entryPassesFilters(e, NOW, F, false))",
        setup=(
            "const ENTRIES = %s; const NOW = 1700000000000; const F = ['png', '.JPG'];"
        )
        % json.dumps(entries),
    )
    assert out == [True, True, False, True]


@node_mark
def test_date_size_and_type_compose_and_folders_bypass_date_and_size():
    now = 1700000000000
    entries = [
        {
            "name": "fresh.png",
            "isDir": False,
            "mtime": now - 3600000,
            "size": 5 * 1024 * 1024,
        },
        {
            "name": "old.png",
            "isDir": False,
            "mtime": now - 10 * 86400000,
            "size": 5 * 1024 * 1024,
        },
        {
            "name": "huge.png",
            "isDir": False,
            "mtime": now - 3600000,
            "size": 200 * 1024 * 1024,
        },
        {
            "name": "fresh.txt",
            "isDir": False,
            "mtime": now - 3600000,
            "size": 5 * 1024 * 1024,
        },
        {"name": "Old folder", "isDir": True, "mtime": 1, "size": 10**12},
    ]
    setup = (
        "const ENTRIES = %s; const NOW = %d; "
        "win.dateFilter = '7days'; win.sizeFilter = 'medium';"
    ) % (json.dumps(entries), now)
    out = run_js(
        "ENTRIES.map(e => win.entryPassesFilters(e, NOW, ['png'], false))",
        setup=setup,
    )
    assert out == [True, False, False, False, True]
    # date boundary: exactly the cutoff passes, one millisecond older does not
    cutoff = now - 7 * 86400000
    edge = [
        {"name": "a", "isDir": False, "mtime": cutoff, "size": 1},
        {"name": "b", "isDir": False, "mtime": cutoff - 1, "size": 1},
    ]
    out = run_js(
        "EDGE.map(e => win.entryPassesFilters(e, NOW, [], false))",
        setup=("const EDGE = %s; const NOW = %d; win.dateFilter = '7days';")
        % (json.dumps(edge), now),
    )
    assert out == [True, False]
    # size boundaries: <1 MB, 1-100 MB, >100 MB
    sizes = [1024 * 1024 - 1, 1024 * 1024, 100 * 1024 * 1024, 100 * 1024 * 1024 + 1]
    entries = [
        {"name": "s" + str(i), "isDir": False, "mtime": now, "size": s}
        for i, s in enumerate(sizes)
    ]
    for preset, expected in (
        ("small", [True, False, False, False]),
        ("medium", [False, True, True, False]),
        ("large", [False, False, False, True]),
        ("any", [True, True, True, True]),
    ):
        out = run_js(
            "ENTRIES.map(e => win.entryPassesFilters(e, NOW, [], false))",
            setup=("const ENTRIES = %s; const NOW = %d; win.sizeFilter = '%s';")
            % (json.dumps(entries), now, preset),
        )
        assert out == expected, preset


@node_mark
def test_active_filter_count_sums_every_active_filter():
    out = run_js(
        "([['all','any','any',''],['images','any','any',''],"
        " ['all','today','small',''],['folders','30days','large','needle']]"
        ".map(a => win.computeActiveFilterCount(a[0],a[1],a[2],a[3])))"
    )
    assert out == [0, 1, 2, 4]
