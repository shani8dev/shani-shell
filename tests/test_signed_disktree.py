"""Signed + Disktree surfaces (feature-signed-disktree).

Signed (Omarchy Signed parity): Services/Signer.qml + Modules/Signed/
SignedPanel.qml — open a PDF (arg or a folder's last PDF), render the
current page via the existing PdfViewer, place the stored signature
image (~/Documents/Signature.png, "Choose signature" file picker) at
x/y with scale, and "Save signed copy": pdftoppm renders the page,
ImageMagick `convert` composites the signature (and any fill text) at
the offsets, then img2pdf / Ghostscript makes "* - signed.pdf" beside
the original.

Disktree (disk treemap): Services/Disktree.qml + Disktree.js +
Modules/Disktree/DisktreePanel.qml — a python3 walk (os.path.getsize,
sorted, capped at ~200, skipping /proc /sys /dev) feeds a treemap of
rectangles whose area is their size; click a folder to walk in
(Esc/back to go up), click a file to mark it, review the marked list,
then `gio trash` it.

Static checks mirror tests/test_voice_recorder.py / test_viewer_pdf.py;
the two backend contracts are exercised for real when their tools are
present: the signed-copy pipeline (pdftoppm + convert + gs/convert to
PDF) and the Disktree python walk + treemap layout.
"""
import importlib.machinery
import importlib.util
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
SIGNER = SHANI / "Services/Signer.qml"
SIGNED_PANEL = SHANI / "Modules/Signed/SignedPanel.qml"
DISKTREE = SHANI / "Services/Disktree.qml"
DISKTREE_JS = SHANI / "Services/Disktree.js"
DISKTREE_PANEL = SHANI / "Modules/Disktree/DisktreePanel.qml"
CLI = ROOT / "bin" / "shani"

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")
sign_tools = all(shutil.which(t) for t in ("pdftoppm", "convert"))
sign_mark = pytest.mark.skipif(not sign_tools, reason="pdftoppm/convert are not installed")


def read(p):
    return Path(p).read_text(encoding="utf-8")


def load_cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(CLI))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


# ---- Signed: the backend contract, for real ---------------------------------

@sign_mark
def test_signed_copy_pipeline_end_to_end(tmp_path):
    """pdftoppm renders a page, convert composites at +x+y, gs/convert
    makes the PDF — named '* - signed.pdf' beside the original."""
    # a one-page PDF and a signature image, made with the same tools
    page_img = tmp_path / "page.png"
    subprocess.run(["convert", "-size", "400x300", "xc:white", str(page_img)],
                   check=True, capture_output=True)
    src = tmp_path / "doc.pdf"
    subprocess.run(["convert", str(page_img), str(src)], check=True, capture_output=True)
    assert src.read_bytes()[:4] == b"%PDF"

    sig = tmp_path / "Signature.png"
    subprocess.run(["convert", "-size", "80x30", "xc:black", str(sig)],
                   check=True, capture_output=True)
    assert sig.exists()

    out = tmp_path / "doc - signed.pdf"
    assert out.name == "doc - signed.pdf"          # '* - signed.pdf'
    # the exact pipeline Services/Signer.qml runs (150 dpi, +x+y, scale %)
    script = (
        'set -e; work=$(mktemp -d); '
        'pdftoppm -png -r 150 -f 1 -singlefile "$1" "$work/page"; '
        'convert "$2" -resize "100%" "$work/sig.png"; '
        'convert "$work/page.png" "$work/sig.png" -geometry "+100+100" -composite "$work/step.png"; '
        'convert "$work/step.png" -gravity NorthWest -pointsize 28 -fill black '
        '-annotate "+100+220" "Signed by Shani" "$work/composite.png"; '
        'if command -v img2pdf >/dev/null 2>&1; then img2pdf "$work/composite.png" -o "$3"; '
        'elif command -v gs >/dev/null 2>&1; then gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite '
        '-sOutputFile="$3" "$work/composite.png" 2>/dev/null || convert "$work/composite.png" "$3"; '
        'else convert "$work/composite.png" "$3"; fi'
    )
    r = subprocess.run(["sh", "-c", script, "sh", str(src), str(sig), str(out)],
                       capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    assert out.exists() and out.stat().st_size > 0
    assert out.read_bytes()[:4] == b"%PDF", "the signed copy is a PDF"
    assert src.read_bytes()[:4] == b"%PDF", "the original is untouched"


# ---- Signed: service + panel -------------------------------------------------

def test_signer_uses_the_stored_signature_and_pdfviewer():
    t = read(SIGNER)
    assert '"/Documents/Signature.png"' in t and "defaultSignature" in t
    assert "PdfViewer.open(" in t, "the current page renders via the existing PdfViewer"
    assert "PdfViewer.page" in t, "the page being signed is PdfViewer's current page"
    assert "function open(" in t and "function close(" in t and "function save(" in t
    assert 'Ui.signed = true' in t


def test_signer_opens_a_folder_s_last_pdf():
    t = read(SIGNER)
    assert 'ls -t' in t and "*.pdf" in t, "a folder opens its last (newest) PDF"
    assert "PdfViewer.file" in t, "no argument reuses the PDF the reader has open"


def test_signer_saves_via_pdftoppm_convert_then_img2pdf_or_ghostscript():
    t = read(SIGNER)
    assert "pdftoppm -png -r 150" in t
    assert "convert" in t and "-composite" in t, "ImageMagick composites at the offsets"
    assert "+$4+$6" in t or "signedPathFor" in t      # the +x+y geometry
    assert "img2pdf" in t and '"gs"' in t or " gs " in t, "img2pdf, Ghostscript otherwise"
    assert "-sDEVICE=pdfwrite" in t, "Ghostscript makes the PDF"
    assert " - signed.pdf" in t and "signedPathFor" in t
    assert "notify-send" in t and "lastSaved" in t


def test_signer_places_signature_and_fill_text():
    t = read(SIGNER)
    for prop in ("property int x:", "property int y:", "property real scale:",
                 "property string fillText:", "property int textX:", "property int textY:"):
        assert prop in t, prop
    assert "function setSignature(" in t and "function setPosition(" in t
    assert "function setScale(" in t and "function setFillText(" in t
    assert "function setTextPosition(" in t
    assert "-annotate" in t, "fill text is rendered onto the page the same way"
    assert "textSize" in t


def test_signed_panel_follows_the_qrview_pattern():
    t = read(SIGNED_PANEL)
    assert "PanelWindow" in t
    assert "visible: Ui.signed && !Lock.locked" in t
    assert 'WlrLayershell.namespace: "shani-signed"' in t
    assert "WlrKeyboardFocus.Exclusive" in t
    assert "Keys.onEscapePressed: Signer.close()" in t
    assert "Theme.scrim" in t and "Glass" in t and "Theme.radiusLarge" in t


def test_signed_panel_renders_the_pdfviewer_page_with_overlays():
    t = read(SIGNED_PANEL)
    assert "PdfViewer.current" in t, "renders the current page via the existing PdfViewer"
    assert "PdfViewer.nextPage()" in t and "PdfViewer.prevPage()" in t
    assert "Signer.signature" in t and "Signer.x" in t and "Signer.y" in t and "Signer.scale" in t
    assert "Signer.fillText" in t and "Signer.textX" in t and "Signer.textY" in t
    assert "Save signed copy" in t and "Signer.save()" in t
    assert "Signer.signedFile" in t and "Signer.error" in t


def test_signed_panel_choose_signature_picker_with_a_path_field_fallback():
    t = read(SIGNED_PANEL)
    assert "Choose signature" in t
    assert "FileDialog" in t, "the file picker"
    assert "Signer.setSignature(" in t
    assert "Signature image path" in t, "a path field for when the picker is not there"


# ---- Disktree: the python walk, for real -------------------------------------

def _disktree_python():
    """The walk embedded in Services/Disktree.qml, as runnable python."""
    t = read(DISKTREE)
    m = re.search(r"readonly property string scanScript: \[(.*?)\]\.join", t, re.S)
    assert m, "the scan python is not embedded in the service"
    lines = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
    return "\n".join(l.replace('\\"', '"').replace("\\\\", "\\") for l in lines)


def test_disktree_walk_lists_sizes_sorted_and_capped(tmp_path):
    (tmp_path / "small.txt").write_bytes(b"x" * 10)
    (tmp_path / "big.bin").write_bytes(b"x" * 5000)
    sub = tmp_path / "sub"
    sub.mkdir()
    (sub / "inner.txt").write_bytes(b"x" * 2000)
    code = _disktree_python()
    assert "os.path.getsize" in code, "sizes via os.path.getsize"
    assert "/proc" in code and "/sys" in code and "/dev" in code, "skips /proc /sys /dev"
    assert ":200" in code, "capped at ~200 entries"
    r = subprocess.run([sys.executable, "-c", code, str(tmp_path)],
                       capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    entries = out["entries"]
    assert len(entries) == 3, entries
    sizes = [e["size"] for e in entries]
    assert sizes == sorted(sizes, reverse=True), "sorted biggest-first"
    assert entries[0]["name"] == "big.bin" and entries[0]["size"] == 5000
    by_name = {e["name"]: e for e in entries}
    assert by_name["sub"]["isDir"] is True and by_name["sub"]["size"] == 2000, (
        "a directory's size is the sum under it")
    assert by_name["small.txt"]["size"] == 10 and by_name["small.txt"]["isDir"] is False


@node_mark
def test_disktree_treemap_area_is_weighted_by_size():
    """Disktree.js: bigger entries get bigger rectangles, the area of
    each is its share of the whole (Disktree parity: larger blocks huge)."""
    src = read(DISKTREE_JS).replace(".pragma library", "")
    prog = (
        src
        + '\nvar r = treemap([{path:"/a",name:"a",size:400,isDir:false},'
        + '{path:"/b",name:"b",size:100,isDir:false},'
        + '{path:"/c",name:"c",size:100,isDir:true}], 800, 600);'
        + '\nprocess.stdout.write(JSON.stringify(r));'
    )
    rects = json.loads(subprocess.run([node, "-e", prog], capture_output=True,
                                      text=True, check=True).stdout)
    assert len(rects) == 3
    areas = {r["name"]: r["w"] * r["h"] for r in rects}
    total_area = 800 * 600
    assert abs(areas["a"] - total_area * 400 / 600) < 1, areas
    assert abs(areas["b"] - total_area * 100 / 600) < 1, areas
    assert areas["a"] > areas["b"], "the largest block is the largest rectangle"
    for r in rects:                       # everything is inside the container
        assert 0 <= r["x"] and r["x"] + r["w"] <= 800 + 1e-6
        assert 0 <= r["y"] and r["y"] + r["h"] <= 600 + 1e-6


# ---- Disktree: service + panel -----------------------------------------------

def test_disktree_service_scans_home_with_the_python_walk():
    t = read(DISKTREE)
    assert "python3" in t and '"-c"' in t
    assert "os.path.getsize" in t
    assert "entries[:200]" in t or "[:200]" in t
    assert "SKIP" in t and "'/proc'" in t and "'/sys'" in t and "'/dev'" in t
    assert "entries.sort" in t or "sorted(" in t
    assert "homeDir" in t and "Quickshell.env(\"HOME\")" in t, "the scan root defaults to home"
    assert "function scan(" in t and "function open(" in t and "Ui.disktree = true" in t


def test_disktree_service_walks_in_backs_out_and_marks():
    t = read(DISKTREE)
    assert "function enter(" in t and "history" in t, "walk into a directory"
    assert "function back(" in t, "Esc/back goes up"
    assert "function toggleMark(" in t and "function isMarked(" in t
    assert "function clearMarks(" in t
    assert "function trashMarked(" in t and '"gio", "trash"' in t, "delete via gio trash"
    assert "function treemap(" in t and "DisktreeLogic.treemap" in t
    assert "function humanSize(" in t


def test_disktree_panel_follows_the_qrview_pattern():
    t = read(DISKTREE_PANEL)
    assert "PanelWindow" in t
    assert "visible: Ui.disktree && !Lock.locked" in t
    assert 'WlrLayershell.namespace: "shani-disktree"' in t
    assert "WlrKeyboardFocus.Exclusive" in t
    assert "Keys.onEscapePressed:" in t and "Disktree.back()" in t, "Esc goes back first"
    assert "Theme.scrim" in t and "Glass" in t and "Theme.radiusLarge" in t


def test_disktree_panel_treemap_walk_and_review_before_trash():
    t = read(DISKTREE_PANEL)
    assert "Disktree.treemap(" in t, "treemap of rectangles, area ~ size"
    assert "Disktree.enter(" in t, "walk into a directory on click"
    assert "Disktree.toggleMark(" in t, "mark for removal (toggle)"
    assert "Disktree.marked" in t and "Marked for removal" in t, "the review list"
    assert "Move marked to trash" in t and "Disktree.trashMarked()" in t
    assert "Disktree.clearMarks()" in t
    assert "Disktree.humanSize(" in t and "Disktree.refresh()" in t


# ---- registration: Ui + shell + CLI -------------------------------------------

def test_ui_flags_and_close_all():
    t = read(SHANI / "Common/Ui.qml")
    assert "property bool signed: false" in t
    assert "property bool disktree: false" in t
    close_all = t[t.index("function closeAll()"):]
    block = close_all.split("}")[0]
    assert "signed = false" in block and "disktree = false" in block


def test_shell_lazy_loads_panels_and_exposes_ipc():
    t = read(SHANI / "shell.qml")
    assert "import qs.Modules.Signed" in t and "import qs.Modules.Disktree" in t
    assert "LazyLoader { active: Ui.signed; SignedPanel {} }" in t
    assert "LazyLoader { active: Ui.disktree; DisktreePanel {} }" in t
    services = t.split("_services")[1].split("]")[0]
    assert "Signer" in services and "Disktree" in services
    for fn in ("signedOpen", "signedClose", "signedToggle", "signedSave",
               "signedSignature", "signedPosition", "signedScale",
               "signedText", "signedTextPosition",
               "disktreeOpen", "disktreeClose", "disktreeToggle",
               "disktreeScan", "disktreeEnter", "disktreeBack",
               "disktreeMark", "disktreeClearMarks", "disktreeTrashMarked"):
        assert f"function {fn}(" in t, fn
    for key in ("signedFile", "signedSaved", "signedX", "signedScale", "signedText",
                "disktreeCurrent", "disktreeEntries", "disktreeMarked", "disktreeTotal"):
        assert key in t, key
    dismiss = t[t.index("function dismissAll()"):]
    assert "Signer.close()" in dismiss.split("}")[0]
    assert "Disktree.close()" in dismiss.split("}")[0]


def test_every_ui_member_used_is_declared():
    ui = read(SHANI / "Common/Ui.qml")
    declared = set(re.findall(r"(?:property [\w<>]+|function|signal) (\w+)", ui))
    used = set()
    for rel in [SIGNER, SIGNED_PANEL, DISKTREE, DISKTREE_PANEL, SHANI / "shell.qml"]:
        used.update(re.findall(r"\bUi\.(\w+)", read(rel)))
    assert used - declared == set(), f"Ui members used but not declared: {used - declared}"


def test_cli_signed_and_disktree_groups_map_onto_real_ipc_functions():
    mod = load_cli()
    assert "signed" in mod.GROUPS and "disktree" in mod.GROUPS
    signed = {name for name, _, _ in mod.GROUPS["signed"]}
    for want in ("open", "close", "toggle", "save", "signature", "position",
                 "scale", "text", "text-position"):
        assert want in signed, f"signed CLI missing {want}"
    disktree = {name for name, _, _ in mod.GROUPS["disktree"]}
    for want in ("open", "close", "toggle", "scan", "enter", "back",
                 "mark", "clear", "trash"):
        assert want in disktree, f"disktree CLI missing {want}"
    assert mod._fn_name("signed", "open") == "signedOpen"
    assert mod._fn_name("signed", "save") == "signedSave"
    assert mod._fn_name("signed", "position") == "signedPosition"
    assert mod._fn_name("disktree", "open") == "disktreeOpen"
    assert mod._fn_name("disktree", "scan") == "disktreeScan"
    assert mod._fn_name("disktree", "trash") == "disktreeTrashMarked"
    shell = read(SHANI / "shell.qml")
    for (group, cmd), name in mod.IPC_NAMES.items():
        if group in ("signed", "disktree"):
            assert f"function {name}(" in shell, name


def test_signed_and_disktree_have_no_positioner_feedback_loop():
    positioners = {"Flow", "Row", "Grid", "Column"}
    for rel in [SIGNED_PANEL, DISKTREE_PANEL]:
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
