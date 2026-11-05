"""bridge/screensaver.py on a private session bus, with fake apps calling Inhibit.

The service runs in a subprocess (emit() printing JSON lines, commands on
stdin); each "app" is its own bus connection, so one can leave the bus the way
a crashed player does.
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
NAME = "org.freedesktop.ScreenSaver"

CHILD = r"""
import json, sys, threading
sys.path.insert(0, sys.argv[1])
from gi.repository import Gio, GLib
from screensaver import ScreenSaver
loop = GLib.MainLoop()
s = ScreenSaver(lambda o: print(json.dumps(o), flush=True))
s.start(Gio.bus_get_sync(Gio.BusType.SESSION, None))
print(json.dumps({"started": True}), flush=True)
def commands():
    for line in sys.stdin:
        cmd = line.strip()
        if cmd in ("locked", "unlocked"):
            GLib.idle_add(lambda c=cmd: s.locked(c == "locked") and False)
        elif cmd == "quit":
            GLib.idle_add(loop.quit)
threading.Thread(target=commands, daemon=True).start()
loop.run()
"""


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


def wait(cond, timeout=5.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.02)
    return False


class App:
    """A fake app: its own connection to the bus, as a player has."""

    def __init__(self, address):
        self.conn = Gio.DBusConnection.new_for_address_sync(
            address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)

    def call(self, method, sig=None, args=None, path="/org/freedesktop/ScreenSaver"):
        r = self.conn.call_sync(NAME, path, NAME, method, GLib.Variant(sig, args) if sig else None,
                                None, Gio.DBusCallFlags.NONE, 3000, None)
        return r.unpack() if r is not None else None

    def leave(self):
        self.conn.close_sync(None)


@pytest.fixture
def service(bus):
    env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=bus)
    child = subprocess.Popen([sys.executable, "-c", CHILD, str(BRIDGE)], env=env, text=True,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines: list[dict] = []
    threading.Thread(target=lambda: [lines.append(json.loads(x)) for x in child.stdout
                                     if x.startswith("{")], daemon=True).start()
    assert wait(lambda: {"started": True} in lines)
    # the name is taken asynchronously
    probe = App(bus)
    assert wait(lambda: probe.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                            "NameHasOwner", GLib.Variant("(s)", (NAME,)), None,
                                            Gio.DBusCallFlags.NONE, 1000, None).unpack()[0])
    yield bus, child, lines
    child.stdin.write("quit\n")
    child.stdin.flush()
    child.wait(5)


def apps_now(lines):
    last = [x for x in lines if x.get("type") == "screensaver" and "inhibitors" in x]
    return sorted(i["app"] for i in last[-1]["inhibitors"]) if last else []


def test_inhibit_and_uninhibit_reach_the_shell(service):
    bus, _child, lines = service
    firefox = App(bus)
    (cookie,) = firefox.call("Inhibit", "(ss)", ("Firefox", "audio-playing"))
    assert wait(lambda: apps_now(lines) == ["Firefox"])
    firefox.call("UnInhibit", "(u)", (cookie,))
    assert wait(lambda: apps_now(lines) == [])


def test_an_app_that_leaves_the_bus_releases_its_inhibition(service):
    bus, _child, lines = service
    mpv, firefox = App(bus), App(bus)
    mpv.call("Inhibit", "(ss)", ("mpv", "Playing a video"))
    # the old path some apps use (KDE's, Chromium's)
    firefox.call("Inhibit", "(ss)", ("Firefox", "video-playing"), path="/ScreenSaver")
    assert wait(lambda: apps_now(lines) == ["Firefox", "mpv"])
    mpv.leave()               # crashed: never said UnInhibit
    assert wait(lambda: apps_now(lines) == ["Firefox"])


def test_only_the_app_that_asked_can_take_it_back(service):
    bus, _child, lines = service
    vlc, other = App(bus), App(bus)
    (cookie,) = vlc.call("Inhibit", "(ss)", ("VLC", "video"))
    assert wait(lambda: apps_now(lines) == ["VLC"])
    other.call("UnInhibit", "(u)", (cookie,))
    time.sleep(0.3)
    assert apps_now(lines) == ["VLC"]


def test_get_active_follows_the_lock_and_activity_is_passed_on(service):
    bus, child, lines = service
    app = App(bus)
    assert app.call("GetActive") == (False,)
    child.stdin.write("locked\n")
    child.stdin.flush()
    assert wait(lambda: app.call("GetActive") == (True,))
    app.call("SimulateUserActivity")
    assert wait(lambda: {"type": "screensaver", "op": "activity"} in lines)
