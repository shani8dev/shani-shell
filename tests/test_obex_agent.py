"""bridge/obex-agent.py against a fake obexd on a private session bus.

A phone's push is asked about (device, file, size); the D-Bus call waits for
the shell's answer; yes returns a path in Downloads that never overwrites, no
is Rejected; a completed transfer is reported. obexd holding another agent
(Chronoa's) makes this one step aside.
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

AGENT = Path(__file__).resolve().parents[1] / "bridge" / "obex-agent.py"
XML = """
<node>
  <interface name="org.bluez.obex.AgentManager1">
    <method name="RegisterAgent"><arg type="o" direction="in"/></method>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="GetAll"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
  </interface>
</node>
"""
SESSION = "/org/bluez/obex/server/session1"


class FakeObex:
    def __init__(self, address: str, taken: bool = False) -> None:
        self.taken = taken
        self.agent = None
        self.conn = Gio.DBusConnection.new_for_address_sync(
            address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        node = Gio.DBusNodeInfo.new_for_xml(XML)
        self.conn.register_object("/org/bluez/obex", node.interfaces[0], self._call, None, None)
        self.transfers = {}
        for i, name in enumerate(["IMG_2041.jpg", "IMG_2041.jpg", "../../etc/evil"]):
            path = f"{SESSION}/transfer{i}"
            self.transfers[path] = name
            self.conn.register_object(path, node.interfaces[1], self._call, None, None)
        self.conn.register_object(SESSION, node.interfaces[1], self._call, None, None)
        self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                            GLib.Variant("(su)", ("org.bluez.obex", 4)), None, Gio.DBusCallFlags.NONE, 2000, None)

    def _call(self, _c, sender, path, _i, method, params, inv):
        if method == "RegisterAgent":
            if self.taken:
                inv.return_dbus_error("org.bluez.obex.Error.AlreadyExists", "Already Exists")
                return
            self.agent = (sender, params.unpack()[0])
            inv.return_value(None)
        elif method == "GetAll":
            if path == SESSION:
                inv.return_value(GLib.Variant("(a{sv})", ({"Destination": GLib.Variant("s", "AA:BB:CC:DD:EE:FF")},)))
            else:
                inv.return_value(GLib.Variant("(a{sv})", ({"Name": GLib.Variant("s", self.transfers[path]),
                                                          "Size": GLib.Variant("t", 2381904),
                                                          "Session": GLib.Variant("o", SESSION)},)))

    def push(self, i, result):
        def done(conn, res):
            try:
                result.append(("ok", conn.call_finish(res).unpack()[0]))
            except GLib.Error as e:
                result.append(("error", Gio.DBusError.get_remote_error(e)))
        self.conn.call(self.agent[0], self.agent[1], "org.bluez.obex.Agent1", "AuthorizePush",
                       GLib.Variant("(o)", (f"{SESSION}/transfer{i}",)), None, Gio.DBusCallFlags.NONE, 10000, None, done)

    def complete(self, i):
        self.conn.emit_signal(None, f"{SESSION}/transfer{i}", "org.freedesktop.DBus.Properties", "PropertiesChanged",
                              GLib.Variant("(sa{sv}as)", ("org.bluez.obex.Transfer1", {"Status": GLib.Variant("s", "complete")}, [])))


@pytest.fixture
def bus():
    if not shutil.which("dbus-daemon"):
        pytest.skip("no dbus-daemon")
    d = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"], stdout=subprocess.PIPE, text=True)
    yield d.stdout.readline().strip()
    d.kill()
    d.wait()


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


def start(bus, tmp_path):
    env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=bus, DBUS_SYSTEM_BUS_ADDRESS=f"unix:path={tmp_path}/none",
               XDG_DOWNLOAD_DIR=str(tmp_path / "Downloads"))
    child = subprocess.Popen([sys.executable, str(AGENT)], env=env, text=True,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines: list = []
    threading.Thread(target=lambda: [lines.append(json.loads(x)) for x in child.stdout], daemon=True).start()
    return child, lines


def test_a_push_is_asked_about_and_saved_without_overwriting(bus, tmp_path):
    fake = FakeObex(bus)
    (tmp_path / "Downloads").mkdir()
    (tmp_path / "Downloads" / "IMG_2041.jpg").write_text("already here")
    child, lines = start(bus, tmp_path)
    say = lambda m: (child.stdin.write(json.dumps(m) + "\n"), child.stdin.flush())
    try:
        assert pump(lambda: {"ready": True} in lines), child.stderr.read() if child.poll() is not None else lines
        r: list = []
        fake.push(0, r)
        assert pump(lambda: any(m.get("ask") == "push" for m in lines))
        ask = next(m for m in lines if m.get("ask") == "push")
        assert ask["device"] == "AA:BB:CC:DD:EE:FF" and ask["file"] == "IMG_2041 (2).jpg" and ask["size"] == 2381904
        pump(lambda: False, 0.3)
        assert r == [], "accepted before the person answered"
        say({"id": ask["id"], "ok": True})
        assert pump(lambda: r == [("ok", str(tmp_path / "Downloads" / "IMG_2041 (2).jpg"))])
        fake.complete(0)
        assert pump(lambda: {"received": str(tmp_path / "Downloads" / "IMG_2041 (2).jpg")} in lines)

        r2: list = []
        fake.push(1, r2)
        assert pump(lambda: sum(m.get("ask") == "push" for m in lines) == 2)
        say({"id": [m for m in lines if m.get("ask") == "push"][-1]["id"], "ok": False})
        assert pump(lambda: r2 == [("error", "org.bluez.obex.Error.Rejected")])

        # a name that tries to climb out of Downloads stays in it
        r3: list = []
        fake.push(2, r3)
        assert pump(lambda: sum(m.get("ask") == "push" for m in lines) == 3)
        say({"id": [m for m in lines if m.get("ask") == "push"][-1]["id"], "ok": True})
        assert pump(lambda: r3 == [("ok", str(tmp_path / "Downloads" / "evil"))])
    finally:
        child.stdin.close()
        child.wait(5)


def test_steps_aside_when_another_agent_holds_obexd(bus, tmp_path):
    FakeObex(bus, taken=True)
    child, lines = start(bus, tmp_path)
    assert pump(lambda: child.poll() is not None, 10)
    assert child.returncode == 1 and any("unavailable" in m for m in lines)
