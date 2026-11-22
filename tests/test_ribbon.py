"""The scrollable-ribbon viewport indicator (shani/Common/Ribbon.js), run in node."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Common" / "Ribbon.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def ratios(windows, workspace, width, gaps=10, anchor="fit", focused=None, memory=None):
    src = JS.read_text().replace(".pragma library", "")
    prog = (
        src
        + "\nprocess.stdout.write(JSON.stringify(computeRatios(%s, %s, %s, %s, %s, %s, %s)));"
        % (
            json.dumps(windows),
            json.dumps(workspace),
            width,
            gaps,
            json.dumps(anchor),
            json.dumps(focused),
            json.dumps(memory),
        )
    )
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def test_one_column_stretches_to_the_viewport():
    w = [
        {
            "id": 1,
            "workspace_id": 1,
            "is_focused": True,
            "layout": {
                "pos_in_scrolling_layout": [0, 0],
                "tile_size": [800, 600],
                "tile_pos_in_workspace_view": [0, 0],
            },
        }
    ]
    r = ratios(w, {"id": 1}, 1600, focused=1)
    assert r["start"] == 0
    assert r["width"] == 1
    assert 0.49 < r["activeWidth"] < 0.51


def test_reported_x_anchors_the_scroll_offset():
    w = [
        {"id": i, "workspace_id": 1, "is_focused": i == 2,
         "layout": {"pos_in_scrolling_layout": [i - 1, 0], "tile_size": [800, 600],
                    "tile_pos_in_workspace_view": [110, 0] if i == 2 else [0, 0]}}
        for i in (1, 2, 3)
    ]
    r = ratios(w, {"id": 1}, 1600, focused=2)
    # 3 columns => canvas ~2420, viewport 1600, ~820px scroll room;
    # column 1 canvas x=810, reported x=110 => viewPos ~700 => start ~0.29
    assert 0.25 < r["start"] < 0.35


def test_empty_workspace_is_a_full_bar():
    assert ratios([], {"id": 1}, 1600) == {
        "start": 0,
        "width": 1,
        "activeStart": 0,
        "activeWidth": 0,
    }
