"""Files 'power tools' pass, benchmarked against Nautilus, Dolphin and Finder.

The QML is checked as text (the shell has no QML runner here); the non-trivial
tab and selection logic is lifted out of the service and executed in node with a
small stand-in for `root`, so the index maths is really tested, not just grepped.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/Files/FilesPanel.qml").read_text(encoding="utf-8")
SERVICE = (ROOT / "shani/Services/Files.qml").read_text(encoding="utf-8")

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


def run_js(parts, prelude, result, statements=""):
    names = re.findall(r"function\s+(\w+)\s*\(", "\n".join(parts))
    attach = "\n".join("root.%s = %s;" % (n, n) for n in names)
    prog = (
        prelude
        + "\n"
        + "\n".join(parts)
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


def qml_block(text, header):
    """The brace-balanced body after a QML function/handler header."""
    start = text.index(header) + len(header)
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[start:j]
    raise AssertionError("unbalanced " + header)


TABS_PRELUDE = """
const Tr = { t: (s, ...a) => s };
const root = {
    tabs: [], tabIndex: 0, closedTabs: [], closedTabMax: 10, path: "/a", note: "",
    get tabPaths() { return this.tabs.length ? this.tabs.map((p, i) => i === this.tabIndex ? this.path : p) : [this.path]; },
    open(p) { this.path = p; },
    hide() { this.hidden = true; }
};
"""
TABS = [
    js_func(SERVICE, n)
    for n in (
        "newTab",
        "switchTab",
        "closeTab",
        "reopenClosedTab",
        "moveTab",
        "duplicateTab",
        "closeOtherTabs",
        "closeTabsToRight",
    )
]


def tabs_js(
    setup,
    call,
    result="({tabs:root.tabs,index:root.tabIndex,path:root.path,closed:root.closedTabs,note:root.note})",
):
    return run_js(TABS, TABS_PRELUDE + setup, result, call)


# ---- tab management: the last tab is reachable, and tabs can be reordered ----------


@node_mark
def test_switch_tab_reaches_every_tab_and_restores_live_paths():
    # Files.tabs holds every tab (the current one's slot carries the live path
    # through tabPaths); switching to the last chip must actually open it
    out = tabs_js(
        'root.tabs = ["/a", "/b"]; root.tabIndex = 0; root.path = "/a";',
        "root.switchTab(1);",
    )
    assert out["path"] == "/b" and out["index"] == 1 and out["tabs"] == ["/a", "/b"]


@node_mark
def test_tab_drag_keeps_the_folder_on_screen_and_fixes_the_index():
    out = tabs_js(
        'root.tabs = ["/a", "/b", "/c", "/d"]; root.tabIndex = 1; root.path = "/b";',
        "const ok = root.moveTab(0, 2);",
        "({ok:ok, tabs:root.tabPaths, index:root.tabIndex, path:root.path})",
    )
    assert out["ok"] is True
    assert out["tabs"] == ["/b", "/c", "/a", "/d"]
    assert out["index"] == 0 and out["path"] == "/b"
    # moving a *different* tab before the current one must not change the folder
    out = tabs_js(
        'root.tabs = ["/a", "/b", "/c"]; root.tabIndex = 0; root.path = "/a";',
        "root.moveTab(2, 0);",
        "({tabs:root.tabPaths, index:root.tabIndex, path:root.path})",
    )
    assert (
        out["tabs"] == ["/c", "/a", "/b"] and out["index"] == 1 and out["path"] == "/a"
    )
    assert tabs_js("", "const bad = root.moveTab(0, 0);", "bad") is False


@node_mark
def test_tab_context_actions_duplicate_close_others_and_close_to_right():
    out = tabs_js(
        'root.tabs = ["/a", "/b", "/c"]; root.tabIndex = 0; root.path = "/a";',
        "root.duplicateTab(0);",
        "({tabs:root.tabPaths, index:root.tabIndex, path:root.path})",
    )
    assert out == {"tabs": ["/a", "/a", "/b", "/c"], "index": 1, "path": "/a"}
    out = tabs_js(
        'root.tabs = ["/a", "/b", "/c"]; root.tabIndex = 0; root.path = "/a";',
        "root.closeOtherTabs(2);",
    )
    assert out["tabs"] == [] and out["index"] == 0 and out["path"] == "/c"
    out = tabs_js(
        'root.tabs = ["/a", "/b", "/c", "/d"]; root.tabIndex = 3; root.path = "/d";',
        "root.closeTabsToRight(1);",
    )
    assert out["tabs"] == ["/a", "/b"] and out["index"] == 1 and out["path"] == "/b"


@node_mark
def test_closed_tabs_are_restored_newest_first_and_capped():
    out = tabs_js(
        'root.tabs = ["/a", "/b"]; root.tabIndex = 0; root.path = "/a";',
        "root.closeTab(1); root.reopenClosedTab();",
        "({tabs:root.tabPaths, index:root.tabIndex, path:root.path, closed:root.closedTabs})",
    )
    assert out["path"] == "/b" and out["closed"] == []
    out = tabs_js(
        'root.tabs = ["/a", "/b"]; root.tabIndex = 0; root.path = "/a";',
        "root.closeTab(0);",
        "root.closedTabs",
    )
    assert out == ["/a"]
    out = tabs_js(
        'root.tabs = ["/a", "/b"]; root.tabIndex = 0; root.path = "/a"; root.closedTabs = Array.from({length:12}, (_, i) => "/old" + i);',
        "root.closeTab(0);",
        "root.closedTabs",
    )
    assert len(out) == 10 and out[0] == "/old3" and out[-1] == "/a"
    out = tabs_js("", "root.reopenClosedTab();", "root.note")
    assert "closed tabs" in out


# ---- selection, split panes and bookmarks ------------------------------------------


@node_mark
def test_select_by_type_groups_by_extension_and_folder_flag():
    src = js_func(SERVICE, "selectByType")
    prelude = """
const root = {
    current: "/d/a.jpg", selected: ["/d/a.jpg"],
    paths: ["/d/a.jpg", "/d/b.JPG", "/d/c.png", "/d/Folder", "/d/nodot"],
    entries: {
        "/d/a.jpg": {name:"a.jpg", isDir:false}, "/d/b.JPG": {name:"b.JPG", isDir:false},
        "/d/c.png": {name:"c.png", isDir:false}, "/d/Folder": {name:"Folder", isDir:true},
        "/d/nodot": {name:"nodot", isDir:false}
    },
    entryFor(p) { return this.entries[p] || null; },
    entryPaths() { return this.paths; }
};
"""
    out = run_js([src], prelude, "({n:root.selectByType(), selected:root.selected})")
    assert out["n"] == 2 and out["selected"] == ["/d/a.jpg", "/d/b.JPG"]
    out = run_js(
        [src],
        prelude + 'root.current = "/d/c.png";',
        "({n:root.selectByType(), selected:root.selected})",
    )
    assert out["selected"] == ["/d/c.png"]
    out = run_js(
        [src],
        prelude + 'root.current = "/d/none"; root.selected = ["/d/Folder"];',
        "root.selectByType()",
    )
    assert out == 1
    out = run_js(
        [src],
        prelude + 'root.current = "/d/missing"; root.selected = [];',
        "root.selectByType()",
    )
    assert out == 0


@node_mark
def test_swap_split_exchanges_folders_and_selections():
    src = js_func(SERVICE, "swapSplit")
    prelude = """
const root = {
    path: "/one", splitActive: true, splitPath: "/two",
    selected: ["/one/a"], splitSelected: ["/two/b"], opened: [],
    open(p) { this.path = p; this.selected = []; this.opened.push(p); }
};
"""
    out = run_js(
        [src],
        prelude,
        "({path:root.path, split:root.splitPath, selected:root.selected, splitSelected:root.splitSelected, opened:root.opened})",
        "root.swapSplit();",
    )
    assert out == {
        "path": "/two",
        "split": "/one",
        "selected": ["/two/b"],
        "splitSelected": ["/one/a"],
        "opened": ["/two"],
    }
    assert (
        run_js([src], prelude + "root.splitActive = false;", "root.swapSplit()")
        is False
    )


def test_bookmark_shortcut_and_split_controls_are_wired():
    for line in (
        "function toggleBookmark(p) {",
        'root.note = on ? Tr.t("Added to the sidebar") : Tr.t("Removed from the sidebar");',
        "function swapSplit() {",
        "root.splitSelected = root.selected.slice();",
    ):
        assert line in SERVICE
    for line in (
        "if (control && !alt && event.key === Qt.Key_D) {",
        "Files.toggleBookmark();",
        'label: Files.isBookmarked(Files.path) ? Tr.t("Remove bookmark") : Tr.t("Bookmark this folder")',
        'tip: Tr.t("Swap panes")',
        "onClicked: Files.swapSplit()",
        "win.openInSplit(e.path)",
    ):
        assert line in PANEL


# ---- tab UI: drag, middle click, context menu, path menu ----------------------------


def test_tab_chips_are_draggable_and_have_accessible_names():
    for line in (
        'Drag.mimeData: ({ "text/x-shani-tab": String(tabChip.index) })',
        'keys: ["text/x-shani-tab"]',
        'd.getData("text/x-shani-tab")',
        "Files.moveTab(from, tabChip.index)",
        "acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton",
        "win.openTabMenu(tabChip.index, tabArea.mapToItem(win, mouse.x, mouse.y))",
        'Accessible.name: Tr.t("Tab %1: %2"',
    ):
        assert line in PANEL
    for line in (
        "function openTabMenu(i, point)",
        "function openPathMenu(path, point)",
        "Files.duplicateTab(i)",
        "Files.closeOtherTabs(i)",
        "Files.closeTabsToRight(i)",
    ):
        assert line in PANEL


def test_breadcrumb_right_click_offers_tab_split_path_and_bookmark():
    menu = PANEL.split("if (e.pathMenu) {", 1)[1].split("if (e.background) {", 1)[0]
    for line in (
        "Files.newTab(p)",
        "win.openInSplit(p)",
        "Files.copyPath(p)",
        "Files.toggleBookmark(p)",
    ):
        assert line in menu
    assert "acceptedButtons: Qt.LeftButton | Qt.RightButton" in PANEL
    assert "win.openPathMenu(modelData.path, mapToItem(win, mouse.x, mouse.y))" in PANEL


def test_shortcuts_sheet_is_reachable_by_key_and_by_button():
    for line in (
        "Qt.Key_Question",
        "win.toggleShortcuts();",
        'icon: "help-faq"',
        "id: shortcutSheet",
        "visible: win.shortcutsShown",
        "model: win.shortcutRows",
        "Keys.onPressed: event => {",
        "keys.forceActiveFocus();",
    ):
        assert line in PANEL
    assert "Ctrl+Shift+T" in PANEL and "Ctrl+Shift+Y" in PANEL and "Ctrl+1…9" in PANEL


def test_keyboard_bindings_do_not_shadow_each_other():
    keys = qml_block(PANEL, "Keys.onPressed: event =>")
    # the Shift+T restore has to be decided before the plain Ctrl+T new tab
    assert keys.index("Qt.ShiftModifier) && event.key === Qt.Key_T") < keys.index(
        "control && event.key === Qt.Key_T"
    )
    for line in (
        "Files.reopenClosedTab();",
        "Files.selectByType())",
        "Files.switchTab(n);",
        "Files.toggleBookmark();",
    ):
        assert line in keys


# ---- empty/error states, grid captions, AT names ------------------------------------


def test_empty_and_error_states_have_a_useful_next_click():
    empty = PANEL.split("// nothing here", 1)[1].split(
        "Text {\n                            anchors.centerIn: parent", 1
    )[0]
    for line in (
        'title: dir.error !== "" ? Tr.t("This folder could not be opened")',
        'actionText: dir.error !== "" ? Tr.t("Retry")',
        'if (dir.error !== "") dir.reload();',
        'win.applyCategory("all")',
        "win.openNewFolder();",
        "Accessible.name: title",
    ):
        assert line in empty
    split = PANEL.split("// split pane files", 1)[1]
    assert 'actionText: splitDir.error !== "" ? Tr.t("Retry") : ""' in split
    assert "onAction: splitDir.reload()" in split


def test_grid_caption_setting_reaches_the_tiles():
    for line in (
        "property string gridCaption:",
        "Settings.data.filesGridCaption = which;",
        "function cycleGridCaption()",
        'label: Tr.t("Grid captions: %1", Files.gridCaption)',
        'visible: Files.gridCaption !== "off"',
        "Files.formatTime(cell.modelData.mtime)",
        "Files.humanSize(cell.modelData.size)",
    ):
        assert line in PANEL + SERVICE


def test_new_controls_have_accessible_names():
    for line in (
        'label: Files.splitActive ? Tr.t("Close split view") : Tr.t("Split view")',
        'Accessible.name: Tr.t("Swap panes")',
        # in the toolbar's More menu: each row is named by its label (KeyFocus name)
        'Tr.t("Bookmark this folder"), icon:',
        'label: Tr.t("Keyboard shortcuts"), icon: "help-faq"',
    ):
        assert line in PANEL
