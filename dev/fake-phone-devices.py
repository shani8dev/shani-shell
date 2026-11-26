#!/usr/bin/env python3
"""bluetoothctl stand-in for the Devices window's live check
(dev/shell-parts/devices.sh), wired in through $SHANI_BTCTL.

Answers the two verbs the Connect-a-device form needs — `devices` and
`pair <address>` — plus the harmless setup verbs a client likes to send.
Every invocation is logged to $SHANI_BTCTL_LOG. Nothing touches a radio:
the nearby handset and the pair result are kept in $SHANI_BTCTL_STATE.

  bluetoothctl devices                 Device AA:BB:... <name>
  bluetoothctl paired-devices          the same, once paired
  bluetoothctl pair <address>          Attempting... / Pairing successful
  bluetoothctl connect <address>       Connection successful
  bluetoothctl show [address]          controller / device info
  bluetoothctl scan on|off, power on, agent on, default-agent, quit

Env:
  SHANI_BTCTL_LOG    call log (default /tmp/fake-bt-calls)
  SHANI_BTCTL_STATE  JSON state file (default /tmp/fake-bt-state.json)
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ADDRESS = "0C:52:34:9A:1B:2C"
NAME = "Pixel 7"
HEADSET = "58:C1:2D:33:44:55"


def log_path() -> Path:
    return Path(os.environ.get("SHANI_BTCTL_LOG", "/tmp/fake-bt-calls"))


def state_path() -> Path:
    return Path(os.environ.get("SHANI_BTCTL_STATE", "/tmp/fake-bt-state.json"))


def load() -> dict:
    try:
        data = json.loads(state_path().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(data: dict) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data), encoding="utf-8")


def show_devices(paired_only: bool) -> None:
    data = load()
    paired = set(data.get("paired", []))
    rows = [(ADDRESS, NAME)]
    if paired_only:
        rows = [r for r in rows if r[0] in paired]
    for address, name in rows:
        print("Device %s %s" % (address, name))


def main() -> int:
    argv = sys.argv[1:]
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(" ".join(argv) + "\n")
    if not argv:
        return 0

    cmd, args = argv[0], argv[1:]
    if cmd == "devices":
        show_devices(False)
    elif cmd == "paired-devices":
        show_devices(True)
    elif cmd == "pair" and args:
        data = load()
        paired = list(dict.fromkeys(data.get("paired", []) + [args[0]]))
        data["paired"] = paired
        save(data)
        print("Attempting to pair with %s" % args[0])
        print("Pairing successful")
    elif cmd == "connect" and args:
        print("Connection successful")
    elif cmd == "disconnect" and args:
        print("Successful disconnected")
    elif cmd == "show":
        if args:
            print("Device %s" % args[0])
            print("\tName: %s" % NAME)
            print("\tPaired: yes")
            print("\tConnected: yes")
        else:
            print("Controller %s" % ADDRESS)
            print("\tPowered: yes")
            print("\tDiscoverable: no")
            print("\tPairable: yes")
    elif cmd == "scan" and args:
        print("Discovering %s" % ("on" if args[0] == "on" else "off"))
    elif cmd in ("power", "agent", "default-agent", "quit", "exit", "list"):
        if cmd == "power" and args:
            print("Changing %s power succeeded" % args[0])
        elif cmd == "agent" and args:
            print("Agent registered")
    # an unknown verb is logged and quietly ignored: a stand-in never guesses
    return 0


if __name__ == "__main__":
    sys.exit(main())
