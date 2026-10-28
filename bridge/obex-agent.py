#!/usr/bin/env python3
"""obex-agent — files sent to this computer over Bluetooth (a phone's
Share > Bluetooth), asked about in the shell.

bluez's obexd receives Object Push and asks its registered agent
(org.bluez.obex.Agent1.AuthorizePush) where each file goes — or whether at
all. This is that agent, on the session bus. JSON lines with the shell:

  out  {"ask": "push", "id": 1, "device": "Pixel 8", "file": "IMG_2041.jpg", "size": 2381904}
  in   {"id": 1, "ok": true}
  out  {"received": "/home/asha/Downloads/IMG_2041.jpg"}   when the transfer completes
  out  {"failed": "IMG_2041.jpg"}

Accepted files land in $XDG_DOWNLOAD_DIR (~/Downloads), never over an existing
file: "name (2).ext". obexd holds one agent; when another program (Chronoa)
already has it, this one says so and exits.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from gi.repository import Gio, GLib

OBEX = "org.bluez.obex"
AGENT_PATH = "/dev/shani/obexagent"
INTROSPECTION = """
<node>
  <interface name="org.bluez.obex.Agent1">
    <method name="Release"/>
    <method name="AuthorizePush"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""


def emit(msg: dict) -> None:
    print(json.dumps(msg), flush=True)


def downloads() -> Path:
    d = os.environ.get("XDG_DOWNLOAD_DIR") or str(Path.home() / "Downloads")
    return Path(d)


def free_name(folder: Path, name: str) -> Path:
    """name, or "name (2).ext", … — never an existing file, never outside folder."""
    name = Path(name).name or "received"
    stem, ext = os.path.splitext(name)
    p, n = folder / name, 2
    while p.exists():
        p, n = folder / f"{stem} ({n}){ext}", n + 1
    return p


class Agent:
    def __init__(self, bus: Gio.DBusConnection) -> None:
        self.bus = bus
        self.pending: dict[int, tuple[Gio.DBusMethodInvocation, str, Path]] = {}
        self.next_id = 1

    def props(self, path: str, iface: str) -> dict:
        try:
            v = self.bus.call_sync(OBEX, path, "org.freedesktop.DBus.Properties", "GetAll",
                                   GLib.Variant("(s)", (iface,)), GLib.VariantType("(a{sv})"),
                                   Gio.DBusCallFlags.NONE, 2000, None)
            return v.unpack()[0]
        except GLib.Error:
            return {}

    def device_name(self, session_path: str) -> str:
        dest = self.props(session_path, "org.bluez.obex.Session1").get("Destination", "")
        if not dest:
            return "A Bluetooth device"
        # the paired device's name from bluez, on the system bus
        try:
            sysbus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            objs = sysbus.call_sync("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
                                    None, GLib.VariantType("(a{oa{sa{sv}}})"), Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
            for ifaces in objs.values():
                d = ifaces.get("org.bluez.Device1")
                if d and d.get("Address", "").upper() == dest.upper():
                    return d.get("Alias") or d.get("Name") or dest
        except GLib.Error:
            pass
        return dest

    def call(self, conn, sender, path, iface, method, params, inv) -> None:
        if method == "AuthorizePush":
            transfer = params.unpack()[0]
            t = self.props(transfer, "org.bluez.obex.Transfer1")
            name = t.get("Name", "received")
            target = free_name(downloads(), name)
            i = self.next_id
            self.next_id += 1
            self.pending[i] = (inv, transfer, target)
            emit({"ask": "push", "id": i, "device": self.device_name(t.get("Session", "")),
                  "file": target.name, "size": int(t.get("Size", 0))})
            # the outcome: Status goes to complete or error
            self.bus.signal_subscribe(OBEX, "org.freedesktop.DBus.Properties", "PropertiesChanged", transfer,
                                      None, Gio.DBusSignalFlags.NONE, self.on_status, target)
        elif method == "Cancel":
            for inv2, _, _ in self.pending.values():
                inv2.return_dbus_error("org.bluez.obex.Error.Canceled", "canceled")
            self.pending.clear()
            emit({"cancel": True})
            inv.return_value(None)
        else:
            inv.return_value(None)

    def on_status(self, conn, sender, path, iface, signal, params, target) -> None:
        changed = params.unpack()[1]
        status = changed.get("Status")
        if status == "complete":
            emit({"received": str(target)})
        elif status == "error":
            emit({"failed": target.name})

    def answer(self, msg: dict) -> None:
        item = self.pending.pop(msg.get("id"), None)
        if not item:
            return
        inv, _, target = item
        if msg.get("ok"):
            target.parent.mkdir(parents=True, exist_ok=True)
            inv.return_value(GLib.Variant("(s)", (str(target),)))
        else:
            inv.return_dbus_error("org.bluez.obex.Error.Rejected", "declined")


def main() -> int:
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error as e:
        print(f"obex-agent: no session bus: {e.message}", file=sys.stderr)
        return 1
    agent = Agent(bus)
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
    bus.register_object(AGENT_PATH, node.interfaces[0], agent.call, None, None)
    try:
        bus.call_sync(OBEX, "/org/bluez/obex", "org.bluez.obex.AgentManager1", "RegisterAgent",
                      GLib.Variant("(o)", (AGENT_PATH,)), None, Gio.DBusCallFlags.NONE, 5000, None)
    except GLib.Error as e:
        # obexd not running (no Bluetooth), or another agent (Chronoa) has it
        print(f"obex-agent: {e.message}", file=sys.stderr)
        emit({"unavailable": e.message})
        return 1
    emit({"ready": True})
    loop = GLib.MainLoop()

    def on_stdin(channel, cond):
        line = channel.readline() if cond & GLib.IO_IN else ""
        if not line:
            loop.quit()
            return False
        try:
            agent.answer(json.loads(line))
        except (ValueError, AttributeError):
            pass
        return True

    GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()), GLib.PRIORITY_DEFAULT,
                      GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
