#!/usr/bin/env python3
"""filemeta — what a file says about itself, for Quick Look and the shell.

One small answer for any file: its size and modified time from the file itself,
and the details a person actually asks for when a tool is there - a picture's
dimensions, a video's codec and length, a PDF's page count, a camera's make.

Read-only, and every path reaches a tool as its own argv element: no shell, no
string built from a filename. ffprobe (ffmpeg) and pdfinfo (poppler) are used
when present; exiftool is optional and looked up by name. Nothing else is
needed - PNG and JPEG dimensions are read from the header with the stdlib.

    filemeta.py <path>      {"type": "image/png", "size": 1024, ...}
    filemeta.py             {"error": "..."}                    (exit 2)
"""

from __future__ import annotations

import datetime as dt
import json
import mimetypes
import os
import re
import shutil
import stat
import struct
import subprocess
import sys

TIMEOUT = 6
# exiftool is optional; the name is kept in a variable so a host without it
# never sees it as a needed program. An env var lets a test/dev shell point at
# a stand-in without changing the shipped default.
EXIF_TOOL = os.environ.get("SHANI_FILEMETA_EXIFTOOL", "exiftool")
PDF_FIELDS = ("Pages", "Title", "Author", "Subject", "Page size")


def _run(cmd):
    """Run an argv list, never a shell string. Empty output on any failure."""
    try:
        p = subprocess.run(
            cmd, capture_output=True, text=True, timeout=TIMEOUT, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return p.stdout if p.returncode == 0 else ""


def _number(value, cast=int):
    try:
        return cast(value)
    except (TypeError, ValueError):
        return None


def png_size(f):
    head = f.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    w, h = struct.unpack(">II", head[16:24])
    return (w, h) if w and h else None


def jpeg_size(f):
    if f.read(2) != b"\xff\xd8":
        return None
    for _ in range(256):  # a malformed file cannot spin here
        marker = f.read(1)
        while marker == b"\xff":  # fill bytes between markers
            marker = f.read(1)
        if not marker:
            return None
        code = marker[0]
        if code in (0x01, 0xD8) or 0xD0 <= code <= 0xD7:
            continue
        if code == 0xD9:  # end of image, no size found
            return None
        raw = f.read(2)
        if len(raw) < 2:
            return None
        length = struct.unpack(">H", raw)[0]
        if length < 2:
            return None
        if 0xC0 <= code <= 0xCF and code not in (0xC4, 0xC8, 0xCC):
            bits = f.read(5)  # precision, height, width
            if len(bits) < 5:
                return None
            h, w = struct.unpack(">HH", bits[1:5])
            return (w, h) if w and h else None
        f.seek(length - 2, os.SEEK_CUR)
    return None


def image_size(path):
    with open(path, "rb") as f:
        size = png_size(f)
        f.seek(0)  # the PNG probe consumed the header
        return size or jpeg_size(f)


def ffprobe(path, out):
    if shutil.which("ffprobe") is None:
        return
    try:
        data = json.loads(
            _run(
                [
                    "ffprobe",
                    "-v",
                    "error",
                    "-of",
                    "json",
                    "-show_format",
                    "-show_streams",
                    "-i",
                    path,
                ]
            )
            or "{}"
        )
    except (TypeError, ValueError):
        return
    fmt = data.get("format") or {}
    streams = data.get("streams") or []
    video = next(
        (s for s in streams if s.get("codec_type") == "video" and s.get("width")), None
    )
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)
    main = audio if out["type"].startswith("audio/") else (video or audio)
    if video:
        w, h = _number(video.get("width")), _number(video.get("height"))
        if w and h:
            out["width"], out["height"] = w, h
    codec = (main or {}).get("codec_name")
    if codec:
        out["codec"] = str(codec)
    length = _number(fmt.get("duration") or (main or {}).get("duration"), float)
    if length and length > 0:
        out["duration"] = round(length, 2)
    rate = _number(fmt.get("bit_rate") or (main or {}).get("bit_rate"))
    if rate and rate > 0:
        out["bitrate"] = rate
    title = (fmt.get("tags") or {}).get("title")
    if title:
        out["title"] = str(title)


def pdfinfo(path, out):
    if shutil.which("pdfinfo") is None:
        return
    rows = {}
    for line in _run(["pdfinfo", "--", path]).splitlines():
        m = re.match(r"^([^:]+):\s+(.*)$", line)
        if m and m.group(1) in PDF_FIELDS:
            rows[m.group(1)] = m.group(2).strip()
    pages = _number((rows.get("Pages") or "").split(" ")[0])
    if pages:
        out["pages"] = pages
    for key in ("Title", "Author", "Subject"):
        if rows.get(key):
            out[key.lower()] = rows[key]


def exif(path, out):
    if shutil.which(EXIF_TOOL) is None:
        return
    raw = _run(
        [
            EXIF_TOOL,
            "-j",
            "-n",
            "-Make",
            "-Model",
            "-LensModel",
            "-DateTimeOriginal",
            "--",
            path,
        ]
    )
    try:
        tags = (json.loads(raw) or [{}])[0]
    except (TypeError, ValueError, IndexError, KeyError):
        return
    make = str(tags.get("Make") or "").strip()
    model = str(tags.get("Model") or "").strip()
    camera = " ".join(dict.fromkeys(x for x in (make, model) if x))
    if camera:
        out["camera"] = camera
    if tags.get("LensModel"):
        out["lens"] = str(tags["LensModel"])
    if tags.get("DateTimeOriginal"):
        out["taken"] = str(tags["DateTimeOriginal"])


def meta(path, st):
    kind = mimetypes.guess_type(path)[0] or "application/octet-stream"
    out = {
        "type": kind,
        "size": st.st_size,
        "modified": dt.datetime.fromtimestamp(st.st_mtime, dt.timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
    }
    try:
        if kind.startswith("image/"):
            size = image_size(path)
            if size:
                out["width"], out["height"] = size
            exif(path, out)
        elif kind.startswith(("video/", "audio/")):
            ffprobe(path, out)
        elif kind == "application/pdf":
            pdfinfo(path, out)
    except OSError:
        pass  # the stat above is the authority
    return out


def main(argv):
    if len(argv) < 2:
        print(json.dumps({"error": "usage: filemeta.py <path>"}))
        return 2
    path = argv[1]
    try:
        st = os.stat(path)
    except OSError:
        print(json.dumps({"error": "This file could not be read"}))
        return 0
    if not stat.S_ISREG(st.st_mode):
        print(json.dumps({"error": "Not a file"}))
        return 0
    print(json.dumps(meta(path, st), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
