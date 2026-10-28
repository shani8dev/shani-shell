#!/usr/bin/env python3
"""bt-agent — the shell's BlueZ pairing agent.

Quickshell's Bluetooth module pairs and connects, but registers no agent, so a
device that shows a code (a phone, a keyboard) cannot pair. This is that agent,
registered as the default with KeyboardDisplay capability. It talks to the
shell in JSON lines:

  out  {"ask": "confirm", "id": 1, "device": "Pixel 8", "passkey": "123456"}
  out  {"ask": "authorize", "id": 2, "device": "Pixel 8"}
  out  {"ask": "pin", "id": 3, "device": "Old Keyboard"}       (answer: the PIN)
  out  {"ask": "passkey", "id": 4, "device": "..."}            (answer: digits)
  out  {"show": "passkey", "device": "K380", "passkey": "045123", "entered": 2}
  out  {"show": "pin", "device": "...", "pin": "0000"}
  out  {"cancel": true}
  in   {"id": 1, "ok": true}            or  {"id": 3, "ok": true, "value": "0000"}

A service on an already paired device is authorized without asking.
"""

from __future__ import annotations

import json
import sys

from gi.repository import Gio, GLib

AGENT_PATH = "/dev/shani/btagent"
REJECTED = "org.bluez.Error.Rejected"
CANCELED = "org.bluez.Error.Canceled"

INTROSPECTION = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""


def emit(msg: dict) -> None:
    print(json.dumps(msg), flush=True)


class Agent:
    def __init__(self, bus: Gio.DBusConnection) -> None:
        self.bus = bus
        self.pending: dict[int, tuple[str, Gio.DBusMethodInvocation]] = {}
        self.next_id = 1

    def device(self, path: str, prop: str):
        try:
            v = self.bus.call_sync("org.bluez", path, "org.freedesktop.DBus.Properties", "Get",
                                   GLib.Variant("(ss)", ("org.bluez.Device1", prop)),
                                   GLib.VariantType("(v)"), Gio.DBusCallFlags.NONE, 2000, None)
            return v.unpack()[0]
        except GLib.Error:
            return None

    def name(self, path: str) -> str:
        return self.device(path, "Alias") or self.device(path, "Name") or path.rsplit("/", 1)[-1].replace("dev_", "").replace("_", ":")

    def ask(self, kind: str, path: str, inv: Gio.DBusMethodInvocation, **extra) -> None:
        i = self.next_id
        self.next_id += 1
        self.pending[i] = (kind, inv)
        emit({"ask": kind, "id": i, "device": self.name(path), **extra})

    def answer(self, msg: dict) -> None:
        item = self.pending.pop(msg.get("id"), None)
        if not item:
            return
        kind, inv = item
        if not msg.get("ok"):
            inv.return_dbus_error(REJECTED, "refused on the device's owner's screen")
            return
        value = str(msg.get("value", ""))
        if kind == "pin":
            inv.return_value(GLib.Variant("(s)", (value,)))
        elif kind == "passkey":
            if not value.isdigit():
                inv.return_dbus_error(REJECTED, "not a number")
                return
            inv.return_value(GLib.Variant("(u)", (int(value),)))
        else:
            inv.return_value(None)

    def call(self, conn, sender, path, iface, method, params, inv) -> None:
        args = params.unpack()
        if method == "RequestConfirmation":
            self.ask("confirm", args[0], inv, passkey=f"{args[1]:06d}")
        elif method == "RequestAuthorization":
            self.ask("authorize", args[0], inv)
        elif method == "RequestPinCode":
            self.ask("pin", args[0], inv)
        elif method == "RequestPasskey":
            self.ask("passkey", args[0], inv)
        elif method == "DisplayPasskey":
            emit({"show": "passkey", "device": self.name(args[0]), "passkey": f"{args[1]:06d}", "entered": args[2]})
            inv.return_value(None)
        elif method == "DisplayPinCode":
            emit({"show": "pin", "device": self.name(args[0]), "pin": args[1]})
            inv.return_value(None)
        elif method == "AuthorizeService":
            # a profile on a device already paired (and so already agreed to)
            if self.device(args[0], "Paired"):
                inv.return_value(None)
            else:
                self.ask("authorize", args[0], inv, service=args[1])
        elif method == "Cancel":
            for _, (_, pending) in list(self.pending.items()):
                pending.return_dbus_error(CANCELED, "canceled")
            self.pending.clear()
            emit({"cancel": True})
            inv.return_value(None)
        else:  # Release
            inv.return_value(None)


def main() -> int:
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    except GLib.Error as e:
        print(f"bt-agent: no bus: {e.message}", file=sys.stderr)
        return 1
    agent = Agent(bus)
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
    bus.register_object(AGENT_PATH, node.interfaces[0], agent.call, None, None)
    for method, params in (("RegisterAgent", GLib.Variant("(os)", (AGENT_PATH, "KeyboardDisplay"))),
                           ("RequestDefaultAgent", GLib.Variant("(o)", (AGENT_PATH,)))):
        try:
            bus.call_sync("org.bluez", "/org/bluez", "org.bluez.AgentManager1", method, params,
                          None, Gio.DBusCallFlags.NONE, 5000, None)
        except GLib.Error as e:
            print(f"bt-agent: {method}: {e.message}", file=sys.stderr)
            return 1
    emit({"ready": True})

    loop = GLib.MainLoop()

    def on_stdin(channel, cond):
        if cond & (GLib.IO_HUP | GLib.IO_ERR):
            loop.quit()
            return False
        line = channel.readline()
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
