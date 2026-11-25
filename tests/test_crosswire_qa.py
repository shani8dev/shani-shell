"""Cross-wiring QA — read-only regression pins for the surfaces that hand data
from one app to another, plus a re-check of the wave-1..6 fixes they rely on.

Surfaces: Files -> apps (open-with routing), apps -> Files (reveal),
Productivity (Notes <-> Calendar <-> Contacts <-> Teleprompter),
Sessions / SpeedDial / Launcher / Dock, and the media chain
(Player -> Files, Share -> Gateway, Files -> Database Browser, screenshots).

Everything here pins CORRECT behaviour: it passes on good code and fails when a
fix is undone. The one exception is the "Bugs" section, which fails on the code
as it stands and names the exact file:line and the fix. No QML is edited.

A surface whose file has not landed yet skips: sibling agents are still writing
these, and a test must not fail just because a file has not arrived.
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

UI = "shani/Common/Ui.qml"
SHELL = "shani/shell.qml"
FILES_SVC = "shani/Services/Files.qml"
FILES_PANEL = "shani/Modules/Files/FilesPanel.qml"
VIEWER = "shani/Modules/Viewer/Viewer.qml"
VIEWER_SVC = "shani/Services/Viewer.qml"
PHOTOS = "shani/Modules/Photos/PhotosWindow.qml"
ARCHIVES = "shani/Modules/Archives/ArchivesWindow.qml"
MEDIA = "shani/Modules/MediaPlayer/MediaPlayerWindow.qml"
PDF = "shani/Modules/PdfReader/PdfReader.qml"
NOTES = "shani/Modules/Notes/NotesPanel.qml"
QUICKNOTES_SVC = "shani/Services/QuickNotes.qml"
CALENDAR = "shani/Modules/Calendar/CalendarPanel.qml"
AGENDA_SVC = "shani/Services/Agenda.qml"
CONTACTS_SVC = "shani/Services/Contacts.qml"
SESSIONS_SVC = "shani/Services/Sessions.qml"
SESSIONS_JS = "shani/Services/Sessions.js"
SPEEDDIAL_SVC = "shani/Services/SpeedDial.qml"
SPEEDDIAL_JS = "shani/Services/SpeedDial.js"
LAUNCHER = "shani/Modules/Launcher/Launcher.qml"
DOCK = "shani/Modules/Dock/Dock.qml"
SHARE_SVC = "shani/Services/Share.qml"
GATEWAY = "shani/Modules/GatewayWindow.qml"
DATABASE = "shani/Modules/DatabaseBrowser.qml"
NETTOOLS = "shani/Modules/NetTools.qml"
TELEPROMPTER = "shani/Modules/Teleprompter.qml"
SCREENSHOTS_SVC = "shani/Services/Screenshots.qml"
LAUNCHER_ACTIONS = "shani/Modules/Launcher/LauncherActions.qml"
PLAYQUEUE_SVC = "shani/Services/PlayQueue.qml"
CAMERA_SVC = "shani/Services/Camera.qml"
TEXTEDITOR = "shani/Modules/TextEditor/TextEditorPanel.qml"
PROCESSES = "shani/Modules/Processes/Processes.qml"
CLOCKS = "shani/Modules/Clocks/ClocksWindow.qml"
OSK_SVC = "shani/Services/Osk.qml"
NOTES_MD = "shani/Modules/Notes/NotesMarkdown.qml"

# Files that must land for the cross-wire surfaces under test.
CROSSWIRE_QML = (
    UI,
    FILES_SVC,
    FILES_PANEL,
    VIEWER,
    PHOTOS,
    ARCHIVES,
    MEDIA,
    PDF,
    NOTES,
    CALENDAR,
    SPEEDDIAL_SVC,
    LAUNCHER,
    DOCK,
    SHARE_SVC,
    GATEWAY,
    DATABASE,
    NETTOOLS,
    TELEPROMPTER,
)
# A handoff marker only exists once its sibling agent's surface has landed.
MARKERS = {
    FILES_PANEL: "function openNetTools(",
    VIEWER: "win.reveal(Viewer.file)",
    PHOTOS: "function reveal(path)",
    ARCHIVES: 'Tr.t("Show in Files")',
    MEDIA: "function reveal()",
    PDF: "win.reveal(PdfViewer.file)",
    NOTES: "function followWikiLink(",
    CALENDAR: "function noteForEvent(",
    LAUNCHER: "Ui.pasteHistory = true",
    SHARE_SVC: "function sendToGatewayPeer(",
    GATEWAY: "function prefillFromClipboard(",
    DATABASE: "onVisibleChanged",
    NETTOOLS: "function takeHandoff(",
    TELEPROMPTER: "function prefillFromClipboard(",
}


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def src(rel: str, marker: str | None = None) -> str:
    """Read a cross-wire file; skip while its subagent has not landed it."""
    path = ROOT / rel
    if not path.exists():
        pytest.skip(f"cross-wire file has not landed yet: {rel}")
    text = path.read_text(encoding="utf-8")
    if marker is None:
        marker = MARKERS.get(rel)
    if marker and marker not in text:
        pytest.skip(f"cross-wire surface not landed in {rel}: {marker!r}")
    return text


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


def line_of(text: str, needle: str) -> int:
    return next(
        (i for i, line in enumerate(text.splitlines(), 1) if needle in line), -1
    )


# ---------------------------------------------------------------------------
# Bugs — FAIL on the code as it stands. Each names the exact file:line and fix.
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_bug_files_nettools_handoff_takes_the_host_not_the_username():
    """FilesPanel.qml:384 (hostFromUri).

    Files -> Network Tools writes a `shani-nettools:<host>` clipboard marker.
    hostFromUri() strips the scheme then splits on `[/?#@]` and keeps element 0,
    so a URI with userinfo yields the *user name*, not the host:

        sftp://user@router.local/share  -> "user"
        https://user:pw@example.com/x   -> "user:pw"

    networkPathHost() accepts that (isNetHost("user") is true), openNetTools()
    writes it, and NetTools.takeHandoff() validates it and pings "user" instead
    of the router. Fix: discard userinfo before taking the host, e.g. add
    `s = s.replace(/^[^@]*@/, "");` after the scheme is stripped (before the
    split), so the value after the last `@` is the host that is probed.
    """
    s = src(FILES_PANEL)
    prog = """
    var win = {};
    %s
    process.stdout.write(JSON.stringify({
      a: win.hostFromUri("sftp://user@router.local/share"),
      b: win.hostFromUri("https://user:pw@example.com:8080/x"),
      c: win.hostFromUri("smb://nas.example.com/Share")
    }));
    """ % bind(s, "win", "hostFromUri")
    out = node(prog)
    assert out == {
        "a": "router.local",
        "b": "example.com",
        "c": "nas.example.com",
    }, (
        "FilesPanel.qml:384 — a URI with userinfo must hand its host to Network "
        "Tools, not the user name: " + repr(out)
    )


# ---------------------------------------------------------------------------
# Files -> apps: open-with routing (correct behaviour).
# ---------------------------------------------------------------------------


def test_ui_open_files_with_guards_empty_and_uses_positional_argv():
    body = source_of(read(UI), "openFilesWith")
    assert "!appId || !files.length" in body
    assert '"sh", appId].concat(files)' in body, "paths must be argv, not script text"
    assert "pkexec" not in body
    # no app id or path is concatenated onto the `sh -c` script literal
    assert not re.search(r"'\s*\+\s*[A-Za-z_$]", body), (
        "a value is spliced into the script"
    )


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_ui_open_files_with_runs_gio_launch_with_the_paths_as_argv():
    s = read(UI)
    prog = """
    var calls = [];
    var Quickshell = { execDetached: function (a) { calls.push(a); } };
    var Ui = {};
    %s
    Ui.openFilesWith("", ["/a"]);
    Ui.openFilesWith("app.desktop", []);
    Ui.openFilesWith("app.desktop", ["/a", "/b"]);
    process.stdout.write(JSON.stringify(calls));
    """ % bind(s, "Ui", "openFilesWith")
    calls = node(prog)
    assert len(calls) == 1, "empty app id / empty file list must be no-ops"
    argv = calls[0]
    assert argv[0] == "sh" and argv[1] == "-c", argv
    assert "gio launch" in argv[2]
    assert argv[-4:] == ["sh", "app.desktop", "/a", "/b"], argv


def test_files_open_with_forwards_to_ui_with_selection_fallback():
    body = source_of(read(FILES_SVC), "openWith")
    assert "Ui.openFilesWith(appId," in body
    assert "root.selected.slice()" in body


def test_shell_ipc_open_files_with_wraps_a_single_file():
    s = read(SHELL)
    assert "function openFilesWith(app: string, file: string)" in s
    assert "Ui.openFilesWith(app, [file]);" in s


def test_dock_drop_decodes_file_urls_before_open_files_with():
    s = read(DOCK)
    assert "decodeURIComponent(" in s
    assert "Ui.openFilesWith(cell.modelData.entry.id, files);" in s


def test_viewer_open_with_uses_the_same_routing_helper():
    body = source_of(read(VIEWER_SVC), "openWith")
    assert "Ui.openFilesWith(appId, [file])" in body
    assert '["gio", "open", root.file]' in body


# ---------------------------------------------------------------------------
# apps -> Files: reveal (correct behaviour).
# ---------------------------------------------------------------------------


# The reveal handoff may live in Files itself (`Files.reveal`) or, after the
# Files->apps routing refactor, as a small `win.reveal` in each viewer. Pin the
# observable behaviour, not the file it happens to be written in.
REVEAL_IMPLEMENTATIONS = (
    (FILES_SVC, "root"),
    (VIEWER, "win"),
    (PHOTOS, "win"),
    (PDF, "win"),
    (MEDIA, "win"),
)


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_reveal_shows_the_dir_and_selects_the_file():
    checked = 0
    for rel, obj in REVEAL_IMPLEMENTATIONS:
        path = ROOT / rel
        if not path.exists():
            continue
        s = path.read_text(encoding="utf-8")
        if "function reveal(" not in s:
            continue
        prog = """
        var calls = [];
        var Files = {
          show: function (d) { calls.push(["show", d]); },
          select: function (p, m) { calls.push(["select", p, m]); }
        };
        var root = Files;
        var win = {};
        var PlayQueue = { isStream: false, current: "" };
        %s
        // feed() covers both shapes: reveal(path) uses the argument, while
        // reveal() in the media player reads PlayQueue.current.
        function feed(p) { PlayQueue.current = p; %s.reveal(p); }
        feed("/home/u/Pictures/a.jpg");
        feed("/x");
        feed("http://host/y");
        process.stdout.write(JSON.stringify(calls));
        """ % (bind(s, obj, "reveal"), obj)
        out = node(prog)
        assert out == [
            ["show", "/home/u/Pictures"],
            ["select", "/home/u/Pictures/a.jpg", "single"],
            ["show", "/"],
            ["select", "/x", "single"],
        ], (
            f"{rel}: reveal must show the parent folder and single-select the file: {out}"
        )
        checked += 1
    assert checked >= 1, "no reveal implementation has landed yet"


@pytest.mark.parametrize("rel", (VIEWER, PHOTOS, ARCHIVES, MEDIA, PDF))
def test_local_viewers_have_a_reveal_handoff(rel):
    s = src(rel)
    # a local win.reveal(), or a direct Files.reveal() call, is acceptable
    assert "function reveal(" in s or "Files.reveal(" in s, (
        f"{rel}: reveal handoff missing"
    )


def test_media_player_reveal_refuses_streams():
    s = src(MEDIA)
    body = source_of(s, "reveal")
    assert "PlayQueue.isStream" in body and "PlayQueue.current" in body


def test_reveal_controls_are_translated_and_guarded():
    for rel in (VIEWER, PDF, MEDIA, ARCHIVES):
        s = src(rel)
        assert 'Tr.t("Show in Files")' in s, f"{rel}: untranslated reveal control"
        assert "reveal(" in s, f"{rel}: reveal control has no handler"


def test_ctrl_l_reveal_is_available_in_each_local_viewer():
    for rel in (VIEWER, ARCHIVES, PDF, MEDIA):
        s = src(rel)
        lines = [
            ln for ln in s.splitlines() if "Qt.Key_L" in ln and "ControlModifier" in ln
        ]
        assert lines, f"{rel}: Ctrl+L reveal shortcut missing"


# ---------------------------------------------------------------------------
# Productivity: Notes <-> Calendar <-> Contacts <-> Teleprompter.
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_notes_wiki_link_target_routes_date_contact_and_plain_note():
    s = src(NOTES)
    prog = """
    var Services = { Contacts: { contacts: [ { name: "Ada Lovelace", uid: "u1" } ] } };
    var win = {};
    %s
    process.stdout.write(JSON.stringify({
      date: win.wikiLinkTarget("2026-11-25"),
      contact: win.wikiLinkTarget("ada lovelace"),
      note: win.wikiLinkTarget("Some Note")
    }));
    """ % bind(s, "win", "wikiLinkTarget")
    out = node(prog)
    assert out["date"]["kind"] == "date" and "when" in out["date"]
    assert out["contact"] == {"kind": "contact", "label": "Ada Lovelace", "uid": "u1"}
    assert out["note"] == {"kind": "note", "label": "Some Note"}


def test_notes_follow_wiki_link_dispatches_to_each_surface():
    body = source_of(src(NOTES), "followWikiLink")
    assert "Services.Agenda.openCalendar()" in body
    assert "Services.Agenda.showDay(target.when)" in body
    assert "Ui.openContacts()" in body
    assert "Services.Contacts.selected = c" in body
    assert "Services.QuickNotes.jumpTo(name)" in body


def test_notes_link_delegate_has_a_translated_accessible_name():
    s = src(NOTES)
    assert 'Accessible.name: Tr.t("Follow the link %1").arg(modelData)' in s


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_calendar_event_note_body_carries_date_location_and_description():
    s = src(CALENDAR)
    prog = r"""
var Time = {
  clockPadded: function(t){ t=String(t||""); return t.length>=5?t:t.padStart(5,"0"); },
  dayKey: function(when){ var d=when instanceof Date?when:typeof when==="string"?new Date(when):new Date(Number(when)||Date.now()); if(!d||isNaN(d.getTime())) return ""; return d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0"); },
  clock: function(s){ s=Number(s)||0; return Math.floor(s/60)+":"+String(Math.floor(s%60)).padStart(2,"0"); },
  hhmmss: function(s){ s=Number(s)||0; return String(Math.floor(s/3600)).padStart(2,"0")+":"+String(Math.floor(s%3600/60)).padStart(2,"0")+":"+String(Math.floor(s%60)).padStart(2,"0"); }
};
    var Tr = { t: function (x) { return x; } };
    var win = {};
    """ + bind(s, "win", "isoDay", "eventNoteBody") + r"""
    var body = win.eventNoteBody({ summary: "Standup", start: 1764000000,
                                   location: "Room 1", description: "agenda" });
    process.stdout.write(JSON.stringify({ body: body, day: win.isoDay(1764000000000) }));
    """
    out = node(prog)
    assert out["body"].startswith("# Standup")
    assert "[[%s]]" % out["day"] in out["body"]
    assert "- Location: Room 1" in out["body"]
    assert "agenda" in out["body"]


def test_calendar_event_to_note_reuses_an_existing_note():
    s = src(CALENDAR)
    body = source_of(s, "noteForEvent")
    assert "Ui.openNotes()" in body
    assert "QuickNotes.notes.some(" in body
    assert 'QuickNotes.open(name, "")' in body, (
        "existing note is opened, not overwritten"
    )
    assert 'QuickNotes.create(name, "")' in body
    assert "noteFill.restart()" in body
    # the loader-retry timer is bounded and documented as a shortcut
    assert "shortcut:" in s


def test_calendar_add_note_control_has_a_translated_accessible_name():
    s = src(CALENDAR)
    assert 'Accessible.name: Tr.t("Add a note for this event")' in s


def test_notes_present_hands_the_open_note_to_teleprompter():
    s = src(NOTES)
    body = source_of(s, "presentNote")
    assert 'Services.QuickNotes.current === ""' in body
    assert "Quickshell.clipboardText = Services.QuickNotes.text" in body
    assert "Ui.teleprompter = true" in body
    tp = src(TELEPROMPTER)
    assert "onVisibleChanged: if (visible) win.prefillFromClipboard()" in tp


def test_agenda_signal_pairs_with_the_calendar_listener():
    assert "signal showDay(real when)" in read(AGENDA_SVC)
    assert "function onShowDay(when)" in src(CALENDAR)


# ---------------------------------------------------------------------------
# Sessions / SpeedDial / Launcher / Dock.
# ---------------------------------------------------------------------------


def test_speed_dial_open_probes_with_a_positional_argv_and_routes_both_ways():
    s = src(SPEEDDIAL_SVC)
    body = source_of(s, "open")
    assert "Logic.canonical(path, root.home)" in body
    assert 'probe.command = ["sh", "-c",' in body and ', "sh", p]' in body
    tail = s[s.index("id: probe") :]
    assert "Files.show(p)" in tail and '["xdg-open", p]' in tail


def test_sessions_capture_is_deduplicated_and_bounded():
    s = read(SESSIONS_SVC)
    body = source_of(s, "captureCurrent")
    assert "Logic.capped(apps)" in body and "Logic.capped(paths)" in body
    assert "indexOf(s) < 0" in body, "paths are deduplicated before saving"
    assert "Reopen.reopen(s.apps)" in read(SESSIONS_SVC)
    assert "function capped(" in read(SESSIONS_JS)


def test_launcher_clipboard_mode_reaches_paste_history():
    s = read(LAUNCHER)
    assert 'title: Tr.t("Clipboard history")' in s
    assert "Ui.closeAll(); Ui.pasteHistory = true;" in s


def test_dock_and_ipc_share_one_open_files_with_entry_point():
    assert "Ui.openFilesWith(cell.modelData.entry.id, files);" in read(DOCK)
    assert "Ui.openFilesWith(app, [file]);" in read(SHELL)


# ---------------------------------------------------------------------------
# Media chain: Player / Share / Gateway / Database Browser / screenshots.
# ---------------------------------------------------------------------------


def test_share_send_to_gateway_uses_a_clipboard_handoff():
    s = src(SHARE_SVC)
    body = source_of(s, "sendToGatewayPeer")
    assert 'Quickshell.clipboardText = "shani-gateway:" + fs[0]' in body
    assert "Ui.closeAll();" in body and "Ui.gateway = true" in body
    assert "if (!fs.length) return false;" in body
    gw = src(GATEWAY)
    prefetch = source_of(gw, "prefillFromClipboard")
    # the marker is validated with an argv-only `test -f` before pendingFile is set
    assert 'const marker = "shani-gateway:"' in prefetch
    assert "handoffCheck.checkedPath = path" in prefetch


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_share_link_encodes_the_path_and_refuses_an_empty_selection():
    s = src(SHARE_SVC)
    prog = """
    var root = { file: "/pics/a b.jpg" };
    %s
    var good = root.shareLink();
    root.file = "";
    var empty = root.shareLink();
    process.stdout.write(JSON.stringify({ good: good, empty: empty }));
    """ % bind(s, "root", "shareLink")
    out = node(prog)
    assert out["good"] == "https://gateway.local/share/%2Fpics%2Fa%20b.jpg", out
    assert out["empty"] == ""


def test_files_database_browser_handoff_uses_a_declared_app_flag():
    s = src(FILES_PANEL)
    assert 'Tr.t("Open in Database Browser")' in s
    assert "Quickshell.clipboardText = e.path" in s
    assert "Files.hide(); Ui.closeAll(); Ui.databaseBrowser = true;" in s
    db = src(DATABASE)
    assert "win.dbPath = seed" in db
    assert "\\.(db|sqlite|sqlite3)$/i.test(seed)" in db


def test_nettools_handoff_is_marker_gated_and_validated():
    s = src(NETTOOLS)
    body = source_of(s, "takeHandoff")
    assert 'const marker = "shani-nettools:"' in body
    assert "raw.indexOf(marker) !== 0" in body
    assert "win.validHost(host)" in body
    assert (
        'Quickshell.clipboardText = ""' not in body
    )  # never destroy the user's clipboard


def test_screenshots_and_recorder_reach_share_and_launcher():
    assert "Share.open(p)" in read(SCREENSHOTS_SVC)
    a = read(LAUNCHER_ACTIONS)
    assert "Screenshots.togglePin(Screenshots.last)" in a
    assert "Recorder.toggle()" in a


# ---------------------------------------------------------------------------
# Guard classes from waves 1-6, re-checked on every cross-wire surface.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("rel", [r for r in CROSSWIRE_QML if r != LAUNCHER])
def test_crosswire_status_reads_never_use_pkexec(rel):
    """Launcher's runAdmin() is the shell's privileged command runner and may
    use pkexec; none of the handoff / read paths may."""
    try:
        s = read(rel)
    except FileNotFoundError:
        pytest.skip(f"cross-wire file has not landed yet: {rel}")
    assert "pkexec" not in s, f"{rel}: pkexec in a read/status path"


def test_crosswire_property_arrays_are_reassigned_not_mutated():
    """A UI-bound property array must be replaced, not pushed/spliced in place.

    Work queues are exempt: they are private sequential state, not a model.
    """
    bad = []
    for rel in CROSSWIRE_QML:
        path = ROOT / rel
        if not path.exists():
            continue
        s = path.read_text(encoding="utf-8")
        for m in re.finditer(
            r"\b(?:root|win|Ui|Files|QuickNotes|Sessions)\.(selected|files|notes|recent|results|peers|apps|paths)\.(?:push|splice|sort|reverse|shift)\(",
            s,
        ):
            bad.append(f"{rel}:{s.count(chr(10), 0, m.start()) + 1}: {m.group(0)}")
    assert bad == [], "in-place mutation of a property array: " + repr(bad)


@pytest.mark.parametrize("rel", CROSSWIRE_QML)
def test_crosswire_no_idle_poll_timers(rel):
    """Only long rollover timers may run while nothing else needs them."""
    path = ROOT / rel
    if not path.exists():
        pytest.skip(f"cross-wire file has not landed yet: {rel}")
    s = path.read_text(encoding="utf-8")
    bad = []
    for m in re.finditer(r"\bTimer\s*\{", s):
        i = s.index("{", m.start())
        depth = 0
        quote = None
        end = None
        for j in range(i, len(s)):
            c = s[j]
            if quote:
                if c == quote:
                    quote = None
                continue
            if c in ('"', "'"):
                quote = c
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    end = j
                    break
        block = s[i : end or len(s)]
        if not re.search(r"\brunning:\s*true\b", block):
            continue
        iv = re.search(r"\binterval:\s*(\d+)", block)
        if not iv or int(iv.group(1)) < 30000:
            bad.append(s.count("\n", 0, m.start()) + 1)
    assert bad == [], f"{rel}: idle timers at lines {bad}"


def test_crosswire_shell_commands_pass_user_values_as_argv():
    """The new handoffs never splice a person's path/host into `sh -c` text."""
    for rel in (FILES_PANEL, SPEEDDIAL_SVC, SESSIONS_SVC, SHARE_SVC):
        s = read(rel)
        for m in re.finditer(r'\["sh",\s*"-c"', s):
            block = s[m.start() : m.start() + 600]
            assert ', "sh", ' in block or '"sh"].concat(' in block, (
                f"{rel}: no positional argv separator"
            )


def test_crosswire_new_controls_have_accessible_names():
    needles = {
        FILES_PANEL: 'Accessible.name: Tr.t("Check host in Network Tools")',
        NOTES: 'Accessible.name: Tr.t("Follow the link %1").arg(modelData)',
        CALENDAR: 'Accessible.name: Tr.t("Add a note for this event")',
    }
    for rel, needle in needles.items():
        assert needle in src(rel), f"{rel}: missing translated accessible name"


def test_crosswire_new_strings_are_translated():
    """The cross-wire rows/controls use Tr.t, not raw English literals."""
    for rel, needles in {
        FILES_PANEL: (
            'text: Tr.t("Network tools")',
            'Tr.t("Open in Database Browser")',
        ),
        LAUNCHER: ('title: Tr.t("Clipboard history")', 'title: Tr.t("Paste history")'),
        SHARE_SVC: ('Tr.t("Copy as share link")', 'Tr.t("Send to gateway peer")'),
        MEDIA: ('tip: Tr.t("Show in Files")',),
        GATEWAY: ('Tr.t("File ready to send: %1")',),
    }.items():
        s = src(rel)
        for needle in needles:
            assert needle in s, f"{rel}: untranslated / missing string {needle!r}"


# ---------------------------------------------------------------------------
# Re-check of the wave-1..6 fixes named in the QA brief.
# ---------------------------------------------------------------------------


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


def test_guard_tr_t_escape_handling_stays_aligned():
    s = read("tests/test_wave3_qa.py")
    assert '.replace(\'\\\\"\', \'"\').replace("\\\\\\\\", "\\\\")' in s


def test_guard_alarm_toggle_goes_through_update_alarm():
    s = read(CLOCKS)
    assert "WorldClock.updateAlarm(" in s
    assert "WorldClock.alarms[" not in s or ".enabled =" not in s


def test_guard_osk_paste_never_uses_a_shell():
    body = source_of(read(OSK_SVC), "paste")
    assert '["wtype", "--", text]' in body
    assert "sh -c" not in body and "shell: true" not in body


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_guard_processes_build_tree_lists_each_pid_once():
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


def test_guard_notes_markdown_preview_is_plain_text():
    md = read(NOTES_MD)
    assert "textFormat: Text.PlainText" in md
    assert "textFormat: Text.RichText" not in md


def test_guard_photos_album_dir_uses_the_shared_data_dir():
    s = read(PHOTOS)
    # the real writer passes win.dataDir for both the mkdir and albums.json slots
    assert '"sh", win.dataDir, win.dataDir,' in s, (
        "album writes go to the same dir the lister reads"
    )


def test_guard_contacts_typed_fields_and_calendar_description_readback():
    contacts = read("shani/Modules/Contacts/ContactsWindow.qml")
    assert "phoneTypes" in contacts and 'Tr.t("Home")' in contacts
    assert read("bridge/contacts.py").find("cell") >= 0
    assert "description" in read("bridge/agenda.py")


def test_guard_playlist_url_allowlist_has_no_local_fallback():
    svc = read(PLAYQUEUE_SVC)
    assert "streamSchemes" in svc and "http" in svc
    assert "pkexec" not in svc
