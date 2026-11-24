"""The "spotlight" launcher upgrade: one coherent set of search fixes.

The launcher and its service are QML singletons/panels, so most checks read the
wiring in source (the pattern in test_launcher_lens_fixes.py). The operator
parser is plain JS, so that one is actually executed through node, exactly as
test_calc_js.py executes Calc.js.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER = (ROOT / "shani/Modules/Launcher/Launcher.qml").read_text(encoding="utf-8")
SERVICE = (ROOT / "shani/Services/LauncherEntries.qml").read_text(encoding="utf-8")
NODE = shutil.which("node") or shutil.which("nodejs")


def block(src, start, end):
    return src.split(start, 1)[1].split(end, 1)[0]


def sections():
    return block(
        LAUNCHER,
        "readonly property var sections: {",
        "\n    readonly property var flat:",
    )


def finish():
    return block(sections(), "const finish = () => {", "\n        };")


# --------------------------------------------------------------------------
# 1. the service: operators and recent searches
# --------------------------------------------------------------------------
def test_service_adds_operators_without_touching_dock_entries():
    # The LauncherEntry API (dock counts/progress) is the service's original job;
    # this upgrade must leave it intact.
    for needle in [
        "property var entries: ({})",
        "property bool ready: false",
        "function of(entry, id)",
        'for (const f of ["count", "countVisible", "progress", "progressVisible", "urgent"])',
        "onExited: {",
        "id: retry; interval: 5000",
    ]:
        assert needle in SERVICE, needle
    assert re.search(
        r'id:\s*"app"[\s\S]*id:\s*"file"[\s\S]*id:\s*"web"[\s\S]*'
        r'id:\s*"clip"[\s\S]*id:\s*"action"',
        SERVICE,
    )


@pytest.mark.skipif(NODE is None, reason="node is not installed")
@pytest.mark.parametrize(
    "raw,expected",
    [
        ("firefox", {"op": "", "text": "firefox", "active": False, "empty": False}),
        ("  firefox  ", {"op": "", "text": "firefox", "active": False, "empty": False}),
        (
            "app:firefox",
            {"op": "app", "text": "firefox", "active": True, "empty": False},
        ),
        (
            "web:  weather today",
            {"op": "web", "text": "weather today", "active": True, "empty": False},
        ),
        ("file:", {"op": "file", "text": "", "active": True, "empty": True}),
        (
            "clip:meeting",
            {"op": "clip", "text": "meeting", "active": True, "empty": False},
        ),
        (":smile", {"op": "", "text": ":smile", "active": False, "empty": False}),
        (
            "https://example.com",
            {"op": "", "text": "https://example.com", "active": False, "empty": False},
        ),
        (
            "c meeting notes",
            {"op": "", "text": "c meeting notes", "active": False, "empty": False},
        ),
        (
            "notanoperator:x",
            {"op": "", "text": "notanoperator:x", "active": False, "empty": False},
        ),
    ],
)
def test_operator_parser_runs_in_js(raw, expected):
    ops = (
        SERVICE.split("readonly property var operators: ", 1)[1].split("\n    ]", 1)[0]
        + "\n    ]"
    )
    fn = block(SERVICE, "function parseQuery(raw) {", "\n    }")
    js = "const operators = " + ops + ";\nfunction parseQuery(raw) {" + fn + "\n    }\n"
    out = subprocess.run(
        [
            NODE,
            "-e",
            js + "console.log(JSON.stringify(parseQuery(" + json.dumps(raw) + ")));\n",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout.strip()) == expected


def test_recent_search_history_is_bounded_and_persisted():
    hist = block(SERVICE, "function remember(raw) {", "\n    FileView {")
    assert "t.length < 2" in hist  # no one-letter queries
    assert "parseQuery(t).active" in hist  # operators are not searches
    assert "slice(0, 12)" in hist
    assert "history.setText(JSON.stringify(h))" in hist
    assert "root.searchHistory[0] === t" in hist  # dedupe consecutive repeats
    for fn in ["function forget(raw) {", "function clearHistory() {"]:
        assert fn in SERVICE
        assert "history.setText(" in block(SERVICE, fn, "\n    }")
    store = block(SERVICE, "FileView {", "\n    }")
    assert 'Quickshell.statePath("launcher-history.json")' in store
    assert "Array.isArray(v)" in store and "catch (e)" in store


# --------------------------------------------------------------------------
# 2. result grouping / operator routing
# --------------------------------------------------------------------------
def test_operators_narrow_the_answer_to_one_group():
    s = sections()
    assert "LauncherEntries.parseQuery(win.q.trim())" in s
    assert 'op === "clip" ? "c " + parsed.text' in s
    assert "out.filter(s => s.group === op)" in s
    # every substantive family is tagged, so a narrow query cannot leak a
    # calculator, web or "Ask Chronoa" fallback into its results
    for group in [
        "app",
        "file",
        "action",
        "clip",
        "calc",
        "event",
        "note",
        "contact",
        "window",
        "provided",
    ]:
        assert 'group: "' + group + '"' in s, group
    assert 'group: "meta"' in s


def test_operator_without_hits_shows_a_state_not_a_fallback():
    f = finish()
    assert "return kept.length ? kept : [win.noResults(parsed.text, op)]" in f
    assert '!out.some(s => s.group && s.group !== "meta")' in f
    assert 'out.unshift(win.noResults(q, ""))' in f
    nores = block(LAUNCHER, "function noResults(text, op) {", "\n    }")
    assert 'title: Tr.t("No results")' in nores
    assert 'kind: "none"' in nores and "run: () => {}" in nores


def test_bare_operator_offers_an_example():
    s = sections()
    # "app:" must not fall through to the app grid before finish() sees it
    assert 'if (q === "") {' in s
    assert "if (op) return [win.operatorHelp(op)];" in s
    help_fn = block(LAUNCHER, "function operatorHelp(op) {", "\n    }")
    for ex in [
        "app:firefox",
        "file:report",
        "web:weather",
        "clip:meeting",
        "action:dark",
    ]:
        assert '"' + ex + '"' in help_fn
    assert 'Tr.t("Example: %1", ex)' in help_fn


def test_web_operator_is_an_engine_picker():
    web = block(LAUNCHER, "function webEngines(text) {", "\n    }")
    assert "Object.keys(Ui.webSearches).map(k =>" in web
    assert "e[1] + encodeURIComponent(t)" in web  # uses the shared engines map
    assert 'group: "web"' in web
    assert 'op === "web"' in finish()
    assert "win.webEngines(parsed.text)" in finish()


def test_web_shortcut_is_discoverable_from_the_default_answer():
    more = block(sections(), 'title: Tr.t("More")', "\n        ] });")
    assert 'Tr.t("Choose a search engine…")' in more
    assert 'search.text = "web:"' in more
    assert "Ui.webSearchUrl(q)" in more  # the default engine stays


# --------------------------------------------------------------------------
# 3. async searches still search the right text
# --------------------------------------------------------------------------
def test_async_searches_use_the_operator_stripped_query():
    deb = block(LAUNCHER, "id: fileDebounce", "\n    }")
    assert "LauncherEntries.parseQuery(win.q.trim())" in deb
    assert 'const scope = !p.active || p.op === "file"' in deb
    assert "if (t.length >= 3 && scope" in deb
    assert 'Bridge.send({ op: "findfiles"' in deb and "query: t" in deb
    assert "fileSearch.query === win.searchText" in LAUNCHER
    assert "contentSearch.query === win.searchText" in LAUNCHER
    assert 'providerSearch.terms.join(" ") !== win.searchText' in LAUNCHER
    assert "searchText = p.text;" in block(LAUNCHER, "onQChanged: {", "\n    }")


# --------------------------------------------------------------------------
# 4. keyboard, accessibility, history management
# --------------------------------------------------------------------------
def test_home_end_and_tab_walk_the_same_flat_list():
    keys = block(
        LAUNCHER, "Keys.onUpPressed: {", "\n                     Keys.onPressed:"
    )
    # Home/End live in the shared Keys.onPressed (Keys.onHomePressed/onEndPressed
    # are not valid QML handlers), alongside the existing Ctrl shortcuts
    assert "e.key === Qt.Key_Home" in keys and "win.sel = 0" in keys
    assert "e.key === Qt.Key_End" in keys and "win.sel = win.flat.length - 1" in keys
    assert (
        "Keys.onTabPressed: win.sel = (win.sel + 1) % Math.max(1, win.flat.length)"
        in keys
    )
    assert (
        "Keys.onBacktabPressed: win.sel = (win.sel - 1 + win.flat.length) % Math.max(1, win.flat.length)"
        in keys
    )


def test_results_and_headers_carry_accessible_names():
    assert "Accessible.role: Accessible.ListItem" in LAUNCHER
    assert (
        'Accessible.name: (tile.modelData.title || "") + (tile.modelData.subtitle ? ", " + tile.modelData.subtitle : "")'
        in LAUNCHER
    )
    assert (
        'Accessible.name: (row.modelData.title || "") + (row.modelData.subtitle ? ", " + row.modelData.subtitle : "")'
        in LAUNCHER
    )
    assert "Accessible.role: Accessible.Heading" in LAUNCHER
    assert (
        'Accessible.name: Tr.t("Search apps, files, settings and the web")' in LAUNCHER
    )


def test_recent_searches_can_be_reused_forgotten_and_cleared():
    s = sections()
    assert 'title: Tr.t("Recent searches")' in s
    assert 'group: "history"' in s
    assert "LauncherEntries.forget(h)" in s
    assert "LauncherEntries.clearHistory()" in s
    assert "search.text = h; search.forceActiveFocus();" in s
    activate = block(
        LAUNCHER, "function activate(i, shift) {", "\n    function askChronoa"
    )
    assert "LauncherEntries.remember(win.q.trim())" in activate
    assert activate.index("remember(") < activate.index("Ui.closeAll()")
    assert 'p.op === "clip"' in block(LAUNCHER, "onQChanged: {", "\n    }")


def test_legacy_query_modes_still_win_over_operators():
    s = sections()
    for needle in [
        'q.startsWith("?")',
        'q.startsWith(">")',
        'q.startsWith(":")',
        'q === "c" || q.startsWith("c ")',
        'q.startsWith("=")',
        "Calc.convert(q)",
        "Calc.isCurrency(q)",
    ]:
        assert needle in s, needle



def test_no_invalid_accessible_roles():
    """Qt has Accessible.Heading/Graphic/Pane/MenuItem but no ListHeader/Image/
    Menu/PaneItem; an unknown enum assigns undefined and warns at render."""
    import re as _re
    invalid = {"ListHeader", "Image", "Menu", "PaneItem", "Widget"}
    found = set(_re.findall(r"Accessible\.(\w+)", LAUNCHER))
    assert not (found & invalid), found & invalid
