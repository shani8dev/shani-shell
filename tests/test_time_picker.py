"""The TimePicker's typed field: HH:MM and spoken times, run as real JS."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "shani/Common/TimePicker.qml"
pytestmark = pytest.mark.skipif(
    shutil.which("node") is None, reason="node is not installed"
)


def parse(*times):
    source = SOURCE.read_text()
    start = source.index("function parseTime(text) {")
    depth = 0
    for end in range(start, len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
            if depth == 0:
                break
    fn = source[start : end + 1]
    prog = (
        fn
        + "\nprocess.stdout.write(JSON.stringify(["
        + ",".join("parseTime(%s)" % json.dumps(t) for t in times)
        + "]));"
    )
    return json.loads(
        subprocess.run(
            ["node", "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def test_hh_mm_and_spoken_times():
    assert parse("23:45", "9am", "9:30pm", "12am", "12pm", "7:05 AM") == [
        [23, 45],
        [9, 0],
        [21, 30],
        [0, 0],
        [12, 0],
        [7, 5],
    ]


def test_garbage_is_refused():
    assert parse("tomorrow", "25:00", "9:60", "13pm", "") == [None] * 5
