#!/usr/bin/env python3
"""handwriting.py - read what was written on the screen keyboard's pad.

    handwriting.py LANG < rows.json        ->  {"rows": ["text of row 1", ...]}

rows.json is [[stroke, ...], ...] - one list per ruled row, a stroke a list of
[x, y] points. Each row is drawn on its own (black ink, white paper, the ink
cropped and padded) and read by Tesseract as one line (--psm 7); rows come back
in order, so the caller can join them with Return - a paragraph stays one.
LANG is Tesseract's (eng, mar, hin...); a missing language falls back to eng.
Nothing leaves the machine.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile


def draw(strokes: list, path: str) -> bool:
    pts = [p for s in strokes for p in s]
    if not pts:
        return False
    x0, y0 = min(p[0] for p in pts), min(p[1] for p in pts)
    x1, y1 = max(p[0] for p in pts), max(p[1] for p in pts)
    pad = 24
    w, h = int(x1 - x0) + 2 * pad, int(y1 - y0) + 2 * pad
    cmds = []
    for s in strokes:
        if len(s) == 1:
            s = [s[0], [s[0][0] + 1, s[0][1]]]
        cmds.append("polyline " + " ".join(f"{p[0] - x0 + pad:.1f},{p[1] - y0 + pad:.1f}" for p in s))
    magick = shutil.which("magick") or shutil.which("convert")
    if not magick:
        return False
    # Tesseract reads printed sizes best: ink scaled to about 48 px tall
    scale = max(1.0, 48.0 / max(1.0, y1 - y0))
    subprocess.run([magick, "-size", f"{w}x{h}", "xc:white", "-fill", "none", "-stroke", "black",
                    "-strokewidth", "4", "-draw", " ".join(cmds), "-resize", f"{scale * 100:.0f}%",
                    path], check=True, capture_output=True, timeout=20)
    return True


def read(path: str, lang: str) -> str:
    out = subprocess.run(["tesseract", path, "stdout", "--psm", "7", "-l", lang],
                         capture_output=True, text=True, timeout=30).stdout
    return " ".join(out.split())


def langs() -> set:
    try:
        out = subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True, timeout=10).stdout
        return {l.strip() for l in out.splitlines()[1:] if l.strip()}
    except (OSError, subprocess.TimeoutExpired):
        return set()


def main(argv: list) -> int:
    lang = argv[1] if len(argv) > 1 else "eng"
    if lang not in langs():
        lang = "eng"
    rows = json.load(sys.stdin)
    texts = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, strokes in enumerate(rows):
            path = os.path.join(tmp, f"row{i}.png")
            texts.append(read(path, lang) if draw(strokes, path) else "")
    print(json.dumps({"rows": texts}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
