"""Proportional workspace map (shani/Common/WorkspaceMap.js), run in node."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Common" / "WorkspaceMap.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def run(fn, *args):
    src = JS.read_text().replace(".pragma library", "")
    prog = src + "\nprocess.stdout.write(JSON.stringify(%s(%s)));" % (
        fn,
        ", ".join(json.dumps(a) for a in args),
    )
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


WINDOWS = [
    {
        "id": 1,
        "workspace_id": 1,
        "is_focused": True,
        "layout": {"pos_in_scrolling_layout": [0, 0], "tile_size": [800, 600]},
    },
    {
        "id": 2,
        "workspace_id": 1,
        "is_focused": False,
        "layout": {"pos_in_scrolling_layout": [0, 1], "tile_size": [800, 400]},
    },
    {
        "id": 3,
        "workspace_id": 1,
        "is_focused": False,
        "layout": {"pos_in_scrolling_layout": [1, 0], "tile_size": [600, 1000]},
    },
    {"id": 4, "workspace_id": 1, "is_floating": True, "title": "floating"},
    {
        "id": 5,
        "workspace_id": 2,
        "is_focused": False,
        "layout": {"pos_in_scrolling_layout": [0, 0], "tile_size": [800, 600]},
    },
]


def test_group_splits_columns_and_floating():
    g = run("group", WINDOWS, 1)
    assert len(g["columns"]) == 2
    assert g["columns"][0]["width"] == 800
    assert len(g["columns"][0]["windows"]) == 2
    assert g["columns"][1]["width"] == 600
    assert len(g["floating"]) == 1 and g["floating"][0]["id"] == 4


def test_rects_preserve_aspect_ratio():
    g = run("group", WINDOWS, 1)
    r = run("rects", g, 100, 60, 2)
    assert len(r) == 3
    # two windows stacked in column 0: first (600h) taller than second (400h)
    assert r[0]["h"] > r[1]["h"]
    # column 1 starts after column 0 width + gap
    assert r[2]["x"] > r[0]["w"]
    assert r[0]["focused"] is True


def test_viewport_and_floating():
    g = run("group", WINDOWS, 1)
    v = run("viewport", g, 800, 2, "fit", 1)
    assert "x" in v and "width" in v
    assert v["width"] <= run("canvasWidth", g, 2)
    f = run("floatingRects", [{"id": 9, "is_focused": True,
                              "layout": {"tile_pos_in_workspace_view": [100, 200], "tile_size": [300, 400]}}],
            1600, 900, 80, 45)
    assert len(f) == 1
    assert abs(f[0]["x"] - 5) < 0.01   # 100 * 80/1600
    assert abs(f[0]["w"] - 15) < 0.01  # 300 * 80/1600
