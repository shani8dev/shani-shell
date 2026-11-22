"""Video Trimmer gaps: I/O/S + frame step, capture frame, cancel/progress, multi-segment join."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SVC = (ROOT / "shani/Services/VideoTrimmer.qml").read_text()
PANEL = (ROOT / "shani/Modules/VideoTrimmer/VideoTrimmerPanel.qml").read_text()
CONVERT = ROOT / "bridge/convert.py"
ffmpeg = shutil.which("ffmpeg")
ffprobe = shutil.which("ffprobe")
needs_ffmpeg = pytest.mark.skipif(ffmpeg is None, reason="ffmpeg is not installed")


def run(*args):
    return subprocess.run(
        [sys.executable, str(CONVERT), *args],
        capture_output=True,
        text=True,
        timeout=60,
    )


# ---- the bridge: a real multi-segment cut + join ------------------------------
@needs_ffmpeg
def test_segments_command_joins_two_windows(tmp_path):
    src = tmp_path / "in.mp4"
    subprocess.run(
        [
            ffmpeg,
            "-y",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            "color=blue:s=160x90:r=10:d=6",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            str(src),
        ],
        check=True,
    )
    out = tmp_path / "joined.mp4"
    r = run("segments", str(src), str(out), "0", "2", "3", "5")
    assert r.returncode == 0, r.stdout + r.stderr
    lines = [json.loads(x) for x in r.stdout.strip().splitlines()]
    assert any("progress" in x for x in lines)
    assert any(x.get("done") == str(out) for x in lines)
    assert out.exists() and out.stat().st_size > 0
    if ffprobe:
        d = float(
            subprocess.run(
                [
                    ffprobe,
                    "-v",
                    "error",
                    "-show_entries",
                    "format=duration",
                    "-of",
                    "csv=p=0",
                    str(out),
                ],
                capture_output=True,
                text=True,
            ).stdout.strip()
        )
        assert 3.0 < d < 5.5, d


def test_segments_rejects_bad_offsets(tmp_path):
    r = run(
        "segments",
        str(tmp_path / "missing.mp4"),
        str(tmp_path / "o.mp4"),
        "0",
        "1",
        "2",
        "3",
    )
    assert r.returncode == 3 and "error" in r.stdout
    r = run("segments", "x", "y", "5", "2", "0", "1")
    assert r.returncode == 3


# ---- the service --------------------------------------------------------------
def test_playhead_and_frame_step():
    assert "property real playhead: 0" in SVC
    assert "readonly property real frameStep: 1 / 30" in SVC
    for fn in (
        "setPlayhead(",
        "nudgePlayhead(",
        "markIn(",
        "markOut(",
        "splitAtPlayhead(",
    ):
        assert f"function {fn}" in SVC, fn
    assert "setStart(playhead)" in SVC and "setEnd(playhead)" in SVC


def test_capture_frame_uses_ffmpeg_argv_slots():
    assert "function captureFrame(" in SVC
    assert "-frames:v 1" in SVC and "XDG_PICTURES_DIR" in SVC
    # the user-controlled path/time/input are argv slots, not shell text
    assert '"sh", out, Math.max(0, t).toFixed(3), input' in SVC
    assert "captureError" in SVC
    assert (
        "VideoTrimmer.captureFrame()" in PANEL and "VideoTrimmer.frameCaptured" in PANEL
    )


def test_progress_and_cancel():
    assert (
        "property real progress: 0" in SVC and "property bool cancelled: false" in SVC
    )
    assert '"-progress", "pipe:1"' in SVC and "out_time_us" in SVC
    assert "function cancelCut(" in SVC and "cutProc.signal(2)" in SVC
    assert "segProc.signal(2)" in SVC
    assert "VideoTrimmer.cancelCut()" in PANEL and "VideoTrimmer.progress" in PANEL


def test_multiple_segments_service_and_panel():
    assert "property var segments: []" in SVC
    for fn in ("addSegment(", "removeSegment(", "clearSegments()", "cutSegments("):
        assert f"function {fn}" in SVC, fn
    assert '"segments", input, out' in SVC and "convertTool" in SVC
    assert "VideoTrimmer.addSegment(" in PANEL and "VideoTrimmer.cutSegments()" in PANEL
    assert (
        'Tr.t("In (I)")' in PANEL
        and 'Tr.t("Out (O)")' in PANEL
        and 'Tr.t("Split (S)")' in PANEL
    )
    assert "Qt.Key_I" in PANEL and "Qt.Key_O" in PANEL and "Qt.Key_S" in PANEL
