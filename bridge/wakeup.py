#!/usr/bin/env python3
"""wakeup — what may wake this computer from sleep, as JSON; no root needed.

    wakeup.py list      [{"path", "name", "kind", "enabled"}]

The kernel's own switch for each device is its sysfs `power/wakeup` file
("enabled" / "disabled"); Settings > Power shows the ones a person recognises
and changes them through shani-admin.py's `wakeup` action:

  usb      a USB device that is not a hub, by its product name (a keyboard or
           mouse that wakes the laptop in a bag)
  lid      the lid (ACPI PNP0C0D): opening it wakes the computer
  network  a network card's Wake-on-LAN, by interface name

Ananta OS lists "wake sources" on its Power page; this is that, read from the
kernel. `path` is the device's sysfs directory (under /sys/devices), the one
shani-admin.py accepts.
SHANI_SYSFS (tests): a directory standing in for /sys.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SYS = Path(os.environ.get("SHANI_SYSFS", "/sys"))


def _read(p: Path) -> str:
    try:
        return p.read_text().strip()
    except OSError:
        return ""


def _entry(dev: Path, name: str, kind: str) -> dict | None:
    state = _read(dev / "power" / "wakeup")
    if state not in ("enabled", "disabled"):
        return None
    return {"path": str(dev.resolve()), "name": name, "kind": kind, "enabled": state == "enabled"}


def devices() -> list[dict]:
    out, seen = [], set()

    def add(e):
        if e and e["path"] not in seen:
            seen.add(e["path"])
            out.append(e)

    for d in sorted((SYS / "bus" / "usb" / "devices").glob("*")):
        if _read(d / "bDeviceClass") == "09" or not (d / "idVendor").exists():
            continue                                    # hubs, and interfaces
        product = _read(d / "product")
        if product:
            maker = _read(d / "manufacturer")
            add(_entry(d, f"{maker} {product}".strip() if maker and maker not in product else product, "usb"))
    for d in sorted((SYS / "bus" / "acpi" / "devices").glob("PNP0C0D:*")):
        add(_entry(d, "Opening the lid", "lid"))
    for n in sorted((SYS / "class" / "net").glob("*")):
        if (n / "device").exists():
            add(_entry(n / "device", f"Wake-on-LAN ({n.name})", "network"))
    return out


def main(argv: list[str]) -> int:
    if argv[1:2] != ["list"]:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    print(json.dumps(devices()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
