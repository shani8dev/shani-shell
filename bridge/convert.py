#!/usr/bin/env python3
"""convert — a file into another format: videos, songs and pictures, with ffmpeg
and ImageMagick (both in the image).

    convert.py formats FILE          {"kind": "video"|"audio"|"image", "formats": [...]}
    convert.py run FILE FORMAT [small|balanced|best]
        one JSON object a line: {"progress": 0..1} while it works, then
        {"done": "/path/of/the/new/file"} or {"error": "why"}

The new file goes beside the old one, named after it ("trip.mov" -> "trip.mp4",
or "trip (2).mp4" when that is taken): nothing is ever written over, and the
original is left as it was. It is written as "<name>.part" first and renamed
when whole, so a stopped conversion leaves nothing half-made behind.

Formats by kind (what makes sense, not every codec there is):
    video -> mp4 (H.264/AAC, plays everywhere), webm (VP9/Opus), mkv, gif,
             and the sound alone: mp3, m4a, ogg
    audio -> mp3, m4a (AAC), ogg (Vorbis), opus, flac, wav
    image -> jpg, png, webp, avif, pdf
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

FFMPEG = os.environ.get("SHANI_FFMPEG", "ffmpeg")
FFPROBE = os.environ.get("SHANI_FFPROBE", "ffprobe")
MAGICK = os.environ.get("SHANI_MAGICK") or ("magick" if shutil.which("magick") else "convert")

VIDEO_IN = {".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".mpg", ".mpeg", ".ogv", ".wmv", ".flv", ".3gp", ".ts"}
AUDIO_IN = {".mp3", ".flac", ".ogg", ".oga", ".opus", ".m4a", ".aac", ".wav", ".wma", ".aiff", ".aif", ".mka"}
IMAGE_IN = {".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif", ".bmp", ".tif", ".tiff", ".heic", ".heif"}
FORMATS = {
    "video": ["mp4", "webm", "mkv", "gif", "mp3", "m4a", "ogg"],
    "audio": ["mp3", "m4a", "ogg", "opus", "flac", "wav"],
    "image": ["jpg", "png", "webp", "avif", "pdf"],
}
# quality: (video crf for x264, vp9 crf, audio bitrate kbit/s, image quality)
QUALITY = {"small": (28, 40, 96, 70), "balanced": (23, 33, 160, 85), "best": (18, 24, 256, 95)}


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def kind_of(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in VIDEO_IN:
        return "video"
    if ext in AUDIO_IN:
        return "audio"
    if ext in IMAGE_IN:
        return "image"
    return ""


def free_name(src: Path, fmt: str) -> Path:
    """Beside the source, its name with the new extension; never one that exists."""
    target = src.with_suffix("." + fmt)
    n = 2
    while target.exists() or target == src:
        target = src.with_name(f"{src.stem} ({n}).{fmt}")
        n += 1
    return target


def duration(src: Path) -> float:
    try:
        out = subprocess.run([FFPROBE, "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(src)],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        return float(out)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return 0.0


def ffmpeg_args(kind: str, fmt: str, q: str) -> list[str]:
    crf264, crfvp9, abr, _ = QUALITY[q]
    audio_only = {"mp3": ["-vn", "-c:a", "libmp3lame", "-b:a", f"{abr}k"], "m4a": ["-vn", "-c:a", "aac", "-b:a", f"{abr}k"],
                  "ogg": ["-vn", "-c:a", "libvorbis", "-b:a", f"{abr}k"], "opus": ["-vn", "-c:a", "libopus", "-b:a", f"{min(abr, 192)}k"],
                  "flac": ["-vn", "-c:a", "flac"], "wav": ["-vn", "-c:a", "pcm_s16le"]}
    if fmt in audio_only:
        return audio_only[fmt]
    if fmt == "mp4":
        return ["-c:v", "libx264", "-preset", "medium", "-crf", str(crf264), "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", f"{abr}k", "-movflags", "+faststart"]
    if fmt == "webm":
        return ["-c:v", "libvpx-vp9", "-crf", str(crfvp9), "-b:v", "0", "-row-mt", "1", "-c:a", "libopus", "-b:a", f"{min(abr, 192)}k"]
    if fmt == "mkv":
        return ["-c:v", "libx264", "-preset", "medium", "-crf", str(crf264), "-c:a", "aac", "-b:a", f"{abr}k"]
    if fmt == "gif":
        width = {"small": 360, "balanced": 480, "best": 720}[q]
        return ["-vf", f"fps=12,scale={width}:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", "-an"]
    raise ValueError(f"cannot make {fmt} from a {kind}")


def run(src: Path, fmt: str, q: str) -> int:
    kind = kind_of(src)
    if not src.is_file():
        emit({"error": f"there is no file at {src}"})
        return 3
    if not kind:
        emit({"error": f"{src.name} is not a video, a song or a picture"})
        return 3
    if fmt not in FORMATS[kind]:
        emit({"error": f"a {kind} cannot be made into {fmt}"})
        return 3
    target = free_name(src, fmt)
    part = target.with_name(target.name + ".part")
    try:
        if kind == "image":
            quality = QUALITY[q][3]
            # one page of a multi-frame picture (a gif's first frame) unless the target keeps frames
            source = f"{src}[0]" if fmt in ("jpg", "png", "avif", "pdf") else str(src)
            cmd = [MAGICK, source, "-auto-orient", "-quality", str(quality), f"{fmt}:{part}"]
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError(r.stderr.strip().split("\n")[-1] or "ImageMagick refused it")
        else:
            total = duration(src)
            container = {"mp3": "mp3", "m4a": "ipod", "ogg": "ogg", "opus": "opus", "flac": "flac", "wav": "wav",
                         "mp4": "mp4", "webm": "webm", "mkv": "matroska", "gif": "gif"}[fmt]
            cmd = [FFMPEG, "-hide_banner", "-nostdin", "-y", "-i", str(src)] + ffmpeg_args(kind, fmt, q) + \
                  ["-progress", "pipe:1", "-nostats", "-f", container, str(part)]
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            last = -1.0
            for line in proc.stdout:
                m = re.match(r"out_time_us=(\d+)", line)
                if m and total > 0:
                    p = min(1.0, int(m.group(1)) / 1e6 / total)
                    if p - last >= 0.01:
                        last = p
                        emit({"progress": round(p, 3)})
            err = proc.stderr.read()
            if proc.wait() != 0:
                raise RuntimeError(err.strip().split("\n")[-1] if err.strip() else "ffmpeg stopped")
        part.rename(target)
    except (OSError, RuntimeError, ValueError) as exc:
        part.unlink(missing_ok=True)
        emit({"error": str(exc)})
        return 1
    emit({"progress": 1.0})
    emit({"done": str(target)})
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "formats":
        kind = kind_of(Path(argv[2]))
        print(json.dumps({"kind": kind, "formats": FORMATS.get(kind, [])}))
        return 0
    if len(argv) >= 4 and argv[1] == "run":
        q = argv[4] if len(argv) > 4 and argv[4] in QUALITY else "balanced"
        return run(Path(argv[2]).expanduser(), argv[3].lower().lstrip("."), q)
    print("usage: convert.py formats FILE | run FILE FORMAT [small|balanced|best]", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
