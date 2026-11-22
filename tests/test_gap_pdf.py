"""Gaps closed in the Document Viewer: the reader's own bookmarks (JSON keyed by
md5), clickable links, embedded attachments, annotations, plus the reader UI
wiring for navigation history, search options, radio forms and merge/split.
Bookmarks run for real; the PyMuPDF-backed readers are tested with a fake doc.
"""

import importlib.util
import json
import os
import subprocess
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "bridge" / "pdfform.py"


def fetch_module():
    """Load pdfform.py with a fake PyMuPDF so its doc-taking helpers are testable."""
    fitz = types.ModuleType("fitz")
    for k, v in dict(
        LINK_GOTO=1,
        LINK_URI=2,
        LINK_NAMED=4,
        LINK_GOTOR=5,
        PDF_WIDGET_TYPE_TEXT=1,
        PDF_WIDGET_TYPE_CHECKBOX=2,
        PDF_WIDGET_TYPE_COMBOBOX=3,
        PDF_WIDGET_TYPE_LISTBOX=4,
        PDF_WIDGET_TYPE_RADIOBUTTON=5,
    ).items():
        setattr(fitz, k, v)
    sys.modules["fitz"] = fitz
    spec = importlib.util.spec_from_file_location("pdfform_gap", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, fitz


def run(home, *args):
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / "cfg"))
    r = subprocess.run(
        [sys.executable, str(TOOL), *map(str, args)],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    return json.loads(r.stdout)


def test_bookmarks_keyed_by_document_md5(tmp_path):
    cfg = tmp_path / "cfg"
    cfg.mkdir()
    doc = tmp_path / "my doc.pdf"
    doc.write_bytes(b"%PDF-1.4 hello")
    copy = tmp_path / "renamed.pdf"
    copy.write_bytes(b"%PDF-1.4 hello")  # same bytes -> same md5
    assert run(tmp_path, "bookmarks", doc)["bookmarks"] == []
    run(tmp_path, "bookmark-add", doc, 3, 'Chapter "X"')
    run(tmp_path, "bookmark-add", copy, 1, "Intro")  # same key through a new name
    marks = run(tmp_path, "bookmarks", doc)["bookmarks"]
    assert [m["page"] for m in marks] == [1, 3]  # kept ordered by page
    assert {m["title"] for m in marks} == {"Intro", 'Chapter "X"'}
    run(tmp_path, "bookmark-add", doc, 3, "duplicate")  # no second mark on a page
    assert len(run(tmp_path, "bookmarks", doc)["bookmarks"]) == 2
    marks = run(tmp_path, "bookmark-remove", doc, 3)["bookmarks"]
    assert [m["page"] for m in marks] == [1]
    store = cfg / "shani" / "pdf-bookmarks.json"
    assert store.exists() and len(json.loads(store.read_text())) == 1


def test_links_attachments_and_annotations_from_a_doc():
    mod, fitz = fetch_module()

    class Doc:
        def __init__(self):
            self.pages, self.embs = [], []

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def __iter__(self):
            return iter(self.pages)

        def embfile_count(self):
            return len(self.embs)

        def embfile_info(self, i):
            return self.embs[i]["info"]

        def embfile_get(self, i):
            return self.embs[i]["data"]

    doc = Doc()
    fitz.open = lambda *a, **k: doc

    class Page:
        def __init__(self, links, annots):
            self._links, self._annots = links, annots

        def get_links(self):
            return self._links

        def annots(self):
            return self._annots

    class Annot:
        type = (8, "Highlight")
        info = {"content": "note", "title": "me"}

    doc.pages = [
        Page(
            [
                {"kind": 1, "page": 4},
                {"kind": 2, "uri": "https://example.org"},
                {"kind": 4, "name": "Dest"},
                {"kind": 99},
            ],
            [Annot()],
        )
    ]
    doc.embs = [{"info": {"name": "notes.txt", "size": 3}, "data": b"abc"}]
    assert mod.links("x")["links"] == [
        {"page": 0, "kind": "goto", "target": 5},
        {"page": 0, "kind": "uri", "uri": "https://example.org"},
        {"page": 0, "kind": "named", "name": "Dest"},
    ]
    assert mod.attachments("x")["attachments"] == [
        {"index": 0, "name": "notes.txt", "size": 3}
    ]
    anns = mod.annotations("x")["annotations"]
    assert (
        anns[0]["type"] == "Highlight"
        and anns[0]["content"] == "note"
        and anns[0]["page"] == 0
    )


def test_radio_widgets_expose_their_states():
    mod, fitz = fetch_module()

    class Widget:
        field_type = fitz.PDF_WIDGET_TYPE_RADIOBUTTON
        field_name = "choice"
        field_label = "Pick one"
        field_value = "Yes"

        def button_states(self):
            return {"Yes": 1, "No": 2, "Off": 0}

    class Page:
        number = 0

        def widgets(self):
            return [Widget()]

    class Doc:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def __iter__(self):
            return iter([Page()])

    fitz.open = lambda *a, **k: Doc()
    f = mod.fields("x")[0]
    assert f["type"] == "radio" and sorted(f["options"]) == ["No", "Yes"]


def test_pdf_ui_wiring():
    svc = (ROOT / "shani/Services/PdfViewer.qml").read_text(encoding="utf-8")
    reader = (ROOT / "shani/Modules/PdfReader/PdfReader.qml").read_text(
        encoding="utf-8"
    )
    # bookmarks, links, attachments and annotations all reach pdfform.py
    for cmd in (
        "bookmarks",
        "bookmark-add",
        "bookmark-remove",
        "links",
        "attachments",
        "attachment-save",
        "annotations",
    ):
        assert '"' + cmd + '"' in svc, cmd
    assert (
        "userBookmarks" in svc
        and "pdfLinks" in svc
        and "attachments" in svc
        and "annotations" in svc
    )
    # navigation history and first/last page
    assert all(
        f in svc
        for f in ("navHistory", "navBack", "navForward", "firstPage", "lastPage")
    )
    # search options instead of an always-lowercased needle
    assert all(f in svc for f in ("caseSensitive", "wholeWord", "wrapSearch", "_hits"))
    # reader UI: radios, extras panels and the merge/split dialog
    assert (
        'modelData.type === "radio"' in reader
        and "doSplit()" in reader
        and "doMerge()" in reader
    )
    assert all(
        s in reader
        for s in ("bookmarks", "links", "attachments", "annotations", "Your bookmarks")
    )
    assert "firstPage()" in reader and "lastPage()" in reader and "canNavBack" in reader
