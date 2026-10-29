#!/usr/bin/env python3
"""modem — the SIM modem, through ModemManager's D-Bus API, for the shell.

ModemManager (in the image with libqmi/libmbim) speaks to the modem; this
speaks to ModemManager and to the shell, in JSON lines:

  out {"modem": {"path", "state", "locked", "operator", "signal", "number",
                 "voice": bool, "messaging": bool}}         on start and change
  out {"modem": null}                                         no modem
  out {"sms": {"path", "from", "text", "time"}}               a text arrived
  out {"call": {"path", "number", "state", "incoming": bool}} a call, on change
  out {"sent": {"to"}} / {"error": "…"}
  in  {"pin": "1234"}                                         unlock the SIM
  in  {"sms": {"to": "+91…", "text": "…"}}                   send a text
  in  {"call": "+91…"}  {"answer": path}  {"hangup": path}    voice

A modem that has no Voice interface simply never reports "voice": true, and
the shell routes calls elsewhere (Chronoa, a phone over Bluetooth). Call
*audio* is the hardware's: ModemManager starts and ends the call, it does not
carry the sound.
"""

from __future__ import annotations

import json
import sys

from gi.repository import Gio, GLib

MM = "org.freedesktop.ModemManager1"
ROOT = "/org/freedesktop/ModemManager1"
I_MODEM = MM + ".Modem"
I_3GPP = MM + ".Modem.Modem3gpp"
I_MSG = MM + ".Modem.Messaging"
I_VOICE = MM + ".Modem.Voice"
I_SIM = MM + ".Sim"
I_SMS = MM + ".Sms"
I_CALL = MM + ".Call"

# MMModemState, MMModemLock, MMCallState, MMSmsState, MMSmsPduType
STATES = {-1: "failed", 0: "unknown", 1: "initializing", 2: "locked", 3: "disabled", 4: "disabling", 5: "enabling",
          6: "enabled", 7: "searching", 8: "registered", 9: "disconnecting", 10: "connecting", 11: "connected"}
LOCKS = {0: "", 1: "", 2: "sim-pin", 3: "sim-pin2", 4: "sim-puk", 5: "sim-puk2"}
CALL_STATES = {0: "unknown", 1: "dialing", 2: "ringing-out", 3: "ringing-in", 4: "active", 5: "held", 6: "waiting", 7: "terminated"}
SMS_RECEIVED, PDU_DELIVER = 3, 1


def emit(msg: dict) -> None:
    print(json.dumps(msg), flush=True)


class Modem:
    def __init__(self, bus: Gio.DBusConnection) -> None:
        self.bus = bus
        self.path = ""
        self.sim = ""
        self.ifaces: dict[str, dict] = {}
        self.calls: dict[str, dict] = {}
        self.told_sms: set[str] = set()

    # ---- reading ----------------------------------------------------------------
    def call(self, path, iface, method, args=None, sig=None):
        return self.bus.call_sync(MM, path, iface, method, args, GLib.VariantType(sig) if sig else None,
                                  Gio.DBusCallFlags.NONE, 20000, None)

    def props(self, path: str, iface: str) -> dict:
        try:
            return self.call(path, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", (iface,)), "(a{sv})").unpack()[0]
        except GLib.Error:
            return {}

    def scan(self) -> None:
        try:
            objs = self.call(ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None, "(a{oa{sa{sv}}})").unpack()[0]
        except GLib.Error:
            objs = {}
        modems = sorted(p for p, i in objs.items() if I_MODEM in i)
        if not modems:
            self.path = ""
            emit({"modem": None})
            return
        self.path = modems[0]
        self.ifaces = objs[self.path]
        self.sim = self.ifaces[I_MODEM].get("Sim", "") or ""
        self.report()
        for path in self.list_calls():
            self.on_call(path)

    def report(self) -> None:
        m = self.ifaces.get(I_MODEM, {})
        q = m.get("SignalQuality") or (0, False)
        numbers = m.get("OwnNumbers") or []
        emit({"modem": {
            "path": self.path,
            "state": STATES.get(m.get("State", 0), "unknown"),
            "locked": LOCKS.get(m.get("UnlockRequired", 0), "locked"),
            "operator": self.ifaces.get(I_3GPP, {}).get("OperatorName", ""),
            "signal": int(q[0]) if isinstance(q, tuple) else 0,
            "number": numbers[0] if numbers else "",
            "voice": I_VOICE in self.ifaces,
            "messaging": I_MSG in self.ifaces,
        }})

    def list_calls(self) -> list[str]:
        if I_VOICE not in self.ifaces:
            return []
        try:
            return list(self.call(self.path, I_VOICE, "ListCalls", None, "(ao)").unpack()[0])
        except GLib.Error:
            return []

    # ---- what ModemManager announces -------------------------------------------------
    def on_signal(self, conn, sender, path, iface, signal, params, _data) -> None:
        if iface == "org.freedesktop.DBus.ObjectManager":
            self.scan()
        elif iface == "org.freedesktop.DBus.Properties" and path == self.path:
            changed_iface, changed = params.unpack()[0], params.unpack()[1]
            self.ifaces.setdefault(changed_iface, {}).update(changed)
            self.report()
        elif iface == "org.freedesktop.DBus.Properties" and path in self.calls:
            self.on_call(path)
        elif iface == "org.freedesktop.DBus.Properties" and params.unpack()[0] == I_SMS:
            self.on_sms(path)
        elif iface == I_MSG and signal == "Added":
            sms_path, received = params.unpack()
            if received:
                self.on_sms(sms_path)
        elif iface == I_VOICE and signal == "CallAdded":
            self.on_call(params.unpack()[0])

    def on_sms(self, path: str) -> None:
        if path in self.told_sms:
            return
        p = self.props(path, I_SMS)
        # a long text arrives in parts: tell it once it is all there
        if p.get("PduType") != PDU_DELIVER or p.get("State") != SMS_RECEIVED:
            return
        self.told_sms.add(path)
        emit({"sms": {"path": path, "from": p.get("Number", ""), "text": p.get("Text", ""), "time": p.get("Timestamp", "")}})

    def on_call(self, path: str) -> None:
        p = self.props(path, I_CALL)
        if not p:
            self.calls.pop(path, None)
            return
        c = {"path": path, "number": p.get("Number", ""), "state": CALL_STATES.get(p.get("State", 0), "unknown"),
             "incoming": p.get("Direction", 0) == 1}
        if self.calls.get(path) != c:
            self.calls[path] = c
            emit({"call": c})
        if c["state"] == "terminated":
            self.calls.pop(path, None)

    # ---- what the shell asks ----------------------------------------------------------
    def handle(self, msg: dict) -> None:
        try:
            if "pin" in msg:
                self.call(self.sim, I_SIM, "SendPin", GLib.Variant("(s)", (str(msg["pin"]),)))
                self.scan()
            elif "sms" in msg:
                s = msg["sms"]
                path = self.call(self.path, I_MSG, "Create", GLib.Variant(
                    "(a{sv})", ({"number": GLib.Variant("s", s["to"]), "text": GLib.Variant("s", s["text"])},)), "(o)").unpack()[0]
                self.call(path, I_SMS, "Send")
                emit({"sent": {"to": s["to"]}})
            elif "call" in msg:
                path = self.call(self.path, I_VOICE, "CreateCall", GLib.Variant(
                    "(a{sv})", ({"number": GLib.Variant("s", msg["call"])},)), "(o)").unpack()[0]
                self.call(path, I_CALL, "Start")
                self.on_call(path)
            elif "answer" in msg:
                self.call(msg["answer"], I_CALL, "Accept")
                self.on_call(msg["answer"])
            elif "hangup" in msg:
                self.call(msg["hangup"], I_CALL, "Hangup")
                self.on_call(msg["hangup"])
        except GLib.Error as e:
            emit({"error": e.message.split(": ")[-1]})
        except (KeyError, TypeError):
            emit({"error": "a request it did not understand"})


def main() -> int:
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    except GLib.Error as e:
        print(f"modem: no system bus: {e.message}", file=sys.stderr)
        return 1
    modem = Modem(bus)
    bus.signal_subscribe(MM, None, None, None, None, Gio.DBusSignalFlags.NONE, modem.on_signal, None)
    modem.scan()
    loop = GLib.MainLoop()

    def on_stdin(channel, cond):
        line = channel.readline() if cond & GLib.IO_IN else ""
        if not line:
            loop.quit()
            return False
        try:
            modem.handle(json.loads(line))
        except ValueError:
            pass
        return True

    GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()), GLib.PRIORITY_DEFAULT,
                      GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
