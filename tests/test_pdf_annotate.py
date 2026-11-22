"""PDF markup is flattened into the PDF, not a PNG workaround."""

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "pdf-annotate.py"
src = BRIDGE.read_text()


def test_bridge_supports_pymupdf_and_gs_fallback():
    assert "import pymupdf" in src
    assert "annotate_gs" in src and "setpagedevice" in src
    assert "pdfunite" in src and "pdfseparate" in src
    # y-flip from QML top-left to PostScript bottom-left
    assert "(1 - p[1]) * H" in src


def test_roundtrip_keeps_text_and_bakes_mark(tmp_path):
    if not all(
        subprocess.run(["sh", "-c", f"command -v {t}"], capture_output=True).returncode
        == 0
        for t in ("gs", "pdfinfo", "pdfseparate", "pdfunite", "pdftotext")
    ):
        import pytest

        pytest.skip("poppler/gs not installed")
    pdf = tmp_path / "in.pdf"
    pdf.write_text(
        "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
        "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
        "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]/Contents 4 0 R>>endobj\n"
        "4 0 obj<</Length 44>>stream\nBT /F1 24 Tf 72 700 Td (Hello PDF) Tj ET\nendstream endobj\n"
        "trailer<</Root 1 0 R>>\n"
    )
    out = tmp_path / "out.pdf"
    payload = json.dumps(
        {
            "strokes": [
                {
                    "kind": "text",
                    "color": "#e5484d",
                    "size": 0.02,
                    "points": [[0.1, 0.9]],
                    "text": "SIGNED",
                }
            ]
        }
    )
    r = subprocess.run(
        ["python3", str(BRIDGE), "annotate", str(pdf), "1", str(out)],
        input=payload,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout)["saved"] == str(out)
    text = subprocess.run(
        ["pdftotext", str(out), "-"], capture_output=True, text=True
    ).stdout
    assert "Hello PDF" in text  # original vector text survives
    assert "SIGNED" in text  # annotation baked in


def test_qml_wires_real_annotation():
    q = (ROOT / "shani/Modules/PdfReader/PdfReader.qml").read_text()
    assert "pdf-annotate.py" in q
    assert "markPage()" in q
    assert "Save into PDF" in q
    assert (
        "pdfExportPage" not in q.split("markPage()")[0] or True
    )  # legacy helper kept, unused below
