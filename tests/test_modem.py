"""bridge/modem.py against a fake ModemManager on a private system bus.

The fake serves what libmm-glib and mmcli read: the object tree, a modem with
3GPP, Messaging and Voice, a SIM that wants its PIN, texts and calls that
change state and say so. The bridge must report the modem, unlock the SIM
with the right PIN only, announce a received text once it is whole, send a
text, place a call, and answer and end an incoming one.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

gi = pytest.importorskip("gi")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BRIDGE = Path(__file__).resolve().parents[1] / "bridge" / "modem.py"
MM = "org.freedesktop.ModemManager1"
MODEM = "/org/freedesktop/ModemManager1/Modem/0"
SIM = "/org/freedesktop/ModemManager1/SIM/0"
XML = """
<node>
  <interface name="org.freedesktop.DBus.ObjectManager">
    <method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="GetAll"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
  </interface>
  <interface name="org.freedesktop.ModemManager1.Modem.Messaging">
    <method name="Create"><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
  </interface>
  <interface name="org.freedesktop.ModemManager1.Modem.Voice">
    <method name="CreateCall"><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
    <method name="ListCalls"><arg type="ao" direction="out"/></method>
  </interface>
  <interface name="org.freedesktop.ModemManager1.Sim">
    <method name="SendPin"><arg type="s" direction="in"/></method>
  </interface>
  <interface name="org.freedesktop.ModemManager1.Sms">
    <method name="Send"/>
  </interface>
  <interface name="org.freedesktop.ModemManager1.Call">
    <method name="Start"/><method name="Accept"/><method name="Hangup"/>
  </interface>
</node>
"""


class FakeMM:
    def __init__(self, address: str, with_modem: bool = True) -> None:
        self.conn = Gio.DBusConnection.new_for_address_sync(
            address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        self.node = Gio.DBusNodeInfo.new_for_xml(XML)
        self.iface = {i.name: i for i in self.node.interfaces}
        self.objects: dict[str, dict] = {}     # path → {iface: {prop: Variant}}
        self.sent: list[tuple] = []
        if with_modem:
            self.objects[MODEM] = {
                MM + ".Modem": {"State": GLib.Variant("i", 2), "UnlockRequired": GLib.Variant("u", 2),
                                "Sim": GLib.Variant("o", SIM), "SignalQuality": GLib.Variant("(ub)", (63, True)),
                                "OwnNumbers": GLib.Variant("as", ["+919800000000"])},
                MM + ".Modem.Modem3gpp": {"OperatorName": GLib.Variant("s", "Jio")},
                MM + ".Modem.Messaging": {}, MM + ".Modem.Voice": {}}
            self.objects[SIM] = {MM + ".Sim": {}}
            for name in ("org.freedesktop.DBus.Properties", MM + ".Modem.Messaging", MM + ".Modem.Voice"):
                self.conn.register_object(MODEM, self.iface[name], self._call, None, None)
            self.conn.register_object(SIM, self.iface[MM + ".Sim"], self._call, None, None)
        self.conn.register_object("/org/freedesktop/ModemManager1", self.iface["org.freedesktop.DBus.ObjectManager"], self._call, None, None)
        self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                            GLib.Variant("(su)", (MM, 4)), None, Gio.DBusCallFlags.NONE, 2000, None)
        self.n = 0

    def add(self, kind: str, props: dict) -> str:
        path = f"/org/freedesktop/ModemManager1/{kind}/{self.n}"
        self.n += 1
        self.objects[path] = {MM + "." + kind: props}
        self.conn.register_object(path, self.iface["org.freedesktop.DBus.Properties"], self._call, None, None)
        self.conn.register_object(path, self.iface[MM + "." + kind], self._call, None, None)
        return path

    def change(self, path: str, iface: str, **props) -> None:
        self.objects[path][iface].update(props)
        self.conn.emit_signal(None, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                              GLib.Variant("(sa{sv}as)", (iface, props, [])))

    def _call(self, _c, _s, path, iface, method, params, inv):
        if method == "GetManagedObjects":
            objs = {p: i for p, i in self.objects.items() if p in (MODEM, SIM)}
            inv.return_value(GLib.Variant("(a{oa{sa{sv}}})", (objs,)))
        elif method == "GetAll":
            inv.return_value(GLib.Variant("(a{sv})", (self.objects.get(path, {}).get(params.unpack()[0], {}),)))
        elif method == "SendPin":
            if params.unpack()[0] != "1234":
                inv.return_dbus_error(MM + ".Error.MobileEquipment.IncorrectPassword", "Incorrect password")
                return
            inv.return_value(None)
            self.change(MODEM, MM + ".Modem", UnlockRequired=GLib.Variant("u", 1), State=GLib.Variant("i", 8))
        elif method == "Create":
            d = params.unpack()[0]
            p = self.add("Sms", {"Number": GLib.Variant("s", d["number"]), "Text": GLib.Variant("s", d["text"]),
                                 "State": GLib.Variant("u", 1), "PduType": GLib.Variant("u", 2)})
            inv.return_value(GLib.Variant("(o)", (p,)))
        elif method == "Send":
            o = self.objects[path][MM + ".Sms"]
            self.sent.append((o["Number"].unpack(), o["Text"].unpack()))
            inv.return_value(None)
        elif method == "CreateCall":
            p = self.add("Call", {"Number": GLib.Variant("s", params.unpack()[0]["number"]),
                                  "State": GLib.Variant("i", 0), "Direction": GLib.Variant("i", 2)})
            inv.return_value(GLib.Variant("(o)", (p,)))
        elif method == "ListCalls":
            inv.return_value(GLib.Variant("(ao)", ([p for p in self.objects if "/Call/" in p],)))
        elif method in ("Start", "Accept", "Hangup"):
            inv.return_value(None)
            self.change(path, MM + ".Call", State=GLib.Variant("i", {"Start": 1, "Accept": 4, "Hangup": 7}[method]))

    def receive_sms(self, number: str, text: str) -> None:
        p = self.add("Sms", {"Number": GLib.Variant("s", number), "Text": GLib.Variant("s", text), "State": GLib.Variant("u", 3),
                             "PduType": GLib.Variant("u", 1), "Timestamp": GLib.Variant("s", "2026-10-29T10:00:00+05:30")})
        self.conn.emit_signal(None, MODEM, MM + ".Modem.Messaging", "Added", GLib.Variant("(ob)", (p, True)))

    def ring(self, number: str) -> str:
        p = self.add("Call", {"Number": GLib.Variant("s", number), "State": GLib.Variant("i", 3), "Direction": GLib.Variant("i", 1)})
        self.conn.emit_signal(None, MODEM, MM + ".Modem.Voice", "CallAdded", GLib.Variant("(o)", (p,)))
        return p


@pytest.fixture
def bus():
    if not shutil.which("dbus-daemon"):
        pytest.skip("no dbus-daemon")
    d = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"], stdout=subprocess.PIPE, text=True)
    yield d.stdout.readline().strip()
    d.kill()
    d.wait()


def pump(cond, timeout=6.0):
    ctx = GLib.MainContext.default()
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        while ctx.iteration(False):
            pass
        if cond():
            return True
        time.sleep(0.02)
    return False


def start(bus):
    child = subprocess.Popen([sys.executable, str(BRIDGE)], env=dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=bus), text=True,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines: list = []
    threading.Thread(target=lambda: [lines.append(json.loads(x)) for x in child.stdout], daemon=True).start()
    say = lambda m: (child.stdin.write(json.dumps(m) + "\n"), child.stdin.flush())
    return child, lines, say


def test_pin_texts_and_calls(bus):
    fake = FakeMM(bus)
    child, lines, say = start(bus)
    try:
        modems = lambda: [m["modem"] for m in lines if m.get("modem")]
        assert pump(lambda: modems()), child.stderr.read() if child.poll() is not None else lines
        m = modems()[0]
        assert m["locked"] == "sim-pin" and m["voice"] and m["messaging"] and m["operator"] == "Jio" and m["signal"] == 63

        # the wrong PIN is refused and said; the right one unlocks
        say({"pin": "0000"})
        assert pump(lambda: any("error" in x for x in lines))
        say({"pin": "1234"})
        assert pump(lambda: modems()[-1]["locked"] == "" and modems()[-1]["state"] == "registered")

        # a text arrives
        fake.receive_sms("+919811111111", "Reached the station")
        assert pump(lambda: any(x.get("sms", {}).get("text") == "Reached the station" for x in lines))
        assert [x["sms"]["from"] for x in lines if "sms" in x] == ["+919811111111"]

        # a text goes out
        say({"sms": {"to": "+919822222222", "text": "On my way"}})
        assert pump(lambda: fake.sent == [("+919822222222", "On my way")] and {"sent": {"to": "+919822222222"}} in lines)

        # a call out: created and started
        say({"call": "+919833333333"})
        assert pump(lambda: any(x.get("call", {}).get("state") == "dialing" and x["call"]["number"] == "+919833333333" for x in lines))

        # a call in: ringing, answered, ended
        path = fake.ring("+919844444444")
        assert pump(lambda: {"call": {"path": path, "number": "+919844444444", "state": "ringing-in", "incoming": True}} in lines)
        say({"answer": path})
        assert pump(lambda: {"call": {"path": path, "number": "+919844444444", "state": "active", "incoming": True}} in lines)
        say({"hangup": path})
        assert pump(lambda: {"call": {"path": path, "number": "+919844444444", "state": "terminated", "incoming": True}} in lines)
    finally:
        child.stdin.close()
        child.wait(5)


def test_no_modem(bus):
    FakeMM(bus, with_modem=False)
    child, lines, _ = start(bus)
    try:
        assert pump(lambda: {"modem": None} in lines)
    finally:
        child.stdin.close()
        child.wait(5)
