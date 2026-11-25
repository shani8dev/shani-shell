"""One markup mark (shani/Common/Markup.js), drawn on a recording context in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
JS = ROOT / "shani" / "Common" / "Markup.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")

RECORDER = """
function rec() {
  const calls = [];
  return new Proxy({ calls }, {
    get(t, k) { if (k === "calls") return calls; return (...a) => calls.push([k, ...a]); },
    set(t, k, v) { calls.push(["set:" + k, v]); return true; },
  });
}
"""


def draw(kind, pts, words=""):
    prog = (JS.read_text().replace(".pragma library", "") + RECORDER
            + "const c = rec(); draw(c, 100, 100, %s, 'red', 0.01, %s, %s);"
              "process.stdout.write(JSON.stringify(c.calls));"
            % (json.dumps(kind), json.dumps(pts), json.dumps(words)))
    out = subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def line_tos(calls):
    return [c[1:] for c in calls if c[0] == "lineTo"]


FREEHAND = [[0.1, 0.1], [0.5, 0.9], [0.9, 0.1]]


def test_a_pen_stroke_keeps_every_point():
    assert line_tos(draw("pen", FREEHAND)) == [[50, 90], [90, 10]]


def test_a_line_goes_straight_to_its_last_point():
    assert line_tos(draw("line", FREEHAND)) == [[90, 10]]


def test_an_arrow_gets_a_filled_head():
    calls = draw("arrow", [[0.1, 0.5], [0.9, 0.5]])
    assert ["fill"] in calls
    assert line_tos(calls)[0] == [90, 50]


def test_a_tap_is_a_dot():
    assert line_tos(draw("pen", [[0.5, 0.5]])) == [[50.1, 50]]


def test_box_and_blur_span_first_to_last():
    assert ["strokeRect", 10, 10, 80, 80] in draw("box", [[0.9, 0.9], [0.5, 0.5], [0.1, 0.1]])
    assert ["fillRect", 10, 10, 80, 80] in draw("blur", [[0.1, 0.1], [0.9, 0.9]])


def test_text_is_written_at_the_first_point():
    assert ["fillText", "hi", 20, 30] in draw("text", [[0.2, 0.3]], "hi")


def test_nothing_to_draw_draws_nothing():
    assert draw("pen", []) == []


def test_both_markup_layers_use_the_shared_drawing():
    # the copies drifted once (PdfReader drew saved pen strokes by the current tool)
    for qml in ("shani/Modules/PdfReader/PdfReader.qml", "shani/Modules/Viewer/Viewer.qml"):
        src = (ROOT / qml).read_text()
        assert "Markup.draw(" in src, qml
        assert "function mark(ctx" not in src, qml
