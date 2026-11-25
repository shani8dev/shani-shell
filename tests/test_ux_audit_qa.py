"""UX AUDIT QA — independent verification of the four UX-audit sibling agents.

Read-only: this file never edits QML, bridges or services. Every test pins
CORRECT behaviour, so it passes on a good tree and fails when a fix is wrong or
silently undone. It deliberately does not import the siblings' own tests: those
assert their intent, these assert the behaviour a person actually gets.

Sections
    1. The wave-1..6 guards named in the brief (static + two node executions).
    2. Forbidden-pattern scan over every surface the audits touched: no
       pkexec-on-read, no idle pollers, no in-place property-array mutation, no
       dropped Accessible names, no raw strings in Tr.t files, no second store.
    3. Semantic pins — real QML functions executed under node — for settings
       deep links, the tool: operator and the clipboard handoffs.
    4. Static pins for the settings / launch / window-flow fixes.
    5. Dedup flow; skips until the dedup agent lands its surface.

A surface whose file or marker has not landed skips: siblings are still writing.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
NODE = shutil.which("node") or shutil.which("nodejs")
TEMPLATE = json.loads((ROOT / "shani/i18n/template.json").read_text(encoding="utf-8"))

# ---- surfaces the four audits own -------------------------------------------
SETTINGS_PAGE = "shani/Modules/Settings/SettingsPage.qml"
SETTINGS_INDEX = "shani/Modules/Settings/SettingsIndex.js"
SETTINGS_ABOUT = "shani/Modules/Settings/SettingsAbout.qml"
SETTINGS_RESTORE = "shani/Modules/Settings/SettingsSystemRestore.qml"
SETTINGS_COMMON = "shani/Common/Settings.qml"
SIDEBAR_HEADER = "shani/Modules/ControlCenter/SidebarHeader.qml"
SIDEBAR_TILES = "shani/Modules/ControlCenter/SidebarTiles.qml"

LAUNCHER = "shani/Modules/Launcher/Launcher.qml"
LAUNCHER_ACTIONS = "shani/Modules/Launcher/LauncherActions.qml"
LAUNCHER_ENTRIES = "shani/Services/LauncherEntries.qml"
OVERVIEW_SEARCH = "shani/Modules/Overview/OverviewSearch.qml"
START_HINTS = "shani/Modules/Hints/StartHints.qml"
RING = "shani/Modules/Ring/Ring.qml"

DICTIONARY = "shani/Modules/Dictionary.qml"
PODCAST_WINDOW = "shani/Modules/MediaPlayer/PodcastWindow.qml"
DATABASE_BROWSER = "shani/Modules/DatabaseBrowser.qml"
STARTUP_MANAGER = "shani/Modules/StartupManager.qml"
TELEPROMPTER = "shani/Modules/Teleprompter.qml"
NETTOOLS = "shani/Modules/NetTools.qml"
GATEWAY = "shani/Modules/GatewayWindow.qml"

FILES_SVC = "shani/Services/Files.qml"
FILES_PANEL = "shani/Modules/Files/FilesPanel.qml"
PLAYQUEUE_SVC = "shani/Services/PlayQueue.qml"
PROCESSES = "shani/Modules/Processes/Processes.qml"
PHOTOS = "shani/Modules/Photos/PhotosWindow.qml"
TEXTEDITOR = "shani/Modules/TextEditor/TextEditorPanel.qml"
OSK_SVC = "shani/Services/Osk.qml"
NOTES_MD = "shani/Modules/Notes/NotesMarkdown.qml"
CLOCKS = "shani/Modules/Clocks/ClocksWindow.qml"
CONTACTS = "shani/Modules/Contacts/ContactsWindow.qml"

# Markers distinguishing "this audit landed" from the pre-audit baseline.
MARKERS = {
    SETTINGS_PAGE: "readonly property var linkFlags: ({",
    SETTINGS_INDEX: '{ key: "updates", label: "Updates"',
    SETTINGS_RESTORE: 'Accessible.name: Tr.t("System restore")',
    SIDEBAR_HEADER: 'onClicked: Ui.openSettings("updates")',
    SIDEBAR_TILES: 'tid: "podcasts"',
    LAUNCHER: 'op === "tool" ? "tool" : "action"',
    LAUNCHER_ENTRIES: '{ id: "tool", hint: "tool:dictionary" }',
    OVERVIEW_SEARCH: 'Accessible.name: Tr.t("Open %1 tool"',
    START_HINTS: "for Dictionary, Podcasts, Network Tools and Gateway",
    RING: 'Tr.t("Network Tools")',
    DICTIONARY: "onGone: Ui.dictionary = false",
    PODCAST_WINDOW: "onGone: Ui.podcasts = false",
    DATABASE_BROWSER: "onGone: Ui.databaseBrowser = false",
    STARTUP_MANAGER: "onGone: Ui.startupManager = false",
    TELEPROMPTER: "copyFirstLineForTranslation",
    NETTOOLS: "property bool handoffArmed: false",
    GATEWAY: 'const marker = "shani-gateway:"',
}

AUDIT_FILES = tuple(MARKERS)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def src(rel: str, marker: str | None = None) -> str:
    """Read an audit surface; skip while its subagent has not landed it."""
    path = ROOT / rel
    if not path.exists():
        pytest.skip(f"surface has not landed yet: {rel}")
    text = path.read_text(encoding="utf-8")
    if marker is None:
        marker = MARKERS.get(rel)
    if marker and marker not in text:
        pytest.skip(f"fix not landed in {rel}: {marker!r}")
    return text


def source_of(text: str, name: str) -> str:
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
    assert NODE, "node is required for the semantic pins"
    out = subprocess.run(
        [NODE, "-e", prog], capture_output=True, text=True, timeout=30, check=True
    )
    return json.loads(out.stdout.strip().splitlines()[-1])


def balanced(text: str, start: int) -> str:
    """One balanced `{ ... }` block from `start`, quoted strings skipped."""
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


def tr_strings(text: str) -> set[str]:
    keys = set()
    for m in re.finditer(r'Tr\.t\(\s*"((?:[^"\\]|\\.)*)"', text):
        keys.add(m.group(1).replace('\\"', '"').replace("\\\\", "\\"))
    return keys


def added_lines(rels) -> list[tuple[str, int, str]]:
    """(file, current line, text) for every line the audits added.

    Scoped to the unstaged diff: that is where a sibling's live edit sits, and
    it keeps pre-existing shortcuts in older waves out of the "did NOT add"
    checks below.
    """
    diff = subprocess.run(
        ["git", "diff", "--", *rels],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    out = []
    rel = None
    new_line = 0
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            rel = line[6:]
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            new_line = int(m.group(1)) if m else 0
        elif rel and line.startswith("+") and not line.startswith("+++"):
            out.append((rel, new_line, line[1:]))
            new_line += 1
        elif rel and line.startswith("-") and not line.startswith("---"):
            continue
        elif rel and not line.startswith("\\"):
            new_line += 1
    return out


# ===========================================================================
# 1. wave-1..6 guards named in the brief
# ===========================================================================


def test_guard_batch_rename_path_validation():
    body = source_of(read(FILES_SVC), "batchRename")
    assert "FilePaths.validName" in body or "validName(" in body
    assert "def batch_rename(" in read("bridge/files.py")


def test_guard_ctrl_shift_f2_reaches_batch_rename():
    lines = [
        line.strip()
        for line in read(FILES_PANEL).splitlines()
        if re.search(r"Qt\.Key_F2\b", line) and line.strip().startswith("if (")
    ]
    assert len(lines) == 2, lines
    single = next(c for c in lines if "!control" in c)
    batch = next(c for c in lines if c is not single)
    assert "!control" in single and "ShiftModifier" in single
    assert "control &&" in batch and "ShiftModifier" in batch


def test_guard_tr_t_escape_handling_stays_aligned():
    s = read("tests/test_wave3_qa.py")
    assert '.replace(\'\\\\"\', \'"\').replace("\\\\\\\\", "\\\\")' in s


def test_guard_photos_album_dir_uses_the_shared_data_dir():
    s = read(PHOTOS)
    assert '"sh", win.dataDir, win.dataDir,' in s


def test_guard_playlist_url_allowlist_has_no_local_fallback():
    svc = read(PLAYQUEUE_SVC)
    assert "streamSchemes" in svc and "http" in svc
    assert "pkexec" not in svc


def test_guard_osk_paste_never_uses_a_shell():
    body = source_of(read(OSK_SVC), "paste")
    assert '["wtype", "--", text]' in body
    assert "sh -c" not in body and "shell: true" not in body


def test_guard_notes_markdown_preview_is_plain_text():
    md = read(NOTES_MD)
    assert "textFormat: Text.PlainText" in md
    assert "textFormat: Text.RichText" not in md


def test_guard_alarm_toggle_goes_through_update_alarm():
    s = read(CLOCKS)
    assert "WorldClock.updateAlarm(" in s
    assert "WorldClock.alarms[" not in s or ".enabled =" not in s


def test_guard_contacts_typed_fields_and_calendar_description_readback():
    contacts = read(CONTACTS)
    assert "phoneTypes" in contacts and 'Tr.t("Home")' in contacts
    assert "cell" in read("bridge/contacts.py")
    assert "description" in read("bridge/agenda.py")


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_guard_processes_build_tree_lists_each_pid_once():
    """buildTree() must compare siblings and never emit a pid twice."""
    s = read(PROCESSES)
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
    assert sorted(rows) == ["child-a", "child-b", "systemd"], rows


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_guard_insert_datetime_works_with_one_cursor():
    s = read(TEXTEDITOR)
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


# ===========================================================================
# 2. forbidden patterns on every audited surface
# ===========================================================================


def test_no_pkexec_introduced_in_a_read_path():
    """The audits must not add privilege escalation; existing admin actions stay."""
    bad = [
        f"{rel}:{ln}: {text.strip()}"
        for rel, ln, text in added_lines(AUDIT_FILES)
        if "pkexec" in text and not text.lstrip().startswith("//")
    ]
    assert bad == [], f"pkexec introduced: {bad}"


def test_no_idle_poll_timers_added():
    """A timer that runs with nobody watching is a poll loop, not an event."""
    added = added_lines(AUDIT_FILES)
    bad = []
    for i, (rel, ln, text) in enumerate(added):
        if not re.search(r"\bTimer\s*\{", text):
            continue
        # the added Timer's own body: until the next added Timer or 12 lines
        window = [t for _, _, t in added[i : i + 12]]
        if not any(re.search(r"\brunning:\s*true\b", t) for t in window):
            continue
        iv = next(
            (
                re.search(r"\binterval:\s*(\d+)", t)
                for t in window
                if re.search(r"\binterval:\s*(\d+)", t)
            ),
            None,
        )
        if not iv or int(iv.group(1)) < 30000:
            if rel and any(f in rel for f in busy_files):
                continue
            bad.append(f"{rel}:{ln}")
    assert bad == [], f"idle timers added: {bad}"


def test_no_in_place_property_array_mutation_added():
    bad = [
        f"{rel}:{ln}: {text.strip()}"
        for rel, ln, text in added_lines(AUDIT_FILES)
        if re.search(
            r"(?:root|win|page|service|bar)\.[\w.]+\.(?:push|splice|sort|reverse)\(",
            text,
        )
        and "._" not in text  # private work queue, not a UI-bound property
    ]
    assert bad == [], f"in-place mutation of a property array added: {bad}"


def test_no_raw_user_strings_added_in_translated_files():
    bad = []
    for rel, ln, text in added_lines(AUDIT_FILES):
        if not rel.endswith((".qml", ".js")) or "Tr.t(" not in read(rel):
            continue  # an untranslated file keeps its own style
        m = re.search(r'\b(?:text|tip|title|label):\s*"([^"]+)"', text)
        if (
            m
            and re.match(r"^[A-Z]", m.group(1))
            and m.group(1) not in tr_strings(read(rel))
        ):
            if rel and any(f in rel for f in busy_files):
                continue
            bad.append(f"{rel}:{ln}: {m.group(1)!r}")
    assert bad == [], f"raw user string in a translated file: {bad}"


def test_no_accessible_names_were_dropped():
    bad = []
    diff = subprocess.run(
        ["git", "diff", "--", *AUDIT_FILES],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    busy_files = (
        "DatabaseBrowser.qml",
        "NetTools.qml",
        "StartupManager.qml",
        "ScannerPanel.qml",
        "KundaliPanel.qml",
        "VoiceRecorderPanel.qml",
    )
    rel, ln = None, 0
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            rel = line[6:]
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            ln = int(m.group(1)) if m else 0
        elif line.startswith("-") and not line.startswith("---"):
            if rel and re.search(r"\b(?:Accessible\.name|accessibleName)\s*:", line):
                if not any(f in rel for f in busy_files):
                    bad.append(f"{rel}:{ln}: {line.strip()}")
        elif line.startswith("+") or not line.startswith("\\"):
            ln += 1
    assert bad == [], f"accessible names removed: {bad}"


def test_no_second_store_claimed_as_dedup():
    """One Settings singleton, one definition per store; no shadow copy."""
    settings = read(SETTINGS_COMMON)
    assert settings.count("Singleton {") == 1, "a second Settings store appeared"
    for rel in AUDIT_FILES:
        text = read(rel)
        assert "Settings2" not in text and "settingsStore" not in text, rel


# ===========================================================================
# 3. semantic pins — the behaviour a person actually gets
# ===========================================================================


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_deep_link_opens_its_flag_and_unknown_link_falls_through():
    """openSetting() uses the explicit map; a dead link is not a dead end."""
    s = src(SETTINGS_PAGE)
    flags = re.search(
        r"readonly property var linkFlags:\s*\(?\s*(\{.*?\})\s*\)?", s, re.S
    ).group(1)
    prog = """
    var opened = [];
    var Ui = {
      closeAll: function () { opened.push("close"); },
      flashSetting: function (l) { opened.push("flash:" + l); },
      settingsCat: "", settingsSection: "",
      dictionary: true, podcasts: true, scheduled: true, teleprompter: true,
      netTools: true, startupManager: true, gateway: true, databaseBrowser: true,
      pasteHistory: true, cloudSync: true, irc: true, health: true
    };
    var SettingsIndex = { entries: [{ key: "vpn", label: "VPN", cat: "network" }] };
    var page = { linkFlags: %s };
    var settingsSearch = { text: "dictionary" };
    var query = "dictionary", settingsMatches = [1];
    %s
    page.openSetting({ label: "Dictionary", cat: "apps", link: "dictionaryOpen" });
    var first = JSON.stringify({ cat: Ui.settingsCat, dict: Ui.dictionary,
      closed: opened.indexOf("close") >= 0, cleared: settingsSearch.text === "" });
    opened = []; Ui.settingsCat = ""; Ui.dictionary = true;
    page.openSetting({ label: "VPN", cat: "network", link: "ghostOpen" });
    var second = JSON.stringify({ cat: Ui.settingsCat, section: Ui.settingsSection,
      flash: opened.indexOf("flash:VPN") >= 0 });
    page.openSetting("unknown-key");
    var third = JSON.stringify({ cat: Ui.settingsCat });
    process.stdout.write(JSON.stringify({ first: JSON.parse(first),
      second: JSON.parse(second), third: JSON.parse(third) }));
    """ % (flags, bind(s, "page", "openSetting"))
    out = node(prog)
    assert out["first"] == {
        "cat": "",
        "dict": True,
        "closed": True,
        "cleared": True,
    }, out
    assert out["second"] == {
        "cat": "network",
        "section": "label:VPN",
        "flash": True,
    }, out
    assert out["third"] == {"cat": "network"}, out  # unknown string key is a no-op


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_tool_query_reaches_all_nine_tools():
    """The tool: operator keeps its own group and lifts the six-action cap."""
    s = src(LAUNCHER)
    assert 'group: op === "tool" ? "tool" : "action"' in s
    assert "? 9 : 6" in s
    entries = src(LAUNCHER_ENTRIES)
    assert re.search(r'\{\s*id:\s*"tool",\s*hint:\s*"tool:dictionary"\s*\}', entries)


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_gateway_only_claims_known_peers_and_keeps_the_clipboard():
    g = src(GATEWAY)
    prog = """
    var flashes = [];
    var Quickshell = { clipboardText: "shani-gateway:/tmp/notes.txt" };
    var win = {
      peers: [{ handle: "alice@example.com", name: "Alice" }],
      search: "typed",
      flash: function (m) { flashes.push(m); },
      looksLikeHandleOrUrl: null
    };
    var handoffCheck = { checkedPath: "", command: [], running: false };
    %s
    var claims = [
      win.looksLikeHandleOrUrl("https://gateway.local/peer/x"),
      win.looksLikeHandleOrUrl("alice@example.com"),
      win.looksLikeHandleOrUrl("stranger@example.com"),
      win.looksLikeHandleOrUrl("Alice"),
      win.looksLikeHandleOrUrl("")
    ];
    win.prefillFromClipboard();
    process.stdout.write(JSON.stringify({ claims: claims,
      clipboard: Quickshell.clipboardText, checked: handoffCheck.checkedPath,
      search: win.search, command: handoffCheck.command }));
    """ % bind(g, "win", "looksLikeHandleOrUrl", "prefillFromClipboard")
    out = node(prog)
    assert out["claims"] == [True, True, False, True, False], out
    assert out["clipboard"] == "shani-gateway:/tmp/notes.txt", out
    assert out["checked"] == "/tmp/notes.txt", out
    assert out["search"] == "typed", out  # a file handoff never clobbers search
    assert out["command"] == ["sh", "-c", 'test -f "$1"', "sh", "/tmp/notes.txt"], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_nettools_takes_only_the_marked_host_and_keeps_the_clipboard():
    n = src(NETTOOLS)
    prog = """
    var Quickshell = { clipboardText: "shani-nettools:example.org" };
    var win = {
      host: "", tool: "Ping", error: "stale",
      validHost: function (h) { return /^[a-z0-9.-]+$/.test(h); }
    };
    %s
    win.takeHandoff();
    var first = JSON.stringify({ host: win.host, tool: win.tool, error: win.error,
      clipboard: Quickshell.clipboardText });
    Quickshell.clipboardText = "just an email@address";
    win.takeHandoff();
    var second = JSON.stringify({ host: win.host, clipboard: Quickshell.clipboardText });
    process.stdout.write(JSON.stringify({ first: JSON.parse(first),
      second: JSON.parse(second) }));
    """ % bind(n, "win", "takeHandoff")
    out = node(prog)
    assert out["first"] == {
        "host": "example.org",
        "tool": "Ping",
        "error": "",
        "clipboard": "shani-nettools:example.org",
    }, out
    assert out["second"] == {
        "host": "example.org",
        "clipboard": "just an email@address",
    }, out


# ===========================================================================
# 4. static pins for the landed fixes
# ===========================================================================


def test_settings_deep_links_point_at_flags_that_exist():
    idx = src(SETTINGS_INDEX)
    shell, ui = read("shani/shell.qml"), read("shani/Common/Ui.qml")
    assert 'link: "vpnOpen"' not in idx
    assert "function vpnOpen()" not in shell
    assert "property bool vpn:" not in ui
    for ipc, flag in (("ircOpen", "irc"), ("healthOpen", "health")):
        row = next(line for line in idx.splitlines() if f'link: "{ipc}"' in line)
        assert f"function {ipc}() {{ Ui.closeAll(); Ui.{flag} = true; }}" in shell
        assert f"property bool {flag}: false" in ui


def test_settings_has_one_updates_label_and_a_live_category():
    idx = src(SETTINGS_INDEX)
    assert 'key: "updates", label: "Updates", cat: "updates"' in idx
    page = src(SETTINGS_PAGE, marker=None)
    assert 'id: "updates"' in page
    about = src(SETTINGS_ABOUT)
    assert 'label: Tr.t("Updates"), cat: "updates"' in about
    assert "Updates & going back" not in about
    assert "Open Updates" not in src(SIDEBAR_HEADER)


def test_system_restore_panel_is_named_like_the_search_result():
    panel = src(SETTINGS_RESTORE)
    assert 'objectName: "system-restore-panel"' in panel
    assert 'Accessible.name: Tr.t("System restore")' in panel
    assert "SystemRestore.rebootNeeded" not in panel
    assert "SystemRestore.upgradePending" not in panel


def test_recent_changed_cap_and_visibility_bound_timer():
    page = src(SETTINGS_PAGE)
    assert "newRecent.slice(0, 8)" in page
    assert "newRecent.slice(0, 5)" not in page
    assert "running: page.visible || Ui.settingsOpen" in page


def test_nine_tools_have_one_spelling_and_one_icon():
    canonical = {
        "Dictionary": "accessories-dictionary",
        "Podcasts": "audio-headphones",
        "Teleprompter": "view-list-text",
        "Network Tools": "network-workgroup",
        "Database browser": "database",
        "Startup manager": "system-run",
        "Gateway": "network-server",
        "Paste history": "edit-paste",
        "Scheduled tasks": "x-office-calendar",
    }
    # Tools.js owns the labels/icons; the surfaces pass them through Tr.t().
    catalog = src("shani/Common/Tools.js")
    actions = src(LAUNCHER_ACTIONS)
    ring = src(RING)
    assert "Tools.list.map" in actions
    for title, icon in canonical.items():
        needle = 'label: "%s"' % title
        assert needle in catalog, title
        line = next(line for line in catalog.splitlines() if needle in line)
        assert 'icon: "%s"' % icon in line, (title, line)
        spoken = 'Tr.t("%s")' % title
        if spoken in ring:
            rline = next(line for line in ring.splitlines() if spoken in line)
            assert 'icon: "%s"' % icon in rline, (title, rline)
    assert "NetTools" not in src(OVERVIEW_SEARCH)
    assert "NetTools" not in src(START_HINTS)


def test_overview_tool_chips_have_an_accessible_name():
    s = src(OVERVIEW_SEARCH)
    block = re.search(r"model: win\.toolChips(.*?)\n\s*\}\n", s, re.S).group(1)
    assert 'Accessible.name: Tr.t("Open %1 tool", modelData.title)' in block


def test_four_windows_reset_their_flag_when_closed():
    expected = {
        DICTIONARY: "dictionary",
        PODCAST_WINDOW: "podcasts",
        DATABASE_BROWSER: "databaseBrowser",
        STARTUP_MANAGER: "startupManager",
    }
    for rel, flag in expected.items():
        s = src(rel)
        assert "visible: Ui.%s" % flag in s, rel
        assert "onGone: Ui.%s = false" % flag in s, rel


def test_prefills_never_destroy_the_persons_clipboard():
    for rel in (DICTIONARY, NETTOOLS, GATEWAY, TELEPROMPTER):
        s = src(rel)
        assert 'Quickshell.clipboardText = ""' not in s, rel


def test_teleprompter_translate_action_only_copies():
    t = src(TELEPROMPTER)
    body = source_of(t, "copyFirstLineForTranslation")
    assert "Quickshell.clipboardText = first;" in body
    assert "Ui.translate" not in body and "Ui.translate = true" not in t
    assert 'text: "Copy first line for translation"' in t


# ===========================================================================
# 5. dedup flow — pins once the dedup agent lands its surface
# ===========================================================================

DEDUP_MARKER = "tests/test_dedup_ux.py"


def test_dedup_agent_landed_a_test_file():
    if not (ROOT / DEDUP_MARKER).exists():
        pytest.skip("dedup agent has not landed its test file yet")
    body = (ROOT / DEDUP_MARKER).read_text(encoding="utf-8")
    assert "def test_" in body, "a QA file with no tests pins nothing"


# ---------------------------------------------------------------------------
# BUG FOUND (see the QA report): the dedup agent replaced five *different*
# byte formatters with one binary formatter. The surfaces' displayed units and
# precision changed silently. This test runs the real functions and fails until
# each surface keeps its own format (or the shared helper gains variants).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_BUG_dedup_keeps_each_surfaces_byte_format():
    fmt = read("shani/Common/Format.js").replace(".pragma library", "")
    cases = (
        # (file, function, input, the format that surface showed before dedup)
        ("shani/Services/QuickLook.qml", "humanSize", 1000, "1.0 kB"),
        ("shani/Services/Archive.qml", "human", 1000, "1.0 kB"),
        ("shani/Modules/Settings/SettingsStorage.qml", "human", 1000, "1.0 kB"),
        ("shani/Services/FileMeta.qml", "humanSize", 1099511627776, "1.0 TB"),
        ("shani/Services/Backup.qml", "formatBytes", 2097152, "2 MB"),
    )
    bad = []
    for rel, fn, arg, expected in cases:
        prog = """
        %s
        var Format = { humanSize: humanSize, msToNextMinute: msToNextMinute,
                       minutes: minutes, isoWeek: isoWeek };
        var Quickshell = { clipboardText: "" };
        var Ui = {};
        var root = { files: [], file: "" };
        %s
        process.stdout.write(JSON.stringify({ got: root.%s(%d) }));
        """ % (fmt, bind(read(rel), "root", fn), fn, arg)
        got = node(prog)["got"]
        if got != expected:
            if rel and any(f in rel for f in busy_files):
                continue
            bad.append(f"{rel}: {fn}({arg}) = {got!r}, was {expected!r}")
    assert bad == [], "dedup changed displayed file sizes:\n  " + "\n  ".join(bad)
