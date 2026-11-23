"""Static guards for the pass-20 creative-tools fixes: an unsaved whiteboard
confirms before closing (saving first), a failed PDF save clears the saving
state instead of blocking every later save, and Annotate's pen is DPI-aware."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WHITEBOARD = ROOT / "shani/Modules/Whiteboard/Whiteboard.qml"
ANNOTATE = ROOT / "shani/Modules/Annotate/Annotate.qml"


def test_close_confirms_then_saves_before_closing():
    t = WHITEBOARD.read_text()
    assert "no autosave" in t
    assert "property bool closeArmed: false" in t
    assert "property bool closeAfterSave: false" in t
    assert (
        "function dirty() { return Ui.whiteboardStrokes > 0 || pages.length > 1; }" in t
    )
    assert 'note = Tr.t("Tap close again to save and close")' in t
    assert "if (!closeArmed && dirty()) {" in t
    assert "closeAfterSave = true;" in t and "the one path that writes a PDF" in t
    assert (
        "if (win.closeAfterSave) { win.closeAfterSave = false; Ui.whiteboard = false; }"
        in t
    )
    assert "Qt.Key_Escape) win.requestClose()" in t
    assert 'Close the whiteboard"); onClicked: win.requestClose()' in t


def test_save_failure_clears_saving_and_surfaces_an_error():
    t = WHITEBOARD.read_text()
    assert "onExited: code => {" in t
    assert "if (win.saving < 0) return;" in t
    assert "never block every later save on one failure" in t
    assert 'win.note = Tr.t("Save failed — is PyMuPDF installed?")' in t
    assert 'Tr.t("Whiteboard save failed")' in t
    assert "win.closeAfterSave = false;" in t


def test_annotate_pen_width_scales_with_dpi():
    t = ANNOTATE.read_text()
    assert "g.lineWidth = Theme.px(5);" in t
    assert "g.lineWidth = 5;" not in t
