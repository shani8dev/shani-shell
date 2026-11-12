"""bridge/mpris-player.py on a private session bus: the shell's Media Player as
an MPRIS player, which is what the bar, the sidebar, the lock screen and the
media keys read. A client here is plain Gio, the way playerctl or Quickshell's
Mpris service talks to it."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

gi = pytest.importorskip("gi")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

TOOL = Path(__file__).resolve().parents[1] / "bridge" / "mpris-player.py"
NAME = "org.mpris.MediaPlayer2.shani_media"
PATH = "/org/mpris/MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"


@pytest.fixture
def bus():
    if not shutil.which("dbus-daemon"):
        pytest.skip("no dbus-daemon")
    daemon = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"], stdout=subprocess.PIPE, text=True)
    address = daemon.stdout.readline().strip()
    yield address
    daemon.kill()
    daemon.wait()


@pytest.fixture
def player(bus):
    env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=bus)
    proc = subprocess.Popen([sys.executable, str(TOOL)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
    conn = Gio.DBusConnection.new_for_address_sync(bus, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
    deadline = time.time() + 5
    while time.time() < deadline:
        owner = conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                               GLib.Variant("(s)", (NAME,)), None, Gio.DBusCallFlags.NONE, -1, None).unpack()[0]
        if owner:
            break
        time.sleep(0.05)
    else:
        proc.kill()
        pytest.fail("the player never took its bus name")
    yield proc, conn
    proc.stdin.close()
    proc.wait(timeout=5)


def get(conn, name, iface=PLAYER):
    return conn.call_sync(NAME, PATH, "org.freedesktop.DBus.Properties", "Get", GLib.Variant("(ss)", (iface, name)),
                          None, Gio.DBusCallFlags.NONE, -1, None).unpack()[0]


def call(conn, method, args=None):
    conn.call_sync(NAME, PATH, PLAYER, method, args, None, Gio.DBusCallFlags.NONE, -1, None)


def say(proc, obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()


def until(fn, timeout=3.0):
    end = time.time() + timeout
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(0.05)
    return fn()


def test_the_state_the_shell_writes_is_what_clients_read(player):
    proc, conn = player
    say(proc, {"status": "Playing", "title": "clip1.webm", "url": "file:///v/clip1.webm", "length": 8, "position": 2.5,
               "volume": 0.6, "canNext": True})
    assert until(lambda: get(conn, "PlaybackStatus") == "Playing")
    md = get(conn, "Metadata")
    assert md["xesam:title"] == "clip1.webm" and md["mpris:length"] == 8_000_000 and md["xesam:url"] == "file:///v/clip1.webm"
    assert get(conn, "Position") == 2_500_000 and abs(get(conn, "Volume") - 0.6) < 1e-9
    assert get(conn, "CanGoNext") and get(conn, "CanSeek") and get(conn, "CanPause")
    assert get(conn, "DesktopEntry", "org.mpris.MediaPlayer2") == "dev.shani.MediaPlayer"


def test_what_a_client_asks_reaches_the_shell(player):
    proc, conn = player
    say(proc, {"status": "Playing", "title": "a", "length": 100, "position": 40})
    until(lambda: get(conn, "PlaybackStatus") == "Playing")
    call(conn, "PlayPause")
    call(conn, "Next")
    call(conn, "Seek", GLib.Variant("(x)", (10_000_000,)))     # 10 s on from 40
    call(conn, "SetPosition", GLib.Variant("(ox)", ("/dev/shani/media/track", 5_000_000)))
    conn.call_sync(NAME, PATH, "org.freedesktop.DBus.Properties", "Set",
                   GLib.Variant("(ssv)", (PLAYER, "Volume", GLib.Variant("d", 0.25))), None, Gio.DBusCallFlags.NONE, -1, None)
    got = [json.loads(proc.stdout.readline()) for _ in range(5)]
    assert got == [{"op": "toggle"}, {"op": "next"}, {"op": "seek", "to": 50.0}, {"op": "seek", "to": 5.0}, {"op": "volume", "value": 0.25}]


def test_it_leaves_the_bus_when_the_player_closes(bus, player):
    proc, conn = player
    proc.stdin.close()
    proc.wait(timeout=5)
    owner = conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                           GLib.Variant("(s)", (NAME,)), None, Gio.DBusCallFlags.NONE, -1, None).unpack()[0]
    assert owner is False
    proc.stdin = open(os.devnull, "w")     # the fixture's own close
