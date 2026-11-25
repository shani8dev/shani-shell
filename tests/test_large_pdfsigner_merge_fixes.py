"""Pds/merge fixes for the PDF signer (Services/PdfSigner.qml +
Modules/PdfSigner/PdfSignerPanel.qml): the page-range editor, add-stamps
(date/page numbers + stamp text), password protect (pdftk), bookmarks
export/import and the PAdES signatures review (pdfsig).

Static checks read the QML; the two runtime checks extract the embedded JS
(validPageRange/pagesIn) and the embedded python (the bookmarks importer)
and run them for real.
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SIGNER = ROOT / "shani" / "Services/PdfSigner.qml"
SIGNED_PANEL = ROOT / "shani" / "Modules/PdfSigner/PdfSignerPanel.qml"

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")


def read(p):
    return Path(p).read_text(encoding="utf-8")


def _save_script(t):
    m = re.search(r"const script = \[(.*?)\]\.join", t, re.S)
    assert m, "save() has no embedded script array"
    lines = re.findall(r"'((?:[^'\\]|\\.)*)'", m.group(1))
    out = []
    for line in lines:
        out.append(line.replace("\\'", "'").replace("\\n", "\n"))
    return "\n".join(out)


def _js_between(t, start_marker, end_marker):
    s = t.index(start_marker)
    e = t.index(end_marker, s)
    return t[s:e]


# ---- the page-range editor ----------------------------------------------------


def test_service_has_valid_page_range():
    t = read(SIGNER)
    assert "function validPageRange(" in t
    assert "function pagesIn(" in t
    assert "function setPageRange(" in t
    assert 'rangeError = s !== "" && !ok' in t


@node_mark
def test_page_range_parser_runs_for_real():
    """validPageRange + pagesIn, extracted and run in node."""
    t = read(SIGNER)
    code = (
        "var Tr = { t: s => s }, PdfViewer = { pages: [1,2,3,4,5,6,7,8,9] };\n"
        + _js_between(t, "function validPageRange(", "// ---- password protect")
    )
    prog = (
        code
        + """
const assert = require("assert");
assert.equal(validPageRange("", 9), true, "empty range = every page");
assert.equal(validPageRange("1-3,5", 9), true);
assert.equal(validPageRange("10", 9), false, "out of range");
assert.equal(validPageRange("5-2", 9), false, "from > to");
assert.equal(validPageRange("0", 9), false, "from < 1");
assert.deepEqual(pagesIn("2-4,7", 9), [2, 3, 4, 7], "sorted, unique");
assert.deepEqual(pagesIn("3,1", 9), [1, 3]);
assert.deepEqual(pagesIn("", 9), [], "empty range = every page");
process.stdout.write("ok");
"""
    )
    r = subprocess.run([node, "-e", prog], capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "ok"


def test_save_script_stamps_only_the_range_pages():
    t = read(SIGNER)
    script = _save_script(t)
    assert "RANGE" in script and "STAMPTEXT" in script and "STAMPPN" in script
    assert "in_range" in script and "stamp_one" in script
    assert script.count("in_range") >= 2, "the range gates the stamp loop"
    assert 'saveProc.command = ["bash", "-c", script, "bash",' in t
    assert 'range.join(",")' in t, "the parsed range reaches the script"
    assert 'stampText || ""' in t and 'stampDate ? "1" : ""' in t


def test_save_script_is_valid_bash(tmp_path):
    script = _save_script(read(SIGNER))
    p = tmp_path / "save.sh"
    p.write_text(script, encoding="utf-8")
    r = subprocess.run(["bash", "-n", str(p)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


# ---- add-stamps ---------------------------------------------------------------


def test_service_has_stamp_properties():
    t = read(SIGNER)
    for prop in (
        "property string stampText:",
        "property bool stampDate:",
        "property bool stampPageNumber:",
        "function setStampText(",
    ):
        assert prop in t, prop
    assert "$(date +%F)" in t and "$(date +%T)" in t and "Page $2" in t
    assert "0-30" in t, "page number stamp"


# ---- password protect ----------------------------------------------------------


def test_service_protects_with_pdftk():
    t = read(SIGNER)
    assert "function protect(" in t
    assert "pdftk" in t and "encrypt" in t
    assert 'protectOut = file + " - protected.pdf"' in t
    assert "function setPassword(" in t
    assert "protectProc" in t and "Process {" in t


# ---- bookmarks export / import --------------------------------------------------


def test_service_exports_and_imports_bookmarks():
    t = read(SIGNER)
    assert "function exportBookmarks(" in t
    assert "function importBookmarks(" in t
    assert "PdfViewer.userBookmarks" in t, "export reads the reader's bookmarks"
    assert "PdfViewer.addBookmark(" in t, "import adds to the reader"
    assert "JSON.stringify" in t and "json" in t


def _import_bookmarks_code(t):
    # unescape the JS string the way the QML engine would (\\' -> ', \n -> newline)
    s = t.index("python3 -c ") + len("python3 -c ")
    e = t.index('"$1"', s)
    code = t[s:e].replace("\\'", "'").replace("\\n", "\n").strip().strip("'")
    assert code.startswith("import json"), code
    return code


def test_import_bookmarks_python_runs_for_real(tmp_path):
    """The embedded importer parses the exported JSON lines."""
    code = _import_bookmarks_code(read(SIGNER))
    src = tmp_path / "bm.jsonl"
    src.write_text(
        '{"page": 0, "title": "Intro"}\n{"page": 2, "title": "Second"}\n',
        encoding="utf-8",
    )
    r = subprocess.run(
        [sys.executable, "-c", code, str(src)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert r.returncode == 0, r.stderr
    assert r.stdout.splitlines() == ["0\tIntro", "2\tSecond"], r.stdout


# ---- PAdES signatures review -----------------------------------------------------


def test_service_lists_signatures():
    t = read(SIGNER)
    assert "function signatures(" in t
    assert "pdfsig" in t and "sigProc" in t


# ---- the panel -------------------------------------------------------------------


def test_panel_has_the_new_controls():
    t = read(SIGNED_PANEL)
    for want in (
        "Pages to stamp",
        "Pages, stamps, password",
        "Stamp text",
        "Protect with password",
        "Show signatures",
        "Export bookmarks",
        "Import bookmarks",
        "bmFileDlg",
        "setPageRange(",
        "setStampText(",
        "setPassword(",
        "rangeError",
    ):
        assert want in t, want
    assert "FileDialog" in t, "the bookmarks import picker"
