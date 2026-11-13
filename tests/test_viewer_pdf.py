"""Viewer + PdfReader rich parity (feature-viewer-pdf-rich).

Loupe side: zoom to cursor, fit/100%/200%, rotate + flip, slideshow,
thumbnail strip, EXIF-aware rotation, copy path, open-with, delete-to-trash,
batch grid mode.
Papers/Evince side: page thumbnails sidebar, text search (pdftotext -bbox
highlight, with a jump-to-page box), outline/bookmarks, fit-width/fit-page,
continuous scroll, rotation, print via lp (Printing.printFile).

Static checks mirror tests/test_wiring.py: every Ui member used is declared,
the new surfaces are reachable (shell IPC + state), and the laundry that must
never regress — the command strings the services shell out to — is present.
"""
import importlib.machinery
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin" / "shani"))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


# ---- image viewer (Loupe parity) --------------------------------------------

def test_viewer_zooms_to_cursor_and_fits():
    t = read("shani/Services/Viewer.qml")
    assert "zoomToCursor" in t, "zoom to cursor"
    assert "zoomFit" in t and "zoomActual" in t and "zoom200" in t, "fit/100%/200%"
    assert 'zoomMode' in t and '"fit"' in t and '"100"' in t and '"200"' in t
    m = read("shani/Modules/Viewer/Viewer.qml")
    assert "zoomToCursor" in m, "wheel must zoom to the cursor"
    for tip in ["Fit to window", "100%", "200%"]:
        assert tip in m, tip


def test_viewer_rotates_and_flips():
    t = read("shani/Services/Viewer.qml")
    assert "rotateCCW" in t and "toggleFlipH" in t and "toggleFlipV" in t
    assert "flipH" in t and "flipV" in t
    m = read("shani/Modules/Viewer/Viewer.qml")
    assert "Flip horizontally" in m and "Flip vertically" in m


def test_viewer_slideshow_thumbs_and_grid():
    t = read("shani/Services/Viewer.qml")
    assert "slideshow" in t and "gridMode" in t and "showThumbs" in t
    assert "interval: 3500" in t, "slideshow timer"
    m = read("shani/Modules/Viewer/Viewer.qml")
    assert "Slideshow" in m and "Grid" in m and "Thumbnails" in m
    assert "thumbRow" in m, "thumbnail strip"
    assert "gridMode" in m, "batch grid mode"


def test_viewer_exif_copy_openwith_trash():
    t = read("shani/Services/Viewer.qml")
    assert "EXIF" in t and "Orientation" in t and "274" in t, "EXIF Orientation (274)"
    assert "exifToRotation" in t, "EXIF → rotation mapping"
    assert "clipboardText" in t, "copy path"
    assert "lastCopied" in t
    assert '"gio", "open"' in t, "open-with via gio"
    assert '"gio", "trash"' in t, "delete-to-trash"
    assert "trashLast" in t
    m = read("shani/Modules/Viewer/Viewer.qml")
    assert "Copy path" in m and "Open with" in m and "Move to trash" in m


# ---- PDF reader (Papers parity) ---------------------------------------------

def test_pdf_sidebar_search_outline():
    t = read("shani/Services/PdfViewer.qml")
    assert "pdftotext -bbox" in t, "bbox word boxes for the highlight"
    assert "pdftotext -layout" in t, "fallback page texts"
    assert "searchWords" in t and "highlight" in t
    assert "findNext" in t and "findPrev" in t
    assert "import pymupdf" in t and "get_toc()" in t, "outline via PyMuPDF"
    assert "mutool" not in t, "PyMuPDF does what mutool did; mupdf-tools is no longer a dependency"
    assert "outline" in t and "goToOutline" in t
    m = read("shani/Modules/PdfReader/PdfReader.qml")
    assert "Find in document" in m, "search box"
    assert "Go to page" in m, "jump-to-page box"
    assert "jumpField" in m and "searchField" in m
    assert "Find previous" in m and "Find next" in m
    assert "sidebar" in m.lower() or "thumbnails" in m.lower(), "page thumbnails sidebar"
    assert "outline" in m.lower(), "outline/bookmarks UI"


def test_pdf_fit_continuous_rotation_print():
    t = read("shani/Services/PdfViewer.qml")
    assert 'fitMode' in t and '"page"' in t and '"width"' in t and '"actual"' in t, "fit-width/fit-page"
    assert "continuous" in t, "continuous scroll option"
    assert "toggleContinuous" in t
    assert "rotation" in t and "rotateCCW" in t
    assert "lp" in t and "Printing.printFile" in t, "print via lp backend"
    assert "printFile" in t
    p = read("shani/Services/Printing.qml")
    assert "printFile" in p and '"lp"' in p, "Printing.printFile backend"
    m = read("shani/Modules/PdfReader/PdfReader.qml")
    assert "Fit page" in m and "Fit width" in m, "fit-width/fit-page buttons"
    assert "Continuous scroll" in m
    assert "Print" in m


# ---- registration: Ui + shell + CLI -----------------------------------------

def test_every_ui_member_used_is_declared():
    ui = read("shani/Common/Ui.qml")
    import re
    declared = set(re.findall(r"(?:property [\w<>]+|function|signal) (\w+)", ui))
    assert "viewer" in declared and "pdfReader" in declared
    used = set()
    for rel in ["shani/Services/Viewer.qml", "shani/Services/PdfViewer.qml",
                "shani/Modules/Viewer/Viewer.qml", "shani/Modules/PdfReader/PdfReader.qml",
                "shani/shell.qml"]:
        used.update(re.findall(r"\bUi\.(\w+)", read(rel)))
    assert used - declared == set(), f"Ui members used but not declared: {used - declared}"


def test_shell_reaches_the_surfaces():
    shell = read("shani/shell.qml")
    for fn in ["openViewer", "closeViewer", "viewerNext", "viewerPrev", "viewerGoTo",
               "viewerZoomIn", "viewerZoomOut", "viewerZoomFit", "viewerZoomActual", "viewerZoom200",
               "viewerRotate", "viewerRotateCCW", "viewerFlipH", "viewerFlipV",
               "viewerSlideshow", "viewerGrid", "viewerThumbs", "viewerCopy",
               "viewerOpenWith", "viewerTrash",
               "openPdf", "closePdf", "pdfNext", "pdfPrev", "pdfGoTo", "pdfSearch",
               "pdfFindNext", "pdfFindPrev", "pdfRotate", "pdfFit", "pdfContinuous",
               "pdfSidebar", "pdfPrint", "pdfOutlineGoTo"]:
        assert f"function {fn}" in shell, f"shell IPC missing {fn}"
    for key in ["viewerShown", "viewerFile", "viewerZoom", "pdfShown", "pdfFile", "pdfPage", "pdfPages"]:
        assert key in shell, f"state missing {key}"
    assert "Viewer" in shell and "PdfViewer" in shell
    assert "Viewer.close()" in shell and "PdfViewer.close()" in shell, "dismissAll closes both"


def test_cli_reaches_the_surfaces():
    m = cli()
    assert "viewer" in m.GROUPS and "pdf" in m.GROUPS
    viewer = {name for name, _, _ in m.GROUPS["viewer"]}
    for want in ["open", "close", "next", "prev", "go-to", "zoom-in", "zoom-out",
                 "zoom-fit", "zoom-100", "zoom-200", "rotate", "rotate-ccw",
                 "flip-h", "flip-v", "slideshow", "grid", "thumbs",
                 "copy-path", "open-with", "open-with-app", "trash"]:
        assert want in viewer, f"viewer CLI missing {want}"
    pdf = {name for name, _, _ in m.GROUPS["pdf"]}
    for want in ["open", "close", "next", "prev", "go-to", "search", "find-next",
                 "find-prev", "rotate", "fit", "continuous", "sidebar", "print", "outline-go-to"]:
        assert want in pdf, f"pdf CLI missing {want}"
    assert m._fn_name("viewer", "open") == "openViewer"
    assert m._fn_name("viewer", "zoom-fit") == "viewerZoomFit"
    assert m._fn_name("viewer", "trash") == "viewerTrash"
    assert m._fn_name("pdf", "open") == "openPdf"
    assert m._fn_name("pdf", "print") == "pdfPrint"
    assert m._fn_name("pdf", "search") == "pdfSearch"


def test_viewer_and_pdf_have_no_positioner_feedback_loop():
    import re
    # the same rule as tests/test_qml_patterns.py, pinned to these surfaces
    positioners = {"Flow", "Row", "Grid", "Column"}
    for rel in ["shani/Modules/Viewer/Viewer.qml", "shani/Modules/PdfReader/PdfReader.qml"]:
        stack = []
        for n, line in enumerate(read(rel).split("\n"), 1):
            m = re.match(r"\s*([A-Z]\w*) \{\s*$", line)
            enclosing = [t for t, _ in stack]
            one = re.match(r"\s*[A-Z]\w* \{.*\bwidth: parent\.width\b", line)
            if one and enclosing and enclosing[-1] in positioners:
                raise AssertionError(f"{rel}:{n} sizes a child to its positioner")
            if m:
                stack.append((m.group(1), len(line) - len(line.lstrip())))
            elif line.strip() == "}" and stack:
                stack.pop()
