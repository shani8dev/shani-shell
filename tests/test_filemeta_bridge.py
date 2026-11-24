"""The file-meta bridge and the three surfaces that show its answer.

The bridge answers from stdin-free argv calls and the stdlib; these tests use a
real temp file where they can, and a stubbed subprocess only to check that a
path is never handed to a shell. The QML hooks are pinned statically: Quick
Look, the Media Player and the Document Viewer need a live shell to render.
"""

import importlib.util
import json
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("filemeta", ROOT / "bridge/filemeta.py")
fm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fm)


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def png(path, w=37, h=19):
    """Just enough of a real PNG for a header read: signature, IHDR, no pixels."""
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + struct.pack(">I", 13)
        + b"IHDR"
        + struct.pack(">II", w, h)
        + bytes([8, 2, 0, 0, 0])
    )
    return path


def run(path):
    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/filemeta.py"), str(path)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


# ---- the bridge ------------------------------------------------------------


def test_a_real_file_has_the_promised_shape(tmp_path):
    path = png(tmp_path / "sample.png")
    got = run(path)
    assert got["type"] == "image/png"
    assert got["size"] == path.stat().st_size
    assert got["modified"].endswith("Z")
    assert got["width"] == 37 and got["height"] == 19
    assert set(got) <= {
        "type",
        "size",
        "modified",
        "width",
        "height",
        "duration",
        "codec",
        "bitrate",
        "pages",
        "title",
        "author",
        "subject",
        "camera",
        "lens",
        "taken",
    }


def test_jpeg_dimensions_come_from_the_header(tmp_path):
    # a minimal SOF: no image data needed, the parser stops at the size
    path = tmp_path / "sample.jpg"
    path.write_bytes(
        b"\xff\xd8\xff\xe0\x00\x10JFIF\x00"
        + b"\x00" * 9
        + b"\xff\xc0\x00\x11\x08\x01\x2c\x02\x58"
        + b"\x00" * 9
    )
    got = run(path)
    assert (got["width"], got["height"]) == (600, 300)


def test_an_invalid_path_is_json_not_a_traceback(tmp_path):
    got = run(tmp_path / "gone.png")
    assert got.get("error")
    assert "width" not in got
    got = run(tmp_path)  # a directory is not a file
    assert got.get("error")


def test_no_arguments_is_a_usage_answer():
    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/filemeta.py")],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 2
    assert "error" in json.loads(out.stdout)


def test_paths_go_as_argv_never_through_a_shell(tmp_path, monkeypatch):
    path = tmp_path / "a file; rm -rf $HOME.mp4"  # metacharacters on purpose
    path.write_bytes(b"")
    calls = []

    class R:
        stdout = "{}"
        returncode = 0

    monkeypatch.setattr(
        fm.shutil, "which", lambda name: "/usr/bin/fake" if name == "ffprobe" else None
    )
    monkeypatch.setattr(
        fm.subprocess, "run", lambda cmd, **kw: calls.append((cmd, kw)) or R()
    )

    got = fm.meta(path, path.stat())
    assert got["type"] == "video/mp4"
    assert len(calls) == 1
    cmd, kw = calls[0]
    assert cmd[0] == "ffprobe" and str(path) in [str(x) for x in cmd]
    assert "shell" not in kw and kw.get("shell") is not True
    assert "rm -rf" not in " ".join(cmd[:-1])  # not a script, just an argument


def test_pdfinfo_pages_and_title(tmp_path, monkeypatch):
    path = tmp_path / "doc.pdf"
    path.write_bytes(b"%PDF-1.7\n")
    monkeypatch.setattr(
        fm.shutil,
        "which",
        lambda name: "/usr/bin/pdfinfo" if name == "pdfinfo" else None,
    )
    monkeypatch.setattr(
        fm,
        "_run",
        lambda cmd: "Title:  A Title\nPages:  12\nPage size: 595 x 842 pts\n",
    )
    got = fm.meta(path, path.stat())
    assert got["pages"] == 12
    assert got["title"] == "A Title"
    assert "page size" not in got


def test_exiftool_is_optional(tmp_path, monkeypatch):
    path = png(tmp_path / "camera.png")
    monkeypatch.setattr(fm.shutil, "which", lambda name: None)
    got = fm.meta(path, path.stat())
    assert "camera" not in got and "taken" not in got

    monkeypatch.setattr(
        fm.shutil,
        "which",
        lambda name: "/usr/bin/exiftool" if name == fm.EXIF_TOOL else None,
    )
    monkeypatch.setattr(
        fm,
        "_run",
        lambda cmd: (
            '[{"Make":"Canon","Model":"EOS R6","DateTimeOriginal":"2026:01:02 03:04:05"}]'
        ),
    )
    got = fm.meta(path, path.stat())
    assert got["camera"] == "Canon EOS R6"
    assert got["taken"] == "2026:01:02 03:04:05"


# ---- the QML hooks ---------------------------------------------------------


def test_quicklook_has_a_disclosure_with_states():
    q = read("shani/Modules/QuickLook/QuickLookSheet.qml")
    assert 'Tr.t("More info")' in q and 'Tr.t("Less info")' in q
    assert "FileMeta.get(path)" in q
    assert "model: FileMeta.rows" in q
    assert "Reading file details…" in q and "EmptyState {" in q
    assert 'FileMeta.error || Tr.t("No details for this file")' in q
    # the staged keyboard work from the other session must survive
    assert "function jumpTo(i)" in q and "listingFlick.contentY" in q


def test_filemeta_service_has_get_and_no_shell():
    q = read("shani/Services/FileMeta.qml")
    assert "pragma Singleton" in q
    assert "function get(path, callback)" in q
    assert 'meta.command = ["python3", root.tool, p]' in q
    assert "if (cb) cb(root.info);" in q
    assert "sh -c" not in q and "shell: true" not in q
    assert '["type", "Type"], ["size", "Size"], ["modified", "Modified"]' in q


def test_media_properties_reuse_the_existing_probe():
    s = read("shani/Services/MediaInfo.qml")
    q = read("shani/Modules/MediaPlayer/MediaPlayerWindow.qml")
    assert "property var details: []" in s
    assert "root.details = root.detailsFor(data)" in s
    assert "MediaInfo.details" in q
    assert 'Tr.t("Media properties")' in q
    assert 'objectName: "media:properties"' in q
    assert '"ffprobe"' not in q  # no second probe in the window


def test_pdf_save_page_uses_the_rendered_png_and_a_file_picker():
    r = read("shani/Modules/PdfReader/PdfReader.qml")
    v = read("shani/Services/PdfViewer.qml")
    assert "function savePageImage()" in r
    assert 'mode: "save"' in r and 'Tr.t("Save this page as an image")' in r
    assert "PdfViewer.savePageImage(paths[0])" in r
    assert "function savePageImage(out)" in v
    assert 'pageCopy.command = ["cp", "--", current, out]' in v
    assert 'root.pageSaveState = code === 0 ? "ok" : "error"' in v
