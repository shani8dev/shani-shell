"""bridge/logind.py against a fake logind on a private bus.

What matters is the order around sleep: the bridge holds a "delay" sleep
inhibitor while awake, tells the shell to lock on PrepareForSleep(true), and
releases the inhibitor only when the shell reports the lock is up — so the
machine never suspends with the session showing. Also: Lock/Unlock from
`loginctl lock-session` reach the shell, and LockedHint follows the shell.

The fake runs in this process on a private dbus-daemon; the bridge side runs
in a subprocess pointed at it as its *system* bus, so nothing here touches the
real system bus or caches a connection to the private one.
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

BRIDGE = Path(__file__).resolve().parents[1] / "bridge"

LOGIND_XML = """
<node>
  <interface name="org.freedesktop.login1.Manager">
    <method name="GetSession"><arg type="s" direction="in"/><arg type="o" direction="out"/></method>
    <method name="Inhibit">
      <arg type="s" direction="in"/><arg type="s" direction="in"/>
      <arg type="s" direction="in"/><arg type="s" direction="in"/>
      <arg type="h" direction="out"/>
    </method>
    <signal name="PrepareForSleep"><arg type="b"/></signal>
  </interface>
  <interface name="org.freedesktop.login1.Session">
    <method name="SetLockedHint"><arg type="b" direction="in"/></method>
    <signal name="Lock"/><signal name="Unlock"/>
  </interface>
</node>
"""
SESSION = "/org/freedesktop/login1/session/_31"

# The bridge side: Logind with emit() printing JSON lines; commands on stdin.
CHILD = r"""
import json, sys, threading
sys.path.insert(0, sys.argv[1])
from gi.repository import GLib
from logind import Logind
loop = GLib.MainLoop()
l = Logind(lambda o: print(json.dumps(o), flush=True))
print(json.dumps({"started": l.start()}), flush=True)
def commands():
    for line in sys.stdin:
        cmd = line.strip()
        if cmd == "locked":
            GLib.idle_add(lambda: l.locked(True) and False)
        elif cmd == "release":
            GLib.idle_add(lambda: l.release_sleep() and False)
        elif cmd == "fd":
            GLib.idle_add(lambda: print(json.dumps({"fd": l.inhibit_fd}), flush=True) and False)
        elif cmd == "quit":
            GLib.idle_add(loop.quit)
threading.Thread(target=commands, daemon=True).start()
loop.run()
"""


class FakeLogind:
    def __init__(self, address: str) -> None:
        self.hints: list[bool] = []
        self.inhibitors: list[tuple] = []
        self.read_ends: list[int] = []
        self.conn = Gio.DBusConnection.new_for_address_sync(
            address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        node = Gio.DBusNodeInfo.new_for_xml(LOGIND_XML)
        self.conn.register_object("/org/freedesktop/login1", node.interfaces[0], self._call, None, None)
        self.conn.register_object(SESSION, node.interfaces[1], self._call, None, None)
        self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                            "RequestName", GLib.Variant("(su)", ("org.freedesktop.login1", 4)),
                            None, Gio.DBusCallFlags.NONE, 2000, None)

    def _call(self, _c, _sender, _path, _iface, method, params, inv):
        if method == "GetSession":
            inv.return_value(GLib.Variant("(o)", (SESSION,)))
        elif method == "Inhibit":
            self.inhibitors.append(params.unpack())
            r, w = os.pipe()
            self.read_ends.append(r)
            fds = Gio.UnixFDList.new()
            fds.append(w)
            os.close(w)
            inv.return_value_with_unix_fd_list(GLib.Variant("(h)", (0,)), fds)
        elif method == "SetLockedHint":
            self.hints.append(params.unpack()[0])
            inv.return_value(None)

    def emit(self, path, iface, signal, params=None):
        self.conn.emit_signal(None, path, iface, signal, params)

    def held(self) -> bool:
        """Whether the newest inhibitor's fd is still open on the client side."""
        import select
        r = self.read_ends[-1]
        ready, _, _ = select.select([r], [], [], 0)
        return not ready      # EOF (readable) means the client closed its end


@pytest.fixture
def bus():
    if not shutil.which("dbus-daemon"):
        pytest.skip("no dbus-daemon")
    daemon = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"],
                              stdout=subprocess.PIPE, text=True)
    address = daemon.stdout.readline().strip()
    yield address
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


def test_lock_requests_and_sleep_wait_for_the_lock(bus):
    fake = FakeLogind(bus)
    env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=bus)
    child = subprocess.Popen([sys.executable, "-c", CHILD, str(BRIDGE)], env=env, text=True,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines: list[dict] = []
    reader = threading.Thread(target=lambda: [lines.append(json.loads(x)) for x in child.stdout
                                              if x.startswith("{")], daemon=True)
    reader.start()
    try:
        assert pump(lambda: {"started": True} in lines), (lines, child.stderr.read() if child.poll() else "")
        assert pump(lambda: len(fake.inhibitors) == 1)
        assert fake.inhibitors[0][0] == "sleep" and fake.inhibitors[0][3] == "delay"
        assert fake.held(), "the delay inhibitor must be held while awake"

        # loginctl lock-session
        fake.emit(SESSION, "org.freedesktop.login1.Session", "Lock")
        assert pump(lambda: {"type": "logind", "op": "lock"} in lines)

        # about to sleep: the shell is told, and sleep is still held back
        fake.emit("/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PrepareForSleep",
                  GLib.Variant("(b)", (True,)))
        assert pump(lambda: {"type": "logind", "op": "sleep"} in lines)
        pump(lambda: False, 0.3)
        assert fake.held(), "sleep was let through before the shell said the lock was up"

        # the shell reports the lock is up: hint set, inhibitor released
        child.stdin.write("locked\n")
        child.stdin.flush()
        assert pump(lambda: fake.hints == [True])
        assert pump(lambda: not fake.held()), "the inhibitor was not released after the lock"

        # awake again: a fresh delay is taken for next time
        fake.emit("/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PrepareForSleep",
                  GLib.Variant("(b)", (False,)))
        assert pump(lambda: len(fake.inhibitors) == 2 and fake.held())
    finally:
        child.stdin.write("quit\n")
        child.stdin.flush()
        child.wait(5)


def test_without_a_system_bus_it_stays_out_of_the_way(tmp_path):
    env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=f"unix:path={tmp_path}/nothing")
    out = subprocess.run([sys.executable, "-c",
                          "import sys; sys.path.insert(0, sys.argv[1]); from logind import Logind;"
                          "print(Logind(print).start())", str(BRIDGE)],
                         env=env, capture_output=True, text=True, timeout=20)
    assert out.stdout.strip().splitlines()[-1] == "False", out.stdout + out.stderr


def test_with_lock_before_suspend_off_sleep_is_let_go_without_a_lock(bus):
    fake = FakeLogind(bus)
    env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=bus)
    child = subprocess.Popen([sys.executable, "-c", CHILD, str(BRIDGE)], env=env, text=True,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines: list[dict] = []
    threading.Thread(target=lambda: [lines.append(json.loads(x)) for x in child.stdout
                                     if x.startswith("{")], daemon=True).start()
    try:
        assert pump(lambda: len(fake.inhibitors) == 1 and fake.held())
        child.stdin.write("release\n")       # awake: nothing to release yet
        child.stdin.flush()
        pump(lambda: False, 0.3)
        assert fake.held(), "released while no sleep was pending"
        fake.emit("/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PrepareForSleep",
                  GLib.Variant("(b)", (True,)))
        assert pump(lambda: {"type": "logind", "op": "sleep"} in lines)
        child.stdin.write("release\n")
        child.stdin.flush()
        assert pump(lambda: not fake.held()), "sleep was held although locking before it is off"
        assert fake.hints == [], "no lock happened, so no LockedHint"
    finally:
        child.stdin.write("quit\n")
        child.stdin.flush()
        child.wait(5)
