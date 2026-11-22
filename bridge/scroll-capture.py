#!/usr/bin/env python3
"""scroll-capture — take a scrolling screenshot and stitch it into one image.

Uses grim (Wayland screenshot), slop (region select), ydotool (send scroll
events) and PIL (stitch overlapping parts). Falls back to manual mode where
the person scrolls themselves and presses Enter between captures.

    scroll-capture.py select              select a region, print "X Y W H"
    scroll-capture.py capture X Y W H N   capture N parts with scrolling, stitch
    scroll-capture.py stitch OUTDIR OUT   stitch existing part-*.png files

The shell calls `select` first (to get the geometry), then `capture` with that
geometry. Output goes to $XDG_SCREENSHOTS_DIR (default ~/Pictures/Screenshots).
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageChops


def sh(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def select_region() -> int:
    """Ask the user to select a region with slop."""
    if not shutil_which("slop"):
        print("slop is not installed", file=sys.stderr)
        return 1
    r = sh(["slop", "-f", "%x %y %w %h", "-b", "2", "-c", "0.2,0.4,0.8,0.6"])
    if r.returncode != 0:
        return 2  # user cancelled
    print(r.stdout.strip())
    return 0


def shutil_which(name: str) -> bool:
    return sh(["sh", "-c", f"command -v {name} >/dev/null 2>&1"]).returncode == 0


def capture_part(geometry: str, out: Path) -> bool:
    return sh(["grim", "-g", geometry, str(out)]).returncode == 0


def scroll_down(lines: int = 12) -> None:
    """Send scroll-down wheel events via ydotool."""
    if not shutil_which("ydotool"):
        return
    # ydotool click 5 = wheel down; 4 = wheel up
    for _ in range(lines):
        sh(["ydotool", "click", "5"])
        time.sleep(0.02)


def find_overlap(a: Image.Image, b: Image.Image, max_overlap: int | None = None) -> int:
    """Find how many top rows of `b` duplicate the bottom rows of `a`.

    Compares the top rows of b against the bottom rows of a, returning the
    largest row count where they match (within a small colour tolerance).
    """
    if a.width != b.width:
        return 0
    w, ah = a.size
    bh = b.height
    limit = min(ah, bh, max_overlap or bh)
    best = 0
    # sample a few columns to keep it fast
    cols = [min(w - 1, int(w * f)) for f in (0.1, 0.3, 0.5, 0.7, 0.9)]
    for n in range(8, limit + 1):  # at least 8 rows; a whole capture can be a duplicate
        strip_a = a.crop((0, ah - n, w, ah))
        strip_b = b.crop((0, 0, w, n))
        diff = ImageChops.difference(strip_a, strip_b)
        # average difference across sampled columns
        total = 0
        count = 0
        for c in cols:
            px = diff.load()
            for y in range(0, n, max(1, n // 12)):
                r, g, b_ = px[c, y][:3]
                total += r + g + b_
                count += 3
        avg = total / max(1, count)
        if avg < 12:  # close enough → these rows overlap
            best = n
    return best


def stitch(parts: list[Path], out: Path) -> bool:
    """Stitch part images by overlapping their duplicate rows."""
    if not parts:
        return False
    acc = Image.open(parts[0]).convert("RGB")
    for p in parts[1:]:
        nxt = Image.open(p).convert("RGB")
        ov = find_overlap(acc, nxt)
        crop = ov if ov > 0 else 0
        merged = Image.new("RGB", (acc.width, acc.height + nxt.height - crop))
        merged.paste(acc, (0, 0))
        merged.paste(nxt, (0, acc.height - crop))
        acc = merged
    out.parent.mkdir(parents=True, exist_ok=True)
    acc.save(out)
    return True


def capture_series(x: str, y: str, w: str, h: str, count: int, out: Path) -> int:
    if not shutil_which("grim"):
        print("grim is not installed", file=sys.stderr)
        return 1
    geometry = f"{x},{y} {w}x{h}"
    tmp = Path(tempfile.mkdtemp(prefix="shani-scroll-"))
    parts: list[Path] = []
    for i in range(count):
        part = tmp / f"part-{i:03d}.png"
        if not capture_part(geometry, part):
            break
        parts.append(part)
        if i < count - 1:
            # scroll and wait for the page to settle
            scroll_down(10)
            time.sleep(0.35)
    if not parts:
        print("no parts captured", file=sys.stderr)
        return 1
    ok = stitch(parts, out)
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: scroll-capture.py select | capture X Y W H N | stitch OUTDIR OUT",
            file=sys.stderr,
        )
        return 2
    cmd = argv[1]
    if cmd == "select":
        return select_region()
    if cmd == "capture":
        if len(argv) < 7:
            print("capture needs X Y W H COUNT", file=sys.stderr)
            return 2
        d = Path(
            os.environ.get("XDG_SCREENSHOTS_DIR")
            or Path.home() / "Pictures" / "Screenshots"
        )
        out = d / f"scroll-{int(time.time())}.png"
        rc = capture_series(argv[2], argv[3], argv[4], argv[5], int(argv[6]), out)
        if rc == 0:
            print(str(out))
        return rc
    if cmd == "stitch":
        if len(argv) < 4:
            print("stitch needs OUTDIR OUT", file=sys.stderr)
            return 2
        parts = sorted(Path(argv[2]).glob("part-*.png"))
        return 0 if stitch(parts, Path(argv[3])) else 1
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
