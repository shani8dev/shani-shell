#!/usr/bin/env python3
"""plugwatch — devices plugged in while the session runs, without polling.

One long-lived `udevadm monitor` (udev's own netlink events, after its rules
ran, so the properties are the ones the rules set) and one JSON line on stdout
per thing the shell greets or follows (Services/Plugged):

  {"event": "add", "kind": "tablet", "name": "Wacom Intuos S", "key": "3/56a/374/110"}
  {"event": "remove", "kind": "controller", "key": "..."}
  {"event": "screens"}                       a monitor plugged in or out (drm hotplug)

kinds: tablet (ID_INPUT_TABLET), controller (ID_INPUT_JOYSTICK), security-key
(ID_FIDO_TOKEN, systemd's 60-fido-id rules), scanner (libsane_matched, SANE's
hwdb), each read from udev's properties - no guessing from names.

udevadm monitor reports what happens from now on, so what was plugged in at
login is never greeted; a device is announced once per run (a flaky cable
re-adding it is not news). One device is several udev devices (a tablet's pen
and pad, a controller's input node and its event node): the key is what they
share. SHANI_UDEVADM replaces the monitor command (the tests feed recorded events).
"""

import json
import os
import shlex
import subprocess
import sys

MONITOR = ["udevadm", "monitor", "--udev", "--property",
           "--subsystem-match=input", "--subsystem-match=hidraw",
           "--subsystem-match=usb", "--subsystem-match=drm"]


def unquote(v):
    return v[1:-1] if len(v) >= 2 and v[0] == v[-1] == '"' else v


def label(p, *keys):
    for k in keys:
        v = unquote(p.get(k, "")).replace("\\x20", " ").replace("_", " ").strip()
        if v:
            return v
    return ""


def classify(p):
    """A udev event's properties -> (kind, name, key), or None for nothing to say."""
    sub = p.get("SUBSYSTEM")
    if sub == "drm":
        return ("screens", "", "") if p.get("HOTPLUG") == "1" else None
    if sub == "input" and "NAME" in p:        # the inputN device: one per physical part
        name = unquote(p["NAME"])
        key = p.get("PRODUCT", "") + "/" + unquote(p.get("UNIQ", ""))
        if p.get("ID_INPUT_TABLET") == "1":
            for tail in (" Pen", " Pad", " Stylus", " Finger", " Touch"):
                if name.endswith(tail):
                    name = name[:-len(tail)]
            return "tablet", name, key
        if p.get("ID_INPUT_JOYSTICK") == "1":
            return "controller", name, key
        return None
    if sub == "hidraw" and p.get("ID_FIDO_TOKEN") == "1":
        key = p.get("ID_SERIAL") or p.get("DEVPATH", "").rsplit("/hidraw", 1)[0]
        return "security-key", label(p, "ID_MODEL_FROM_DATABASE", "ID_MODEL") or "Security key", key
    if sub == "usb" and p.get("DEVTYPE") == "usb_device" and p.get("libsane_matched") == "yes":
        name = " ".join(x for x in (label(p, "ID_VENDOR_FROM_DATABASE", "ID_VENDOR"),
                                    label(p, "ID_MODEL_FROM_DATABASE", "ID_MODEL")) if x)
        return "scanner", name or "Scanner", p.get("ID_SERIAL") or p.get("DEVPATH", "")
    return None


def records(stream):
    """udevadm's --property output: a header line, KEY=VALUE lines, a blank line."""
    props = None
    for line in stream:
        line = line.rstrip("\n")
        if not line:
            if props:
                yield props
            props = None
        elif line.startswith(("UDEV ", "KERNEL")):
            props = {}
        elif props is not None and "=" in line:
            k, v = line.split("=", 1)
            props[k] = v
    if props:
        yield props


def run(stream, out=sys.stdout):
    greeted = set()
    present = {}                              # key -> kind, for what comes back out
    for p in records(stream):
        action = p.get("ACTION")
        c = classify(p)
        if not c:
            continue
        kind, name, key = c
        if kind == "screens":
            if action == "change":
                print(json.dumps({"event": "screens"}), file=out, flush=True)
            continue
        if action == "add":
            present[(kind, key)] = True
            if (kind, key) in greeted:
                continue
            greeted.add((kind, key))
            print(json.dumps({"event": "add", "kind": kind, "name": name, "key": key}), file=out, flush=True)
        elif action == "remove" and present.pop((kind, key), None):
            print(json.dumps({"event": "remove", "kind": kind, "key": key}), file=out, flush=True)


def main() -> int:
    cmd = shlex.split(os.environ["SHANI_UDEVADM"]) if os.environ.get("SHANI_UDEVADM") else MONITOR
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, errors="replace")
    except OSError as e:
        print(f"plugwatch: {e}", file=sys.stderr)
        return 1
    print(json.dumps({"event": "ready"}), flush=True)
    try:
        run(proc.stdout)
    finally:
        proc.kill()
    return proc.wait() or 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
