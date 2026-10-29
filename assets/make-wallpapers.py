#!/usr/bin/env python3
"""make-wallpapers — render ShaniOS's default wallpapers, a dark and a light one.

Soft aurora ribbons in the shell's palette (ShaniOS teal #7fd1c1 and an indigo)
over a deep or pale ground: several layered sine bands, each a gaussian glow,
plus a little noise so the gradients never band on 8-bit screens. No text, no
version numbers — a wallpaper should not go stale.

    make-wallpapers.py OUT_DIR [WIDTH HEIGHT]     → shani-dark.jpg, shani-light.jpg

JPEG at quality 93 without chroma subsampling: 0.75 MB at 4K where PNG is 9 MB
(the anti-banding noise does not compress), and no visible loss on a gradient.

Pure numpy + Pillow, deterministic (fixed seed), so a rebuild gives the same files.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image


def hex_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


def render(w: int, h: int, dark: bool) -> Image.Image:
    rng = np.random.default_rng(7)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = x / w, y / h

    # the ground: a diagonal gradient
    if dark:
        a, b = hex_rgb("#070a10"), hex_rgb("#0d1420")
    else:
        a, b = hex_rgb("#f4f7f8"), hex_rgb("#dfe9ee")
    t = np.clip(0.55 * u + 0.45 * v, 0, 1)[..., None]
    img = a * (1 - t) + b * t

    # aurora ribbons: (colour, centre height, amplitude, frequency, phase, width, strength)
    if dark:
        ribbons = [("#7fd1c1", 0.58, 0.10, 1.3, 0.4, 0.060, 0.55),
                   ("#4a8fd8", 0.66, 0.08, 1.7, 2.1, 0.080, 0.35),
                   ("#7b6fd8", 0.48, 0.12, 0.9, 4.0, 0.110, 0.28),
                   ("#7fd1c1", 0.70, 0.05, 2.4, 1.2, 0.025, 0.40)]
    else:
        ribbons = [("#3fb3a0", 0.60, 0.10, 1.3, 0.4, 0.070, 0.30),
                   ("#6aa8e8", 0.68, 0.08, 1.7, 2.1, 0.090, 0.22),
                   ("#a99be8", 0.46, 0.11, 0.9, 4.0, 0.120, 0.20),
                   ("#3fb3a0", 0.72, 0.05, 2.4, 1.2, 0.030, 0.22)]
    for col, c, amp, freq, ph, width, strength in ribbons:
        centre = c + amp * np.sin(2 * np.pi * freq * u + ph) + 0.03 * np.sin(2 * np.pi * 3.1 * u + ph * 1.7)
        d = (v - centre) / width
        glow = np.exp(-d * d)
        # brightest in the middle, softer towards the edges — never cut off
        glow *= 0.55 + 0.45 * np.sin(np.pi * u)
        k = (strength * glow)[..., None]
        if dark:
            img = img + hex_rgb(col) * k * (1 - img)          # screen: light added to the dark
        else:
            img = img * (1 - k) + hex_rgb(col) * k            # tint on the pale ground

    # a soft vignette, then fine noise against banding
    r = np.sqrt((u - 0.5) ** 2 + (v - 0.55) ** 2)
    vig = (1 - 0.35 * np.clip(r / 0.75, 0, 1) ** 2)[..., None] if dark else (1 - 0.06 * np.clip(r / 0.75, 0, 1) ** 2)[..., None]
    img = img * vig
    img = img + rng.normal(0, 1.2 / 255.0, img.shape).astype(np.float32)
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def main(argv: list[str]) -> int:
    out = Path(argv[1]) if len(argv) > 1 else Path(".")
    w, h = (int(argv[2]), int(argv[3])) if len(argv) > 3 else (3840, 2160)
    out.mkdir(parents=True, exist_ok=True)
    render(w, h, True).save(out / "shani-dark.jpg", quality=93, subsampling=0, optimize=True)
    render(w, h, False).save(out / "shani-light.jpg", quality=93, subsampling=0, optimize=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
