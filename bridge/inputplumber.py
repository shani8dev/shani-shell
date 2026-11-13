#!/usr/bin/env python3
"""inputplumber - the shell's side of InputPlumber (org.shadowblip.InputPlumber,
system bus; shani-peripherals ships and enables it).

    inputplumber.py watch     runs while the shell wants it; one JSON line per change:
        {"type": "state", "running": bool, "manageAll": bool, "supported": [...],
         "devices": [{"path", "name", "profile", "targets": [...], "intercept": n}]}
        {"type": "input", "event": "ui_accept", "value": 1.0, "device": PATH}
      and reads one JSON command per line on stdin:
        {"op": "intercept", "path": PATH | "*", "mode": 0|1|2|3}
        {"op": "targets", "path": PATH, "targets": ["xbox-elite", "keyboard", "mouse"]}
        {"op": "manageAll", "on": true}

InputPlumber merges a controller's pad, gyro and extra buttons into one virtual
device (a CompositeDevice) of the kind a game expects - its "TargetDevices". Its
"intercept" modes are how a desktop overlay borrows the controller without the game
seeing it: 0 none, 1 pass (everything goes to the game but the guide button, which
comes here and switches the device to 2), 2 always (everything comes here, as
DBusDevice InputEvent "ui_up" ... "ui_accept"), 3 gamepad only. The shell keeps
devices in 1 while controller navigation is on, and hands a device back with 1
when its own surfaces close.
"""
from __future__ import annotations

import json
import sys

from gi.repository import Gio, GLib

BUS = "org.shadowblip.InputPlumber"
PREFIX = "/org/shadowblip/InputPlumber"
MANAGER = PREFIX + "/Manager"
I_MANAGER = "org.shadowblip.InputManager"
I_COMPOSITE = "org.shadowblip.Input.CompositeDevice"
I_DBUSDEV = "org.shadowblip.Input.DBusDevice"
PROPS = "org.freedesktop.DBus.Properties"

bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def call(path: str, iface: str, method: str, args=None, reply=None, timeout=3000):
    return bus.call_sync(BUS, path, iface, method, args, reply, Gio.DBusCallFlags.NONE, timeout, None)


def get_all(path: str, iface: str) -> dict:
    try:
        return call(path, PROPS, "GetAll", GLib.Variant("(s)", (iface,)), GLib.VariantType("(a{sv})")).unpack()[0]
    except GLib.Error:
        return {}


def set_prop(path: str, iface: str, name: str, value: GLib.Variant) -> str:
    try:
        call(path, PROPS, "Set", GLib.Variant("(ssv)", (iface, name, value)))
        return ""
    except GLib.Error as exc:
        return exc.message


def composite_paths() -> list:
    """Every CompositeDevice, from the bus's own object tree."""
    try:
        xml = call(PREFIX, "org.freedesktop.DBus.Introspectable", "Introspect", None,
                   GLib.VariantType("(s)")).unpack()[0]
    except GLib.Error:
        return []
    info = Gio.DBusNodeInfo.new_for_xml(xml)
    return sorted(PREFIX + "/" + n.path for n in info.nodes if n.path.startswith("CompositeDevice"))


def running() -> bool:
    try:
        owner = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                              "NameHasOwner", GLib.Variant("(s)", (BUS,)), GLib.VariantType("(b)"),
                              Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
        return bool(owner)
    except GLib.Error:
        return False


def state() -> dict:
    if not running():
        return {"type": "state", "running": False, "manageAll": False, "supported": [], "supportedIds": [], "devices": []}
    m = get_all(MANAGER, I_MANAGER)
    devices = []
    for p in composite_paths():
        d = get_all(p, I_COMPOSITE)
        devices.append({"path": p, "name": d.get("Name", ""), "profile": d.get("ProfileName", ""),
                        "targets": list(d.get("TargetDevices", [])), "intercept": int(d.get("InterceptMode", 0)),
                        "dbus": list(d.get("DbusDevices", []))})
    return {"type": "state", "running": True, "manageAll": bool(m.get("ManageAllDevices", False)),
            "supported": list(m.get("SupportedTargetDevices", [])),
            "supportedIds": list(m.get("SupportedTargetDeviceIds", [])), "devices": devices}


last = {"json": ""}


def report(*_args) -> bool:
    s = state()
    j = json.dumps(s, sort_keys=True)
    if j != last["json"]:
        last["json"] = j
        emit(s)
    return False


def soon(*_args) -> None:
    GLib.timeout_add(120, report)        # a burst of property changes reads once


def on_input(_conn, _sender, path, _iface, _signal, params) -> None:
    event, value = params.unpack()
    # the input comes from a DBus target device; its controller is the one listing it
    owner = ""
    for d in json.loads(last["json"] or "{}").get("devices", []):
        if path in d.get("dbus", []):
            owner = d["path"]
            break
    emit({"type": "input", "event": event, "value": value, "device": owner, "from": path})


def command(line: str) -> None:
    try:
        c = json.loads(line)
    except ValueError:
        return
    op = c.get("op")
    err = ""
    if op == "intercept":
        paths = composite_paths() if c.get("path") in ("*", None) else [c["path"]]
        for p in paths:
            err = set_prop(p, I_COMPOSITE, "InterceptMode", GLib.Variant("u", int(c.get("mode", 0)))) or err
    elif op == "targets":
        err = set_prop(c["path"], I_COMPOSITE, "TargetDevices", GLib.Variant("as", [str(t) for t in c.get("targets", [])]))
    elif op == "manageAll":
        err = set_prop(MANAGER, I_MANAGER, "ManageAllDevices", GLib.Variant("b", bool(c.get("on"))))
    if err:
        emit({"type": "error", "op": op, "error": err})
    soon()


def on_stdin(channel, _cond) -> bool:
    line = channel.readline()
    if not line:
        loop.quit()
        return False
    command(line.strip())
    return True


def main(argv: list) -> int:
    if len(argv) < 2 or argv[1] != "watch":
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    # the service coming, going, its devices appearing and changing
    bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", None, BUS,
                         Gio.DBusSignalFlags.NONE, soon)
    bus.signal_subscribe(BUS, PROPS, "PropertiesChanged", None, None, Gio.DBusSignalFlags.NONE, soon)
    bus.signal_subscribe(BUS, "org.freedesktop.DBus.ObjectManager", None, None, None, Gio.DBusSignalFlags.NONE, soon)
    bus.signal_subscribe(BUS, I_DBUSDEV, "InputEvent", None, None, Gio.DBusSignalFlags.NONE, on_input)
    report()
    GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()), GLib.IO_IN | GLib.IO_HUP, on_stdin)
    global loop
    loop = GLib.MainLoop()
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
