#!/usr/bin/env python3
"""plugwatch — devices plugged in while the session runs, without polling.

One long-lived `udevadm monitor` (udev's own netlink events, after its rules
ran, so the properties are the ones the rules set) and one JSON line on stdout
per thing the shell greets or follows (Services/Plugged):

  {"event": "add", "kind": "tablet", "name": "Wacom Intuos S", "key": "3/56a/374/110"}
  {"event": "remove", "kind": "controller", "key": "..."}
  {"event": "screens"}                       a monitor plugged in or out (drm hotplug)

kinds: input (a keyboard, touchscreen or switch: followed, never greeted),
tablet (ID_INPUT_TABLET), controller (ID_INPUT_JOYSTICK), security-key
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
import re
import shlex
import subprocess
import sys

MONITOR = ["udevadm", "monitor", "--udev", "--property",
           "--subsystem-match=input", "--subsystem-match=hidraw",
           "--subsystem-match=usb", "--subsystem-match=drm", "--subsystem-match=sound",
           "--subsystem-match=video4linux", "--subsystem-match=tty"]

# a presentation clicker: a "keyboard" whose keys are only these (page up / down,
# B for a black screen, F5 / Shift+F5 to start, Escape, period, the arrows)
CLICKER_KEYS = {1, 42, 48, 52, 63, 103, 104, 105, 106, 108, 109, 425, 431}
CLICKER_NAME = re.compile(r"presenter|clicker|remote|spotlight|\bR[48]00\b", re.I)
CAPTURE_NAME = re.compile(r"capture|hdmi|cam ?link|game ?cap", re.I)


def keys_of(bitmask):
    """The KEY= property of an input device: hex words, the highest first -> key codes."""
    codes, words = set(), bitmask.split()
    for i, w in enumerate(reversed(words)):
        v = int(w, 16)
        for b in range(64):
            if v >> b & 1:
                codes.add(i * 64 + b)
    return codes


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
        if p.get("HOTPLUG") == "1":
            return "screens", "", ""
        # a whole graphics card arriving while the session runs: only an external one
        # (Thunderbolt) does that - cards in the machine are there before login
        if re.fullmatch(r"/dev/dri/card\d+", p.get("DEVNAME", "")) and p.get("DEVTYPE") == "drm_minor":
            return "egpu", label(p, "ID_MODEL_FROM_DATABASE") or "External graphics card", p.get("DEVPATH", "")
        return None
    if sub == "sound" and re.fullmatch(r"/dev/snd/midiC\d+D\d+", p.get("DEVNAME", "")):
        return "midi", label(p, "ID_MODEL_FROM_DATABASE", "ID_MODEL") or "MIDI device", p.get("ID_SERIAL") or p.get("DEVPATH", "")
    if sub == "video4linux" and "capture" in p.get("ID_V4L_CAPABILITIES", ""):
        name = label(p, "ID_V4L_PRODUCT", "ID_MODEL_FROM_DATABASE", "ID_MODEL")
        if CAPTURE_NAME.search(name):
            return "capture", name, p.get("ID_SERIAL") or p.get("DEVPATH", "")
        return None
    if sub == "tty" and re.fullmatch(r"/dev/tty(ACM|USB)\d+", p.get("DEVNAME", "")):
        name = " ".join(x for x in (label(p, "ID_VENDOR_FROM_DATABASE", "ID_VENDOR"),
                                    label(p, "ID_MODEL_FROM_DATABASE", "ID_MODEL")) if x)
        return "serial", (name or "Serial device") + " - " + p["DEVNAME"], p.get("ID_SERIAL") or p.get("DEVPATH", "")
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
        keys = keys_of(p.get("KEY", "")) if p.get("KEY") else set()
        if p.get("ID_INPUT_KEYBOARD") == "1" and (CLICKER_NAME.search(name) or (keys and keys <= CLICKER_KEYS)):
            return "clicker", name, key
        # not greeted, but followed: what there is to type and touch with changed
        # (the screen keyboard opens by itself without a keyboard - Services/InputKinds)
        if any(p.get(k) == "1" for k in ("ID_INPUT_KEYBOARD", "ID_INPUT_TOUCHSCREEN", "ID_INPUT_SWITCH")):
            return "input", name, key
        return None
    if sub == "hidraw" and p.get("ID_FIDO_TOKEN") == "1":
        key = p.get("ID_SERIAL") or p.get("DEVPATH", "").rsplit("/hidraw", 1)[0]
        return "security-key", label(p, "ID_MODEL_FROM_DATABASE", "ID_MODEL") or "Security key", key
    if sub == "usb" and p.get("DEVTYPE") == "usb_device":
        name = " ".join(x for x in (label(p, "ID_VENDOR_FROM_DATABASE", "ID_VENDOR"),
                                    label(p, "ID_MODEL_FROM_DATABASE", "ID_MODEL")) if x)
        key = p.get("ID_SERIAL") or p.get("DEVPATH", "")
        if p.get("BRLTTY_BRAILLE_DRIVER"):                       # brltty's own udev rules
            return "braille", name or "Braille display", key
        if p.get("ID_VENDOR_ID", "").lower() == "05ac" and re.search(r"iphone|ipad|ipod", name, re.I):
            return "iphone", label(p, "ID_MODEL") or "iPhone", key
        if p.get("ID_MTP_DEVICE") == "1":                       # libmtp's rules: a phone (or player) as storage
            return "phone", name or "Phone", key
        if p.get("ID_GPHOTO2") == "1":                          # libgphoto2's: a camera (PTP)
            return "camera", name or "Camera", key
        if ":0b0000:" in p.get("ID_USB_INTERFACES", ""):         # USB class 0x0b: a smart card reader (CCID)
            return "cardreader", name or "Card reader", key
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
            if (kind, key) in greeted and kind != "input":     # input is followed, not greeted: every time
                continue
            greeted.add((kind, key))
            print(json.dumps({"event": "add", "kind": kind, "name": name, "key": key}), file=out, flush=True)
        elif action == "remove" and present.pop((kind, key), None):
            print(json.dumps({"event": "remove", "kind": kind, "key": key}), file=out, flush=True)


def die_with_parent():
    import ctypes
    import signal
    ctypes.CDLL(None).prctl(1, signal.SIGTERM)          # PR_SET_PDEATHSIG


def main() -> int:
    cmd = shlex.split(os.environ["SHANI_UDEVADM"]) if os.environ.get("SHANI_UDEVADM") else MONITOR
    try:
        # the monitor goes with this bridge, however it ends: a shell restarted (or
        # killed) once left its udevadm running, an orphan holding a netlink socket -
        # and in the tests a second reader on the events FIFO, eating events
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, errors="replace", preexec_fn=die_with_parent)
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
