#!/usr/bin/env python3
"""Stands in for libratbag's ratbagctl (no ratbagd or gaming mouse in a container).

One mouse, "Logitech G502 HERO", as ratbagctl 0.18 prints it (list, info, dpi
get-all, rate get-all) and as its set commands change it. The mouse's state is
the JSON file FAKE_RATBAG_STATE (default /tmp/ratbag-state.json); every call is
appended to FAKE_RATBAG_LOG (default /tmp/ratbag-log). FAKE_RATBAG_NONE=1: no mouse.
"""
import json
import os
import sys

STATE = os.environ.get("FAKE_RATBAG_STATE", "/tmp/ratbag-state.json")
DPIS = list(range(100, 25650, 50))
DEV = "singing-gundi"
s = {"dpi": 1600, "rate": 1000, "buttons": ["button 1", "button 2", "button 3", "button 4", "button 5", "button 4", "button 5", "none"]}
try:
    s.update(json.load(open(STATE)))
except (OSError, ValueError):
    pass
a = sys.argv[1:]
with open(os.environ.get("FAKE_RATBAG_LOG", "/tmp/ratbag-log"), "a") as log:
    log.write(" ".join(a) + "\n")
if os.environ.get("FAKE_RATBAG_NONE"):
    print("No devices available.")
    sys.exit(0)
if a == ["list"]:
    print("{:20s} {:32s}".format(DEV + ":", "Logitech G502 HERO Gaming Mouse"))
    sys.exit(0)
if not a or a[0] not in (DEV, "Logitech G502 HERO Gaming Mouse"):
    print(f"Unable to find device {a[0] if a else ''}")
    sys.exit(1)
a = a[1:]


def mapped(b):
    return "none" if b == "none" else (f"key '{b[4:]}'" if b.startswith("key ") else f"'{b}'")


if a == ["info"]:
    print(f"{DEV} - Logitech G502 HERO Gaming Mouse")
    print("             Model: usb:046d:c08b:0")
    print("       Device Type: Mouse")
    print(f" Number of Buttons: {len(s['buttons'])}")
    print("    Number of Leds: 2")
    print("Number of Profiles: 2")
    for p in (0, 1):
        print(f"  Profile {p}:{' (active)' if p == 0 else ''}")
        print("    Name: n/a")
        print(f"    Report Rate: {s['rate'] if p == 0 else 500}Hz")
        print("    Resolutions:")
        for i, d in enumerate([800, s["dpi"], 3200]):
            print(f"      {i}: {d}dpi{' (active)' if i == 1 else ''}{' (default)' if i == 1 else ''}")
        for i, b in enumerate(s["buttons"] if p == 0 else ["button 1"] * len(s["buttons"])):
            print(f"    Button: {i} is mapped to {mapped(b)}")
elif a == ["dpi", "get-all"]:
    print(" ".join(map(str, DPIS)))
elif a == ["rate", "get-all"]:
    print("125 250 500 1000")
elif a[:2] == ["dpi", "set"] and int(a[2]) in DPIS:
    s["dpi"] = int(a[2])
elif a[:2] == ["rate", "set"] and a[2] in ("125", "250", "500", "1000"):
    s["rate"] = int(a[2])
elif a[:1] == ["button"] and a[2:4] == ["action", "set"] and int(a[1]) < len(s["buttons"]):
    n = int(a[1])
    if a[4] == "button":
        s["buttons"][n] = "button " + a[5]
    elif a[4] == "key" and a[5].startswith("KEY_"):
        s["buttons"][n] = "key " + a[5]
    elif a[4] == "disabled":
        s["buttons"][n] = "none"
    else:
        sys.exit(1)
else:
    print("Invalid command", file=sys.stderr)
    sys.exit(2)
json.dump(s, open(STATE, "w"))
