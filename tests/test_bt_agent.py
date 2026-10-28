"""bridge/bt-agent.py against a fake BlueZ on a private bus.

The agent registers itself as the default, then each question BlueZ asks
(confirm a passkey, authorize, a PIN) reaches the shell as a JSON line and the
D-Bus call waits for the shell's answer: a yes completes it, a no is
org.bluez.Error.Rejected. A service on a paired device is not asked about.
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

AGENT = Path(__file__).resolve().parents[1] / "bridge" / "bt-agent.py"
BLUEZ_XML = """
<node>
  <interface name="org.bluez.AgentManager1">
    <method name="RegisterAgent"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestDefaultAgent"><arg type="o" direction="in"/></method>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
  </interface>
</node>
"""
PHONE = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
HEADSET = "/org/bluez/hci0/dev_11_22_33_44_55_66"


class FakeBluez:
    def __init__(self, address: str) -> None:
        self.calls: list[tuple] = []
        self.conn = Gio.DBusConnection.new_for_address_sync(
            address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        node = Gio.DBusNodeInfo.new_for_xml(BLUEZ_XML)
        self.conn.register_object("/org/bluez", node.interfaces[0], self._call, None, None)
        for path in (PHONE, HEADSET):
            self.conn.register_object(path, node.interfaces[1], self._call, None, None)
        self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                            "RequestName", GLib.Variant("(su)", ("org.bluez", 4)),
                            None, Gio.DBusCallFlags.NONE, 2000, None)

    def _call(self, _c, sender, path, _iface, method, params, inv):
        if method == "Get":
            prop = params.unpack()[1]
            value = {(PHONE, "Alias"): GLib.Variant("s", "Pixel 8"), (PHONE, "Paired"): GLib.Variant("b", False),
                     (HEADSET, "Alias"): GLib.Variant("s", "Buds"), (HEADSET, "Paired"): GLib.Variant("b", True)}.get((path, prop))
            if value is None:
                inv.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", "no such property")
            else:
                inv.return_value(GLib.Variant("(v)", (value,)))
            return
        self.calls.append((method, params.unpack(), sender))
        inv.return_value(None)

    def ask_agent(self, sender, method, params, result: list):
        """Call the agent the way BlueZ does; the reply (or error) lands in result."""
        def done(conn, res):
            try:
                result.append(("ok", conn.call_finish(res).unpack()))
            except GLib.Error as e:
                result.append(("error", Gio.DBusError.get_remote_error(e)))
        self.conn.call(sender, "/dev/shani/btagent", "org.bluez.Agent1", method, params,
                       None, Gio.DBusCallFlags.NONE, 10000, None, done)


@pytest.fixture
def bus():
    if not shutil.which("dbus-daemon"):
        pytest.skip("no dbus-daemon")
    daemon = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"],
                              stdout=subprocess.PIPE, text=True)
    yield daemon.stdout.readline().strip()
    daemon.kill()
    daemon.wait()


def pump(cond, timeout=5.0):
    ctx = GLib.MainContext.default()
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        while ctx.iteration(False):
            pass
        if cond():
            return True
        time.sleep(0.02)
    return False


def test_agent_asks_the_shell_and_waits_for_its_answer(bus):
    fake = FakeBluez(bus)
    child = subprocess.Popen([sys.executable, str(AGENT)], env=dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=bus),
                             text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines: list[dict] = []
    threading.Thread(target=lambda: [lines.append(json.loads(x)) for x in child.stdout], daemon=True).start()

    def say(msg):
        child.stdin.write(json.dumps(msg) + "\n")
        child.stdin.flush()
    try:
        assert pump(lambda: {"ready": True} in lines), child.stderr.read() if child.poll() is not None else lines
        methods = [c[0] for c in fake.calls]
        assert methods == ["RegisterAgent", "RequestDefaultAgent"]
        assert fake.calls[0][1] == ("/dev/shani/btagent", "KeyboardDisplay")
        agent = fake.calls[0][2]

        # a phone shows 012345: the shell is asked, the call waits, yes completes it
        r1: list = []
        fake.ask_agent(agent, "RequestConfirmation", GLib.Variant("(ou)", (PHONE, 12345)), r1)
        assert pump(lambda: any(m.get("ask") == "confirm" for m in lines))
        ask = next(m for m in lines if m.get("ask") == "confirm")
        assert ask["device"] == "Pixel 8" and ask["passkey"] == "012345"
        pump(lambda: False, 0.3)
        assert r1 == [], "the pairing went through before the shell answered"
        say({"id": ask["id"], "ok": True})
        assert pump(lambda: r1 == [("ok", ())])

        # no: Rejected
        r2: list = []
        fake.ask_agent(agent, "RequestAuthorization", GLib.Variant("(o)", (PHONE,)), r2)
        assert pump(lambda: any(m.get("ask") == "authorize" for m in lines))
        say({"id": next(m for m in lines if m.get("ask") == "authorize")["id"], "ok": False})
        assert pump(lambda: r2 == [("error", "org.bluez.Error.Rejected")])

        # an old keyboard wants a PIN typed: the shell's text is returned
        r3: list = []
        fake.ask_agent(agent, "RequestPinCode", GLib.Variant("(o)", (PHONE,)), r3)
        assert pump(lambda: any(m.get("ask") == "pin" for m in lines))
        say({"id": next(m for m in lines if m.get("ask") == "pin")["id"], "ok": True, "value": "0000"})
        assert pump(lambda: r3 == [("ok", ("0000",))])

        # a profile on paired buds: no question
        n = len(lines)
        r4: list = []
        fake.ask_agent(agent, "AuthorizeService", GLib.Variant("(os)", (HEADSET, "0000110b-0000-1000-8000-00805f9b34fb")), r4)
        assert pump(lambda: r4 == [("ok", ())])
        assert len(lines) == n

        # a keyboard shows the code to type on it
        r5: list = []
        fake.ask_agent(agent, "DisplayPasskey", GLib.Variant("(ouq)", (PHONE, 45123, 2)), r5)
        assert pump(lambda: {"show": "passkey", "device": "Pixel 8", "passkey": "045123", "entered": 2} in lines)

        # BlueZ gives up: whatever was being asked is cancelled
        r6: list = []
        fake.ask_agent(agent, "RequestConfirmation", GLib.Variant("(ou)", (PHONE, 1)), r6)
        assert pump(lambda: sum(m.get("ask") == "confirm" for m in lines) == 2)
        fake.ask_agent(agent, "Cancel", None, [])
        assert pump(lambda: r6 == [("error", "org.bluez.Error.Canceled")] and {"cancel": True} in lines)
    finally:
        child.stdin.close()
        child.wait(5)


def test_without_bluez_it_exits_quietly(tmp_path):
    env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=f"unix:path={tmp_path}/nothing")
    out = subprocess.run([sys.executable, str(AGENT)], env=env, capture_output=True, text=True, timeout=20)
    assert out.returncode == 1 and "bt-agent" in out.stderr
