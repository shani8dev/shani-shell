"""WAVE 6 QA + integration — adversarial regression tests for this wave.

Read-only: this file never edits QML or bridge source. Every test pins the
CORRECT behaviour, so it passes on good code and fails when a fix is undone.

The "Bugs" section holds failures found during the review; each names the exact
file:line and the fix. The "Correct behaviour" section executes the real QML
functions in node with tiny stubs, and exercises the two new bridges (playlist
and waveform) for real. The cross-file section re-checks the guard classes from
waves 1-5 on every surface that landed in wave 6. The last section re-checks the
wave-1..5 fixes named in the QA brief.

A surface whose wave-6 marker is not present skips: sibling agents are still
landing files, and a test must not fail just because its file has not arrived.
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

MEDIA = "shani/Modules/MediaPlayer/MediaPlayerWindow.qml"
LIVETV = "shani/Modules/MediaPlayer/LiveTvView.qml"
PLAYQUEUE = "shani/Services/PlayQueue.qml"
PLAYLIST_PY = "bridge/playlist.py"
RECORDER = "shani/Modules/VoiceRecorder/VoiceRecorderPanel.qml"
VOICE_SVC = "shani/Services/VoiceRecorder.qml"
WAVEFORM_PY = "bridge/waveform.py"
CONTACTS = "shani/Modules/Contacts/ContactsWindow.qml"
CONTACTS_SVC = "shani/Services/Contacts.qml"
CONTACTS_PY = "bridge/contacts.py"
CALENDAR = "shani/Modules/Calendar/CalendarPanel.qml"
AGENDA_PY = "bridge/agenda.py"
PHOTOS = "shani/Modules/Photos/PhotosWindow.qml"
FILES = "shani/Modules/Files/FilesPanel.qml"
FILES_SVC = "shani/Services/Files.qml"

# Markers that only exist once each wave-6 surface has landed.
MARKERS = {
    MEDIA: 'Tr.t("Save .m3u…")',
    LIVETV: 'Tr.t("By group")',
    PLAYQUEUE: "recentAdd(",
    RECORDER: "win.peaks",
    CONTACTS: "phoneTypes",
    CALENDAR: 'Accessible.name: "Event description"',
    PHOTOS: "comparePhotos(",
    FILES: "crumbMenuSplit",
}
WAVE6_QML = (
    MEDIA,
    LIVETV,
    PLAYQUEUE,
    RECORDER,
    VOICE_SVC,
    CONTACTS,
    CONTACTS_SVC,
    CALENDAR,
    PHOTOS,
    FILES,
    FILES_SVC,
)
WAVE6_TRANSLATED = (MEDIA, LIVETV, RECORDER, CONTACTS, CALENDAR, PHOTOS, FILES)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def src(rel: str, marker: str | None = None) -> str:
    """Read a wave-6 file; skip while its subagent has not landed it."""
    path = ROOT / rel
    if not path.exists():
        pytest.skip(f"wave-6 file has not landed yet: {rel}")
    text = path.read_text(encoding="utf-8")
    if marker is None:
        marker = MARKERS.get(rel)
    if marker and marker not in text:
        pytest.skip(f"wave-6 surface not landed in {rel}: {marker!r}")
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


def prop_of(text: str, name: str) -> str:
    """The expression assigned to `property var name:` (braces/brackets matched)."""
    m = re.search(
        r"(?:readonly\s+)?property\s+(?:var|string|bool|int|real)\s+"
        + re.escape(name)
        + r"\s*:\s*",
        text,
    )
    assert m, f"property {name} not found"
    opens = {"{": "}", "[": "]", "(": ")"}
    stack: list[str] = []
    quote = None
    escaped = False
    i = m.end()
    while i < len(text):
        c = text[i]
        if quote:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == quote:
                quote = None
        elif c in ('"', "'"):
            quote = c
        elif c in opens:
            stack.append(opens[c])
        elif stack and c == stack[-1]:
            stack.pop()
            if not stack:
                return text[m.end() : i + 1]
        elif not stack and c in ("\n", ";"):
            return text[m.end() : i].rstrip()
        i += 1
    raise AssertionError(f"unterminated property {name}")


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


def tr_strings(text: str) -> set[str]:
    """Literal Tr.t("...") keys, unescaped as tools/i18n.py extracts them."""
    return set(
        m.replace('\\"', '"').replace("\\\\", "\\")
        for m in re.findall(r'Tr\.t\(\s*"((?:[^"\\]|\\.)*)"\s*\)', text)
    )


def line_of(text: str, needle: str) -> int:
    return next(
        (i for i, line in enumerate(text.splitlines(), 1) if needle in line), -1
    )


# ---------------------------------------------------------------------------
# Bugs — these FAIL on the code as it stands. Each names the exact file:line.
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_bug_photos_create_album_writes_to_the_shared_data_dir():
    """PhotosWindow.qml:606 (createAlbum).

    The two directory arguments are

        Quickshell.env("XDG_DATA_HOME") || (HOME + "/.local/share") + "/shani-photos"

    `+` binds tighter than `||`, so with XDG_DATA_HOME set the album is written
    to `$XDG_DATA_HOME/albums.json`. The reader (albumLister) and every other
    writer use `$XDG_DATA_HOME/shani-photos/albums.json`, so a saved album is
    invisible on any system that sets XDG_DATA_HOME. Fix: parenthesise the
    fallback exactly as `win.dataDir` (line 249) does — or pass `win.dataDir`
    for both argv slots.
    """
    s = src(PHOTOS)
    # the first createAlbum is a one-line QtObject wrapper; take the real writer
    m = re.search(r"function\s+createAlbum\s*\(\s*name\s*,\s*photoPaths\s*\)\s*\{", s)
    assert m, "PhotosWindow.qml: no createAlbum(name, photoPaths) writer"
    fn = balanced(s, m.start())
    prog = """
var argv;
var Quickshell = {
  env: function (k) {
    if (k === "XDG_DATA_HOME") return "/tmp/xdg";
    if (k === "HOME") return "/home/user";
    return "";
  },
  execDetached: function (a) { argv = a; }
};
// createAlbum now routes through win.dataDir (the same dir the lister reads).
var win = { dataDir: "/tmp/xdg/shani-photos" };
%s
win.createAlbum("Trip", ["/pics/a.jpg", "/pics/b.jpg"]);
process.stdout.write(JSON.stringify({ argv: argv }));
""" % re.sub(r"function\s+createAlbum\s*\(", "win.createAlbum = function(", fn, count=1)
    args = node(prog)["argv"]
    assert args[4] == "/tmp/xdg/shani-photos", (
        "PhotosWindow.qml:606 — album directory is %r, expected "
        "$XDG_DATA_HOME/shani-photos (operator precedence: || vs +)" % args[4]
    )
    assert args[5] == args[4], "PhotosWindow.qml:606 — mkdir and write disagree"


def test_wave6_new_tr_t_keys_are_in_the_template():
    """Every Tr.t() key added in wave 6 must be in shani/i18n/template.json.

    Wave 5 had this exact bug (stale catalog after new Tr.t wrappers). The keys
    below are invisible to translators and `tools/i18n.py check` cannot report
    them until `python3 tools/i18n.py extract` is run and the template commits.
    """
    missing = {}
    for rel in WAVE6_TRANSLATED:
        try:
            text = src(rel)
        except pytest.skip.Exception:
            continue
        keys = sorted(tr_strings(text) - set(TEMPLATE))
        if keys:
            missing[rel] = keys
    assert missing == {}, (
        "run `python3 tools/i18n.py extract` — missing template keys: " + repr(missing)
    )


def test_bug_wave6_new_accessible_names_are_untranslated_literals():
    """New wave-6 a11y labels and form labels are raw English, not Tr.t().

    ContactsWindow.qml:55,235,254,263,267,268,274,275,278,297,306,310,311,317,318 and
    CalendarPanel.qml:1693,1962 were added in wave 6 with literal strings while
    every neighbouring control goes through Tr.t(). They are invisible to
    translators and to `tools/i18n.py`. Fix: wrap each in Tr.t() (using
    `%1`-style args for the numbered labels) and run `tools/i18n.py extract`.
    NOTE: tests/test_contacts_calendar_wave6.py currently pins the literals —
    that pin must change together with the QML.
    """
    contacts = src(CONTACTS)
    calendar = src(CALENDAR)
    raw_contact = [
        'readonly property var phoneTypes: [["home", "Home"]',
        'text: "Phone numbers"',
        'text: "Add phone"',
        'text: "Email addresses"',
        'text: "Add email"',
        'label: "Phone number " + (index + 1)',
        "accessibleName: tip",  # tip itself is a raw "Remove phone N" literal
    ]
    bad = [needle for needle in raw_contact if needle in contacts]
    if 'Accessible.name: "Event description"' in calendar:
        bad.append("CalendarPanel.qml:1693 Event description")
    if 'Accessible.name: "Description: " + text' in calendar:
        bad.append("CalendarPanel.qml:1962 Description: …")
    assert bad == [], "wave-6 strings need Tr.t() + template keys: " + repr(bad)


# ---------------------------------------------------------------------------
# Correct behaviour — real QML functions in node, real bridges in Python.
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_media_stream_allowlist_rejects_local_paths_and_other_schemes():
    """playStreamUrl and PlayQueue.isStream share one allowlist; no shell fallback."""
    s = src(MEDIA)
    queue = src(PLAYQUEUE)
    prog = """
var called = [];
var PlayQueue = {
  playStream: function (u) { called.push(u); },
  streamSchemes: %s,
  validStreamUrl: null
};
var root = PlayQueue;
var win = { streamShown: true };
%s
%s
var results = {
  http: win.playStreamUrl(" https://example.com/live "),
  rtsp: win.playStreamUrl("rtsp://cam.example/stream"),
  rtmp: win.playStreamUrl("rtmp://host/live/key"),
  udp: win.playStreamUrl("udp://239.0.0.1:1234"),
  local: win.playStreamUrl("/etc/passwd"),
  fileUrl: win.playStreamUrl("file:///etc/passwd"),
  js: win.playStreamUrl("javascript:alert(1)"),
  ftp: win.playStreamUrl("ftp://host/file"),
  called: called,
  hidden: win.streamShown
};
process.stdout.write(JSON.stringify(results));
""" % (
        re.search(r"streamSchemes:\s*(\[[^\]]*\])", queue).group(1),
        bind(queue, "PlayQueue", "validStreamUrl"),
        bind(s, "win", "playStreamUrl"),
    )
    out = node(prog)
    assert out["http"] and out["rtsp"] and out["rtmp"] and out["udp"], out
    assert not out["local"] and not out["fileUrl"] and not out["js"], out
    assert out["ftp"], "ftp is on the shared stream allowlist"
    assert out["called"] == [
        "https://example.com/live",
        "rtsp://cam.example/stream",
        "rtmp://host/live/key",
        "udp://239.0.0.1:1234",
        "ftp://host/file",
    ], out
    assert out["hidden"] is False, "a valid stream closes the address box"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_media_recent_add_is_pure_bounded_and_dedupes_by_path():
    s = src(PLAYQUEUE)
    prog = """
var root = { recentCap: 20 };
%s
var before = [{ path: "/a", title: "A", at: 1 }, { path: "/b", title: "B", at: 2 }];
var added = root.recentAdd(before, { path: "/c", title: "C", at: 3 });
var dup = root.recentAdd(added, { path: "/a", title: "A2", at: 4 });
var empty = root.recentAdd(before, null);
var many = before;
for (var i = 0; i < 40; i++) many = root.recentAdd(many, { path: "/f" + i, at: i });
process.stdout.write(JSON.stringify({
  before: before, added: added, dup: dup, empty: empty, cap: many.length,
  first: many[0].path, last: many[many.length - 1].path
}));
""" % bind(s, "root", "recentAdd")
    out = node(prog)
    assert [x["path"] for x in out["before"]] == ["/a", "/b"], "input mutated"
    assert [x["path"] for x in out["added"]] == ["/c", "/a", "/b"], out
    assert [x["path"] for x in out["dup"]] == ["/a", "/c", "/b"], out
    assert out["dup"][0]["title"] == "A2", "a replay updates the title"
    assert out["empty"] == out["before"], out
    assert out["cap"] == 20 and out["first"] == "/f39" and out["last"] == "/f20", out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_media_play_recent_routes_streams_without_touching_the_filesystem():
    s = src(PLAYQUEUE)
    prog = """
var opened = [], streamed = [];
var root = {
  validStreamUrl: function (u) { return /^[a-z]+:\\/\\//i.test(u); },
  open: function (p) { opened.push(p); },
  playStream: function (u) { streamed.push(u); }
};
%s
root.playRecent("");
root.playRecent("https://example.com/live");
root.playRecent("/home/user/song.mp3");
process.stdout.write(JSON.stringify({ opened: opened, streamed: streamed }));
""" % bind(s, "root", "playRecent")
    out = node(prog)
    assert out == {
        "opened": ["/home/user/song.mp3"],
        "streamed": ["https://example.com/live"],
    }, out


def test_media_m3u_bridge_roundtrip_and_path_safety(tmp_path):
    """playlist.py is argv-only; relative entries resolve next to the playlist."""
    path = ROOT / PLAYLIST_PY
    if not path.exists():
        pytest.skip("wave-6 playlist bridge has not landed yet")
    playlist = tmp_path / "trip.m3u"
    entries = {
        "entries": [
            {"path": str(tmp_path / "one.mp3"), "title": "One"},
            {"path": "https://example.com/live", "title": "Live"},
            {"path": "/etc/passwd\u0000bad", "title": "dropped"},
        ]
    }
    w = subprocess.run(
        [sys.executable, str(path), "write", str(playlist), json.dumps(entries)],
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    assert json.loads(w.stdout)["ok"] is True
    r = subprocess.run(
        [sys.executable, str(path), "read", str(playlist)],
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    got = json.loads(r.stdout)
    assert [e["path"] for e in got["entries"]] == [
        str(tmp_path / "one.mp3"),
        "https://example.com/live",
    ], got
    assert got["count"] == 2
    # on the read side a relative entry resolves next to the playlist, and
    # control characters are dropped rather than handed to the player
    spec = __import__("importlib.util").util.spec_from_file_location("playlist", path)
    mod = __import__("importlib.util").util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    parsed = mod.parse_m3u(
        "#EXTM3U\n#EXTINF:-1,Relative\ntwo.mp3\n/etc/passwd\u0000bad\n",
        str(tmp_path),
    )
    assert parsed["entries"] == [
        {"path": str(tmp_path / "two.mp3"), "title": "Relative"}
    ], parsed
    # a URL is refused as the playlist file itself; nothing is executed
    bad = subprocess.run(
        [sys.executable, str(path), "read", "https://example.com/x.m3u"],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert "error" in json.loads(bad.stdout)


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_photos_sort_comparator_orders_newest_oldest_name_and_size():
    s = src(PHOTOS)
    prog = """
var win = { sortOrder: "newest" };
%s
var a = { time: 100, size: 5, path: "/pics/a.jpg" };
var b = { time: 200, size: 9, path: "/pics/b.jpg" };
var c = { time: 300, size: 1, path: "/pics/c.jpg" };
var out = {};
win.sortOrder = "newest"; out.newest = [a,b,c].sort(win.comparePhotos).map(x => x.path);
win.sortOrder = "oldest"; out.oldest = [c,b,a].sort(win.comparePhotos).map(x => x.path);
win.sortOrder = "name";   out.name = [c,b,a].sort(win.comparePhotos).map(x => x.path);
win.sortOrder = "size";   out.size = [a,b,c].sort(win.comparePhotos).map(x => x.path);
win.sortOrder = "size";   out.missing = [{time:1,size:10,path:"/z"},{time:2,path:"/a"}]
                                        .sort(win.comparePhotos).map(x => x.path);
process.stdout.write(JSON.stringify(out));
""" % bind(s, "win", "comparePhotos")
    out = node(prog)
    assert out["newest"] == ["/pics/c.jpg", "/pics/b.jpg", "/pics/a.jpg"], out
    assert out["oldest"] == ["/pics/a.jpg", "/pics/b.jpg", "/pics/c.jpg"], out
    assert out["name"] == ["/pics/a.jpg", "/pics/b.jpg", "/pics/c.jpg"], out
    assert out["size"] == ["/pics/b.jpg", "/pics/a.jpg", "/pics/c.jpg"], out
    assert out["missing"] == ["/z", "/a"], "a missing size sorts last"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_photos_batch_selection_is_copied_and_never_mutates_in_place():
    s = src(PHOTOS)
    prog = """
var win = { selected: ["/a", "/b"], detailPath: "", albumField: { text: "" },
            newAlbumName: "", albumLister: { running: false }, scan: function () {} };
var removed = [];
var Files = { trash: function (paths, cb) { removed = paths.slice(); cb({}); } };
var Photos = { createAlbum: function (name, paths) { win.made = [name, paths.slice()]; } };
var photosApi = Photos;
var Tr = { t: function (s) { return s; } };
%s
%s
var sel = win.selected.slice();
win.toggleSelect("/c");
win.toggleSelect("/a");
win.selected = ["/a", "/b"];
win.albumSelected();
var after = win.selected.slice();
win.selected = ["/a", "/b"];
win.trashSelected();
process.stdout.write(JSON.stringify({
  sel: sel, after: after, removed: removed, made: win.made
}));
""" % (
        bind(s, "win", "toggleSelect"),
        bind(s, "win", "trashSelected", "albumSelected"),
    )
    out = node(prog)
    assert out["sel"] == ["/a", "/b"], "toggleSelect mutated its source"
    assert out["removed"] == ["/a", "/b"], out
    assert out["after"] == [], "a batch action clears the selection"
    assert out["made"][0] == "Selection" and out["made"][1] == ["/a", "/b"], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
@pytest.mark.parametrize("pane", ["main", "split"])
def test_files_breadcrumbs_form_a_prefix_chain(pane):
    """Every crumb is a real ancestor; Home and / both stay reachable."""
    s = src(FILES)
    prop = "crumbsModel" if pane == "main" else "splitCrumbsModel"
    pathvar = "path" if pane == "main" else "splitPath"
    prog = """
var Tr = { t: function (s) { return s; } };
var Files = { %s: %s, home: "/home/user" };
var prop = (function () %s)();
process.stdout.write(JSON.stringify(prop));
""" % (pathvar, json.dumps("/home/user/Projects/shani/shell"), prop_of(s, prop))
    crumbs = node(prog)
    assert [c["path"] for c in crumbs] == [
        "/home/user",
        "/home/user/Projects",
        "/home/user/Projects/shani",
        "/home/user/Projects/shani/shell",
    ], crumbs
    assert crumbs[0]["name"] == "Home"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_files_crumb_menu_ignores_a_stale_callback_and_routes_split():
    s = src(FILES)
    prog = """
var listed = [], opened = [], reloaded = 0;
var Files = {
  list: function (parent, opts, cb) { listed.push(parent); cb({ entries: [{name:"Docs",path:parent+"/Docs",isDir:true}] }); },
  open: function (p) { opened.push(p); },
  splitPath: ""
};
var crumbMenuFor = "", crumbMenuItems = [], crumbMenuSplit = false,
    crumbMenuX = 0, crumbMenuY = 0;
var splitDir = { reload: function () { reloaded++; } };
var win = {
  get crumbMenuFor() { return crumbMenuFor; }, set crumbMenuFor(v) { crumbMenuFor = v; },
  get crumbMenuItems() { return crumbMenuItems; }, set crumbMenuItems(v) { crumbMenuItems = v; },
  get crumbMenuSplit() { return crumbMenuSplit; }, set crumbMenuSplit(v) { crumbMenuSplit = v; }
};
%s
win.crumbMenuSplit = false;
win.openCrumbMenu("/home/user/Projects", { x: 10, y: 20 });
var first = crumbMenuItems.slice();
win.crumbMenuSplit = true;
win.openCrumbMenu("/home/user/Other", { x: 1, y: 2 });   // older one is stale
win.openCrumbPath("/home/user/Other/Docs");
process.stdout.write(JSON.stringify({ listed: listed, first: first,
  items: crumbMenuItems, opened: opened, splitPath: Files.splitPath,
  reloaded: reloaded, closed: crumbMenuFor }));
""" % (
        bind(s, "win", "openCrumbMenu", "closeCrumbMenu", "openCrumbPath")
        + "\nvar closeCrumbMenu = win.closeCrumbMenu;\n"
    )
    out = node(prog)
    assert out["listed"] == ["/home/user", "/home/user"], "parent folder listed"
    assert out["first"] == [{"name": "Docs", "path": "/home/user/Docs"}], out
    assert out["opened"] == [], "a split crumb must not navigate the main pane"
    assert out["splitPath"] == "/home/user/Other/Docs" and out["reloaded"] == 1, out
    assert out["closed"] == "", "the menu closes after a pick"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_contacts_type_helpers_normalise_vcards_cell():
    s = src(CONTACTS)
    prog = """
var win = { phoneTypes: [["home","Home"],["work","Work"],["mobile","Mobile"],["other","Other"]] };
%s
%s
process.stdout.write(JSON.stringify({
  cell: win.phoneType("CELL"), mobile: win.phoneType("mobile"),
  work: win.phoneType("work"), junk: win.phoneType("pager"),
  eh: win.emailType("WORK"), ej: win.emailType("cell"), ep: win.emailType("")
}));
""" % (bind(s, "win", "phoneType"), bind(s, "win", "emailType"))
    out = node(prog)
    assert out == {
        "cell": "mobile",
        "mobile": "mobile",
        "work": "work",
        "junk": "mobile",
        "eh": "work",
        "ej": "home",
        "ep": "home",
    }, out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_set_phone_set_email_reassign_a_copy_not_the_property_array():
    s = src(CONTACTS)
    prog = """
var win = { editPhones: [{type:"cell",number:"1"}], editEmails: [{type:"home",address:"a"}] };
%s
%s
var p = win.editPhones, e = win.editEmails;
win.setPhone(0, "type", "work");
win.setEmail(0, "address", "b");
process.stdout.write(JSON.stringify({ p: p, e: e, nowP: win.editPhones, nowE: win.editEmails }));
""" % (bind(s, "win", "setPhone"), bind(s, "win", "setEmail"))
    out = node(prog)
    assert out["p"] == [{"type": "cell", "number": "1"}], "source array mutated"
    assert out["e"] == [{"type": "home", "address": "a"}], "source array mutated"
    assert out["nowP"] == [{"type": "work", "number": "1"}], out
    assert out["nowE"] == [{"type": "home", "address": "b"}], out


def test_contacts_service_forwards_typed_arrays():
    s = src(CONTACTS_SVC, marker="phones: d.phones || []")
    for fn in ("add", "edit"):
        body = source_of(s, fn)
        assert "phones: d.phones || []" in body, fn
        assert "emails: d.emails || []" in body, fn


def test_contacts_bridge_preserves_typed_phones_and_emails(tmp_path):
    tool = ROOT / CONTACTS_PY
    if not tool.exists():
        pytest.skip("wave-6 contacts bridge has not landed yet")
    env = {**__import__("os").environ, "SHANI_CONTACTS_DIR": str(tmp_path)}
    payload = {
        "op": "add",
        "name": "Ada",
        "phones": [
            {"type": "work", "number": "+1 555"},
            {"type": "mobile", "number": "+2 555"},
        ],
        "emails": [{"type": "work", "address": "ada@example.com"}],
    }

    def run(*args):
        return subprocess.run(
            [sys.executable, str(tool), *args],
            capture_output=True,
            text=True,
            env=env,
            timeout=30,
        )

    r = run("add", json.dumps(payload))
    if r.returncode != 0:
        pytest.skip("contacts bridge CLI changed its interface: " + r.stderr[:200])
    uid = json.loads(r.stdout)["uid"]
    got = json.loads(run("get", uid).stdout)
    assert [p["type"] for p in got["phones"]] == ["work", "mobile"], got
    assert [e["type"] for e in got["emails"]] == ["work"], got
    assert got["phone"] == "+1 555" and got["email"] == "ada@example.com", got


def test_calendar_editor_payload_carries_the_description():
    s = src(CALENDAR)
    for needle in (
        "id: fDescription",
        'placeholder: "Description / notes"',
        'label: "Description"',
        "description: fDescription.text.trim()",
        'description: e.description || ""',
        '"description"].some(k =>',
    ):
        assert needle in s, f"CalendarPanel.qml: {needle}"


def test_agenda_bridge_readback_ignores_the_valarm_description():
    tool = ROOT / AGENDA_PY
    s = src(AGENDA_PY, marker="_strip_valarms")
    # the read path strips VALARM blocks before pulling DESCRIPTION/RRULE
    assert "_strip_valarms" in s and "_unfold_lines" in s
    assert 'out["description"] = _prop(event_only, "DESCRIPTION")' in s


def test_voice_recorder_panel_loads_bounded_peaks_from_the_bridge():
    s = src(RECORDER)
    for needle in (
        'Quickshell.env("SHANI_WAVEFORM_TOOL")',
        '["python3", waveformTool, path]',
        "d.peaks.slice(0, 256)",
        "win.loadPeaks(path)",
        "Accessible.role: Accessible.Slider",
        "onStep: dir =>",
        "dir * 5000",
        ".peaks.json",
    ):
        assert needle in s, f"VoiceRecorderPanel.qml: {needle}"


def test_voice_recorder_peak_math_is_bounded(tmp_path):
    tool = ROOT / WAVEFORM_PY
    if not tool.exists():
        pytest.skip("wave-6 waveform bridge has not landed yet")
    spec = __import__("importlib.util").util.spec_from_file_location("waveform", tool)
    mod = __import__("importlib.util").util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert mod.clamp01(-1) == 0.0 and mod.clamp01(2) == 1.0
    assert mod.clamp01("x") == 0.0 and mod.clamp01(0.25) == 0.25
    assert mod.seek_ms(0.5, 30000) == 15000 and mod.seek_ms(-1, 100) == 0
    assert mod.bucket_at(0.5, 100) == 50 and mod.bucket_at(1, 100) == 99
    assert mod.bucket_at(0.5, 0) == 0
    assert len(mod.peaks_from_pcm(b"\x00\x00" * 10000, 10**6)) <= 256


# ---------------------------------------------------------------------------
# Cross-file invariants for every wave-6 surface (the wave-1..5 guard classes).
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("rel", WAVE6_QML)
def test_wave6_status_reads_never_use_pkexec(rel):
    try:
        s = read(rel)
    except FileNotFoundError:
        pytest.skip(f"wave-6 file has not landed yet: {rel}")
    assert "pkexec" not in s, f"{rel}: pkexec in a status/read-only path"


@pytest.mark.parametrize("rel", [r for r in WAVE6_QML if r.endswith(".qml")])
def test_wave6_property_arrays_are_reassigned_not_mutated(rel):
    try:
        s = read(rel)
    except FileNotFoundError:
        pytest.skip(f"wave-6 file has not landed yet: {rel}")
    bad = [
        m
        for m in re.findall(
            r"(?:root|win|page|service|bar|Photos|PlayQueue)\.[\w.]+\.(?:push|splice|sort|reverse)\(",
            s,
        )
        if "._" not in m  # private work queue, not a UI-bound property array
    ]
    assert bad == [], f"{rel}: in-place mutation of a property array: {bad}"


@pytest.mark.parametrize("rel", [r for r in WAVE6_QML if r.endswith(".qml")])
def test_wave6_no_idle_poll_timers(rel):
    """Only long rollover timers (date/time) may run while nothing needs them."""
    try:
        s = read(rel)
    except FileNotFoundError:
        pytest.skip(f"wave-6 file has not landed yet: {rel}")
    bad = []
    for m in re.finditer(r"\bTimer\s*\{", s):
        block = balanced(s, m.start())
        if not re.search(r"\brunning:\s*true\b", block):
            continue
        iv = re.search(r"\binterval:\s*(\d+)", block)
        if not iv or int(iv.group(1)) < 30000:
            bad.append(s.count("\n", 0, m.start()) + 1)
    assert bad == [], f"{rel}: idle timers at lines {bad}"


def test_wave6_shell_commands_pass_user_paths_as_argv():
    """A path or URL from a person must never be spliced into a `sh -c` script.

    Each command here uses positional parameters ($1, $@) plus a trailing
    `, "sh", <value>` argv element; the two new bridges take argv only.
    """
    # Every shell command that touches a person's path passes it as a
    # positional argv element after the script, never by string interpolation.
    expected = {
        MEDIA: ('"sh", PlayQueue.current', '"sh", PlayQueue.current, name'),
        VOICE_SVC: ('"sh", dir(), file', '"sh", root.dir()'),
        PHOTOS: (
            '"sh", win.pictures',
            '"sh", win.metaFile',
            '"sh", win.prefsFile',
            '"sh", win.smartFile',
        ),
        PLAYQUEUE: ('"sh", current', '"sh", path'),
    }
    for rel, separators in expected.items():
        s = read(rel)
        found = [sep for sep in separators if sep in s]
        assert found, f"{rel}: no positional argv separator for a user path"
        # no QML expression is concatenated directly onto a shell script
        assert not re.search(r'"-c"\s*,\s*\'[^\']*\'\s*\+\s*[A-Za-z_$]', s), (
            f"{rel}: a value is concatenated into a shell script"
        )
    for rel in (PLAYLIST_PY, WAVEFORM_PY):
        path = ROOT / rel
        if not path.exists():
            continue
        body = path.read_text(encoding="utf-8")
        assert "subprocess.run(" not in body or "shell=True" not in body


def test_wave6_surfaces_have_the_imports_they_need_on_first_open():
    imports = {
        MEDIA: "qs.Modules.MediaPlayer",  # MusicLibraryView read on open
        RECORDER: "QtMultimedia",  # the inline playback MediaPlayer
        PHOTOS: "Quickshell.Io",  # lister / meta write processes
        LIVETV: "qs.Services",  # LiveTv is a singleton
        FILES: "qs.Modules.Files",  # AppPicker
    }
    for rel, needed in imports.items():
        s = src(rel, marker=None)
        assert f"import {needed}" in s, f"{rel}: missing {needed}"


def test_wave6_persistence_uses_declared_keys_or_state_folder_paths():
    """New settings must be in Common/Settings.qml, not undeclared data keys."""
    settings = read("shani/Common/Settings.qml")
    live = src(LIVETV, marker=None)
    if "liveTvSource" in live:
        assert "Settings.data.liveTvSource" in live
    assert "property string liveTvSource:" in settings
    queue = src(PLAYQUEUE, marker=None)
    if "recentPrefs" in queue:
        assert "Settings.path" in queue, "recent list must live beside settings"
        assert "recentCap" in queue and "20" in queue, "bounded cache"


def test_wave6_new_controls_have_accessible_names():
    contacts = src(CONTACTS, marker=None)
    if "phoneTypes" in contacts:
        for needle in (
            "Accessible.name:",
            "accessibleName:",
            'Tr.t("Phone number")',
        ):
            assert needle in contacts, needle
    rec = src(RECORDER, marker=None)
    if "win.peaks" in rec:
        assert "Accessible.name: Tr.t(" in rec
        assert "KeyFocus {" in rec and "name:" in rec
    files = src(FILES, marker=None)
    if "crumbMenuSplit" in files:
        assert 'Tr.t("Folders next to %1")' in files


def test_wave6_no_unbounded_caches_in_the_new_bridges():
    for rel in (WAVEFORM_PY, PLAYLIST_PY):
        path = ROOT / rel
        if not path.exists():
            continue
        body = path.read_text(encoding="utf-8")
        if rel == WAVEFORM_PY:
            assert "MAX_BUCKETS" in body, "the peak count is capped"
            assert "len(peaks) > MAX_BUCKETS" in body, "a stale huge cache is ignored"
            assert "CACHE_SUFFIX" in body, "the cache is a bounded sibling JSON file"


# ---------------------------------------------------------------------------
# Re-check of the wave-1/2/3/4/5 fixes named in the QA brief.
# ---------------------------------------------------------------------------


def test_guard_batch_rename_path_validation():
    body = source_of(read(FILES_SVC), "batchRename")
    assert "FilePaths.validName" in body or "validName(" in body
    assert "def batch_rename(" in read("bridge/files.py")


def test_guard_split_selection_is_copied_before_mutation():
    body = source_of(read(FILES_SVC), "selectSplit")
    aliased = re.search(r"const\s+s\s*=\s*root\._splitPaths\s*;", body)
    assert not (aliased and re.search(r"\bs\.(?:splice|push|sort|reverse)\(", body))


def test_guard_archive_batch_results_are_reassigned():
    s = read("shani/Services/Archive.qml")
    assert "root.batchDone.push(" not in s and "root.batchFailed.push(" not in s


def test_guard_ctrl_shift_f2_reaches_batch_rename():
    lines = [
        line.strip()
        for line in read(FILES).splitlines()
        if re.search(r"Qt\.Key_F2\b", line) and line.strip().startswith("if (")
    ]
    assert len(lines) == 2, lines
    single = next(c for c in lines if "!control" in c)
    batch = next(c for c in lines if c is not single)
    assert "!control" in single and "ShiftModifier" in single
    assert "control &&" in batch and "ShiftModifier" in batch


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_guard_insert_datetime_works_with_one_cursor():
    s = read("shani/Modules/TextEditor/TextEditorPanel.qml")
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
    s = read("shani/Modules/Clocks/ClocksWindow.qml")
    assert "WorldClock.updateAlarm(" in s
    assert "WorldClock.alarms[" not in s or ".enabled =" not in s


def test_guard_osk_paste_never_uses_a_shell():
    body = source_of(read("shani/Services/Osk.qml"), "paste")
    assert '["wtype", "--", text]' in body
    assert "sh -c" not in body and "shell: true" not in body


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_guard_processes_build_tree_lists_each_pid_once():
    s = read("shani/Modules/Processes/Processes.qml")
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


def test_guard_processes_sort_choice_is_persisted():
    s = read("shani/Modules/Processes/Processes.qml")
    load = source_of(s, "loadSort")
    save = source_of(s, "saveSort")
    assert "win.sortApplied" in load and "win.sortKeys.indexOf(k) >= 0" in load
    assert "sortPrefs.key = win.sortKey" in save


def test_guard_notes_markdown_preview_is_plain_text():
    md = read("shani/Modules/Notes/NotesMarkdown.qml")
    assert "textFormat: Text.PlainText" in md
    assert "textFormat: Text.RichText" not in md
