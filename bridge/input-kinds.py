#!/usr/bin/env python3
"""input-kinds — what this computer has to type and touch with, from udev's database.

  input-kinds.py      JSON: {"keyboard": bool, "touchscreen": bool, "tabletSwitch": bool}

keyboard: a device udev calls a keyboard (ID_INPUT_KEYBOARD=1) that is not a
power, lid, sleep or video button, a hotkey device, or a virtual keyboard
(wtype's, ydotool's). Without one - or with only a touchscreen - the screen
keyboard opens by itself wherever a password is asked (lock, sign-in, setup, an
administrator's prompt), so a broken keyboard never locks anyone out.
tabletSwitch: a convertible's tablet-mode switch (ID_INPUT_SWITCH, SW_TABLET_MODE
among its switches is told by the shell's tablet-mode reader).

One `udevadm info --export-db` at start; the shell asks again when an input
device comes or goes (bridge/plugwatch.py). SHANI_UDEV_DB reads a file instead
(the tests' fakes).
"""
import json
import os
import re
import subprocess
import sys

NOT_A_KEYBOARD = re.compile(r"power button|lid switch|sleep button|video bus|virtual|consumer control|"
                            r"system control|wmi hotkeys|hid events|pc speaker|headphone|hdmi", re.I)


def blocks(text):
    for b in text.split("\n\n"):
        props = {}
        for line in b.splitlines():
            if line.startswith("E: ") and "=" in line:
                k, v = line[3:].split("=", 1)
                props[k] = v.strip('"')
        if props:
            yield props


def kinds(text):
    out = {"keyboard": False, "touchscreen": False, "tabletSwitch": False}
    for p in blocks(text):
        if p.get("SUBSYSTEM") != "input":
            continue
        name = p.get("NAME", "")
        if p.get("ID_INPUT_KEYBOARD") == "1" and name and not NOT_A_KEYBOARD.search(name):
            out["keyboard"] = True
        if p.get("ID_INPUT_TOUCHSCREEN") == "1":
            out["touchscreen"] = True
        if p.get("ID_INPUT_SWITCH") == "1" and re.search(r"tablet|virtual switches|hid switches|convertible", name, re.I):
            out["tabletSwitch"] = True
    return out


def main():
    path = os.environ.get("SHANI_UDEV_DB")
    if path:
        try:
            text = open(path).read()
        except OSError:
            text = ""
    else:
        try:
            text = subprocess.run(["udevadm", "info", "--export-db"], capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.TimeoutExpired):
            # no udev to ask: assume a keyboard, as before this existed
            print(json.dumps({"keyboard": True, "touchscreen": False, "tabletSwitch": False}))
            return 0
    print(json.dumps(kinds(text)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
