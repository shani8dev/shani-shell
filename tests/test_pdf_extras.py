"""Wave 4 deep pass: the Document Viewer's remaining paper-parity extras.

The facing-pages pass (``test_pdf_facing_viewer.py``) pinned the spread math.
This file pins the four extras that GAPS.md still called open even though an
earlier mass pass had already put the first three in place:

* per-document bookmarks — persisted by the bridge's JSON store, keyed by the
  document's content md5 (a rename keeps the marks), served to QML by
  ``pdfform.py bookmarks|bookmark-add|bookmark-remove``;
* navigation history — a bounded stack of visited pages with Back / Forward
  and spread-aware First / Last; search and Find jumps are visits too;
* the annotations list — the flattened markup PyMuPDF reads back from the PDF;
* a validated print-page range — CUPS ``page-ranges=1-3,5``, passed to ``lp``
  as its own argument, never through a shell.

The pure helpers below mirror the QML JS exactly; the bookmark tests call the
real bridge, so a key or persistence regression fails here as it would on disk.
"""

import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


SERVICE = "shani/Services/PdfViewer.qml"
READER = "shani/Modules/PdfReader/PdfReader.qml"


def load_bridge():
    spec = importlib.util.spec_from_file_location("pdfform", ROOT / "bridge/pdfform.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pdfform = load_bridge()


# ---- pure logic: page range (mirrors PdfViewer.validPageRange) --------------


def valid_page_range(text, count: int) -> bool:
    s = str(text or "").strip()
    if s == "":
        return True
    if not re.fullmatch(r"\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*", s):
        return False
    for part in s.split(","):
        bounds = [int(n) for n in part.split("-")]
        start, end = bounds[0], bounds[-1]
        if start < 1 or end > count or start > end:
            return False
    return True


def test_page_range_accepts_the_documented_shapes():
    assert valid_page_range("", 6)
    assert valid_page_range("1", 6)
    assert valid_page_range("1-3,5", 6)
    assert valid_page_range("2,4-6", 6)
    assert (
        valid_page_range("  1 - 3  ", 6) is False
    )  # spaces inside are not CUPS syntax
    assert valid_page_range(" 1-3,5 ", 6)
    assert valid_page_range("1-6", 6)


def test_page_range_rejects_anything_unsafe_or_out_of_bounds():
    for bad in (
        "0",
        "7",
        "1-7",
        "3-1",
        "1,,2",
        "1-",
        "-1",
        "1--3",
        "1.5",
        "1;2",
        "a",
        "1-3,7",
    ):
        assert not valid_page_range(bad, 6), bad
    # a document with no rendered pages must not accept a numbered range
    assert valid_page_range("", 0)
    assert not valid_page_range("1", 0)


# ---- pure logic: navigation history (mirrors PdfViewer.goTo/nav*) -----------


class History:
    def __init__(self):
        self.stack = []
        self.index = -1

    def go_to(self, page: int, current: int, count: int) -> int:
        n = max(0, min(count - 1, page))
        if n != current:
            if self.index < len(self.stack) - 1:
                self.stack = self.stack[: self.index + 1]
            self.stack.append(n)
            if len(self.stack) > 50:
                self.stack = self.stack[1:]
            self.index = len(self.stack) - 1
        return n

    @property
    def can_back(self):
        return self.index > 0

    @property
    def can_forward(self):
        return 0 <= self.index < len(self.stack) - 1

    def back(self):
        if self.can_back:
            self.index -= 1
        return self.stack[self.index] if self.index >= 0 else 0

    def forward(self):
        if self.can_forward:
            self.index += 1
        return self.stack[self.index]


def test_history_walks_visited_pages_in_both_directions():
    h = History()
    page = h.go_to(2, 0, 6)
    assert page == 2 and not h.can_back and not h.can_forward
    page = h.go_to(5, page, 6)
    page = h.go_to(0, page, 6)
    assert h.can_back and not h.can_forward
    assert h.back() == 5
    assert h.back() == 2
    assert h.forward() == 5
    assert h.forward() == 0
    assert not h.can_forward


def test_history_truncates_the_future_when_a_new_page_is_visited():
    h = History()
    page = h.go_to(1, 0, 6)
    page = h.go_to(2, page, 6)
    assert h.back() == 1
    assert h.can_forward
    page = h.go_to(4, 2, 6)  # branching drops 2 from the forward history
    assert not h.can_forward
    assert h.stack == [1, 4]
    assert page == 4


def test_history_is_bounded_and_first_last_respect_spreads():
    h = History()
    page = 0
    for _ in range(80):
        page = h.go_to(1 - page, page, 6)  # 0 ↔ 1; 80 visits, stack capped at 50
    assert len(h.stack) == 50 and h.index == 49
    # First is page 0; Last opens the final spread (pages 5+6 of six)
    assert h.go_to(0, page, 6) == 0
    last = 5 - (5 % 2)
    assert h.go_to(last, 0, 6) == last == 4  # 0-based index of the final spread


# ---- pure logic: bookmark keys and persistence (the real bridge) -----------


def test_bookmark_key_is_the_content_hash_so_a_rename_keeps_marks(tmp_path):
    first = tmp_path / "paper.pdf"
    renamed = tmp_path / "renamed.pdf"
    changed = tmp_path / "changed.pdf"
    body = b"%PDF-1.4\n" + b"the same bytes" * 40
    first.write_bytes(body)
    renamed.write_bytes(body)
    changed.write_bytes(body + b" edited")

    assert pdfform.file_key(str(first)) == pdfform.file_key(str(renamed))
    assert pdfform.file_key(str(first)) != pdfform.file_key(str(changed))
    assert len(pdfform.file_key(str(first))) == 32  # md5 hex


def test_bookmarks_add_remove_and_survive_a_reload(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    doc = tmp_path / "chapter.pdf"
    doc.write_bytes(b"%PDF-1.4 bookmarks")

    assert pdfform.bookmarks(str(doc)) == {"bookmarks": []}
    pdfform.bookmark_add(str(doc), 3, "Conclusions")
    pdfform.bookmark_add(str(doc), 0, "Cover")
    pdfform.bookmark_add(str(doc), 3, "duplicate")  # one mark per page
    assert pdfform.bookmarks(str(doc)) == {
        "bookmarks": [
            {"page": 0, "title": "Cover"},
            {"page": 3, "title": "Conclusions"},
        ]
    }
    assert (tmp_path / "config" / "shani" / "pdf-bookmarks.json").is_file()
    pdfform.bookmark_remove(str(doc), 0)
    assert pdfform.bookmarks(str(doc))["bookmarks"] == [
        {"page": 3, "title": "Conclusions"}
    ]
    renamed = tmp_path / "chapter-v2.pdf"
    renamed.write_bytes(b"%PDF-1.4 bookmarks")
    assert pdfform.bookmarks(str(renamed))["bookmarks"] == [
        {"page": 3, "title": "Conclusions"}
    ]


# ---- static: the service owns all four features ----------------------------


def test_service_reads_and_writes_per_document_bookmarks():
    s = read(SERVICE)
    assert "property var userBookmarks: []" in s
    assert 'formTool, "bookmarks", file' in s
    assert 'formTool, "bookmark-add", file' in s
    assert 'formTool, "bookmark-remove", file' in s
    assert "id: bmRead" in s and "id: bmWrite" in s
    assert "function loadExtras()" in s
    assert "function addBookmark(pageNo, title)" in s
    assert "function removeBookmark(pageNo)" in s
    assert s.count("userBookmarks = []") >= 4  # load + open + close + read-error


def test_service_owns_a_bounded_history_with_first_last_and_spreads():
    s = read(SERVICE)
    for hook in (
        "property var navHistory: []",
        "property int navIndex: -1",
        "readonly property bool canNavBack:",
        "readonly property bool canNavForward:",
        "function navBack()",
        "function navForward()",
        "function firstPage() { goTo(0); }",
        "function lastPage()",
        "navHistory.length > 50",
        "navHistory.slice(0, navIndex + 1)",
        "function nextSpread()",
        "function prevSpread()",
    ):
        assert hook in s, hook
    assert "goTo(facingActive ? n - (n % 2) : n)" in s, "Last opens the final spread"
    # a search hit and each Find step are visits, so Back can walk them
    assert "goTo(hits[0].page)" in s
    assert "goTo(pagesWith[0])" in s
    assert s.count("goTo(highlight.page)") == 2


def test_service_reads_saved_annotations_for_the_list():
    s = read(SERVICE)
    assert "property var annotations: []" in s
    assert 'formTool, "annotations", file' in s
    assert "id: annRead" in s
    assert "root.annotations = r.annotations || []" in s
    assert "annotations = []" in s  # cleared on open/close


def test_service_validates_the_print_range_before_spooling():
    s = read(SERVICE)
    assert "function validPageRange(text, count)" in s
    assert r"/^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$/.test(s)" in s
    assert "from < 1 || to > count || from > to" in s
    assert "function printFile(range)" in s
    assert (
        'Quickshell.execDetached(["lp", "-o", "page-ranges=" + spec, "--", root.pdf || file])'
        in s
    )
    assert 'printState = "invalid page range"' in s
    assert "Printing.printFile(root.pdf || file)" in s  # empty range = whole document


# ---- static: the reader exposes the extras ---------------------------------


def test_reader_has_named_keyboard_accessible_bookmark_and_annotation_rows():
    m = read(READER)
    assert 'property string extraPanel: ""' in m
    assert 'win.toggleExtra("bookmarks")' in m
    assert 'win.toggleExtra("annotations")' in m
    assert "model: PdfViewer.userBookmarks" in m
    assert "PdfViewer.addBookmark(PdfViewer.page, bookmarkTitle.text)" in m
    assert "PdfViewer.removeBookmark(modelData.page)" in m
    assert 'model: win.extraPanel === "annotations" ? PdfViewer.annotations : []' in m
    assert m.count("PdfViewer.goTo(modelData.page)") >= 2, "both lists jump to a page"
    # row activation is available to a keyboard / screen-reader user too
    assert m.count("KeyFocus { onActivated: PdfViewer.goTo(modelData.page) }") == 2
    assert 'Accessible.name: Tr.t("Bookmark page %1", modelData.page + 1)' in m
    assert 'Accessible.name: modelData.type + " · "' in m


def test_reader_has_back_forward_and_first_last_controls():
    m = read(READER)
    for hook in (
        'tip: Tr.t("First page")',
        'tip: Tr.t("Previous page")',
        'tip: Tr.t("Back")',
        'tip: Tr.t("Forward")',
        'tip: Tr.t("Last page")',
        "PdfViewer.firstPage()",
        "PdfViewer.navBack()",
        "PdfViewer.navForward()",
        "PdfViewer.lastPage()",
        "enabled: PdfViewer.canNavBack",
        "enabled: PdfViewer.canNavForward",
        "Qt.Key_BracketLeft",
        "Qt.Key_BracketRight",
    ):
        assert hook in m, hook


def test_reader_has_a_validated_print_range_dialog():
    m = read(READER)
    assert "property bool printShown: false" in m
    assert "win.printShown = false" in m  # resets with the document / after printing
    assert 'tip: Tr.t("Print (P)")' in m
    assert "on: win.printShown" in m
    assert "id: printRangeField" in m
    assert 'label: Tr.t("Page range")' in m
    assert 'placeholder: Tr.t("Page range (e.g. 1-5), or all")' in m
    assert (
        "enabled: PdfViewer.validPageRange(printRangeField.text, PdfViewer.pageCount)"
        in m
    )
    assert "PdfViewer.printFile(printRangeField.text)" in m
    assert "printShown ? printShown = false :" in m, "Esc closes the top-most card"
