"""Sectioned Speed Dial (libcprime PinManage / corebox Speed Dial).

Two layers, both checked here:

* static shape - the singleton persists a JSON document under Quickshell's
  state path, the service opens folders in the shell's file manager and files
  with xdg-open, and the Files sidebar shows a Speed Dial section built from
  Common widgets;
* the real rules - shani/Services/SpeedDial.js is plain JS, so canonical-path
  dedupe, caps, ordering and every CRUD operation run in node, the way
  tests/test_sessions_service.py runs its rules, without a QuickShell runtime.

GTK bookmarks in Services/Files.qml are deliberately not used: they are flat,
owned by GTK apps and have neither names nor sections.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SERVICE = ROOT / "shani/Services/SpeedDial.qml"
LOGIC = ROOT / "shani/Services/SpeedDial.js"
PANEL = ROOT / "shani/Modules/Files/SpeedDialPanel.qml"
FILES_PANEL = ROOT / "shani/Modules/Files/FilesPanel.qml"
FILES_SERVICE = ROOT / "shani/Services/Files.qml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def call(expr):
    prog = (
        LOGIC.read_text(encoding="utf-8").replace(".pragma library", "")
        + "\nprocess.stdout.write(JSON.stringify(%s));" % expr
    )
    got = subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True)
    return json.loads(got.stdout)


def seed():
    return call("seed(null)")


# ---- static shape ----------------------------------------------------------


def test_service_and_logic_exist():
    assert SERVICE.exists() and LOGIC.exists()
    q = read(SERVICE)
    assert "pragma Singleton" in q
    assert 'import "SpeedDial.js" as Logic' in q
    assert "import Quickshell.Io" in q


def test_service_persists_json_in_quickshell_state():
    q = read(SERVICE)
    assert 'Quickshell.statePath("speed-dial.json")' in q
    assert "onLoaded:" in q and "Logic.seed(JSON.parse(text())" in q
    assert "store.setText(JSON.stringify(next))" in q
    assert "printErrors: false" in q


def test_service_exposes_the_crud_api():
    q = read(SERVICE)
    for fn in [
        "function clearError()",
        "function sections()",
        "function entries(",
        "function addSection(",
        "function renameSection(",
        "function removeSection(",
        "function addEntry(",
        "function removeEntry(",
        "function renameEntry(",
        "function canonical(",
        "function open(",
    ]:
        assert fn in q, fn
    assert "property var data: ({ sections: [] })" in q
    assert 'property string error: ""' in q
    assert "Date.now()" in q  # the pin timestamp
    assert "Already in %1 as %2" in q  # a duplicate path says where it is
    assert 'Tr.t("Type a path")' in q
    assert 'Tr.t("No section called %1", section)' in q


def test_open_uses_existing_apis_and_clears_the_error():
    q = read(SERVICE)
    assert "Files.show(p)" in q
    assert "xdg-open" in q
    assert '[ -d "$1" ]' in q  # a flat shortcut does not say dir or file
    assert 'root.error = ""' in q


def test_panel_uses_common_widgets_and_has_a11y():
    q = read(PANEL)
    for widget in [
        "SectionTitle",
        "ListRow",
        "TextField",
        "IconButton",
        "Button",
        "Text",
    ]:
        assert widget in q, widget
    assert "import qs.Common" in q and "import qs.Services" in q
    assert 'objectName: "region:speedDial"' in q
    assert "Tr.t(" in q and "Theme." in q
    assert "SpeedDial.open(" in q and "SpeedDial.error" in q
    # no opaque cards: rows and headers are the shared ListRow / SectionTitle
    assert "Rectangle {" not in q and "color: Theme.surface" not in q


def test_panel_has_both_add_flows_and_confirmations():
    q = read(PANEL)
    assert 'openForm("section"' in q
    assert 'openForm("entry"' in q
    assert 'openForm("rename-entry"' in q
    assert "SpeedDial.addSection(" in q and "SpeedDial.addEntry(" in q
    assert "SpeedDial.removeSection(" in q and "SpeedDial.removeEntry(" in q
    assert "SpeedDial.renameSection(" in q and "SpeedDial.renameEntry(" in q
    assert "function asking(" in q and "confirmTimer" in q
    assert "Accessible" in q or "tip:" in q


def test_files_sidebar_shows_the_panel_but_gtk_bookmarks_stay():
    q = read(FILES_PANEL)
    assert "SpeedDialPanel { Layout.fillWidth: true }" in q
    f = read(FILES_SERVICE)
    assert "bookmark-add" in f and "bookmark-remove" in f
    assert "SpeedDial" not in f  # no duplicate model in Files


# ---- names and canonical paths ---------------------------------------------


def test_names_are_trimmed_bounded_and_safe():
    assert call('cleanName("  Work  ")') == "Work"
    assert call('cleanName("")') == ""
    assert call("cleanName(%s)" % json.dumps("a" * 60)) == "a" * 60
    assert call("cleanName(%s)" % json.dumps("a" * 61)) == ""
    for bad in [
        "one/two",
        "one\\two",
        "..",
        "a\nb",
        "a\u0000b",
        "__proto__",
        "constructor",
    ]:
        assert call("cleanName(%s)" % json.dumps(bad)) == "", bad


def test_paths_are_canonicalised_before_dedupe():
    assert call('canonical("/a/./b/../c//")') == "/a/c"
    assert call('canonical("/a/b/", "/home/u")') == "/a/b"
    assert call('canonical("~/Docs/x", "/home/u")') == "/home/u/Docs/x"
    assert call('canonical("relative/../x")') == "x"
    assert call('canonical("")') == ""
    assert call('canonical("~/x")') == ""  # no home to expand into


# ---- loading a hand-edited JSON file ---------------------------------------


def test_empty_file_seeds_the_default_section():
    assert seed() == {"sections": [{"name": "Speed Dial", "entries": []}]}
    assert call("seed(null)") == seed()
    assert call("normalise([])") == {"sections": []}


def test_bad_sections_and_entries_are_dropped_not_fatal():
    raw = {
        "sections": [
            {
                "name": "Work",
                "entries": [
                    {"name": "Docs", "path": "/home/u/docs", "pinnedAt": 200},
                    {"name": "no path", "path": "", "pinnedAt": 300},
                    {"name": "bad/name", "path": "/x", "pinnedAt": 300},
                    "not an object",
                ],
            },
            {"name": "bad/section", "entries": []},
            {
                "name": "work",
                "entries": [{"name": "Other", "path": "/z", "pinnedAt": 1}],
            },
            "broken",
        ]
    }
    got = call("normalise(%s, '/home/u')" % json.dumps(raw))
    assert got == {
        "sections": [
            {
                "name": "Work",
                "entries": [
                    {"name": "Docs", "path": "/home/u/docs", "pinnedAt": 200},
                ],
            }
        ]
    }


def test_caps_keep_the_file_small():
    data = seed()
    for i in range(30):
        next_data = call(
            "addSection(%s, %s)" % (json.dumps(data), json.dumps("S%d" % i))
        )
        if next_data is not None:
            data = next_data
    assert len(call("sections(%s)" % json.dumps(data))) == 12

    data = seed()
    for i in range(60):
        next_data = call(
            "addEntry(%s, 'Speed Dial', %s, %s, %d, '/home/u')"
            % (
                json.dumps(data),
                json.dumps("e%d" % i),
                json.dumps("/home/u/e%d" % i),
                i,
            )
        )
        if next_data is not None:
            data = next_data
    assert len(call("entries(%s, 'Speed Dial')" % json.dumps(data))) == 40


# ---- section CRUD -----------------------------------------------------------


def test_sections_add_rename_remove():
    data = seed()
    data = call('addSection(%s, "Work")' % json.dumps(data))
    assert [s["name"] for s in call("sections(%s)" % json.dumps(data))] == [
        "Speed Dial",
        "Work",
    ]
    assert call('addSection(%s, "work")' % json.dumps(data)) is None
    assert call('addSection(%s, "bad/one")' % json.dumps(data)) is None
    data = call('renameSection(%s, "Work", "Personal")' % json.dumps(data))
    assert [s["name"] for s in call("sections(%s)" % json.dumps(data))] == [
        "Speed Dial",
        "Personal",
    ]
    assert (
        call('renameSection(%s, "Personal", "Speed Dial")' % json.dumps(data)) is None
    )
    data = call('removeSection(%s, "Personal")' % json.dumps(data))
    assert [s["name"] for s in call("sections(%s)" % json.dumps(data))] == [
        "Speed Dial"
    ]
    assert call('removeSection(%s, "missing")' % json.dumps(data)) is None


def test_removing_a_section_removes_its_entries():
    data = call('addEntry(%s, "Speed Dial", "a", "/a", 1, "")' % json.dumps(seed()))
    data = call('addSection(%s, "Work")' % json.dumps(data))
    data = call('removeSection(%s, "Speed Dial")' % json.dumps(data))
    assert call('findPath(%s, "/a")' % json.dumps(data)) is None
    assert [s["name"] for s in call("sections(%s)" % json.dumps(data))] == ["Work"]


# ---- entry CRUD, dedupe and ordering ----------------------------------------


def test_entries_are_newest_first_and_a_rename_keeps_the_pin():
    data = call(
        'addEntry(%s, "Speed Dial", "old", "/old", 100, "")' % json.dumps(seed())
    )
    data = call('addEntry(%s, "Speed Dial", "new", "/new", 300, "")' % json.dumps(data))
    data = call('addEntry(%s, "Speed Dial", "mid", "/mid", 200, "")' % json.dumps(data))
    assert [
        e["name"] for e in call('entries(%s, "Speed Dial")' % json.dumps(data))
    ] == ["new", "mid", "old"]
    data = call('renameEntry(%s, "Speed Dial", "old", "older")' % json.dumps(data))
    got = call('entries(%s, "Speed Dial")' % json.dumps(data))
    assert got[2] == {"name": "older", "path": "/old", "pinnedAt": 100}


def test_a_path_is_pinned_once_across_all_sections():
    data = call('addSection(%s, "Work")' % json.dumps(seed()))
    data = call(
        'addEntry(%s, "Work", "code", "/home/u/code/", 100, "/home/u")'
        % json.dumps(data)
    )
    assert (
        call(
            'addEntry(%s, "Speed Dial", "same", "/home/u/./code", 200, "/home/u")'
            % json.dumps(data)
        )
        is None
    )
    assert call('findPath(%s, "~/code", "/home/u")' % json.dumps(data)) == {
        "section": "Work",
        "name": "code",
    }
    assert call('findPath(%s, "/nowhere")' % json.dumps(data)) is None


def test_names_are_unique_per_section_case_insensitively():
    data = call(
        'addEntry(%s, "Speed Dial", "Docs", "/docs", 1, "")' % json.dumps(seed())
    )
    assert (
        call('addEntry(%s, "Speed Dial", "DOCS", "/other", 2, "")' % json.dumps(data))
        is None
    )
    assert (
        call('renameEntry(%s, "Speed Dial", "Docs", "dOcS")' % json.dumps(data))
        is not None
    )
    data = call(
        'addEntry(%s, "Speed Dial", "Other", "/other", 2, "")' % json.dumps(data)
    )
    assert (
        call('renameEntry(%s, "Speed Dial", "Docs", "Other")' % json.dumps(data))
        is None
    )


def test_unknown_targets_are_refused_and_valid_data_is_stable():
    data = seed()
    assert call('addEntry(%s, "missing", "a", "/a", 1, "")' % json.dumps(data)) is None
    assert call('removeEntry(%s, "Speed Dial", "a")' % json.dumps(data)) is None
    assert call('renameEntry(%s, "Speed Dial", "a", "b")' % json.dumps(data)) is None
    data = call('addEntry(%s, "Speed Dial", "a", "/a", 1, "")' % json.dumps(data))
    assert call("normalise(%s, '/home/u')" % json.dumps(data)) == data
    data = call('removeEntry(%s, "Speed Dial", "a")' % json.dumps(data))
    assert call('entries(%s, "Speed Dial")' % json.dumps(data)) == []
