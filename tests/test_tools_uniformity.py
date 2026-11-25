"""One tool catalog, six surfaces: uniformity guards for Common/Tools.js.

Static checks pin that every surface imports and reads the catalog rather than
spelling its own labels, icons, flags or order. The pure logic is executed in
node: Tools.js is plain JS, and each surface's own derivation expression is
lifted out of its source and run against the same catalog, so a drift in any one
surface fails the comparison instead of silently shipping.

The surfaces need a running shell to render, so nothing here starts the shell.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent

CATALOG = "shani/Common/Tools.js"
LAUNCHER = "shani/Modules/Launcher/LauncherActions.qml"
WINDOWMENU = "shani/Modules/WindowMenu/WindowMenu.qml"
DOCK = "shani/Modules/Dock/Dock.qml"
SIDEBAR = "shani/Modules/ControlCenter/SidebarTiles.qml"
SETTINGS = "shani/Modules/Settings/SettingsIndex.js"
QUICK = "shani/Modules/QuickPanel/QuickPanel.qml"

SURFACES = [LAUNCHER, WINDOWMENU, DOCK, SIDEBAR, SETTINGS, QUICK]
QML_IMPORT = 'import "../../Common/Tools.js" as Tools'
JS_IMPORT = '.import "../../Common/Tools.js" as Tools'

NODE = shutil.which("node") or shutil.which("nodejs")
node_mark = pytest.mark.skipif(NODE is None, reason="node is needed for the JS logic")


def src(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def node_json(program):
    r = subprocess.run(
        [NODE, "-e", program], capture_output=True, text=True, timeout=20
    )
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout.strip().splitlines()[-1])


def catalog():
    """Execute the real catalog in node and return its rows."""
    return node_json(src(CATALOG) + "\nprocess.stdout.write(JSON.stringify(list));\n")


def balanced(text, start, open_ch, close_ch):
    """Source from start through the matching closing bracket."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_ch:
            depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    raise AssertionError(
        "unbalanced %s%s after %r" % (open_ch, close_ch, text[start : start + 40])
    )


def map_expr(rel, marker):
    """The `Tools.list...map(...)` call a surface derives its rows from."""
    text = src(rel)
    start = text.index(marker)
    start = text.index("Tools.list", start)
    open_at = text.index(".map(", start) + len(".map") - 1
    return text[start : balanced_index(text, open_at, "(", ")")]


def balanced_index(text, start, open_ch, close_ch):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_ch:
            depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0:
                return i + 1
    raise AssertionError("unbalanced brackets")


def eval_rows(expr, extra=""):
    """Run a surface's own derivation against the catalog in node."""
    program = (
        "var Tools = { list: " + json.dumps(catalog()) + " };\n"
        "var Tr = { t: s => s };\n"
        "var toolRuns = {};\n"
        "var Ui = { closeAll: function () {} };\n"
        + extra
        + "process.stdout.write(JSON.stringify("
        + expr
        + "));\n"
    )
    return node_json(program)


# ---- static: every surface reads the one catalog ------------------------------


@pytest.mark.parametrize("rel", SURFACES)
def test_surface_imports_the_catalog(rel):
    expected = JS_IMPORT if rel == SETTINGS else QML_IMPORT
    assert expected in src(rel), rel


def test_surfaces_derive_rows_instead_of_hand_copying():
    launcher = src(LAUNCHER)
    assert "...Tools.list.map(t => ({" in launcher
    for needle in (
        "title: Tr.t(t.label)",
        "words: t.words",
        "icon: t.icon",
        "run: () => Ui.openTool(t.flag)",
    ):
        assert needle in launcher, needle

    menu = src(WINDOWMENU)
    assert "readonly property var tools: Tools.list.map(t => ({" in menu
    for needle in (
        "tool: true",
        "label: Tr.t(t.label)",
        "icon: t.icon",
        "run: () => Ui.openTool(t.flag)",
    ):
        assert needle in menu, needle

    dock = src(DOCK)
    assert (
        "readonly property var tools: Tools.list.map(t => ({ label: t.label, run: () => Ui.openTool(t.flag) }))"
        in dock
    )

    sidebar = src(SIDEBAR)
    assert "...Tools.list.map(t => t.flag)" in sidebar  # tile order
    assert "model: Tools.list" in sidebar
    for needle in (
        "tid: modelData.flag",
        "icon: modelData.icon",
        "title: Tr.t(modelData.label)",
        "Ui.openTool(modelData.flag)",
    ):
        assert needle in sidebar, needle

    quick = src(QUICK)
    assert "Tools.list.slice(0, 4)" in quick
    for needle in ("label: Tr.t(t.label)", "icon: t.icon", "run: () => Ui.openTool(t.flag)"):
        assert needle in quick, needle

    settings = src(SETTINGS)
    assert "...Tools.list.filter(t => !t.settings).map(t => {" in settings
    for needle in (
        "label: t.label",
        "link: t.op",
        'words: t.words.replace(/^tool /, "")',
    ):
        assert needle in settings, needle


def test_no_surface_spells_a_catalog_label_itself():
    for rel in SURFACES:
        body = src(rel)
        # a tool that is a Settings page is named by that page, which Settings spells
        for label in (row["label"] for row in catalog() if not row.get("settings")):
            assert 'Tr.t("%s")' % label not in body, (rel, label)
            assert 'label: "%s"' % label not in body, (rel, label)


# ---- pure logic: the catalog and every derived view agree ---------------------


@node_mark
def test_catalog_has_nine_coherent_rows():
    rows = catalog()
    assert len(rows) == 9
    for field in ("label", "icon", "flag", "op", "words"):
        values = [r[field] for r in rows]
        assert len(set(values)) == len(values), field
    for r in rows:
        assert r["words"].startswith("tool "), r
        assert r["op"] == r["flag"] + "Open", r


@node_mark
def test_launcher_menu_and_dock_agree_with_the_catalog():
    full = catalog()
    launcher = eval_rows(map_expr(LAUNCHER, "...Tools.list.map"))
    menu = eval_rows(map_expr(WINDOWMENU, "readonly property var tools:"))
    dock = eval_rows(map_expr(DOCK, "readonly property var tools:"))
    assert [r["title"] for r in launcher] == [r["label"] for r in full]
    assert [r["words"] for r in launcher] == [r["words"] for r in full]
    assert [r["icon"] for r in launcher] == [r["icon"] for r in full]
    assert [r["label"] for r in menu] == [r["label"] for r in full]
    assert [r["icon"] for r in menu] == [r["icon"] for r in full]
    assert [r["label"] for r in dock] == [r["label"] for r in full]


@node_mark
def test_quick_panel_uses_only_the_first_four():
    assert [
        r["label"] for r in eval_rows(map_expr(QUICK, "Tools.list.slice(0, 4)"))
    ] == [r["label"] for r in catalog()[:4]]


@node_mark
def test_sidebar_tile_order_and_delegate_agree_with_the_catalog():
    full = catalog()
    text = src(SIDEBAR)
    bracket = text.index("[", text.index("readonly property var known:"))
    known = eval_rows(balanced(text[bracket:], 0, "[", "]"))
    assert known[-len(full) :] == [r["flag"] for r in full]

    body = src(SIDEBAR)
    delegate = body[body.index("delegate: Tile {") :]
    get = lambda key: (
        re.search(r"\b" + key + r":\s*([^\n]+)", delegate).group(1).strip()
    )
    extra = "var tileGrid = { toolSubtitles: {} };\n"
    rows = eval_rows(
        "Tools.list.map(function (modelData) { return { tid: "
        + get("tid")
        + ", icon: "
        + get("icon")
        + ", title: "
        + get("title")
        + " }; })",
        extra,
    )
    assert [r["tid"] for r in rows] == [r["flag"] for r in full]
    assert [r["icon"] for r in rows] == [r["icon"] for r in full]
    assert [r["title"] for r in rows] == [r["label"] for r in full]


@node_mark
def test_settings_deep_links_agree_with_the_catalog():
    settings = src(SETTINGS)
    meta = re.search(r"var toolMeta = (\{.*?\});", settings, re.S).group(1)
    rows = eval_rows(
        map_expr(SETTINGS, "...Tools.list.filter(t => !t.settings).map"), "var toolMeta = " + meta + ";\n"
    )
    # tools that are Settings pages have their own literal rows (startupApps, automations)
    full = [r for r in catalog() if not r.get("settings")]
    assert [r["label"] for r in rows] == [r["label"] for r in full]
    assert [r["link"] for r in rows] == [r["op"] for r in full]
    assert [r["words"].split() for r in rows] == [r["words"][5:].split() for r in full]
    assert len({r["key"] for r in rows}) == len(full) == 7
