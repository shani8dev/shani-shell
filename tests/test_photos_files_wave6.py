"""Wave 6 deep pass on Photos and Files.

The QML is not loaded by pytest: static hooks pin the wiring (including the
features earlier passes added), and the small pieces of logic are lifted out of
the QML and really executed in node with stand-ins for `win` / `Files` / `Tr`,
as in test_files_filter_popover.py.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PHOTOS = (ROOT / "shani/Modules/Photos/PhotosWindow.qml").read_text(encoding="utf-8")
PANEL = (ROOT / "shani/Modules/Files/FilesPanel.qml").read_text(encoding="utf-8")

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")


def block(src, name, prefix="function"):
    """One whole function or property block, braces balanced, ready for node."""
    pattern = (
        r"(?m)^[ \t]*function %s\(" % re.escape(name)
        if prefix == "function"
        else r"(?m)^[ \t]*readonly property var %s: \{" % re.escape(name)
    )
    m = re.search(pattern, src)
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
    raise AssertionError("unbalanced " + name)


def run_node(result, funcs, prelude="", statements=""):
    prog = "\n".join(
        [prelude]
        + funcs
        + [statements, "process.stdout.write(JSON.stringify(" + result + "));"]
    )
    r = subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


# ---- static wiring ---------------------------------------------------------


def test_photos_batch_and_sort_hooks_from_earlier_passes_survive():
    for hook in (
        "property var selected: []",
        "function toggleSelect(path)",
        "function clearSelect()",
        "function selectAll()",
        "function trashSelected()",
        "function albumSelected()",
        "Files.trash(paths",
        "Photos.createAlbum(name",
        "Qt.ControlModifier | Qt.ShiftModifier",
        'Tr.t("%1 selected"',
        "Add to album",
        "Move to trash",
        "property bool filmstrip: false",
        "property var smartAlbums: []",
        "id: photosApi",
        "const Photos = photosApi;",
        "Text {",
        'text: Tr.t("Sort")',
        "property var allTags",
        "property var people",
        "property var places",
        "property var duplicatePaths: []",
        "PhotoMeta.details",
        "function tagPeopleSelected()",
    ):
        assert hook in PHOTOS, hook


def test_photos_size_sort_reuses_the_one_existing_scan():
    for hook in (
        'property string sortOrder: "newest"  // newest | oldest | name | size',
        "function comparePhotos(a, b)",
        'win.sortOrder === "size"',
        "shown.slice().sort((a, b) => win.comparePhotos(a, b))",
        '["size", Tr.t("Size")]',
        '-printf "%T@ %s %p\\\\n"',
        "size: size",
        "const size = parseFloat(rest.substring(0, sp));",
    ):
        assert hook in PHOTOS, hook
    # no second scanner: the only find pipeline still ends in sort/head
    assert PHOTOS.count('find "$1" -maxdepth 4') == 1
    assert "sort -rn | head -5000" in PHOTOS


def test_files_breadcrumb_and_prior_agent_features_survive():
    for hook in (
        "Files.open(modelData.path)",
        "win.openPathMenu(modelData.path",
        "id: pathBox",
        "Qt.Key_L",
        "pathBox.forceActiveFocus()",
        "function openCrumbMenu(path, point)",
        "crumbMenuItems = (r.entries || []).filter(e => e.isDir)",
        "Files.selectMatching(matchPattern)",
        "win.applyMatch()",
        "activeFilterCount",
        "filterShown",
        "tabPaths",
        "selectByType()",
        "openNewFolder()",
        "askSymlink(",
    ):
        assert hook in PANEL, hook


def test_split_breadcrumbs_match_the_main_pane():
    # isolate the split path bar: crumbs stay clickable, arrows list siblings,
    # and a right click reaches the shared menu (which has "Copy path")
    split = PANEL.split("// split path breadcrumbs", 1)[1].split(
        "// split pane files", 1
    )[0]
    for hook in (
        "Files.splitPath = modelData.path; splitDir.reload();",
        "acceptedButtons: Qt.LeftButton | Qt.RightButton",
        "win.openPathMenu(modelData.path",
        "win.crumbMenuSplit = true; win.openCrumbMenu(modelData.path",
        'Accessible.name: Tr.t("Folders next to %1").arg(modelData.name)',
        "KeyFocus {",
        "Theme.font",
    ):
        assert hook in split, hook
    for hook in (
        "property bool crumbMenuSplit: false",
        "function openCrumbPath(path)",
        "if (split) { Files.splitPath = path; splitDir.reload(); }",
        "else Files.open(path);",
        "crumbMenuSplit = false;",
        'Tr.t("Copy path")',
    ):
        assert hook in PANEL, hook
    # the shared popup navigates the pane the crumb came from
    popup = PANEL.split("// ---- the breadcrumb sibling list", 1)[1].split(
        "// ---- Select Items Matching", 1
    )[0]
    assert "win.openCrumbPath(modelData.path);" in popup


# ---- pure logic: the sort comparator ---------------------------------------


@node_mark
def test_sort_comparator_orders_time_name_and_size():
    photos = [
        {"path": "/Pictures/b.jpg", "time": 300, "size": 10},
        {"path": "/Pictures/a.jpg", "time": 100, "size": 50},
        {"path": "/Pictures/c.jpg", "time": 200, "size": 30},
        {"path": "/Pictures/no-size.jpg", "time": 400},
    ]
    func = block(PHOTOS, "comparePhotos")
    out = run_node(
        "orders.map(o => { win.sortOrder = o; return "
        "photos.slice().sort(win.comparePhotos).map(p => p.path.split('/').pop()); })",
        [func],
        prelude=(
            "const win = { sortOrder: 'newest' };\n"
            "win.comparePhotos = comparePhotos;\n"
            "const photos = " + json.dumps(photos) + ";\n"
            "const orders = ['newest', 'oldest', 'name', 'size'];"
        ),
    )
    assert out == [
        ["no-size.jpg", "b.jpg", "c.jpg", "a.jpg"],  # newest first, scan order
        ["a.jpg", "c.jpg", "b.jpg", "no-size.jpg"],  # oldest first
        ["a.jpg", "b.jpg", "c.jpg", "no-size.jpg"],  # file name
        ["a.jpg", "c.jpg", "b.jpg", "no-size.jpg"],  # biggest first
    ]


@node_mark
def test_sort_comparator_handles_missing_and_equal_sizes():
    func = block(PHOTOS, "comparePhotos")
    out = run_node(
        "[win.comparePhotos(missing, small), win.comparePhotos(small, big), "
        "win.comparePhotos(big, missing)]",
        [func],
        prelude=(
            "const win = { sortOrder: 'size' };\n"
            "win.comparePhotos = comparePhotos;\n"
            "const missing = { path: '/x.jpg' };\n"
            "const small = { path: '/y.jpg', size: 5 };\n"
            "const big = { path: '/z.jpg', size: 500 };"
        ),
    )
    assert out == [5, 495, -500]  # no size sorts last, never NaN


# ---- pure logic: batch selection and its caps ------------------------------


@node_mark
def test_batch_tagged_paths_and_existing_batch_caps():
    collage_cap = int(re.search(r"paths\.slice\(0, (\d+)\)", PHOTOS).group(1))
    places_cap = int(re.search(r"win\.shown\.slice\(0, (\d+)\)", PHOTOS).group(1))
    assert collage_cap == 40 and places_cap == 400

    tagged = block(PHOTOS, "taggedPaths")
    prelude = (
        "const win = { selected: [], detailPath: '' };\n"
        "win.taggedPaths = taggedPaths;\n"
        "const all = Array.from({length: 60}, (_, i) => '/p/' + i + '.jpg');\n"
        "const shown = Array.from({length: 500}, (_, i) => ({path: '/p/' + i + '.jpg'}));"
    )
    # selection wins over the detail panel; both fall back to empty
    assert run_node(
        "win.taggedPaths()",
        [tagged],
        prelude=prelude + "\nwin.selected = ['/a', '/b'];",
    ) == ["/a", "/b"]
    assert run_node(
        "win.taggedPaths()", [tagged], prelude=prelude + "\nwin.detailPath = '/detail';"
    ) == ["/detail"]
    assert run_node("win.taggedPaths()", [tagged], prelude=prelude) == []

    # the two existing batch operations stay bounded: a collage takes at most
    # 40, the GPS scan at most 400, in their original order
    out = run_node(
        "[win.taggedPaths().slice(0, " + str(collage_cap) + ").length,"
        " win.taggedPaths().slice(0, " + str(collage_cap) + ")[0],"
        " shown.slice(0, " + str(places_cap) + ").length]",
        [tagged],
        prelude=prelude + "\nwin.selected = all;",
    )
    assert out == [40, "/p/0.jpg", 400]


# ---- pure logic: breadcrumb ancestor chains --------------------------------


def crumbs(src, name, prelude):
    body = block(src, name, prefix="property")
    body = re.sub(
        r"readonly property var \w+: ", "function " + name + "() ", body, count=1
    )
    return run_node(name + "()", [body], prelude=prelude)


@node_mark
def test_breadcrumb_ancestor_chain_stays_a_prefix_chain():
    cases = {
        "/": [("/", "/")],
        "/home/user": [("Home", "/home/user")],
        "/home/user/Pictures/2026": [
            ("Home", "/home/user"),
            ("Pictures", "/home/user/Pictures"),
            ("2026", "/home/user/Pictures/2026"),
        ],
        "/var/tmp/x": [
            ("/", "/"),
            ("var", "/var"),
            ("tmp", "/var/tmp"),
            ("x", "/var/tmp/x"),
        ],
    }
    for path, expected in cases.items():
        prelude = (
            "const Files = { path: " + json.dumps(path) + ", home: '/home/user' };"
            " const Tr = { t: s => s };"
        )
        got = crumbs(PANEL, "crumbsModel", prelude)
        assert [(c["name"], c["path"]) for c in got] == expected
        # every crumb is an ancestor of the folder on screen
        assert all(
            path == p or path.startswith(p.rstrip("/") + "/") for _, p in expected
        )


@node_mark
def test_long_breadcrumb_keeps_first_and_last_three():
    prelude = (
        "const Files = { path: '/home/user/a/b/c/d/e', home: '/home/user' };"
        " const Tr = { t: s => s };"
    )
    got = crumbs(PANEL, "crumbsModel", prelude)
    assert [c["name"] for c in got] == ["Home", "c", "d", "e"]
    assert [c["path"] for c in got] == [
        "/home/user",
        "/home/user/a/b/c",
        "/home/user/a/b/c/d",
        "/home/user/a/b/c/d/e",
    ]


@node_mark
def test_split_breadcrumbs_build_the_same_chain():
    prelude = (
        "const Files = { splitPath: '/home/user/Pictures/2026', path: '/', home: '/home/user' };"
        " const Tr = { t: s => s };"
    )
    got = crumbs(PANEL, "splitCrumbsModel", prelude)
    assert [c["path"] for c in got] == [
        "/home/user",
        "/home/user/Pictures",
        "/home/user/Pictures/2026",
    ]
