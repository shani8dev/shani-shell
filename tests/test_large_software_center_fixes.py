"""Large Software-centre upgrade, benchmarked against GNOME Software, KDE
Discover and the macOS App Store.

No QML runtime is available in this repo, so each fix is checked as source text;
the non-trivial branches (job queue, stale-search guard, collection merge,
history, error mapping) are *lifted out of the QML and executed in node* with
small stand-ins, like the sibling test_large_files_power_fixes.py does.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QML = (ROOT / "shani/Modules/Software/SoftwareWindow.qml").read_text(encoding="utf-8")
BRIDGE = (ROOT / "bridge/appstore.py").read_text(encoding="utf-8")

NODE = shutil.which("node")
node_mark = pytest.mark.skipif(NODE is None, reason="node is not installed")


# ---- helpers -------------------------------------------------------------------------
def js_func(src, name):
    """One whole function declaration, braces balanced, ready for node."""
    m = re.search(r"(?m)^[ \t]*function %s\(" % re.escape(name), src)
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


def run_js(funcs, prelude, statements, result):
    # QML methods live on `win`; global functions must be attached to the stand-in.
    attach = "\n".join(
        "win.%s = %s;" % (name, name)
        for name in re.findall(r"function\s+(\w+)\s*\(", "\n".join(funcs))
    )
    prog = (
        prelude
        + "\n"
        + "\n".join(funcs)
        + "\n"
        + attach
        + "\n"
        + statements
        + "\nprocess.stdout.write(JSON.stringify("
        + result
        + "));\n"
    )
    r = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


WIN_STUB = """
const Tr = { t: (s, ...a) => s };
const win = { jobQueue: [], error: "", progress: -1, jobLine: "", job: "", jobAction: "",
    jobCancelled: false, jobHistory: [], jobFailed: false, lastJob: null, tool: "/appstore.py",
    showing: "", results: [], searchGen: 0, installedOnly: false, collections: [], tabIds: [] };
const Ui = { softwareResults: [], softwareDone: "" };
const jobProc = { running: false, command: null };
const Qt = { callLater: f => f() };
"""


# ---- static: 12 concrete fixes -------------------------------------------------------
def test_fix_01_jobs_queue_instead_of_being_dropped():
    # Discover/App Store let you line up several installs; the old window
    # simply returned when a job was running, silently losing the click.
    body = QML.split("function runJob(args, forId) {", 1)[1].split(
        "function startNextJob()", 1
    )[0]
    assert "if (jobProc.running) return;" not in body
    assert (
        'win.jobQueue = win.jobQueue.concat([{ args: args, forId: forId || "" }]);'
        in body
    )
    assert "win.startNextJob();" in body
    assert "function startNextJob() {" in QML
    assert 'text: Tr.t("%1 queued", win.jobQueue.length)' in QML


def test_fix_02_cancel_stops_the_job_and_clears_the_batch():
    assert "function cancelJob() {" in QML
    assert (
        "jobProc.running = false;         // Quickshell's supported way to stop a Process"
        in QML
    )
    assert "win.jobQueue = [];               // abandon the whole batch" in QML
    assert 'text: Tr.t("Cancel")' in QML
    assert 'Accessible.name: Tr.t("Cancel the current operation")' in QML
    exit_body = QML.split("onExited: code => {", 1)[1].split("win.recordJob(code);", 1)[
        0
    ]
    assert "const cancelled = win.jobCancelled;" in exit_body


def test_fix_03_session_installation_history():
    assert "property var jobHistory: []" in QML
    assert '["history", Tr.t("History")]' in QML
    assert "function recordJob(code) {" in QML
    assert ".concat(win.jobHistory).slice(0, 50);" in QML
    assert "id: historyList" in QML
    assert 'title: Tr.t("No activity yet")' in QML
    assert 'Tr.t("Clear history")' in QML


def test_fix_04_search_generation_filter_and_hint():
    assert "const gen = ++win.searchGen;" in QML
    assert "if (gen !== win.searchGen) return false;" in QML
    assert 'Tr.t("Type at least 3 characters to search.")' in QML
    assert "SearchField {" in QML
    assert 'Choice { text: Tr.t("Installed only")' in QML
    assert "model: win.filteredResults()" in QML
    assert 'Tr.t("No installed apps in these results. Turn off Installed only.")' in QML


def test_fix_05_collections_from_existing_categories():
    assert "readonly property var collections:" in QML
    assert "function showCollection(name, cats) {" in QML
    assert 'cats.forEach(c => ask(["category", c], r => {' in QML
    assert "const seen = new Set(merged.map(a => a.id));" in QML
    assert "win.applyCollection(merged);" in QML
    assert 'text: Tr.t("Collections")' in QML


def test_fix_06_keyboard_navigation():
    assert "Keys.onPressed: e => {" in QML
    for key in (
        "Qt.Key_Slash",
        "Qt.Key_Down",
        "Qt.Key_Up",
        "Qt.Key_Return",
        "Qt.ControlModifier",
    ):
        assert key in QML, key
    assert "win.gotoTab(e.key - Qt.Key_1)" in QML
    assert "grid.positionViewAtIndex(grid.currentIndex, GridView.Contain)" in QML
    assert "ilist.positionViewAtIndex(ilist.currentIndex, ListView.Contain)" in QML
    assert "highlight: Rectangle" in QML


def test_fix_07_accessible_names():
    # Choice/Button/IconButton name themselves; these are the extra names on
    # cards, rows, fields and progress that had none.
    assert QML.count("Accessible.name:") >= 20
    assert "label: Tr.t(\"Find apps on Flathub\")" in QML
    assert 'Accessible.name: Tr.t("Operation progress")' in QML
    assert "Accessible.name: irow.modelData.name" in QML
    assert "Accessible.role: Accessible.ListItem" in QML
    assert "win.openApp(card.modelData.id)" in QML and "Accessible.onPressAction:" in QML
    assert "Accessible.name: modelData.name + (modelData.installed" in QML


def test_fix_08_ratings_only_where_data_exists():
    assert 'Tr.t("No ratings yet — community reviews come from ODRS.")' in QML
    assert 'Tr.t("%1 out of 5 stars", appCol.a.rating || 0)' in QML
    assert '"☆".repeat(5 -' in QML
    assert "appCol.a.reviews" in QML and "appCol.a.ratingCount" in QML


def test_fix_09_permissions_empty_state():
    assert "win.appPermissions.length === 0" in QML
    assert 'Tr.t("This app declares no special permissions.")' in QML
    assert "win.permsLoading" in QML


def test_fix_10_changelog_expand():
    assert "property bool showAllReleases: false" in QML
    assert "win.showAllReleases = false;" in QML
    assert (
        "model: win.showAllReleases ? (appCol.a.releases || []) : (appCol.a.releases || []).slice(0, 5)"
        in QML
    )
    assert 'Tr.t("Show all %1 versions", (appCol.a.releases || []).length)' in QML
    assert 'Tr.t("Show fewer versions")' in QML


def test_fix_11_friendly_errors_and_retry():
    assert "function friendlyError() {" in QML
    assert 'Tr.t("Not enough free space to finish this operation.")' in QML
    assert 'Tr.t("You are offline — reconnect and try again.")' in QML
    assert "text: win.friendlyError()" in QML
    assert "function retry() {" in QML and "onClicked: win.retry()" in QML
    assert 'Accessible.name: Tr.t("Try the operation again")' in QML


def test_fix_12_binary_size_units():
    assert '" GiB"' in QML and '" MiB"' in QML and '" KiB"' in QML
    assert "[KMG]i?B" in QML


def test_all_commands_still_in_the_existing_bridge_contract():
    """No new bridge command or dependency was invented in the window."""
    verbs = set(re.findall(r'cmd\s*==\s*"([a-z-]+)"', BRIDGE))
    for group in re.findall(r"cmd\s+in\s+\(([^)]*)\)", BRIDGE):
        verbs |= set(re.findall(r'"([a-z-]+)"', group))
    used = set(re.findall(r'(?:win\.ask|ask|runJob)\(\["([a-z-]+)"', QML))
    assert used <= verbs, "unknown bridge commands: %s" % sorted(used - verbs)
    assert QML.count("import ") == 7  # the original six, plus its own folder (SoftwareCliTools): no new dependency


# ---- executed: the non-trivial branches -----------------------------------------------
@node_mark
def test_queue_two_jobs_cancel_and_guard():
    out = run_js(
        [
            js_func(QML, "runJob"),
            js_func(QML, "startNextJob"),
            js_func(QML, "cancelJob"),
        ],
        WIN_STUB,
        """
        win.runJob(["install", "a.b.C"], "a.b.C");
        const first = { verb: jobProc.command[2], id: jobProc.command[3], running: jobProc.running,
                        queued: win.jobQueue.length, job: win.job };
        win.runJob(["remove", "d.e.F"], "d.e.F");
        const queued = win.jobQueue.length;
        win.startNextJob();                       // must not preempt a running job
        const stillFirst = jobProc.command[3];
        jobProc.running = false;                  // first job finished
        win.startNextJob();
        const second = { verb: jobProc.command[2], id: jobProc.command[3], queued: win.jobQueue.length };
        win.cancelJob();
        const cancelled = { running: jobProc.running, queued: win.jobQueue.length,
                            flag: win.jobCancelled, progress: win.progress };
        win.startNextJob();                       // empty queue resets progress
        const idle = { progress: win.progress, job: win.job };
        """,
        "{first, queued, stillFirst, second, cancelled, idle}",
    )
    assert out["first"] == {
        "verb": "install",
        "id": "a.b.C",
        "running": True,
        "queued": 0,
        "job": "a.b.C",
    }
    assert out["queued"] == 1
    assert out["stillFirst"] == "a.b.C"
    assert out["second"] == {"verb": "remove", "id": "d.e.F", "queued": 0}
    assert out["cancelled"] == {
        "running": False,
        "queued": 0,
        "flag": True,
        "progress": -1,
    }
    assert out["idle"] == {"progress": -1, "job": ""}


@node_mark
def test_stale_search_answer_is_ignored():
    out = run_js(
        [js_func(QML, "applyResults")],
        WIN_STUB + "\nwin.searchGen = 7; win.results = [{id: 'old'}];\n",
        """
        const stale = win.applyResults(6, [{id: 'new'}]);
        const old = win.results.map(a => a.id);
        const fresh = win.applyResults(7, [{id: 'new'}]);
        const now = win.results.map(a => a.id);
        """,
        "{stale, old, fresh, now, ui: Ui.softwareResults}",
    )
    assert out == {
        "stale": False,
        "old": ["old"],
        "fresh": True,
        "now": ["new"],
        "ui": ["new"],
    }


@node_mark
def test_filter_and_sort_results():
    out = run_js(
        [js_func(QML, "filteredResults")],
        WIN_STUB
        + "\nwin.results = [{id:'z',name:'Zed',installed:false},{id:'a',name:'Alpha',installed:true},{id:'m',name:'Mid',installed:true}];\n",
        """
        const all = win.filteredResults().map(a => a.name);
        win.installedOnly = true;
        const installed = win.filteredResults().map(a => a.name);
        """,
        "{all, installed}",
    )
    assert out["all"] == ["Alpha", "Mid", "Zed"]
    assert out["installed"] == ["Alpha", "Mid"]


@node_mark
def test_collection_merges_categories_without_duplicates():
    prelude = (
        WIN_STUB
        + """
    const catalogue = { Graphics: [{id:'g1',name:'G1'},{id:'shared',name:'Shared'}],
                        AudioVideo: [{id:'a1',name:'A1'},{id:'shared',name:'Shared'}] };
    function ask(args, cb) { cb(catalogue[args[1]] || []); }
    """
    )
    out = run_js(
        [js_func(QML, "showCollection"), js_func(QML, "applyCollection")],
        prelude,
        'win.showCollection("Creativity", ["Graphics", "AudioVideo"]);',
        "{showing: win.showing, ids: win.results.map(a => a.id), ui: Ui.softwareResults}",
    )
    assert out == {
        "showing": "collection:Creativity",
        "ids": ["g1", "shared", "a1"],
        "ui": ["g1", "shared", "a1"],
    }


@node_mark
def test_clamp_index_never_leaves_the_model():
    out = run_js(
        [js_func(QML, "clampIndex")],
        WIN_STUB,
        "",
        "[win.clampIndex(2, 5), win.clampIndex(-1, 5), win.clampIndex(9, 5), win.clampIndex(0, 0)]",
    )
    assert out == [2, 0, 4, -1]


@node_mark
def test_history_labels_and_bounds():
    out = run_js(
        [js_func(QML, "recordJob")],
        WIN_STUB,
        """
        win.jobAction = 'install'; win.job = 'org.x.App'; win.recordJob(0);
        const first = win.jobHistory[0];
        win.jobAction = 'update-all'; win.job = 'all'; win.recordJob(1);
        const second = win.jobHistory[0];
        for (let i = 0; i < 60; i++) win.recordJob(0);
        """,
        "{first, second, n: win.jobHistory.length}",
    )
    assert out["first"]["action"] == "Installed"
    assert out["first"]["ok"] is True
    assert out["first"]["name"] == "org.x.App"
    assert out["second"]["action"] == "Update all"
    assert out["second"]["ok"] is False
    assert out["n"] == 50


@node_mark
def test_error_mapping():
    prelude = WIN_STUB + "\nconst Net = { online: true };\n"
    out = run_js(
        [js_func(QML, "friendlyError")],
        prelude,
        """
        const missing = (win.error = 'flatpak: No such file or directory', win.friendlyError());
        const denied  = (win.error = 'flatpak: permission denied', win.friendlyError());
        const space   = (win.error = 'error: No space left on device', win.friendlyError());
        const badid   = (win.error = 'not an app id: x', win.friendlyError());
        const plain   = (win.error = 'some other bridge text', win.friendlyError());
        Net.online = false;
        const offline = (win.error = 'network is unreachable', win.friendlyError());
        """,
        "{missing, denied, space, badid, plain, offline}",
    )
    assert "Flatpak isn't installed" in out["missing"]
    assert "Permission denied" in out["denied"]
    assert "free space" in out["space"]
    assert "could not be found" in out["badid"]
    assert out["plain"] == "some other bridge text"
    assert "offline" in out["offline"]


@node_mark
def test_retry_reruns_failed_job_or_reloads_view():
    prelude = (
        WIN_STUB
        + """
    win.calls = [];
    win.runJob = (a, b) => win.calls.push(['job', a[0], b]);
    win.search = s => win.calls.push(['search', s]);
    win.showCategory = c => win.calls.push(['category', c]);
    win.start = () => win.calls.push(['start']);
    win.showCollection = (n, c) => win.calls.push(['collection', n]);
    """
    )
    out = run_js(
        [js_func(QML, "retry"), js_func(QML, "reloadCurrentView")],
        prelude,
        """
        win.error = 'boom'; win.jobFailed = true; win.lastJob = {args:['install','x.y.Z'], forId:'x.y.Z'};
        win.retry();
        win.error = 'boom'; win.jobFailed = false; win.showing = 'search:firefox';
        win.retry();
        win.showing = 'category:Game'; win.retry();
        """,
        "{calls: win.calls, error: win.error}",
    )
    assert out == {
        "calls": [
            ["job", "install", "x.y.Z"],
            ["search", "firefox"],
            ["category", "Game"],
        ],
        "error": "",
    }


@node_mark
def test_size_helpers():
    out = run_js(
        [js_func(QML, "human"), js_func(QML, "bytesOf")],
        WIN_STUB,
        "",
        """{
            mb: win.bytesOf('12.0 MB'), gib: win.bytesOf('2 GiB'), bad: win.bytesOf('nonsense'),
            human1: win.human(2 * 1048576), human2: win.human(512 * 1024)
        }""",
    )
    assert out["mb"] == 12 * 1048576
    assert out["gib"] == 2 * 1073741824
    assert out["bad"] == 0
    assert out["human1"] == "2.0 MiB"
    assert out["human2"] == "512 KiB"
