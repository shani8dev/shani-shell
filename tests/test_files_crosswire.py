"""Files → the shell's own apps (cross-wiring, not new features).

Files.qml owns one pure mapping (extension → app id) and one dispatcher; the
context menu only asks for the route and keeps its old "Open with…" picker as
the fallback. The pure functions are lifted out of the QML and run in node, so
the tests exercise the very code the shell runs instead of a Python copy.

Static hooks pin the wiring that a UI test cannot reach here: double click,
Quick Look, the app picker and type-to-search must all survive.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SERVICE = ROOT / "shani/Services/Files.qml"
PANEL = ROOT / "shani/Modules/Files/FilesPanel.qml"
CATALOG = json.loads((ROOT / "shani/i18n/template.json").read_text(encoding="utf-8"))
NODE = shutil.which("node") or shutil.which("nodejs")

pytestmark = pytest.mark.skipif(NODE is None, reason="node is not installed")


def read(path):
    return path.read_text(encoding="utf-8")


def qml_function(text, name):
    """One function's verbatim source, from its signature to its closing brace."""
    m = re.search(r"\n    function " + re.escape(name) + r"\(", text)
    assert m, name
    start = text.index("{", m.start())
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[m.start() + 1 : i + 1]
    raise AssertionError("unclosed function " + name)


ROUTES_SRC = "\n".join(
    qml_function(read(SERVICE), n)
    for n in ("routeForPath", "routeForPaths", "routeInfo")
)


@pytest.fixture(scope="module")
def routes():
    """The route functions from Files.qml as a plain node script."""
    return ROUTES_SRC


def call(js, fn, *args):
    prog = (
        js
        + "\nconsole.log(JSON.stringify("
        + fn
        + "("
        + ", ".join(json.dumps(a) for a in args)
        + ")));\n"
    )
    r = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout.strip().splitlines()[-1])


def route(path, notes_dir="/home/me/Documents/Notes"):
    return call(ROUTES_SRC, "routeForPath", path, notes_dir)


# ---- the routing table ---------------------------------------------------------


@pytest.mark.parametrize(
    "path,expected",
    [
        ("/pics/holiday.JPG", "viewer"),
        ("/pics/a.PNG", "viewer"),
        ("/pics/scan.TiFF", "viewer"),
        ("/pics/vector.svg", "viewer"),
        ("/docs/report.PDF", "pdf"),
        ("/books/novel.EPUB", "pdf"),
        ("/docs/issue.cbr", "pdf"),
        ("/tmp/photos.ZIP", "archive"),
        ("/tmp/dump.TAR.GZ", "archive"),
        ("/tmp/t.tgz", "archive"),
        ("/tmp/set.7Z", "archive"),
        ("/tmp/disc.ISO", "archive"),
        ("/music/song.MP3", "media"),
        ("/videos/clip.MKV", "media"),
        ("/docs/notes.TXT", "text"),
        ("/docs/code.PY", "text"),
        ("/docs/page.MD", "text"),
        ("/docs/invite.ICS", "calendar"),
        ("/people/card.VCF", "contacts"),
        ("/tmp/mystery.bin", ""),
        ("/tmp/no-extension", ""),
        ("", ""),
    ],
)
def test_extension_route_is_case_insensitive_and_falls_back(path, expected):
    assert route(path) == expected


def test_markdown_inside_the_notes_folder_is_a_note():
    notes = "/home/me/Documents/Notes"
    assert route(notes + "/ideas.md", notes) == "notes"
    assert route(notes + "/work/ideas.MD", notes) == "notes"
    # QuickNotes only understands one notebook level: deeper is a plain file
    assert route(notes + "/work/deep/ideas.md", notes) == "text"
    # a similarly named folder elsewhere is not the notes folder
    assert route("/other/Notes/ideas.md", notes) == "text"


# ---- multi-select: one route valid for every file ------------------------------


@pytest.mark.parametrize(
    "paths,expected",
    [
        (["/a.jpg", "/B.JPG"], "viewer"),  # the viewer has a folder list
        (["/a.mp3", "/b.flac"], "media"),  # the player has a queue
        (["/a.txt", "/b.md"], ""),  # the editor opens one at a time
        (["/a.pdf", "/b.pdf"], ""),  # one document surface
        (["/a.zip", "/b.zip"], ""),  # one archive surface
        (["/a.ics", "/b.ics"], ""),  # one import at a time
        (["/a.vcf", "/b.vcf"], ""),
        (["/a.jpg", "/b.mp3"], ""),  # no route shared by both
        (["/a.jpg", "/b.unknown"], ""),
        (["/a.jpg"], "viewer"),
        ([], ""),
    ],
)
def test_route_intersection(routes, paths, expected):
    assert call(routes, "routeForPaths", paths, "/home/me/Documents/Notes") == expected


@pytest.mark.parametrize(
    "app,label,icon",
    [
        ("viewer", "Image Viewer", "applications-graphics"),
        ("pdf", "Document Viewer", "document-open"),
        ("text", "Text Editor", "accessories-text-editor"),
        ("archive", "Archive Manager", "package-x-generic"),
        ("media", "Media Player", "media-playback-start"),
        ("calendar", "Calendar", "entry-calendar"),
        ("contacts", "Contacts", "x-office-address-book"),
        ("notes", "Notes", "document-edit"),
        ("", "", ""),
    ],
)
def test_route_info_has_a_label_and_a_theme_icon(routes, app, label, icon):
    assert call(routes, "routeInfo", app) == {"label": label, "icon": icon}


def test_the_table_covers_each_target_apps_own_extensions(routes):
    """The mapping follows the extension lists the apps themselves declare."""
    viewer = re.search(
        r"function isImage\(p\) \{[^}]*", read(ROOT / "shani/Services/Viewer.qml")
    ).group(0)
    for ext in re.findall(r"png|jpe?g|webp|avif|gif|bmp|tiff?|heic|heif|svg", viewer):
        assert call(routes, "routeForPath", "x." + ext, "") == "viewer", ext
    pdf = re.search(
        r"otherTypes: \[([^\]]*)\]", read(ROOT / "shani/Services/PdfViewer.qml")
    ).group(1)
    for ext in re.findall(r'"(\w+)"', pdf):
        assert call(routes, "routeForPath", "x." + ext, "") == "pdf", ext
    queue = read(ROOT / "shani/Services/PlayQueue.qml")
    for field, want in (("videoTypes", "media"), ("audioTypes", "media")):
        body = re.search(field + r": \[([^\]]*)\]", queue).group(1)
        for ext in re.findall(r'"(\w+)"', body):
            if ext == "ts":
                # TypeScript wins over MPEG-TS; that video keeps the picker
                assert call(routes, "routeForPath", "x.ts", "") == "text"
                continue
            assert call(routes, "routeForPath", "x." + ext, "") == want, ext
    archive = re.search(
        r"types: \[([^\]]*)\]", read(ROOT / "shani/Services/Archive.qml")
    ).group(1)
    for ext in re.findall(r'"(\w+)"', archive):
        assert call(routes, "routeForPath", "x." + ext, "") == "archive", ext


# ---- wiring --------------------------------------------------------------------


def test_open_entry_tries_the_shell_app_before_xdg_open():
    s = read(SERVICE)
    assert "if (root.openRoute([p]))" in s
    assert s.index("if (root.openRoute([p]))") < s.index(
        'Quickshell.execDetached(["xdg-open", p])'
    )
    # folders, disk images and Quick Look are untouched
    assert "if (e && e.isDir) {" in s
    assert "root.mountImage(p);" in s


def test_the_dispatcher_reaches_the_existing_surfaces():
    s = read(SERVICE)
    for hook in (
        "Viewer.open(list[0])",
        "PdfViewer.open(list[0])",
        "Archive.open(list[0])",
        "PlayQueue.playList(list, 0)",
        "PlayQueue.open(list[0])",
        "TextDocs.open(list[0])",
        "Agenda.importFile(list[0])",
        "Contacts.importFile(list[0])",
        "QuickNotes.open(",
        "Ui.closeAll()",
    ):
        assert hook in s, hook
    # .ics and .vcf are imports, not documents to read in place
    assert s.index("Ui.calendar = true;\n            Agenda.importFile") < s.index(
        "Ui.contacts = true;\n            Contacts.importFile"
    )


def test_context_menu_offers_the_route_first_and_keeps_the_picker():
    q = read(PANEL)
    assert "Files.routeForPaths(chosen, QuickNotes.dir)" in q
    assert "Files.routeInfo(routed)" in q
    assert 'Tr.t("Open in %1", info.label)' in q
    assert "Files.openRoute(chosen)" in q
    routed = q.index("Files.routeForPaths(chosen, QuickNotes.dir)")
    picker = q.index('Tr.t("Open with…"), icon: "view-app-grid"')
    assert routed < picker
    # the old actions are still there
    assert 'Tr.t("Open with…"), icon: "view-app-grid"' in q
    assert "win.openWithPaths = chosen.slice();" in q
    assert "Files.openEntry(e.path)" in q
    assert "onPeek: QuickLook.open(cell.modelData.path, Files._paths)" in q
    assert "win.typed += event.text.toLowerCase()" in q
    # keyboard/a11y: the menu's KeyFocus names the item it activates
    assert "KeyFocus {" in q and "name: modelData.label" in q


def test_no_new_translation_literal_is_introduced():
    """Catalogs belong to another wave; reuse a key that is already there."""
    for path in (SERVICE, PANEL):
        for m in re.finditer(r'Tr\.t\(\s*("(?:[^"\\]|\\.)*")', read(path)):
            assert json.loads(m.group(1)) in CATALOG, (path.name, m.group(1))
