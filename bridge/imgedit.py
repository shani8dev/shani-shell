#!/usr/bin/env python3
"""imgedit — the Image Viewer's edits, saved: turn, flip, markup, crop, resize, in
that order, with ImageMagick (one run, an argument list - nothing through a shell).

    imgedit.py save <file> <copy|replace>     the edit as JSON on stdin; prints the
                                              file written ("" on failure)

The edit: {"flipH", "flipV", "rotation": 0|90|180|270, "crop": [x, y, w, h]
(fractions of the picture as shown), "resize": "50%" | "1920x1920>" | "",
"marks": [...]}. A mark is {"kind", "color", "size", "points": [[x, y]...],
"text"}: points are fractions of the picture as shown (after the turn), size a
fraction of its shorter side. Kinds (Drawing's tools): pen, highlight (wide, see
-through), line, arrow, box, text, blur (the box blurred: hides a face, a number).

"copy" writes "<name> (edited).<ext>" beside it (or "(edited 2)" ...); "replace"
puts the original in the trash first (it can be put back), then writes in its
place. Nothing is overwritten that is not in the trash.
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile


def size_of(path: str) -> tuple[int, int]:
    r = subprocess.run(["magick", "identify", "-format", "%w %h ", path + "[0]"], capture_output=True, text=True)
    w, h = r.stdout.split()[:2]
    return int(w), int(h)


def _q(s: str) -> str:
    """Words for MVG's text: in double quotes, which MVG cannot escape inside - a
    typed " becomes ”; % doubled (ImageMagick reads %w and the like as escapes)."""
    return '"' + s.replace('"', "\u201d").replace("%", "%%").replace("\n", " ") + '"'


def mark_args(marks: list[dict], W: int, H: int) -> list[str]:
    """ImageMagick arguments for the marks on a W x H picture: blurs first (so
    what is drawn after stays sharp), then one -draw for the rest."""
    m = min(W, H)
    px = lambda p: (p[0] * W, p[1] * H)
    blur, mvg = [], []
    for k in marks:
        kind = k.get("kind", "pen")
        pts = [px(p) for p in k.get("points") or []]
        if not pts:
            continue
        c = k.get("color", "#e01b24")
        w = max(1.0, float(k.get("size", 0.008)) * m)
        a, b = pts[0], pts[-1]
        if kind == "blur":
            x0, y0, x1, y1 = min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])
            gw, gh = max(1, round(x1 - x0)), max(1, round(y1 - y0))
            blur += ["-region", "%dx%d+%d+%d" % (gw, gh, round(x0), round(y0)), "-blur", "0x%d" % max(8, round(m * 0.05)), "+region"]
            continue
        line = "stroke '%s' stroke-width %.1f fill none stroke-linecap round stroke-linejoin round " % (c, w)
        if kind in ("pen", "highlight"):
            if kind == "highlight":
                line = "stroke '%s' stroke-opacity 0.4 stroke-width %.1f fill none stroke-linecap round stroke-linejoin round " % (c, w * 4)
            if len(pts) == 1:
                pts = pts * 2
            mvg.append(line + "polyline " + " ".join("%.1f,%.1f" % p for p in pts))
        elif kind == "line":
            mvg.append(line + "line %.1f,%.1f %.1f,%.1f" % (a + b))
        elif kind == "arrow":
            mvg.append(line + "line %.1f,%.1f %.1f,%.1f" % (a + b))
            ang = math.atan2(b[1] - a[1], b[0] - a[0])
            L = max(10.0, w * 5)
            h1 = (b[0] - L * math.cos(ang - 0.45), b[1] - L * math.sin(ang - 0.45))
            h2 = (b[0] - L * math.cos(ang + 0.45), b[1] - L * math.sin(ang + 0.45))
            mvg.append("stroke '%s' fill '%s' stroke-width 1 polygon %.1f,%.1f %.1f,%.1f %.1f,%.1f" % ((c, c) + b + h1 + h2))
        elif kind == "box":
            mvg.append(line + "rectangle %.1f,%.1f %.1f,%.1f" % (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])))
        elif kind == "text" and k.get("text"):
            mvg.append("stroke none fill '%s' font-size %.1f text %.1f,%.1f %s" % (c, max(12.0, w * 5), a[0], a[1], _q(k["text"])))
    return blur + (["-draw", "\n".join(mvg)] if mvg else [])


def edit_args(path: str, e: dict) -> list[str]:
    W, H = size_of(path)
    rot = int(e.get("rotation", 0)) % 360
    if rot % 180:
        W, H = H, W
    args = []
    if e.get("flipH"):
        args.append("-flop")
    if e.get("flipV"):
        args.append("-flip")
    args += ["-rotate", str(rot), "-orient", "TopLeft"]
    args += mark_args(e.get("marks") or [], W, H)
    x, y, w, h = (e.get("crop") or [0, 0, 1, 1])
    cw, ch = max(1, round(W * w)), max(1, round(H * h))
    args += ["-crop", "%dx%d+%d+%d" % (cw, ch, round(W * x), round(H * y)), "+repage"]
    if e.get("resize"):
        args += ["-resize", e["resize"]]
    return args


def save(path: str, mode: str, e: dict) -> str:
    d, n = os.path.split(path)
    stem, ext = os.path.splitext(n)
    fd, tmp = tempfile.mkstemp(prefix=".shani-edit.", suffix=ext, dir=d)
    os.close(fd)
    r = subprocess.run(["magick", path] + edit_args(path, e) + [tmp], capture_output=True, text=True)
    if r.returncode != 0:
        os.remove(tmp)                                   # only the one this run made
        print(r.stderr.strip(), file=sys.stderr)
        return ""
    if mode == "replace":
        if subprocess.run(["gio", "trash", "--", path]).returncode != 0:
            os.remove(tmp)
            return ""
        os.rename(tmp, path)
        return path
    out, i = os.path.join(d, "%s (edited)%s" % (stem, ext)), 2
    while os.path.lexists(out):
        out, i = os.path.join(d, "%s (edited %d)%s" % (stem, i, ext)), i + 1
    os.rename(tmp, out)
    return out


def main(argv: list[str]) -> int:
    if len(argv) == 4 and argv[1] == "save" and argv[3] in ("copy", "replace"):
        try:
            e = json.loads(sys.stdin.read() or "{}")
        except ValueError:
            e = {}
        out = save(argv[2], argv[3], e)
        print(out, end="")
        return 0 if out else 1
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
