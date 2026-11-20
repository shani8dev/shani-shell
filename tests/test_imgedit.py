"""bridge/imgedit.py with the real ImageMagick: crop after the turn, each markup
kind lands where it was drawn on the picture as shown, blur hides, resize, and a
copy never writes over anything."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "imgedit.py"
pytestmark = pytest.mark.skipif(not shutil.which("magick"), reason="no ImageMagick")


def make(p, spec):
    subprocess.run(["magick"] + spec + [str(p)], check=True)


def save(p, edit, mode="copy"):
    r = subprocess.run([sys.executable, str(BRIDGE), "save", str(p), mode], input=json.dumps(edit), capture_output=True, text=True)
    return r.stdout


def px(p, x, y):
    return subprocess.run(["magick", str(p), "-format", "%%[pixel:p{%d,%d}]" % (x, y), "info:"], capture_output=True, text=True).stdout


def dims(p):
    return subprocess.run(["magick", "identify", "-format", "%wx%h", str(p)], capture_output=True, text=True).stdout


def test_turn_then_crop(tmp_path):
    p = tmp_path / "pic.png"; make(p, ["-size", "400x200", "xc:red", "-fill", "blue", "-draw", "rectangle 0,0 199,199"])
    out = save(p, {"rotation": 90, "crop": [0, 0, 0.5, 0.25]})
    assert out.endswith("pic (edited).png") and dims(out) == "100x100" and px(out, 5, 5) in ("blue", "srgb(0,0,255)")


@pytest.mark.parametrize("kind,at,extra", [("pen", (50, 150), {}), ("line", (50, 150), {}), ("arrow", (50, 150), {}),
                                            ("highlight", (50, 150), {})])
def test_marks_land_where_drawn_on_the_turned_picture(tmp_path, kind, at, extra):
    p = tmp_path / "w.png"; make(p, ["-size", "300x100", "xc:white"])
    out = save(p, {"rotation": 90, "marks": [dict(kind=kind, color="#00ff00", size=0.05, points=[[0.5, 0.1], [0.5, 0.9]], **extra)]})
    assert dims(out) == "100x300"
    c = px(out, *at)
    assert c not in ("white", "srgb(255,255,255)", "gray(255)"), c
    assert px(out, 5, 5) in ("white", "srgb(255,255,255)", "gray(255)")


def test_box_and_text(tmp_path):
    p = tmp_path / "w.png"; make(p, ["-size", "200x200", "xc:white"])
    out = save(p, {"marks": [{"kind": "box", "color": "#0000ff", "size": 0.02, "points": [[0.25, 0.25], [0.75, 0.75]]},
                             {"kind": "text", "color": "#ff0000", "size": 0.03, "points": [[0.1, 0.95]], "text": 'Say "hi"'}]})
    assert px(out, 50, 100) in ("blue", "srgb(0,0,255)")            # the box's left side
    assert px(out, 100, 100) in ("white", "srgb(255,255,255)")       # not filled
    red = subprocess.run(["magick", out, "-crop", "200x40+0+160", "-fill", "black", "+opaque", "#ff0000", "-format", "%[fx:mean]", "info:"], capture_output=True, text=True).stdout
    assert float(red) > 0                                            # the words are there


def test_blur_hides_a_detail(tmp_path):
    p = tmp_path / "c.png"; make(p, ["-size", "200x200", "pattern:checkerboard"])
    out = save(p, {"marks": [{"kind": "blur", "points": [[0, 0], [0.5, 0.5]]}]})
    sd = lambda g: float(subprocess.run(["magick", out, "-crop", g, "-colorspace", "gray", "-format", "%[fx:standard_deviation]", "info:"], capture_output=True, text=True).stdout)
    assert sd("80x80+10+10") < sd("80x80+110+110") / 3


def test_resize_and_never_over(tmp_path):
    p = tmp_path / "g.png"; make(p, ["-size", "400x200", "xc:green"])
    a = save(p, {"resize": "50%"}); b = save(p, {"resize": "1920x1920>"})
    assert dims(a) == "200x100" and b.endswith("g (edited 2).png") and dims(b) == "400x200"
    assert dims(p) == "400x200"
