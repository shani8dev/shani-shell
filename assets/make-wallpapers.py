#!/usr/bin/env python3
"""make-wallpapers — rebuild assets/shani-{light,dark,night}.jpg.

The default wallpapers are ShaniOS's own artwork (raven beneath a ringed
planet, one composition in three palettes), stored as masters under
assets/masters/. This script upscales them to 3840x2160 (Lanczos — the masters
are 1672x941, which is 16:9) and re-encodes them as quality-88 JPEGs so the
repo stays small:

    day.png   ->  shani-light.jpg   (light theme)
    dusk.png  ->  shani-dark.jpg    (dark theme — the amber dusk, so the
                                     shell's default look carries the brand)
    night.png ->  shani-night.jpg   (picker wallpaper; the Plasma look's
                                     "night" slot uses the same file)

Accent colours: Dark #ff7f50, Light #bc3e18, dusk (twilight in the Plasma
look) #ff7f50.

usage:
    make-wallpapers.py [OUT_DIR]     (default: this script's directory)
"""
import os
import sys

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("make-wallpapers: needs Pillow (apt install python3-pil)")

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "masters")
TARGET = (3840, 2160)
QUALITY = 88
PAIRS = [
    ("day.png", "shani-light.jpg"),
    ("dusk.png", "shani-dark.jpg"),
    ("night.png", "shani-night.jpg"),
]


def main(argv):
    out = argv[1] if len(argv) > 1 else HERE
    os.makedirs(out, exist_ok=True)
    for src, name in PAIRS:
        path = os.path.join(SRC, src)
        if not os.path.exists(path):
            sys.exit(f"make-wallpapers: missing {path}")
        im = Image.open(path).convert("RGB")
        print(f"{src}: {im.size[0]}x{im.size[1]} -> {TARGET[0]}x{TARGET[1]} (lanczos, unsharp)")
        im = im.resize(TARGET, Image.LANCZOS)
        # the masters are 1672x941, so this is a 2.3x upscale: Lanczos keeps the
        # edges but leaves them soft. A mild unsharp restores the micro-contrast
        # (checked at 3x: crisper cloud and ring edges, no halos or banding);
        # threshold 2 keeps the smooth sunset gradients from getting noisy.
        im = im.filter(ImageFilter.UnsharpMask(radius=1.0, percent=55, threshold=2))
        dst = os.path.join(out, name)
        im.save(dst, quality=QUALITY, subsampling=0, optimize=True)
        print(f"{name}: {os.path.getsize(dst) // 1024} KiB")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
