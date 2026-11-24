"""Media Player keyboard shortcuts and the bounds behind them.

The CuboCore coreplayer's keys are all already handled in MediaPlayerWindow's
single `key(e)`; this file pins that down so a later edit cannot quietly drop
one, and checks the clamping the service now owns for MPRIS/CLI requests. The
clamp functions are plain JS, so they are run through node rather than guessed
at from the source text.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / "shani/Services/PlayQueue.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text(
    encoding="utf-8"
)

NODE = shutil.which("node") or shutil.which("nodejs")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


# ---- the shortcuts themselves ----------------------------------------------


def test_all_cubocore_keys_are_handled_once():
    # one handler, attached to a focused Item, with accepted set so the keys do
    # not fall through to niri or another widget
    assert WINDOW.count("function key(e)") == 1
    assert "Keys.onPressed: e => { if (win.key(e)) e.accepted = true; }" in WINDOW
    assert "focus: true" in WINDOW

    keys = {
        "play/pause": "Qt.Key_Space",
        "fullscreen": "Qt.Key_F",
        "seek back": "Qt.Key_Left",
        "seek forward": "Qt.Key_Right",
        "volume up": "Qt.Key_Up",
        "volume down": "Qt.Key_Down",
        "mute": "Qt.Key_M",
        "next": "Qt.Key_N",
        "previous": "Qt.Key_P",
    }
    for name, key in keys.items():
        assert f"e.key === {key}" in WINDOW, name

    # each key maps to a real command, not just a comparison
    assert "win.toggle()" in WINDOW
    assert 'Niri.action("fullscreen-window")' in WINDOW
    assert "win.skip(big ? -30 : -5)" in WINDOW and "win.skip(big ? 30 : 5)" in WINDOW
    assert "win.louder(0.05)" in WINDOW and "win.louder(-0.05)" in WINDOW
    assert "PlayQueue.muted = !PlayQueue.muted" in WINDOW
    assert "PlayQueue.next()" in WINDOW and "PlayQueue.previous()" in WINDOW


def test_shift_extends_seek_and_repeat():
    assert "const big = e.modifiers & Qt.ShiftModifier" in WINDOW
    assert "Qt.Key_Left) win.skip(big ? -30 : -5)" in WINDOW
    assert "Qt.Key_Right) win.skip(big ? 30 : 5)" in WINDOW
    assert "Qt.Key_R && big) win.cycleRepeat()" in WINDOW


def test_window_clamps_seek_and_volume_at_the_edges():
    # the window owns the player: its own helpers keep the playhead and the
    # volume inside the media engine's limits on every key press
    assert (
        "function skip(seconds) { player.position = Math.max(0, Math.min(player.duration, player.position + seconds * 1000)); }"
        in WINDOW
    )
    assert (
        "function louder(by) { PlayQueue.muted = false; PlayQueue.volume = Math.max(0, Math.min(1, PlayQueue.volume + by)); }"
        in WINDOW
    )


# ---- the service's shared bounds -------------------------------------------


def test_service_exposes_clamps_and_one_key_legend():
    assert (
        "function clampVolume(v)" in QUEUE
        and "function clampSeek(seconds, length)" in QUEUE
    )
    # MPRIS asks go through them, instead of a second copy of the formula
    assert "root.seekRequested(clampSeek(c.to, root.duration))" in QUEUE
    assert "root.volume = clampVolume(c.value)" in QUEUE
    assert "Math.max(0, Math.min(1, Number(c.value)))" not in QUEUE
    # discoverability: one string the hint/toast areas and the button tips can share
    assert (
        'readonly property string keyHints: "Space play/pause · ← → seek · M mute · F fullscreen · P/N playlist"'
        in QUEUE
    )


def _clamp_source(name: str) -> str:
    """The one function, verbatim, with no QML around it."""
    m = re.search(r"function " + name + r"\([^)]*\) \{[^}]*\}", QUEUE)
    assert m, name
    return m.group(0)


@pytest.mark.skipif(NODE is None, reason="node is not installed")
@pytest.mark.parametrize(
    "value,want",
    [
        ("-1", 0),
        ("0", 0),
        ("0.3", 0.3),
        ("1", 1),
        ("2", 1),
        ("NaN", 0),
        ("undefined", 0),
        ('"0.5"', 0.5),
        ('"loud"', 0),
    ],
)
def test_clamp_volume_keeps_audio_output_valid(value, want):
    js = _clamp_source("clampVolume")
    prog = js + f"\nconsole.log(JSON.stringify(clampVolume({value})));\n"
    out = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout.strip().splitlines()[-1]) == want


@pytest.mark.skipif(NODE is None, reason="node is not installed")
@pytest.mark.parametrize(
    "seconds,length,want",
    [
        ("-5", "100", 0),
        ("10", "100", 10),
        ("150", "100", 100),
        ("50", "0", 0),
        ("50", "-10", 0),
        ("NaN", "100", 0),
        ("10", "NaN", 0),
    ],
)
def test_clamp_seek_keeps_playhead_inside_the_file(seconds, length, want):
    js = _clamp_source("clampSeek")
    prog = js + f"\nconsole.log(JSON.stringify(clampSeek({seconds}, {length})));\n"
    out = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout.strip().splitlines()[-1]) == want
