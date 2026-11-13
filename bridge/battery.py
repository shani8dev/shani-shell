#!/usr/bin/env python3
"""battery — the battery's health and its charge history, from UPower, for
Settings > Power > Battery.

    battery.py info              one JSON object (or {"present": false})
    battery.py history SECONDS   [[unix time, percent, state], ...] oldest first

UPower's own D-Bus API on the system bus (the same numbers `upower -i` prints):
health is EnergyFull against EnergyFullDesign (UPower's Capacity), cycles
are ChargeCycles where the firmware tells (-1 where it does not), and the
history is what upowerd has recorded (GetHistory "charge"), kept by it across
boots in /var/lib/upower.
"""
from __future__ import annotations

import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "org.freedesktop.UPower"
DEVICE = "org.freedesktop.UPower.Device"
STATES = {0: "unknown", 1: "charging", 2: "discharging", 3: "empty", 4: "full", 5: "pending-charge", 6: "pending-discharge"}
TECH = {0: "", 1: "Lithium-ion", 2: "Lithium polymer", 3: "Lithium iron phosphate", 4: "Lead-acid", 5: "Nickel-cadmium", 6: "Nickel-metal hydride"}


def bus():
    return Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def call(conn, path, iface, method, args=None, reply=None):
    return conn.call_sync(NAME, path, iface, method, args, GLib.VariantType(reply) if reply else None,
                          Gio.DBusCallFlags.NONE, 5000, None).unpack()


def props(conn, path):
    return call(conn, path, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", (DEVICE,)), "(a{sv})")[0]


def the_battery(conn):
    """The laptop's own battery: type 2 and a power supply (not a mouse's)."""
    for path in call(conn, "/org/freedesktop/UPower", NAME, "EnumerateDevices", None, "(ao)")[0]:
        p = props(conn, path)
        if p.get("Type") == 2 and p.get("PowerSupply") and p.get("IsPresent", True):
            return path, p
    return None, None


def info() -> dict:
    conn = bus()
    path, p = the_battery(conn)
    if not path:
        return {"present": False}
    full, design = float(p.get("EnergyFull", 0)), float(p.get("EnergyFullDesign", 0))
    health = round(100 * full / design, 1) if design > 0 and full > 0 else round(float(p.get("Capacity", 0)), 1)
    return {
        "present": True,
        "path": path,
        "percent": round(float(p.get("Percentage", 0)), 1),
        "state": STATES.get(int(p.get("State", 0)), "unknown"),
        "health": health,                                   # % of what it held new
        "cycles": int(p.get("ChargeCycles", -1)),
        "energy": round(float(p.get("Energy", 0)), 2),       # Wh now
        "energyFull": round(full, 2),                        # Wh when full, today
        "energyDesign": round(design, 2),                    # Wh when full, new
        "rate": round(float(p.get("EnergyRate", 0)), 2),     # W in or out
        "voltage": round(float(p.get("Voltage", 0)), 2),
        "temperature": round(float(p.get("Temperature", 0)), 1),
        "timeToEmpty": int(p.get("TimeToEmpty", 0)),
        "timeToFull": int(p.get("TimeToFull", 0)),
        "technology": TECH.get(int(p.get("Technology", 0)), ""),
        "vendor": str(p.get("Vendor", "")).strip(),
        "model": str(p.get("Model", "")).strip(),
    }


def history(seconds: int) -> list:
    conn = bus()
    path, _ = the_battery(conn)
    if not path:
        return []
    rows = call(conn, path, DEVICE, "GetHistory", GLib.Variant("(suu)", ("charge", int(seconds), 200)), "(a(udu))")[0]
    out = [[int(t), round(float(v), 1), STATES.get(int(s), "unknown")] for t, v, s in rows if t > 0]
    return sorted(out)


def main(argv: list[str]) -> int:
    try:
        if len(argv) >= 2 and argv[1] == "info":
            print(json.dumps(info()))
            return 0
        if len(argv) >= 3 and argv[1] == "history":
            print(json.dumps(history(int(argv[2]))))
            return 0
    except GLib.Error as e:
        print(json.dumps({"present": False, "error": e.message}))
        return 0
    print("usage: battery.py info | history SECONDS", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
