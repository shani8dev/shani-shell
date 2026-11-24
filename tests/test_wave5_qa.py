"""WAVE 5 QA + integration — regression tests for the surfaces landed this wave.

Read-only: this file never edits QML or bridge source. Every test pins the
CORRECT behaviour, so it passes on good code and fails the moment a fix is
undone. Where a surface is pure logic the *exact* QML functions are executed in
node with tiny stubs; elsewhere the guard is pinned in the source.

The "Bugs" section pins behaviour that is WRONG in the code as it stands: each
failure names the file and line and describes the fix. The "Guards" section
documents fixes that are already in place so a later edit cannot undo them;
the last section re-checks the wave-1..4 fixes against a wave-5 regression.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge"
if str(BRIDGE) not in sys.path:
    sys.path.insert(0, str(BRIDGE))

NODE = shutil.which("node") or shutil.which("nodejs")
TEMPLATE = json.loads((ROOT / "shani/i18n/template.json").read_text(encoding="utf-8"))

TEXT_EDITOR = "shani/Modules/TextEditor/TextEditorPanel.qml"
NOTES = "shani/Modules/Notes/NotesPanel.qml"
NOTES_MD = "shani/Modules/Notes/NotesMarkdown.qml"
PROCESSES = "shani/Modules/Processes/Processes.qml"
FEEDS = "shani/Modules/Feeds/FeedsWindow.qml"
MAIL = "shani/Modules/Mail/MailWindow.qml"
POPUPS = "shani/Modules/Notifications/Popups.qml"
NOTIF_CARD = "shani/Modules/Notifications/NotificationCard.qml"
BAR = "shani/Modules/Bar/Bar.qml"
SWITCHER = "shani/Modules/Switcher/Switcher.qml"

WAVE5_QML = (
    TEXT_EDITOR,
    NOTES,
    NOTES_MD,
    PROCESSES,
    FEEDS,
    MAIL,
    POPUPS,
    NOTIF_CARD,
    BAR,
    SWITCHER,
)
WAVE5_SERVICES = (
    "shani/Services/QuickNotes.qml",
    "shani/Services/TopProcesses.qml",
    "shani/Services/SysStats.qml",
    "shani/Services/Notifs.qml",
)


def src(rel: str) -> str:
    """Read a wave-5 file, or skip while its subagent has not landed it."""
    path = ROOT / rel
    if not path.exists():
        pytest.skip(f"wave-5 file has not landed yet: {rel}")
    return path.read_text(encoding="utf-8")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def source_of(text: str, name: str) -> str:
    """One `function name(...) { ... }` verbatim, braces matched."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", text)
    assert m, f"function {name}() not found"
    depth = 0
    for j in range(m.end() - 1, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[m.start() : j + 1]
    raise AssertionError(f"unterminated function {name}()")


def bind(text: str, obj: str, *names: str) -> str:
    """Turn real QML functions into methods of a node stub object."""
    out = []
    for name in names:
        fn = source_of(text, name)
        out.append(
            re.sub(
                r"function\s+" + re.escape(name) + r"\s*\(",
                f"{obj}.{name} = function(",
                fn,
                count=1,
            )
        )
    return "\n".join(out)


def node(prog: str):
    assert NODE, "node is required"
    out = subprocess.run(
        [NODE, "-e", prog], capture_output=True, text=True, timeout=30, check=True
    )
    return json.loads(out.stdout.strip().splitlines()[-1])


def tr_strings(text: str) -> set[str]:
    """Literal Tr.t("...") keys, unescaped the way tools/i18n.py extracts them."""
    return set(
        m.replace('\\"', '"').replace("\\\\", "\\")
        for m in re.findall(r'Tr\.t\(\s*"((?:[^"\\]|\\.)*)"\s*\)', text)
    )


def balanced(text: str, start: int) -> str:
    """One balanced `{ ... }` block beginning at `start`, quoted strings skipped."""
    i = text.index("{", start)
    quote = None
    escaped = False
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if quote:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == quote:
                quote = None
            continue
        if c in ('"', "'"):
            quote = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start : j + 1]
    raise AssertionError(f"unterminated block at {start}")


# ---------------------------------------------------------------------------
# Bugs — these FAIL on the code as it stands. Each names the exact file:line.
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_bug_processes_tree_lists_each_pid_exactly_once():
    """Processes.qml:150.

    `roots = procs.filter(p => p.ppid <= 1 || !byPid[p.ppid])` treats every
    child of PID 1 as a root *and* as a child of PID 1. On a real machine PID 1
    is in /proc, so systemd's children are drawn twice: once indented under it
    and once flat at the top. Run the real buildTree() with a three-process
    tree; each pid must appear once. Fix: root on `!byPid[p.ppid]` alone —
    PID 1 has ppid 0, which is not in the list, so it stays a root.
    """
    s = src(PROCESSES)
    procs = [
        {"pid": 1, "ppid": 0, "name": "systemd", "cpu": 1, "mem": 1},
        {"pid": 2, "ppid": 1, "name": "child-a", "cpu": 9, "mem": 1},
        {"pid": 3, "ppid": 1, "name": "child-b", "cpu": 5, "mem": 1},
    ]
    prog = """
var TopProcesses = { list: %s, diskIo: {} };
var win = { sortKey: "cpu", sortDesc: true };
%s
process.stdout.write(JSON.stringify({ rows: win.buildTree().map(r => r.p.name) }));
""" % (json.dumps(procs), bind(s, "win", "metric", "sortRows", "buildTree"))
    rows = node(prog)["rows"]
    assert sorted(rows) == ["child-a", "child-b", "systemd"], (
        "Processes.qml:150 — tree duplicates PID 1's children: " + repr(rows)
    )


def test_bug_wave5_tr_t_literals_are_in_the_template():
    """Every new Tr.t() key must be in shani/i18n/template.json.

    Wave 5 added Tr.t wrappers but did not re-run `tools/i18n.py extract`, so
    the catalog template is stale. Missing keys are invisible to translators
    and `tools/i18n.py check` cannot report them.
    """
    missing = {}
    for rel in WAVE5_QML:
        keys = sorted(tr_strings(src(rel)) - set(TEMPLATE))
        if keys:
            missing[rel] = keys
    assert missing == {}, (
        "run `python3 tools/i18n.py extract` — missing template keys: " + repr(missing)
    )


def test_bug_markdown_preview_a11y_strings_are_translatable():
    """TextEditorPanel.qml:1262-1263.

    The new preview pane names itself with raw English literals while every
    other control in the file goes through Tr.t(). Fix: wrap both in Tr.t()
    and extract the keys.
    """
    s = src(TEXT_EDITOR)
    assert 'Accessible.name: Tr.t("Markdown preview")' in s, (
        "TextEditorPanel.qml:1262 — raw Accessible.name"
    )
    assert (
        'Accessible.description: Tr.t("Rendered view of the current document; '
        'Page Up and Page Down scroll")' in s
    ), "TextEditorPanel.qml:1263 — raw Accessible.description"


def test_bug_no_debug_output_is_left_in_wave5_surfaces():
    """TextEditorPanel.qml:250.

    `onMarkdownPreviewChanged: console.log("MDDBG", ...)` ships a debug trace
    to the journal on every preview toggle. Fix: delete the handler.
    """
    for rel in WAVE5_QML:
        for i, line in enumerate(src(rel).splitlines(), 1):
            if "console.log(" in line:
                # a snippet body is a string, not a call in shipped code
                assert re.search(r':\s*"[^"]*console\.log\(', line), (
                    f"{rel}:{i} — debug console.log left in a wave-5 surface"
                )


def test_bug_notes_trash_toggle_and_processes_overview_are_translatable():
    """NotesPanel.qml:377 and Processes.qml:237.

    The trash toggle and the system-overview heading are shown in English in
    every locale; the neighbouring labels already use Tr.t(). Fix: wrap them
    and extract the keys.
    """
    notes = src(NOTES)
    assert re.search(r'text:\s*Tr\.t\("Trash…"\)', notes), (
        "NotesPanel.qml:377 — raw trash-toggle label"
    )
    proc = src(PROCESSES)
    assert re.search(r'text:\s*Tr\.t\("System overview"\)', proc), (
        "Processes.qml:237 — raw section title"
    )


# ---------------------------------------------------------------------------
# Correct behaviour — pure logic, executed with the real QML function bodies.
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_editor_smart_indent_keeps_the_files_own_indent_unit():
    s = src(TEXT_EDITOR)
    prog = """
var win = {};
%s
process.stdout.write(JSON.stringify({
  spaces: win.indentOnEnter("    if (x) {", "}"),
  tabs: win.indentOnEnter("\\tswitch (x) {", "}"),
  plain: win.indentOnEnter("    let x = 1", "y"),
  empty: win.indentOnEnter("", "")
}));
""" % bind(s, "win", "indentUnit", "indentOnEnter")
    out = node(prog)
    assert out["spaces"] == "\n        \n    ", out
    assert out["tabs"] == "\n\t\t\n\t", out
    assert out["plain"] == "\n    ", out
    assert out["empty"] == "\n", out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_editor_markdown_inline_escapes_html_and_opens_only_safe_links():
    s = src(TEXT_EDITOR)
    prog = """
var opened = [];
var Qt = { openUrlExternally: function (u) { opened.push(u); } };
var win = {};
%s
process.stdout.write(JSON.stringify({
  raw: win.markdownInline("<script>alert(1)</script>"),
  amp: win.markdownInline("a & b < c"),
  bold: win.markdownInline("**bold** and *it*"),
  code: win.markdownInline("`x < y`"),
  link: win.markdownInline("[label](https://example.com/x?a=1&b=2)"),
  opened: opened,
  winOpen: (win.openMarkdownLink("https://ok.example"),
            win.openMarkdownLink("mailto:a@b.c"),
            win.openMarkdownLink("javascript:alert(1)"),
            win.openMarkdownLink("file:///etc/passwd"), opened)
}));
""" % bind(s, "win", "markdownInline", "openMarkdownLink")
    out = node(prog)
    assert "<script>" not in out["raw"] and "&lt;script&gt;" in out["raw"], out
    assert out["amp"] == "a &amp; b &lt; c", out
    assert "<b>bold</b>" in out["bold"] and "<i>it</i>" in out["bold"], out
    assert "<code>x &lt; y</code>" in out["code"], out
    assert '<a href="https://example.com/x?a=1&amp;b=2">label</a>' == out["link"], out
    assert out["winOpen"] == ["https://ok.example", "mailto:a@b.c"], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_editor_markdown_rows_cover_blocks_and_cap_list_depth():
    s = src(TEXT_EDITOR)
    prog = """
var win = {};
%s
var rows = win.markdownRows("# Title\\n\\n- a\\n        - deep\\n> quote\\n---\\n"
  + "```\\nraw <b>x</b>\\n```\\n1. one\\nplain");
process.stdout.write(JSON.stringify({
  kinds: rows.map(r => r.kind),
  level: rows[0].level, size: rows[0].size,
  depths: rows.filter(r => r.kind === "list").map(r => r.depth),
  code: rows.filter(r => r.kind === "code").map(r => r.html)
}));
""" % (
        bind(s, "win", "markdownInline", "mdRow", "markdownRows")
        + "\nvar mdRow = win.mdRow, markdownInline = win.markdownInline;\n"
    )
    out = node(prog)
    assert out["kinds"] == [
        "heading",
        "blank",
        "list",
        "list",
        "quote",
        "rule",
        "blank",
        "code",
        "blank",
        "list",
        "para",
    ], out
    assert out["level"] == 1 and out["size"] == 1.7, out
    assert out["depths"] == [0, 4, 0], out
    assert out["code"] == ["raw &lt;b&gt;x&lt;/b&gt;"], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_processes_sort_rows_uses_key_and_direction_without_mutating_input():
    s = src(PROCESSES)
    rows = [
        {"pid": 1, "name": "zebra", "cpu": 1, "mem": 5},
        {"pid": 2, "name": "alpha", "cpu": 9, "mem": 1},
    ]
    prog = """
var TopProcesses = { list: [], diskIo: { 1: 500, 2: 100 } };
var win = { sortKey: "cpu", sortDesc: true };
%s
var src = %s;
var before = src.map(r => r.pid).join(",");
var desc = win.sortRows(src).map(r => r.pid);
var asc = (win.sortDesc = false, win.sortRows(src).map(r => r.pid));
win.sortKey = "name"; var byName = win.sortRows(src).map(r => r.pid);
win.sortKey = "disk"; win.sortDesc = true;
var byDisk = win.sortRows(src).map(r => r.pid);
process.stdout.write(JSON.stringify({ before: before, after: src.map(r => r.pid).join(","),
  desc: desc, asc: asc, byName: byName, byDisk: byDisk }));
""" % (bind(s, "win", "metric", "sortRows"), json.dumps(rows))
    out = node(prog)
    assert out["before"] == out["after"] == "1,2", out
    assert out["desc"] == [2, 1] and out["asc"] == [1, 2], out
    assert out["byName"] == [2, 1] and out["byDisk"] == [1, 2], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_processes_pressure_meters_have_bounded_thresholds_and_theme_colours():
    s = src(PROCESSES)
    prog = """
var Theme = { red: "red", amber: "amber", accent: "accent" };
var win = {};
%s
process.stdout.write(JSON.stringify({
  load: [win.loadLevel(0.69, 1), win.loadLevel(0.7, 1), win.loadLevel(0.99, 1),
         win.loadLevel(1, 1), win.loadLevel(1.4, 2), win.loadLevel(1.3, 2)],
  swap: [win.swapLevel(5, 0), win.swapLevel(69, 100), win.swapLevel(70, 100),
         win.swapLevel(90, 100)],
  psi: [win.psiLevel(19), win.psiLevel(20), win.psiLevel(40)],
  colours: [win.pressureColor(0), win.pressureColor(1), win.pressureColor(2)]
}));
""" % bind(s, "win", "loadLevel", "swapLevel", "psiLevel", "pressureColor")
    out = node(prog)
    assert out["load"] == [0, 1, 1, 2, 1, 0], out
    assert out["swap"] == [0, 0, 1, 2], out
    assert out["psi"] == [0, 1, 2], out
    assert out["colours"] == ["accent", "amber", "red"], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_mail_operators_threads_and_undo_are_pure_view_state():
    s = src(MAIL)
    prog = """
var Mail = {
  messages: [
    { uid: 1, subject: "Re: Hello", from: "a@x", snippet: "", date: "2026-01-01", unread: true },
    { uid: 2, subject: "Fwd: Hello", from: "b@x", snippet: "", date: "2026-01-02", unread: false },
    { uid: 3, subject: "Other", from: "c@x", snippet: "", date: "2026-01-03", unread: false }
  ],
  markUnread: function (u) { Mail._unread.push(u); },
  flag: function (u, f, v) { Mail._flag.push([u, v]); },
  _unread: [], _flag: []
};
var win = { filterUnread: false, filterStarred: false, filterText: "",
  sortField: "date", sortNewest: true, threaded: false, expandedThreads: [],
  lastBulk: {} };
var searchField = { text: "x" };
%s
var rows = win.visibleMessages();
win.threaded = true;
var grouped = win.visibleMessages();
var thread = grouped.filter(r => r.isThread)[0];
win.toggleThread(thread.threadKey);
var expanded = win.expandedThreads.slice();
win.toggleThread(thread.threadKey);
win.lastBulk = { kind: "read", uids: [3] };
var undoYes = win.undoAvailable(); win.undoBulk();
win.lastBulk = { kind: "archive", uids: [3] };
var undoNo = win.undoAvailable();
process.stdout.write(JSON.stringify({
  key: win.conversationKey(Mail.messages[1]),
  hasOp: win.hasOperators("from:a is:unread"),
  plain: win.hasOperators("hello world"),
  matches: win.matchesOperators(Mail.messages[0], "FROM:a is:unread"),
  sorted: rows.map(r => r.uid),
  plainCount: rows.length, groupedCount: grouped.length,
  threadUids: thread.threadUids, expanded: expanded,
  collapsed: win.expandedThreads, undoYes: undoYes, undoNo: undoNo,
  unread: Mail._unread
}));
""" % bind(
        s,
        "win",
        "conversationKey",
        "hasOperators",
        "matchesOperators",
        "passesFilters",
        "sortedMessages",
        "visibleMessages",
        "toggleThread",
        "undoAvailable",
        "undoBulk",
    )
    out = node(prog)
    assert out["key"] == "hello" and out["hasOp"] and not out["plain"], out
    assert out["matches"], out
    assert out["sorted"] == [3, 2, 1], out
    assert out["plainCount"] == 3 and out["groupedCount"] == 2, out
    assert out["threadUids"] == [2, 1], out
    assert len(out["expanded"]) == 1 and out["collapsed"] == [], out
    assert out["undoYes"] and not out["undoNo"] and out["unread"] == [3], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_popups_group_by_app_keep_critical_and_dismiss_non_critical_only():
    s = src(POPUPS)
    prog = """
var NotificationUrgency = { Critical: 2 };
var Notifs = { popups: [], _dismissed: [] };
var win = { expanded: { "org.x.mail": true } };
var Tr = { t: function (s) { return s; } };
%s
Notifs.popups = [
  { id: 1, appName: "Mail", desktopEntry: "", urgency: 0, dismiss: function () { Notifs._dismissed.push(1); } },
  { id: 2, appName: "mail", desktopEntry: "org.x.Mail", urgency: 0, dismiss: function () { Notifs._dismissed.push(2); } },
  { id: 3, appName: "Phone", urgency: NotificationUrgency.Critical,
    dismiss: function () { Notifs._dismissed.push(3); } }
];
var groups = win.groupPopups();
var mail = groups.filter(g => g.items.length === 2)[0];
win.dismissGroup(mail);
process.stdout.write(JSON.stringify({
  groups: groups.length, sizes: groups.map(g => g.items.length),
  keys: groups.map(g => g.key), dismissed: Notifs._dismissed,
  expanded: win.expanded
}));
""" % bind(s, "win", "appKey", "groupPopups", "toggleGroup", "dismissGroup")
    out = node(prog)
    assert out["groups"] == 2 and sorted(out["sizes"]) == [1, 2], out
    assert sorted(out["keys"]) == ["critical:3", "org.x.mail"], out
    assert sorted(out["dismissed"]) == [1, 2], out
    assert "org.x.mail" not in out["expanded"], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_notification_card_body_is_plain_data_and_links_are_allowlisted():
    s = src(NOTIF_CARD)
    prog = """
var opened = [];
var Qt = { openUrlExternally: function (u) { opened.push(u); } };
var root = {};
%s
process.stdout.write(JSON.stringify({
  body: root.safeBody("<img src=x onerror=alert(1)>"),
  open: (root.openLink("https://ok.example"), root.openLink("mailto:a@b.c"),
         root.openLink("javascript:alert(1)"), root.openLink("/etc/passwd"), opened)
}));
""" % bind(s, "root", "safeBody", "openLink")
    out = node(prog)
    assert out["body"] == "<img src=x onerror=alert(1)>", out
    assert out["open"] == ["https://ok.example", "mailto:a@b.c"], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_switcher_groups_windows_and_bounds_selection():
    s = src(SWITCHER)
    prog = """
var win = {};
var list = [], sel = 0, grouped = true, groups = [];
%s
list = [
  { id: 1, app_id: "org.x.A" }, { id: 2, app_id: "org.x.A" },
  { id: 3, app_id: "org.x.B" }
];
groups = win.buildGroups();
var count0 = win.count();
win.step(1); var afterStep = sel;
win.step(99); var wrapped = sel;
var app = win.appWindows().map(w => w.id);
var cur = win.currentWindows().map(w => w.id);
sel = 99; win.clampSel();
process.stdout.write(JSON.stringify({ count: count0, afterStep: afterStep,
  wrapped: wrapped, app: app, cur: cur, clamped: sel }));
""" % bind(
        s,
        "win",
        "appKey",
        "buildGroups",
        "count",
        "clampSel",
        "currentWindows",
        "appWindows",
        "step",
    )
    out = node(prog)
    assert out["count"] == 2, out
    assert out["afterStep"] == 1 and out["wrapped"] == 0, out
    assert out["app"] == [1, 2] and out["cur"] == [1, 2], out
    assert out["clamped"] == 1, out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_bar_percentage_and_menu_flatten_are_bounded():
    s = src(BAR)
    prog = """
var bar = { inlineExpanded: {} };
%s
var pcts = [bar.peripheralPct({ percentage: 0.5 }), bar.peripheralPct({ percentage: 1 }),
            bar.peripheralPct({ percentage: 0 }), bar.peripheralPct({ percentage: NaN }),
            bar.peripheralPct(null)];
var items = [{ path: "a", items: [{ path: "a1" }] }, { path: "b" }];
var closed = bar.inlineFlatten(items, 0).map(x => x.path);
bar.inlineExpanded = { a: true };
var open = bar.inlineFlatten(items, 0).map(x => x.path);
process.stdout.write(JSON.stringify({ pcts: pcts, closed: closed, open: open }));
""" % bind(s, "bar", "peripheralPct", "inlineFlatten")
    out = node(prog)
    assert out["pcts"] == [50, 1, 0, -1, 0], out
    assert out["closed"] == ["a", "b"] and out["open"] == ["a", "a1", "b"], out


# ---------------------------------------------------------------------------
# Cross-file invariants for every wave-5 surface.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("rel", WAVE5_QML + WAVE5_SERVICES)
def test_wave5_status_reads_never_use_pkexec(rel):
    s = src(rel)
    assert "pkexec" not in s, f"{rel}: pkexec in a status/read-only path"


@pytest.mark.parametrize("rel", [r for r in WAVE5_QML if r.endswith(".qml")])
def test_wave5_property_arrays_are_reassigned_not_mutated(rel):
    s = src(rel)
    bad = re.findall(
        r"(?:root|win|page|service|bar)\.[\w.]+\.(?:push|splice|sort|reverse)\(", s
    )
    assert bad == [], f"{rel}: in-place mutation of a property array: {bad}"


@pytest.mark.parametrize("rel", [r for r in WAVE5_QML if r.endswith(".qml")])
def test_wave5_timers_do_not_run_when_nothing_needs_them(rel):
    s = src(rel)
    running = []
    for m in re.finditer(r"\bTimer\s*\{", s):
        block = balanced(s, m.start())
        if re.search(r"\brunning:\s*true\b", block):
            running.append(s.count("\n", 0, m.start()) + 1)
    assert running == [], f"{rel}: idle timers at lines {running}"


def test_wave5_shell_commands_pass_paths_as_argv():
    """A user path must never be concatenated into a `sh -c` string."""
    notes = src(NOTES)
    body = source_of(notes, "insertImage")
    assert '"sh", "-c"' in body and '"sh", folder, paste.target]' in body, (
        "NotesPanel.qml:901 — clipboard image path must stay in argv"
    )
    quick = src(WAVE5_SERVICES[0])
    for fn in ("remove", "restore", "emptyTrash"):
        f = source_of(quick, fn)
        assert "sh -c" not in f or re.search(r'"\$[12]"', f), (
            f"QuickNotes.qml:{fn} — path must be a positional shell argument"
        )


def test_wave5_new_controls_have_accessible_names():
    ed = src(TEXT_EDITOR)
    notes = src(NOTES)
    popups = src(POPUPS)
    proc = src(PROCESSES)
    assert re.search(r'accessibleName:\s*Tr\.t\("Markdown preview"\)', ed)
    assert 'Accessible.name: Tr.t("Permanently delete every trashed note")' in notes
    assert 'Accessible.name: Tr.t("Restore note %1").arg(modelData)' in notes
    assert 'accessibleName: Tr.t("Dismiss %1 notifications from %2"' in popups
    m = re.search(r"\bIconButton\s*\{\s*\n\s*id:\s*filterBtn\b", ed)
    if m:  # pre-existing, but must stay named
        btn = balanced(ed, m.start())
        assert "accessibleName:" in btn and "Tr.t(" in btn


def test_wave5_lists_are_bounded():
    bar = src(BAR)
    popups_svc = src("shani/Services/Notifs.qml")
    editor = src(TEXT_EDITOR)
    assert "slice(0, bar.trayCap)" in bar and "slice(bar.trayCap)" in bar
    assert "root.popups = root.popups.concat([n]).slice(-4)" in popups_svc
    assert "win.findFilesResults.length >= 200" in editor
    assert "matchOffsets.slice(0, 200)" in editor


def test_wave5_text_is_rendered_as_plain_text_not_html():
    """A note or notification body must never become the shell's markup."""
    notes_md = src(NOTES_MD)
    assert "textFormat: Text.PlainText" in notes_md
    assert "textFormat: Text.RichText" not in notes_md
    assert "text: Services.QuickNotes.markdownHtml()" not in src(NOTES)
    card = src(NOTIF_CARD)
    assert 'function safeBody(body) { return String(body || ""); }' in card


# ---------------------------------------------------------------------------
# Re-check of the wave-1/2/3/4 fixes. None may be silently undone by wave 5.
# ---------------------------------------------------------------------------


def test_guard_batch_rename_path_validation():
    import files  # noqa: E402 (conftest puts bridge/ on sys.path)

    body = source_of(read("shani/Services/Files.qml"), "batchRename")
    assert "FilePaths.validName" in body or "validName(" in body
    assert "def batch_rename(" in read("bridge/files.py")


def test_guard_split_selection_is_copied_before_mutation():
    body = source_of(read("shani/Services/Files.qml"), "selectSplit")
    aliased = re.search(r"const\s+s\s*=\s*root\._splitPaths\s*;", body)
    assert not (aliased and re.search(r"\bs\.(?:splice|push|sort|reverse)\(", body))


def test_guard_archive_batch_results_are_reassigned():
    s = read("shani/Services/Archive.qml")
    assert "root.batchDone.push(" not in s and "root.batchFailed.push(" not in s


def test_guard_ctrl_shift_f2_reaches_batch_rename():
    lines = [
        line.strip()
        for line in read("shani/Modules/Files/FilesPanel.qml").splitlines()
        if re.search(r"Qt\.Key_F2\b", line) and line.strip().startswith("if (")
    ]
    assert len(lines) == 2, lines
    single = next(c for c in lines if "!control" in c)
    batch = next(c for c in lines if c is not single)
    assert "!control" in single and "ShiftModifier" in single
    assert "control &&" in batch and "ShiftModifier" in batch


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_guard_insert_datetime_works_with_one_cursor():
    s = read(TEXT_EDITOR)
    prog = """
var win = {};
var edit = { cursorPosition: 6, text: "abcdef", forceActiveFocus: function () {} };
var extraCursors = [], loading = false;
var Qt = { formatDateTime: function () { return "2026-01-01 00:00"; } };
var TextDocs = { setText: function (t) { edit.text = t; } };
var repaint = { restart: function () {} };
%s
win.insertDateTime();
process.stdout.write(JSON.stringify({ text: edit.text, cursor: edit.cursorPosition }));
""" % (
        bind(s, "win", "insertDateTime", "insertAtCursors")
        + "\nvar multiCursor = extraCursors.length > 0;\n"
    )
    out = node(prog)
    assert "2026-01-01" in out["text"] and out["cursor"] > 6, out


def test_guard_tr_t_escape_handling_stays_aligned():
    """The extractor and the QA helper must unescape identically (commit caa0315)."""
    s = read("tests/test_wave3_qa.py")
    assert '.replace(\'\\\\"\', \'"\').replace("\\\\\\\\", "\\\\")' in s


def test_guard_alarm_toggle_goes_through_update_alarm():
    s = read("shani/Modules/Clocks/ClocksWindow.qml")
    assert "WorldClock.updateAlarm(" in s
    assert "WorldClock.alarms[" not in s or ".enabled =" not in s


def test_guard_osk_paste_never_uses_a_shell():
    s = read("shani/Services/Osk.qml")
    body = source_of(s, "paste")
    assert '["wtype", "--", text]' in body
    assert "sh -c" not in body and "shell: true" not in body


def test_guard_files_panel_escape_is_accepted_once():
    s = read("shani/Modules/Files/FilesPanel.qml")
    m = re.search(r"\bGlass\s*\{\s*\n\s*id:\s*filterBox\b", s)
    assert m
    box = balanced(s, m.start())
    inner = re.search(r"Keys\.onEscapePressed:\s*([^\n]+)", box)
    assert inner and "toggleFilters" in inner.group(1)
    assert "event.accepted" in inner.group(1)
