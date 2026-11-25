#!/usr/bin/env python3
"""Persistent, bounded waveform peaks for Voice Recorder takes.

Standard library only. A WAV is decoded with `wave`; Opus/FLAC and everything
else go through ffmpeg (already a shani-shell dependency for trimming/export)
to 8 kHz mono s16le on stdout. The result is an array of at most 256 absolute
peaks, cached in a sibling `<take>.peaks.json` keyed by the file path and
validated against the take's size + mtime, so a renamed or re-recorded take
never borrows another take's waveform.

    python3 waveform.py <take.opus> [--buckets 256]

Prints one JSON object on stdout: {"peaks": [...], "duration": s, "source": ...}
where source is "cache", "wav" or "ffmpeg". Failures go to stderr, exit 1.
"""

import argparse
import json
import os
import subprocess
import sys
from array import array

MAX_BUCKETS = 256
CACHE_SUFFIX = ".peaks.json"


# ---- pure maths (shared with the panel's click-to-seek) ---------------------


def clamp01(x):
    """A seek ratio is always inside 0..1, even for a stray drag/parse."""
    try:
        x = float(x)
    except (TypeError, ValueError):
        return 0.0
    return 0.0 if x < 0 else (1.0 if x > 1 else x)


def seek_ms(ratio, duration_ms):
    """Where a click at `ratio` along the waveform lands, in milliseconds."""
    return int(round(clamp01(ratio) * max(0, float(duration_ms))))


def bucket_at(ratio, count):
    """Which cached bucket a playhead ratio belongs to."""
    if count <= 0:
        return 0
    return min(count - 1, max(0, int(clamp01(ratio) * count)))


# ---- decoding --------------------------------------------------------------


def _mono_s16(raw, width, channels):
    """Downmix interleaved PCM to signed 16-bit mono bytes."""
    if width == 2 and channels == 1:
        return raw
    frames = len(raw) // (width * channels)
    out = array("h", [0]) * frames
    for i in range(frames):
        total = 0
        for c in range(channels):
            b = raw[
                i * width * channels + c * width : i * width * channels
                + (c + 1) * width
            ]
            if width == 1:  # 8-bit WAV is unsigned
                v = (b[0] - 128) << 8
            elif width == 4:  # 32-bit -> 16-bit
                v = int.from_bytes(b, "little", signed=True) >> 16
            else:  # 24-bit -> 16-bit
                v = int.from_bytes(b, "little", signed=True) >> 8
            total += v
        v = total // channels
        out[i] = -32768 if v < -32768 else (32767 if v > 32767 else v)
    return out.tobytes()


def decode(path):
    """Return (mono s16le bytes, sample rate, source)."""
    if path.lower().endswith(".wav"):
        import wave

        with wave.open(path, "rb") as w:
            channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
            if channels < 1 or width < 1 or rate < 1:
                raise ValueError("bad WAV header")
            raw = _mono_s16(w.readframes(w.getnframes()), width, channels)
        return raw, rate, "wav"

    # voice notes do not need 48 kHz to draw a bar; 8 kHz keeps the decode small
    p = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            path,
            "-f",
            "s16le",
            "-ac",
            "1",
            "-ar",
            "8000",
            "-",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode(errors="replace").strip() or "ffmpeg failed")
    return p.stdout, 8000, "ffmpeg"


def peaks_from_pcm(raw, buckets=MAX_BUCKETS):
    """One absolute peak per equally sized slice of s16le mono PCM, 0..1."""
    n = len(raw) // 2
    if n == 0:
        return []
    count = min(max(1, int(buckets)), MAX_BUCKETS, n)
    out = []
    for i in range(count):
        seg = raw[(i * n // count) * 2 : ((i + 1) * n // count) * 2]
        vals = array("h")
        vals.frombytes(seg)
        peak = max((abs(v) for v in vals), default=0)
        out.append(round(min(1.0, peak / 32768.0), 4))
    return out


# ---- sibling-JSON cache ----------------------------------------------------


def cache_path(path):
    return path + CACHE_SUFFIX


def read_cache(path):
    """A cache entry is only valid for this exact file at this size + mtime."""
    try:
        with open(cache_path(path), encoding="utf-8") as f:
            d = json.load(f)
        st = os.stat(path)
    except (OSError, ValueError):
        return None
    peaks = d.get("peaks") if isinstance(d, dict) else None
    if not isinstance(peaks, list) or not peaks or len(peaks) > MAX_BUCKETS:
        return None
    if (
        d.get("path") != path
        or d.get("size") != st.st_size
        or d.get("mtime") != int(st.st_mtime)
    ):
        return None
    return d


def write_cache(path, peaks, duration, source):
    st = os.stat(path)
    d = {
        "path": path,
        "size": st.st_size,
        "mtime": int(st.st_mtime),
        "buckets": len(peaks),
        "duration": round(duration, 3),
        "source": source,
        "peaks": peaks,
    }
    tmp = cache_path(path) + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(d, f)
        os.replace(tmp, cache_path(path))
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def compute(path, buckets=MAX_BUCKETS):
    cached = read_cache(path)
    if cached:
        return {
            "peaks": cached["peaks"],
            "duration": cached.get("duration", 0),
            "source": "cache",
        }
    raw, rate, source = decode(path)
    peaks = peaks_from_pcm(raw, buckets)
    duration = (len(raw) // 2) / rate if rate else 0
    write_cache(path, peaks, duration, source)
    return {"peaks": peaks, "duration": round(duration, 3), "source": source}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("path", help="audio take to read")
    ap.add_argument(
        "--buckets",
        type=int,
        default=MAX_BUCKETS,
        help=f"peak count, capped at {MAX_BUCKETS} (default: %(default)s)",
    )
    args = ap.parse_args(argv)
    if not os.path.isfile(args.path):
        print("no such recording: " + args.path, file=sys.stderr)
        return 1
    try:
        result = compute(args.path, args.buckets)
    except (OSError, ValueError, RuntimeError) as e:
        print(str(e), file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
