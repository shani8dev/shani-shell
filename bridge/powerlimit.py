#!/usr/bin/env python3
"""powerlimit — a handheld's chip power limit (watts), as JSON; no root needed.

    powerlimit.py show    {"method", "min", "max", "current"} or null

Where the kernel lets it be set (Ananta OS's Gaming > Handheld, the same two ways):
  asus     ASUS firmware attributes (ROG Ally and others):
           /sys/class/firmware-attributes/asus-armoury/attributes/ppt_pl1_spl
           (and ppt_pl2_sppt, ppt_fppt, which follow it), in watts
  amdgpu   the AMD graphics driver's package power cap (Steam Deck, many AMD
           handhelds): /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap, in µW
Changed through shani-admin.py's `power-limit` action. The power mode itself
stays power-profiles-daemon's (one owner per setting).
SHANI_SYSFS (tests): a directory standing in for /sys.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SYS = Path(os.environ.get("SHANI_SYSFS", "/sys"))


def _num(p: Path) -> int:
    try:
        return int(p.read_text().strip())
    except (OSError, ValueError):
        return 0


def find(sys_root: Path = SYS) -> tuple[str, Path] | None:
    asus = sys_root / "class/firmware-attributes/asus-armoury/attributes"
    if (asus / "ppt_pl1_spl/current_value").exists():
        return "asus", asus
    for card in sorted((sys_root / "class/drm").glob("card*")):
        try:
            if (card / "device/vendor").read_text().strip() != "0x1002":
                continue
        except OSError:
            continue
        for hw in sorted((card / "device/hwmon").glob("hwmon*")):
            if (hw / "power1_cap").exists() and (hw / "power1_cap_max").exists():
                return "amdgpu", hw
    return None


def show(sys_root: Path = SYS) -> dict | None:
    f = find(sys_root)
    if not f:
        return None
    method, d = f
    if method == "asus":
        lo, hi, cur = (_num(d / "ppt_pl1_spl" / n) for n in ("min_value", "max_value", "current_value"))
    else:
        lo, hi, cur = (_num(d / n) // 1_000_000 for n in ("power1_cap_min", "power1_cap_max", "power1_cap"))
    return {"method": method, "min": max(lo, 3), "max": hi, "current": cur}


def main(argv: list[str]) -> int:
    if argv[1:2] != ["show"]:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    print(json.dumps(show()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
