"""The global Shortcut centre upgrade (Settings > Keyboard shortcuts): search
across the niri binds and the custom binds, category filters, preview cards,
the reassign confirm, favourites, per-binding parameters, recently used,
export as text/JSON and the empty states.

The centre is QML with its data model on Settings.data.customBinds, so the
source is read as text and the pure helpers are lifted out and executed in
node, like the sibling passes do (test_large_launcher_search_fixes.py,
test_large_software_center_fixes.py).
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PAGE = (ROOT / "shani/Modules/Settings/SettingsShortcuts.qml").read_text(
    encoding="utf-8"
)
INPUT = (ROOT / "shani/Services/InputConfig.qml").read_text(encoding="utf-8")
SETTINGS = (ROOT / "shani/Common/Settings.qml").read_text(encoding="utf-8")

NODE = shutil.which("node") or shutil.which("nodejs")
node_mark = pytest.mark.skipif(NODE is None, reason="node is not installed")


# ---- helpers -------------------------------------------------------------------------
def js_func(src, name):
    """One whole function declaration, braces balanced, ready for node."""
    m = re.search(rf"(?m)^[ \t]*function {re.escape(name)}\(", src)
    assert m, "no function " + name
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


def run_js(prog):
    r = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def sorted_expr():
    """The readonly property `sortedBinds` initialiser, as an expression."""
    m = re.search(
        r"readonly property var sortedBinds:\s*(.*?)\n(?=    function )",
        PAGE,
        re.DOTALL,
    )
    assert m, "sortedBinds missing"
    return m.group(1)


# --------------------------------------------------------------------------
# 1. search across the niri binds AND the custom binds (the centre's grep)
# --------------------------------------------------------------------------
def test_search_covers_niri_and_custom_binds():
    assert "readonly property string filterQ" in PAGE
    assert "function searchMatches(" in PAGE
    assert "page.searchMatches(b)" in PAGE  # the niri list is filtered by it
    assert (
        "[b.title, b.key, b.command, b.param]" in PAGE
    )  # custom binds search title/key/command/param
    assert "model: page.filtered" in PAGE


@node_mark
def test_search_matches_in_node():
    out = run_js(
        "const page = { filterQ: 'file' };\n"
        + js_func(PAGE, "searchMatches")
        + "process.stdout.write(JSON.stringify({"
        "files: searchMatches({title: 'Files'}), "
        "key: searchMatches({key: 'Mod+X'}), "
        "cmd: searchMatches({key: 'Mod+X', command: 'a file picker'}), "
        "none: searchMatches({key: 'Mod+Y', command: 'grep'}), "
        "empty: (page.filterQ = '', searchMatches({key: 'Anything'})) }));"
    )
    assert out == {
        "files": True,
        "key": False,
        "cmd": True,
        "none": False,
        "empty": True,
    }


# --------------------------------------------------------------------------
# 2. category filters
# --------------------------------------------------------------------------
def test_category_filters_present():
    assert "function categoryOf(" in PAGE
    assert "readonly property var cats" in PAGE
    assert 'property string cat: "all"' in PAGE
    assert "page.categoryOf(b.title) === page.cat" in PAGE  # filtered by category
    assert "onClicked: page.cat = modelData" in PAGE  # chips select the category
    assert "page.binds.length > 0" in PAGE  # the row of chips shows once binds exist


@node_mark
def test_category_of_in_node():
    out = run_js(
        "const Tr = { t: s => s };\n"
        + js_func(PAGE, "categoryOf")
        + "process.stdout.write(JSON.stringify(["
        "categoryOf('Files'), categoryOf('Terminal'), categoryOf('Minimise'), "
        "categoryOf('Show the desktop'), categoryOf('Ring (pie menu)'), categoryOf('Clipboard history')]));"
    )
    assert out == ["Apps", "Apps", "Windows", "Windows", "Tools", "Tools"]


# --------------------------------------------------------------------------
# 3. preview cards: key + title + command preview; sorted binds = favourites,
#    then recently used
# --------------------------------------------------------------------------
def test_preview_cards_present():
    assert "page.commandOf(modelData)" in PAGE  # command is shown in the row
    assert "readonly property var sortedBinds" in PAGE
    assert (
        "Number(b.fav)" in PAGE and "Number(a.lastUsed || 0)" in PAGE
    )  # fav then recently used
    assert "function commandOf(" in PAGE


@node_mark
def test_command_of_and_sorted_binds_in_node():
    f = js_func(PAGE, "commandOf")
    out = run_js(
        f + "process.stdout.write(JSON.stringify(["
        "commandOf({command: 'foot', param: 'home'}), commandOf({command: 'foot'}), commandOf({command: '', param: 'x'})]));"
    )
    assert out == ["foot home", "foot", "x"]

    out = run_js(
        "const d = { customBinds: [{key: 'Mod+J', title: 'Files', fav: false, lastUsed: 100},"
        " {key: 'Mod+F', title: 'Files', fav: true, lastUsed: 200}, {key: 'Mod+T', title: 'Terminal', fav: true, lastUsed: 50}]};\n"
        "const sortedBinds = " + sorted_expr() + ";\n"
        "process.stdout.write(JSON.stringify(sortedBinds.map(b => b.key)));"
    )
    assert out == ["Mod+F", "Mod+T", "Mod+J"]


# --------------------------------------------------------------------------
# 4. the reassign confirm
# --------------------------------------------------------------------------
def test_reassign_confirm_present():
    for needle in [
        "function startReassign(",
        "function onCaptured(",
        "page.pendingReassign = { title",
        'Tr.t("Move it from %1 to %2?")',
        "function confirmReassign(",
        "function cancelReassign(",
        "takenBy(combo, reassignTarget)",  # the target's own key is not a conflict
    ]:
        assert needle in PAGE, needle
    assert (
        "page.reassigningTarget ? Tr.t" in PAGE
    )  # the capture rect names the bind being moved


# --------------------------------------------------------------------------
# 5. favourites
# --------------------------------------------------------------------------
def test_favourites_present():
    assert "function favToggle(" in PAGE
    assert 'icon: modelData.fav ? "starred" : "star"' in PAGE
    assert 'Tr.t("Add to your favourites")' in PAGE


# --------------------------------------------------------------------------
# 6. per-binding parameter
# --------------------------------------------------------------------------
def test_per_binding_param_present():
    assert "id: paramArg" in PAGE
    assert 'Tr.t("Optional parameter, appended to the command")' in PAGE
    assert 'param: paramArg.text !== "" ? paramArg.text : ""' in PAGE
    # the centre writes the parameter into the command niri binds:
    assert (
        'JSON.stringify(b.command + (b.param ? " " + String(b.param).trim() : ""))'
        in INPUT
    )


# --------------------------------------------------------------------------
# 7. recently used
# --------------------------------------------------------------------------
def test_recently_used_present():
    assert "function setLastUsed(" in PAGE
    assert "Date.now()" in PAGE
    assert "function runNow(" in PAGE
    assert "running: !!toRun" in PAGE
    assert 'Tr.t("Run now")' in PAGE


# --------------------------------------------------------------------------
# 8. export as text / JSON
# --------------------------------------------------------------------------
def test_export_present():
    assert "function exportText(" in PAGE
    assert "function exportJson(" in PAGE
    assert "Quickshell.clipboardText" in PAGE
    assert 'Tr.t("Copy all as text")' in PAGE
    assert 'Tr.t("Copy all as JSON")' in PAGE
    assert "page.exported" in PAGE


# --------------------------------------------------------------------------
# 9. AT names on the new elements
# --------------------------------------------------------------------------
def test_at_names_present():
    for needle in [
        "Accessible.name: page.exported",  # export status
        "Accessible.name: page.reassigningTarget",  # the reassign capture rect
        'Accessible.name: Tr.t("No binds found in your niri config yet")',
        'Accessible.name: Tr.t("No shortcuts match that search")',
        'Accessible.name: Tr.t("No shortcuts yet - press a combo below")',
        'tip: modelData.fav ? Tr.t("Remove from your favourites") : Tr.t("Add to your favourites")',
        'Tr.t("Reassign")',
        'Tr.t("Remove it")',
    ]:
        assert needle in PAGE, needle


# --------------------------------------------------------------------------
# 10. the empty states
# --------------------------------------------------------------------------
def test_empty_states_present():
    assert 'Tr.t("No binds found in your niri config yet")' in PAGE
    assert 'Tr.t("No shortcuts match that search")' in PAGE
    assert 'Tr.t("No shortcuts yet - press a combo below")' in PAGE


# --------------------------------------------------------------------------
# 11. the data model grew the fields the centre uses (Settings.customBinds)
# --------------------------------------------------------------------------
def test_custom_binds_model_fields():
    assert "property var customBinds: []" in SETTINGS
    assert 'param: "", fav: false, lastUsed: 0' in SETTINGS


# --------------------------------------------------------------------------
# 12. every function on the page parses (node)
# --------------------------------------------------------------------------
@node_mark
def test_all_page_functions_parse():
    names = re.findall(r"function\s+(\w+)\s*\(", PAGE)
    funcs = [js_func(PAGE, n) for n in names]
    prog = "\n".join(funcs)
    r = subprocess.run([NODE, "-e", prog], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr + prog[:400]
