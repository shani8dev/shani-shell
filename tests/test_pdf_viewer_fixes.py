"""Small static regressions for five PDF/Viewer fixes not covered elsewhere:

1. document-scoped properties and panels reset when a new file is opened;
2. annotation strokes cleared when the page turns (they are page-specific);
3. Copy page text reports success or the empty-page case;
4. the Viewer's two-click trash confirmation is declared and shared by Del;
5. dragging at fit zoom no longer pans the picture off-centre.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


PDF = "shani/Modules/PdfReader/PdfReader.qml"
VIEWER = "shani/Modules/Viewer/Viewer.qml"


def test_pdf_resets_document_scoped_state_on_file_change():
    """Opening another PDF must not keep the old pdfinfo card or open panels."""
    text = read(PDF)
    block = re.search(
        r"Connections\s*\{\s*target:\s*PdfViewer\s*(.*?)\n    \}", text, re.S
    )
    assert block, "a Connections block watches PdfViewer"
    body = block.group(1)
    handler = re.search(r"function onFileChanged\(\)\s*\{(.*?)\}", body, re.S)
    assert handler, "onFileChanged resets the per-document UI"
    for stmt in (
        "PdfViewer.info = null",
        'win.extraPanel = ""',
        "win.mergeSplitShown = false",
        "win.pdfAnnoMode = false",
        "win.clearMarks()",
        'win.note = ""',
    ):
        assert stmt in handler.group(1), f"file change does not reset: {stmt}"


def test_pdf_clears_strokes_when_the_page_changes():
    """Strokes saved after a page turn would be stamped on the wrong page."""
    text = read(PDF)
    block = re.search(
        r"Connections\s*\{\s*target:\s*PdfViewer\s*(.*?)\n    \}", text, re.S
    )
    assert block
    handler = re.search(r"function onPageChanged\(\)\s*\{([^\n]*)\}", block.group(1))
    assert handler and "win.clearMarks()" in handler.group(1)


def test_pdf_copy_text_reports_result():
    """The copy button uses the bool copyPageText() returns, with a note."""
    text = read(PDF)
    button = re.search(r"IconButton \{[^\n]*Copy this page's text[^\n]*\}", text)
    assert button, "copy page text button"
    code = button.group(0)
    assert "win.note = PdfViewer.copyPageText() ?" in code
    assert 'Tr.t("Copied this page\'s text")' in code
    assert 'Tr.t("This page has no text to copy")' in code


def test_viewer_trash_confirmation_is_declared_and_shared():
    """trashConfirm was used without being declared; Del bypassed the guard."""
    text = read(VIEWER)
    assert re.search(r"property string trashConfirm:\s*\"\"", text)
    assert "function askTrash()" in text
    assert 'Viewer.trash(); trashConfirm = "";' in text
    assert "trashConfirmTimer.restart()" in text
    # toolbar and keyboard go through the same two-click path
    assert re.search(r"onClicked:\s*win\.askTrash\(\)", text)
    assert "Qt.Key_Delete || e.key === Qt.Key_Backspace) win.askTrash();" in text
    assert "Qt.Key_Backspace) Viewer.trash();" not in text


def test_viewer_does_not_pan_at_fit_zoom():
    """A fit picture shows an Arrow cursor, so dragging must not move it."""
    text = read(VIEWER)
    at = text.index("Viewer.panX = win.dragPanX")
    start = text.rfind("onPositionChanged", 0, at)
    assert start >= 0, "the pan handler"
    body = text[start:at]
    assert "Viewer.zoom <= 1.05" in body, "fit zoom is excluded from panning"
