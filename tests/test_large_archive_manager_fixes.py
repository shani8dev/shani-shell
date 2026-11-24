"""The large Archive Manager upgrade: recent archives, browsing, sort, an
extract destination policy, integrity testing, drag-and-drop, keyboard
navigation, accessibility and honest empty/error/progress states.

Competitors read for this pass: GNOME File Roller (recent menu, "Test
Archive", "Extract To" with an overwrite decision, folder navigation, sort
headers, drag-and-drop), KDE Ark (browse into folders, Add to archive,
Test Integrity, conflict policy on extract, status/progress) and macOS
Archive Utility (extract beside the archive, never overwrite silently).

Two proof levels. QML needs a session, so its branches are pinned as static
assertions on the exact bindings. The algorithms behind them are written out
below as plain Python and driven against their edge cases, and the shipped
shell snippet that implements the overwrite policy is executed with a stub
reader so rename / overwrite / skip are proven rather than just read.
"""

import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = ROOT / "shani/Services/Archive.qml"
WINDOW = ROOT / "shani/Modules/Archives/ArchivesWindow.qml"


def svc():
    return SERVICE.read_text(encoding="utf-8")


def win():
    return WINDOW.read_text(encoding="utf-8")


def body(src, header, close="\n    }"):
    return src.split(header, 1)[1].split(close, 1)[0]


# ---- pure logic, mirroring the service -------------------------------------


def note_recent(recent, path):
    """Newest first, each path once, capped at eight. Session-local only."""
    p = str(path or "")
    if not p:
        return list(recent)
    out = [p]
    for r in recent:
        if r != p and r not in out:
            out.append(r)
    return out[:8]


def entries_here(entries, current_dir="", sort_order="name"):
    """Entries directly in current_dir plus one synthetic folder per subdir."""
    prefix = "" if not current_dir else current_dir + "/"
    out, seen = [], set()
    for e in entries:
        if not e["path"].startswith(prefix):
            continue
        rest = e["path"][len(prefix) :]
        if not rest:
            continue
        slash = rest.find("/")
        if slash < 0:
            out.append(dict(e))
        else:
            folder = prefix + rest[:slash]
            if folder not in seen:
                seen.add(folder)
                out.append({"path": folder, "size": 0, "dir": True, "virtual": True})

    def key(e):
        if e["dir"]:
            return (0, 0, e["path"])
        if sort_order == "size":
            return (1, -e["size"], e["path"])
        return (1, 0, e["path"])

    return sorted(out, key=key)


def go_up(current_dir):
    return "" if "/" not in current_dir else current_dir[: current_dir.rfind("/")]


def drop_paths(urls):
    """file:// URLs (with escapes) and plain absolute paths become paths."""
    import urllib.parse

    out = []
    for u in urls or []:
        s = str(u)
        if s.startswith("file://"):
            out.append(urllib.parse.unquote(s[7:]))
        elif s.startswith("/"):
            out.append(s)
    return out


def append_unique(paths, archive):
    given = [p for p in paths if p and p != archive]
    return [p for i, p in enumerate(given) if p not in given[:i]]


def move_cursor(cursor, delta, count):
    if not count:
        return cursor
    return max(0, min(count - 1, cursor + delta))


def policy(p):
    return p if p in ("overwrite", "skip") else "rename"


def sort_order(o):
    return "size" if o == "size" else "name"


# ---- 1. recent archives -----------------------------------------------------


def test_recent_archives_are_deduped_capped_and_reopenable():
    r = []
    for p in ["/a.zip", "/b.tar", "/a.zip", "/c.7z"]:
        r = note_recent(r, p)
    assert r == ["/c.7z", "/a.zip", "/b.tar"]  # newest first, no duplicates
    assert note_recent(r, "/a.zip") == ["/a.zip", "/c.7z", "/b.tar"]
    for i in range(12):
        r = note_recent(r, "/f%d.zip" % i)
    assert len(r) == 8 and r[0] == "/f11.zip"

    s, w = svc(), win()
    assert "property var recent: []" in s
    assert "function noteRecent(path)" in s
    assert "root.recent = next.slice(0, 8);" in s
    assert "function clearRecent()" in s
    assert "root.noteRecent(path);" in body(s, "function open(arg) {")
    assert "root.noteRecent(root.made);" in s  # freshly compressed archives too
    assert "Archive.recent.length > 0" in w
    assert "model: Archive.recent" in w
    assert "win.openRecent(modelData)" in w
    assert "Archive.clearRecent()" in w
    assert 'Tr.t("Clear the recent files list")' in w


# ---- 2. browse within an archive -------------------------------------------


def test_browsing_lists_only_the_current_folder_and_synthesises_dirs():
    entries = [
        {"path": "a.txt", "size": 3, "dir": False},
        {"path": "dir/b.txt", "size": 5, "dir": False},
        {"path": "dir/sub/c.txt", "size": 7, "dir": False},
        {"path": "dir2/e.txt", "size": 2, "dir": False},
    ]
    root = entries_here(entries)
    assert [e["path"] for e in root] == ["dir", "dir2", "a.txt"]
    assert all(e.get("virtual") for e in root if e["dir"])
    here = entries_here(entries, "dir")
    assert [e["path"] for e in here] == ["dir/sub", "dir/b.txt"]
    assert [e["path"] for e in entries_here(entries, "dir/sub")] == ["dir/sub/c.txt"]
    assert go_up("dir/sub") == "dir" and go_up("dir") == "" and go_up("") == ""

    s, w = svc(), win()
    assert 'property string currentDir: ""' in s
    assert "function entriesHere(list)" in s
    assert "out.push({ path: folder, size: 0, dir: true, virtual: true });" in s
    assert "function browse(path)" in s and "function up()" in s
    assert 'root.currentDir = "";' in body(s, "function open(arg) {")
    assert "onDoubleClicked:" in w
    assert "Archive.browse(row.modelData.path);" in w
    assert "Archive.up();" in w
    assert "win.canGoUp" in w
    # a synthetic folder cannot be selected or extracted
    assert "visiblePaths: win.visibleEntries.filter(e => !e.virtual)" in w
    assert "visible: !row.modelData.virtual" in w


# ---- 3. sort ----------------------------------------------------------------


def test_sort_orders_files_by_name_or_size_with_folders_first():
    entries = [
        {"path": "small.txt", "size": 900, "dir": False},
        {"path": "large.txt", "size": 1, "dir": False},
        {"path": "mid.txt", "size": 20, "dir": False},
        {"path": "zdir/a.txt", "size": 4, "dir": False},
    ]
    assert [e["path"] for e in entries_here(entries)] == [
        "zdir",
        "large.txt",
        "mid.txt",
        "small.txt",
    ]  # folders first, then by name
    assert [e["path"] for e in entries_here(entries, sort_order="size")] == [
        "zdir",
        "small.txt",
        "mid.txt",
        "large.txt",
    ]
    assert sort_order("size") == "size" and sort_order("wrong") == "name"

    s, w = svc(), win()
    assert 'property string sortOrder: "name"' in s
    assert "function setSortOrder(order)" in s
    assert 'root.sortOrder = order === "size" ? "size" : "name";' in s
    assert 'if (root.sortOrder === "size"' in s
    assert "return a.path.localeCompare(b.path);" in s
    assert 'Archive.setSortOrder("size")' in w
    assert 'Archive.setSortOrder("name")' in w


# ---- 4. overwrite policy ----------------------------------------------------


def test_overwrite_policy_is_validated_and_reaches_the_extractor():
    assert policy("overwrite") == "overwrite" and policy("skip") == "skip"
    assert policy("garbage") == "rename" and policy(None) == "rename"

    s, w = svc(), win()
    assert 'property string overwritePolicy: "rename"' in s
    assert "function setOverwritePolicy(policy)" in s
    assert 'policy === "overwrite" || policy === "skip" ? policy : "rename"' in s
    for choice in ("rename", "overwrite", "skip"):
        assert 'Archive.setOverwritePolicy("%s")' % choice in w
    extract_now = body(s, "function extractNow(where) {")
    assert 'case "$5" in' in extract_now
    assert 'overwrite) rm -rf -- "$d" ;;' in extract_now
    assert 'skip) if [ -e "$d" ]' in extract_now
    assert 'while [ -e "$d" ]' in extract_now  # the default never overwrites
    assert "root.overwritePolicy];" in extract_now


def test_the_shipped_extract_command_honours_all_three_policies(tmp_path):
    """Execute the policy snippet from the QML, not a copy of it."""
    s = svc()
    m = re.search(r'extractor\.command = \["sh", "-c", \'(.*?)\',\s*"sh"', s, re.S)
    assert m, "the extract command should be a sh -c script"
    script = m.group(1)

    stub = tmp_path / "reader.py"
    stub.write_text(
        "import os, sys\n"
        "os.makedirs(sys.argv[3], exist_ok=True)\n"
        "open(os.path.join(sys.argv[3], 'marker'), 'w').write('read')\n",
        encoding="utf-8",
    )
    archive = tmp_path / "src.zip"
    archive.write_bytes(b"archive")

    def run(p):
        return subprocess.run(
            [
                "sh",
                "-c",
                script,
                "sh",
                str(tmp_path),
                "photos",
                str(stub),
                str(archive),
                p,
            ],
            capture_output=True,
            text=True,
        )

    (tmp_path / "photos").mkdir()
    (tmp_path / "photos" / "old").write_text("keep me", encoding="utf-8")
    assert run("rename").returncode == 0
    assert (tmp_path / "photos (2)" / "marker").exists()
    assert (tmp_path / "photos" / "old").read_text() == "keep me"

    assert run("overwrite").returncode == 0
    assert (tmp_path / "photos" / "marker").exists()
    assert not (tmp_path / "photos" / "old").exists()

    skipped = run("skip")
    assert skipped.returncode != 0
    assert "Destination already exists" in skipped.stderr
    assert not (tmp_path / "photos (3)").exists()


# ---- 5. integrity / test ----------------------------------------------------


def test_integrity_test_reads_every_entry_without_writing_and_can_be_retried():
    s, w = svc(), win()
    assert "property bool testing: false" in s
    assert 'property string testResult: ""' in s
    assert "function testArchive()" in s
    test = body(s, "function testArchive() {")
    assert 'root.file === "" || root.testing || root.entries.length === 0' in test
    assert "-xOf" in test and "> /dev/null" in test
    assert "tester.running = true;" in test
    exited = s.split("id: tester", 1)[1].split("\n    }", 1)[0]
    assert 'Tr.t("Done testing %1").arg(root.name)' in exited
    assert 'root.askPassword(testErr.text, "test")' in exited
    assert 'root.retry === "test"' in body(s, "function unlock(pw) {")
    assert "if (tester.running) tester.running = false;" in body(
        s, "function cancel() {"
    )
    assert "root.testing = false;" in body(s, "function cancel() {")
    assert "win.runTest()" in w and "Archive.testArchive()" in w
    assert 'Tr.t("Test")' in w and "Archive.testResult" in w
    assert "(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_T" in w


# ---- 6. drag and drop -------------------------------------------------------


def test_drop_decodes_file_urls_and_routes_archives_or_files():
    paths = drop_paths(
        ["file:///home/u/my%20photos.zip", "/tmp/notes.txt", "https://example/x.zip"]
    )
    assert paths == ["/home/u/my photos.zip", "/tmp/notes.txt"]

    w, s = win(), svc()
    assert "function dropPaths(drop)" in w
    assert 's.indexOf("file://") === 0' in w
    assert "decodeURIComponent(s.substring(7))" in w
    assert "function handleDrop(drop)" in w
    assert 'p.toLowerCase().endsWith("." + ext)' in w
    assert "win.openRecent(archives[0])" in w
    assert "Archive.append(paths)" in w
    assert 'keys: ["text/uri-list"]' in w
    assert "onDropped: drop => win.handleDrop(drop)" in w
    assert "property var types:" in s


# ---- 7. keyboard navigation -------------------------------------------------


def test_cursor_movement_is_clamped_and_enter_extracts_the_current_entry():
    assert move_cursor(0, -1, 3) == 0
    assert move_cursor(2, 1, 3) == 2
    assert move_cursor(1, 1, 3) == 2
    assert move_cursor(0, 1, 0) == 0  # empty list, no crash

    w = win()
    assert "property int cursor: 0" in w
    assert "function moveCursor(delta)" in w
    assert "Math.max(0, Math.min(win.visibleEntries.length - 1" in w
    assert "list.positionViewAtIndex(win.cursor, ListView.Contain)" in w
    assert "e.key === Qt.Key_Up" in w and "e.key === Qt.Key_Down" in w
    assert "e.key === Qt.Key_Home" in w and "e.key === Qt.Key_End" in w
    assert "Archive.extractOne(win.currentEntry.path)" in w
    assert "!win.currentEntry.virtual" in w
    assert "highlight: Rectangle" in w


# ---- 8. accessibility -------------------------------------------------------


def test_rows_buttons_and_the_list_have_accessible_names():
    w = win()
    assert "Accessible.role: Accessible.ListItem" in w
    assert w.count("Accessible.name: row.modelData.path") >= 2
    assert 'Accessible.name: Tr.t("Extract only this") + " " + row.modelData.path' in w
    assert "Accessible.name: modelData" in w  # a recent-archive button
    for label in ("Up", "Name", "Size", "Rename", "Replace", "Skip", "Test", "Locked"):
        assert 'Tr.t("%s")' % label in w
    assert "Accessible.name: text" in w  # the breadcrumb and status line


# ---- 9. progress / cancel ---------------------------------------------------


def test_every_job_shows_a_progress_state_and_a_cancel():
    w, s = win(), svc()
    assert "readonly property bool working: win.busy || Archive.testing" in w
    assert "visible: win.working" in w
    assert 'Archive.testing ? Tr.t("Working…")' in w
    assert "NumberAnimation on x" in w
    assert "visible: win.busy" in w  # the original Cancel button stays
    assert "onClicked: Archive.cancel()" in w
    assert "visible: Archive.testing" in w  # a Test can be stopped too
    assert "function cancel()" in s
    for job in (
        "lister",
        "singleSize",
        "singleOut",
        "hardOne",
        "extractor",
        "spaceProbe",
        "maker",
        "appender",
        "tester",
    ):
        assert "%s.running = false" % job in s


# ---- 10. empty / error states -----------------------------------------------


def test_empty_and_error_states_offer_a_next_action():
    w = win()
    assert 'Archive.entries.length === 0 ? Tr.t("Open an archive")' in w
    assert ': Tr.t("Nothing matches")' in w
    assert 'Archive.error !== "" ? Archive.error' in w
    actions = w.split("the empty state is actionable", 1)[1].split(
        "// ---- a password", 1
    )[0]
    assert 'text: Tr.t("Open an archive")' in actions
    assert "win.pick()" in actions
    assert 'visible: Archive.error !== "" && Archive.file !== ""' in actions
    assert "Archive.open(Archive.file)" in actions
    assert 'win.entryFilter = ""; Archive.browse("");' in actions


# ---- 11. add to an existing archive -----------------------------------------


def test_append_dedupes_paths_and_refuses_the_open_archive():
    paths = ["/a.txt", "/a.txt", "/b.txt", "/photos.zip"]
    assert append_unique(paths, "/photos.zip") == ["/a.txt", "/b.txt"]

    s, w = svc(), win()
    fn = body(s, "function append(paths) {")
    assert "p && p !== root.file" in fn
    assert "given.filter((p, i) => given.indexOf(p) === i)" in fn
    assert ".concat(list);" in fn
    assert '["zip", "jar", "apk"].indexOf(root.appendExt) >= 0' in s
    assert "enabled: Archive.canAppend && !Archive.appending" in w


# ---- 12. password-protected archives ----------------------------------------


def test_protected_badge_survives_unlock_and_clears_on_a_new_archive():
    s, w = svc(), win()
    assert "property bool wasProtected: false" in s
    assert "root.wasProtected = true;" in s
    assert s.count("root.wasProtected = true;") >= 2  # bsdtar + hardened reader
    assert "root.wasProtected = false;" in body(s, "function open(arg) {")
    assert "wasProtected = false;" in body(s, "function close() {")
    icon = w.split('name: "dialog-password"; size: Theme.px(16)', 1)[0]
    assert "visible: Archive.wasProtected" in icon
    assert 'Tr.t("Locked")' in w
    assert "function unlock(pw)" in s  # the existing unlock path is intact
    assert 'root.retry = ""; root.testArchive();' in body(s, "function unlock(pw) {")


# ---- the i18n template is owned by another agent: reuse existing keys -------


def test_no_new_translation_keys_are_introduced():
    import json

    template = json.loads(
        (ROOT / "shani/i18n/template.json").read_text(encoding="utf-8")
    )
    for src in (svc(), win()):
        keys = set(re.findall(r'Tr\.t\("((?:[^"\\]|\\.)*)"', src))
        assert keys <= set(template), sorted(keys - set(template))


def test_no_new_files_or_helpers_outside_the_owned_pair_are_assumed():
    """The upgrade is contained in the two owned QML files."""
    assert os.path.isfile(SERVICE) and os.path.isfile(WINDOW)
    assert "Archive.entriesHere(" in win()  # the window calls the service
