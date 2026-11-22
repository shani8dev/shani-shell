#!/usr/bin/env python3
"""pdf-annotate — flatten markup strokes into a PDF page.

    pdf-annotate.py annotate <PDF> <page-1-based> <OUT>
        stdin: {"strokes": [{kind, color, size, points:[[x,y]…], text?}, …]}
        stdout: {"saved": "<OUT>"} or {"error": "..."}

Stroke model matches bridge/imgedit.py and Services/Viewer.qml: points are
fractions (0..1) of the page, top-left origin, `size` a fraction of the
shorter side. Uses PyMuPDF when installed (vector-preserving), else a
Ghostscript BeginPage overlay + pdfseparate/pdfunite (poppler, both already
shipped for the PDF viewer). The gs path keeps the page's text extractable.
No new dependency when Ghostscript is present.
"""

from __future__ import annotations

import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def q(s: str) -> str:
    """Escape a string for PostScript (...) literal."""
    return (
        s.replace("\\", "\\\\")
        .replace("(", "\\(")
        .replace(")", "\\)")
        .replace("\n", " ")
    )


def rgb(color: str) -> tuple[float, float, float]:
    c = re.sub(r"[^0-9a-fA-F]", "", color or "e5484d")[:6].ljust(6, "0")
    return tuple(int(c[i : i + 2], 16) / 255 for i in (0, 2, 4))


def ps_for(strokes: list[dict], W: float, H: float) -> str:
    """PostScript drawing operators for the strokes, in PS coords (bottom-left y)."""
    m = min(W, H)
    out = []
    for k in strokes:
        kind = k.get("kind", "pen")
        pts = k.get("points") or []
        if not pts:
            continue
        r, g, b = rgb(k.get("color", "#e5484d"))
        w = max(1.0, float(k.get("size", 0.008)) * m)
        P = lambda p: (p[0] * W, (1 - p[1]) * H)  # y flip
        a, z = P(pts[0]), P(pts[-1])
        head = f"{r:.3f} {g:.3f} {b:.3f} setrgbcolor {w:.2f} setlinewidth 1 setlinecap 1 setlinejoin\n"
        if kind in ("pen", "highlight", "line"):
            if kind == "highlight":
                head = f"{r:.3f} {g:.3f} {b:.3f} setrgbcolor {w * 4:.2f} setlinewidth\n"
            seq = pts if len(pts) > 1 else [pts[0], pts[0]]
            out.append(
                head
                + "newpath "
                + " ".join(
                    (
                        f"{P(p)[0]:.2f} {P(p)[1]:.2f} "
                        + ("moveto" if i == 0 else "lineto")
                    )
                    for i, p in enumerate(seq)
                )
                + " stroke"
            )
        elif kind == "arrow":
            ang = math.atan2(z[1] - a[1], z[0] - a[0])
            L = max(10.0, w * 5)
            h1 = (z[0] - L * math.cos(ang - 0.45), z[1] - L * math.sin(ang - 0.45))
            h2 = (z[0] - L * math.cos(ang + 0.45), z[1] - L * math.sin(ang + 0.45))
            out.append(
                head
                + f"newpath {a[0]:.2f} {a[1]:.2f} moveto {z[0]:.2f} {z[1]:.2f} lineto stroke"
            )
            out.append(
                f"{r:.3f} {g:.3f} {b:.3f} setrgbcolor newpath {z[0]:.2f} {z[1]:.2f} moveto "
                f"{h1[0]:.2f} {h1[1]:.2f} lineto {h2[0]:.2f} {h2[1]:.2f} lineto closepath fill"
            )
        elif kind == "box":
            xs = [P(p)[0] for p in pts[:2]]
            ys = [P(p)[1] for p in pts[:2]]
            out.append(
                head
                + "newpath %.2f %.2f %.2f %.2f rectstroke"
                % (min(xs), min(ys), abs(xs[1] - xs[0]), abs(ys[1] - ys[0]))
            )
        elif kind == "blur":
            xs = [P(p)[0] for p in pts[:2]]
            ys = [P(p)[1] for p in pts[:2]]
            out.append(
                "0.5 0.5 0.5 setrgbcolor newpath %.2f %.2f %.2f %.2f rectfill"
                % (min(xs), min(ys), abs(xs[1] - xs[0]), abs(ys[1] - ys[0]))
            )
        elif kind == "text" and k.get("text"):
            size = max(12.0, w * 5)
            out.append(
                f"{r:.3f} {g:.3f} {b:.3f} setrgbcolor /Helvetica findfont {size:.1f} scalefont setfont "
                f"newpath {a[0]:.2f} {a[1]:.2f} moveto ({q(str(k['text']))}) show"
            )
    return "\n".join(out)


def page_size(pdf: str, page: int) -> tuple[float, float]:
    r = subprocess.run(
        ["pdfinfo", "-f", str(page), "-l", str(page), pdf],
        capture_output=True,
        text=True,
    )
    m = re.search(r"Page\s+%d size:\s+([\d.]+) x ([\d.]+)" % page, r.stdout)
    if not m:
        raise RuntimeError("could not read the page size")
    return float(m.group(1)), float(m.group(2))


def annotate_pymupdf(pdf: str, page: int, strokes: list[dict], out: str) -> bool:
    try:
        import pymupdf as fitz
    except ImportError:
        try:
            import fitz
        except ImportError:
            return False
    doc = fitz.open(pdf)
    pg = doc[page - 1]
    W, H = pg.rect.width, pg.rect.height
    m = min(W, H)
    P = lambda p: fitz.Point(p[0] * W, p[1] * H)
    for k in strokes:
        pts = k.get("points") or []
        if not pts:
            continue
        col = rgb(k.get("color", "#e5484d"))
        w = max(1.0, float(k.get("size", 0.008)) * m)
        kind = k.get("kind", "pen")
        if kind in ("pen", "highlight", "line"):
            seq = [P(p) for p in pts] if len(pts) > 1 else [P(pts[0]), P(pts[0])]
            pg.draw_polyline(
                seq,
                color=col,
                width=w * (4 if kind == "highlight" else 1),
                stroke_opacity=0.4 if kind == "highlight" else 1,
            )
        elif kind == "arrow":
            a, z = P(pts[0]), P(pts[-1])
            pg.draw_line(a, z, color=col, width=w)
            ang = math.atan2(z.y - a.y, z.x - a.x)
            L = max(10.0, w * 5)
            pg.draw_polyline(
                [
                    z,
                    fitz.Point(
                        z.x - L * math.cos(ang - 0.45), z.y - L * math.sin(ang - 0.45)
                    ),
                    fitz.Point(
                        z.x - L * math.cos(ang + 0.45), z.y - L * math.sin(ang + 0.45)
                    ),
                ],
                color=col,
                fill=col,
                width=1,
            )
        elif kind == "box":
            xs = [P(p).x for p in pts[:2]]
            ys = [P(p).y for p in pts[:2]]
            pg.draw_rect(
                fitz.Rect(min(xs), min(ys), max(xs), max(ys)), color=col, width=w
            )
        elif kind == "blur":
            xs = [P(p).x for p in pts[:2]]
            ys = [P(p).y for p in pts[:2]]
            pg.draw_rect(
                fitz.Rect(min(xs), min(ys), max(xs), max(ys)),
                color=None,
                fill=(0.5, 0.5, 0.5),
                fill_opacity=0.75,
            )
        elif kind == "text" and k.get("text"):
            pg.insert_text(
                P(pts[0]),
                str(k["text"]),
                fontsize=max(12.0, w * 5),
                fontname="helv",
                color=col,
            )
    doc.save(out, garbage=1, deflate=True)
    return True


def annotate_gs(pdf: str, page: int, strokes: list[dict], out: str) -> None:
    if not (
        shutil.which("gs") and shutil.which("pdfseparate") and shutil.which("pdfunite")
    ):
        raise RuntimeError(
            "needs PyMuPDF or Ghostscript + poppler (pdfseparate, pdfunite)"
        )
    work = tempfile.mkdtemp(prefix="shani-pdf-ann-")
    try:
        W, H = page_size(pdf, page)
        subprocess.run(
            ["pdfseparate", pdf, str(Path(work) / "p-%d.pdf")],
            check=True,
            capture_output=True,
        )
        ps = (
            "%!PS\n<< /BeginPage {\n" + ps_for(strokes, W, H) + "\n} >> setpagedevice\n"
        )
        (Path(work) / "overlay.ps").write_text(ps)
        target = Path(work) / f"p-{page}.pdf"
        ann = Path(work) / f"p-{page}-ann.pdf"
        subprocess.run(
            [
                "gs",
                "-q",
                "-dNOPAUSE",
                "-dBATCH",
                "-sDEVICE=pdfwrite",
                "-sOutputFile=" + str(ann),
                str(Path(work) / "overlay.ps"),
                str(target),
            ],
            check=True,
            capture_output=True,
        )
        parts = sorted(Path(work).glob("p-*.pdf"))
        parts = [
            p for p in parts if p != target
        ]  # annotated page replaces the plain one
        subprocess.run(
            ["pdfunite"] + [str(p) for p in parts] + [out],
            check=True,
            capture_output=True,
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main(argv: list[str]) -> int:
    if len(argv) < 5 or argv[1] != "annotate":
        print(
            "usage: pdf-annotate.py annotate PDF PAGE OUT  (strokes JSON on stdin)",
            file=sys.stderr,
        )
        return 2
    try:
        req = json.loads(sys.stdin.read() or "{}")
        strokes = req.get("strokes") or []
        if not isinstance(strokes, list):
            raise ValueError("strokes must be a list")
        if annotate_pymupdf(argv[2], int(argv[3]), strokes, argv[4]):
            r = {"saved": argv[4]}
        else:
            annotate_gs(argv[2], int(argv[3]), strokes, argv[4])
            r = {"saved": argv[4]}
    except Exception as exc:  # noqa: BLE001
        r = {"error": str(exc)}
    print(json.dumps(r))
    return 0 if "saved" in r else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
