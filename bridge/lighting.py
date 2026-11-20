#!/usr/bin/env python3
"""lighting — the coloured lights this computer has, as JSON; no root needed.

    lighting.py list      [{"led", "label", "color": "#rrggbb", "level": 0..100}]

The kernel's multicolour LED class (Documentation/leds/leds-class-multicolor):
each light is /sys/class/leds/<led>/ with multi_index (the channel order, e.g.
"red green blue"), multi_intensity (one value per channel, 0..max_brightness)
and brightness (the overall level, 0..max_brightness). A DualSense's light bar,
a handheld's stick rings and some RGB keyboards are lights of that class - no
OpenRGB. Settings > Controllers shows them and changes them through
shani-admin.py's `lighting` action. Ananta OS's Display & Lighting page, read
from the kernel.
SHANI_LEDS_DIR (tests): a directory standing in for /sys/class/leds.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

LEDS = Path(os.environ.get("SHANI_LEDS_DIR", "/sys/class/leds"))


def _read(p: Path) -> str:
    try:
        return p.read_text().strip()
    except OSError:
        return ""


def label(led: str) -> str:
    n = led.lower()
    if "joystick_rings" in n or "stick" in n:
        return "Stick lights"
    if "kbd_backlight" in n or "keyboard" in n:
        return "Keyboard light"
    if n.startswith("input") or "indicator" in n or "lightbar" in n:
        return "Controller light"
    return led


def lights() -> list[dict]:
    out = []
    for d in sorted(LEDS.glob("*")):
        index = _read(d / "multi_index").split()
        values = _read(d / "multi_intensity").split()
        if sorted(index) != ["blue", "green", "red"] or len(values) != 3:
            continue
        try:
            top = int(_read(d / "max_brightness") or 255)
            chan = {c: int(v) for c, v in zip(index, values)}
            level = int(_read(d / "brightness") or 0)
        except ValueError:
            continue
        top = top or 255
        rgb = [max(0, min(255, round(chan[c] * 255 / top))) for c in ("red", "green", "blue")]
        out.append({"led": d.name, "label": label(d.name), "color": "#%02x%02x%02x" % tuple(rgb),
                    "level": round(level * 100 / top)})
    return out


def main(argv: list[str]) -> int:
    if argv[1:2] != ["list"]:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    print(json.dumps(lights()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
