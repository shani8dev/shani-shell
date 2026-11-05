"""The handwriting pad: its geometry (Modules/Osk/Handwriting.js, in node) and the
reader (bridge/handwriting.py, Tesseract) on strokes drawn like a hand would."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
JS = ROOT / "shani" / "Modules" / "Osk" / "Handwriting.js"
TOOL = ROOT / "bridge" / "handwriting.py"
node = shutil.which("node")


def js(expr: str):
    src = JS.read_text().replace(".pragma library", "")
    out = subprocess.run([node, "-e", src + f"\nprocess.stdout.write(JSON.stringify({expr}));"],
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def line(x0, y0, x1, y1, n=10):
    return [{"x": x0 + (x1 - x0) * i / n, "y": y0 + (y1 - y0) * i / n, "p": 0.5} for i in range(n + 1)]


ZIGZAG = [{"x": 10 + (30 if i % 2 else 0), "y": 20 + i, "p": 0.5} for i in range(14)]


@pytest.mark.skipif(node is None, reason="node is not installed")
class TestGeometry:
    def test_a_scribble_is_a_scribble(self):
        assert js(f"isScribble({json.dumps(ZIGZAG)})") is True

    def test_letters_are_not_scribbles(self):
        m = line(0, 40, 0, 0) + line(0, 0, 10, 30) + line(10, 30, 20, 0) + line(20, 0, 20, 40)   # an M: three turns at most
        assert js(f"isScribble({json.dumps(m)})") is False
        assert js(f"isScribble({json.dumps(line(0, 20, 60, 20))})") is False

    def test_a_scribble_rubs_out_what_it_covers_and_nothing_else(self):
        under, beside = line(15, 20, 35, 30), line(200, 20, 230, 30)
        kept = js(f"rubOut({json.dumps([under, beside])}, {json.dumps(ZIGZAG)})")
        assert kept == [beside]

    def test_a_descender_stays_on_its_own_row(self):
        g = line(10, 60, 10, 150)            # starts in row 0 (0-100), reaches row 1
        assert js(f"rowOf({json.dumps(g)}, 100, 3)") == 0
        assert js(f"rowOf({json.dumps(line(10, 120, 40, 180))}, 100, 3)") == 1

    def test_a_hovering_pen_draws_nothing_a_finger_always_does(self):
        assert js('isInk({x: 0, y: 0, p: 0.02}, true)') is False
        assert js('isInk({x: 0, y: 0, p: 0.4}, true)') is True
        assert js('isInk({x: 0, y: 0, p: -1}, false)') is True


# block capitals, as strokes of [x, y] points: what a pen leaves
def block(letters: str, x=10, y=10, h=60, w=36, gap=18):
    out = []
    for ch in letters:
        L = {"H": [[(0, 0), (0, h)], [(w, 0), (w, h)], [(0, h / 2), (w, h / 2)]],
             "E": [[(w, 0), (0, 0), (0, h), (w, h)], [(0, h / 2), (w * 0.8, h / 2)]],
             "L": [[(0, 0), (0, h), (w, h)]],
             "T": [[(0, 0), (w, 0)], [(w / 2, 0), (w / 2, h)]]}[ch]
        for s in L:
            out.append([[x + px, y + py] for px, py in s])
        x += w + gap
    return out


@pytest.mark.skipif(not shutil.which("tesseract") or not (shutil.which("magick") or shutil.which("convert")),
                    reason="tesseract or ImageMagick is not installed")
def test_rows_are_read_in_order():
    rows = [block("HELL"), [], block("TELL")]
    out = subprocess.run([sys.executable, str(TOOL), "eng"], input=json.dumps(rows),
                         capture_output=True, text=True, timeout=60, check=True)
    got = json.loads(out.stdout)["rows"]
    assert got[1] == ""
    assert got[0].upper().replace(" ", "") == "HELL"
    assert got[2].upper().replace(" ", "") == "TELL"
