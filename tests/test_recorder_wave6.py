"""Wave 6 deep pass: persistent peaks and a seekable waveform in Voice Recorder.

- static hooks: the panel really decodes the take through bridge/waveform.py,
  renders the cached peaks as bars, and gives the seek bar a keyboard route and
  an accessible name.
- the bridge for real: a generated WAV is decoded to a bounded peak array,
  cached beside the take, re-read from the cache, and invalidated when the file
  changes. No new dependency: the WAV path is the standard library.
- the seek maths the panel mirrors, as pure functions.
"""

import importlib.machinery
import importlib.util
import json
import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = ROOT / "shani/Modules/VoiceRecorder/VoiceRecorderPanel.qml"
BRIDGE = ROOT / "bridge/waveform.py"


def load_bridge():
    loader = importlib.machinery.SourceFileLoader("waveform", str(BRIDGE))
    spec = importlib.util.spec_from_loader("waveform", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def make_wav(path, seconds=1.0, rate=8000):
    """A loud first half and silence after it: the peaks must show the split."""
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        half = int(seconds * rate / 2)
        loud = b"".join(
            struct.pack("<h", int(22000 * math.sin(2 * math.pi * 220 * i / rate)))
            for i in range(half)
        )
        w.writeframes(loud + b"\x00\x00" * (rate - half))


# ---- static hooks ----------------------------------------------------------


def test_panel_decodes_takes_through_the_bridge():
    t = PANEL.read_text()
    assert 'Quickshell.env("SHANI_WAVEFORM_TOOL")' in t
    assert "/usr/lib/shani-shell/waveform.py" in t
    assert 'command = ["python3", waveformTool, path]' in t
    assert "onStreamFinished:" in t and "JSON.parse(text)" in t
    assert "d.peaks.slice(0, 256)" in t  # bounded, even if a cache is huge
    assert "win.loadPeaks(path)" in t  # only decoded when played inline
    assert ".peaks.json" in t  # a trashed take drops its cache


def test_panel_has_a_seekable_waveform_with_a11y_and_theme_tokens():
    t = PANEL.read_text()
    assert "Repeater {" in t and "model: win.peaks" in t
    assert "playback.setPosition" in t and "onPressed: m => seekAt(m.x)" in t
    assert "Accessible.role: Accessible.Slider" in t
    assert "Waveform — seek in recording" in t
    assert "KeyFocus {" in t and "slider: true" in t
    assert "onStep: dir =>" in t and "dir * 5000" in t  # Left/Right: ±5 s
    assert "Theme.accent" in t and "wave.height" in t
    assert "color: Theme.text" in t  # playhead uses a token, not opaque ink


# ---- the bridge, for real --------------------------------------------------


def test_bridge_computes_and_caches_bounded_peaks(tmp_path):
    take = tmp_path / "Recording 1 2026-11-25 10-00-00.wav"
    make_wav(take)
    out = subprocess.run(
        [sys.executable, str(BRIDGE), str(take)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    first = json.loads(out.stdout)
    assert first["source"] == "wav"
    assert 0 < len(first["peaks"]) <= 256
    assert all(0 <= v <= 1 for v in first["peaks"])
    # the loud half is clearly louder than the silent half
    n = len(first["peaks"])
    assert sum(first["peaks"][: n // 2]) / (n // 2 or 1) > 0.4
    assert sum(first["peaks"][n // 2 :]) / (n - n // 2 or 1) < 0.01
    assert abs(first["duration"] - 1.0) < 0.05

    cache = Path(str(take) + ".peaks.json")
    assert cache.exists() and cache.stat().st_size < 8192  # bounded on disk too
    saved = json.loads(cache.read_text())
    assert saved["path"] == str(take) and saved["buckets"] == n

    # a second call must read the cache, not decode again
    again = subprocess.run(
        [sys.executable, str(BRIDGE), str(take)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert again.returncode == 0, again.stderr
    cached = json.loads(again.stdout)
    assert cached["source"] == "cache" and cached["peaks"] == first["peaks"]

    # a changed take invalidates the stale cache
    make_wav(take, seconds=1.0, rate=16000)
    fresh = subprocess.run(
        [sys.executable, str(BRIDGE), str(take)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert fresh.returncode == 0, fresh.stderr
    assert json.loads(fresh.stdout)["source"] == "wav"


def test_bridge_handles_a_stereo_24_bit_wav_and_a_missing_file(tmp_path):
    take = tmp_path / "stereo.wav"
    with wave.open(str(take), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(3)  # 24-bit: no audioop in Python 3.14
        w.setframerate(8000)
        w.writeframes(
            b"".join(
                (1000).to_bytes(3, "little", signed=True)
                + (-1000).to_bytes(3, "little", signed=True)
                for _ in range(8000)
            )
        )
    # opposite-phase channels downmix to silence: the path still runs, no crash
    r = subprocess.run(
        [sys.executable, str(BRIDGE), str(take)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout)["source"] == "wav"

    missing = subprocess.run(
        [sys.executable, str(BRIDGE), str(tmp_path / "gone.opus")],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert missing.returncode == 1 and "no such recording" in missing.stderr


def test_bridge_never_stores_more_than_the_cap(tmp_path):
    b = load_bridge()
    take = tmp_path / "long.wav"
    make_wav(take, seconds=2.0)
    result = b.compute(str(take), buckets=100000)
    assert len(result["peaks"]) <= b.MAX_BUCKETS == 256


# ---- pure seek maths -------------------------------------------------------


def test_clamp01_seek_ms_and_bucket_at():
    b = load_bridge()
    assert b.clamp01(-3) == 0.0 and b.clamp01(1.7) == 1.0 and b.clamp01("x") == 0.0
    assert b.clamp01(0.25) == 0.25
    assert b.seek_ms(-1, 30000) == 0
    assert b.seek_ms(0.5, 30000) == 15000
    assert b.seek_ms(2, 30000) == 30000
    assert b.seek_ms(0.25, -5) == 0
    assert b.bucket_at(0.5, 100) == 50
    assert b.bucket_at(-1, 100) == 0
    assert b.bucket_at(1, 100) == 99
    assert b.bucket_at(0.5, 0) == 0
