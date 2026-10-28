#!/usr/bin/env python3
"""fake-mpris — one MPRIS media player on the session bus, for the shell's
media chip and the sidebar's media card (showcase and tests). Plays nothing.

    fake-mpris.py TITLE ARTIST [ART_PNG]
"""
from __future__ import annotations

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <property name="Identity" type="s" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <method name="Raise"/><method name="Quit"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="PlayPause"/><method name="Play"/><method name="Pause"/>
    <method name="Next"/><method name="Previous"/><method name="Stop"/>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="CanControl" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
  </interface>
</node>
"""

title, artist = sys.argv[1], sys.argv[2]
art = sys.argv[3] if len(sys.argv) > 3 else ""
state = {"status": "Playing"}


def prop(_c, _s, _p, iface, name):
    if name == "Identity":
        return GLib.Variant("s", "Shani Player")
    if name == "PlaybackStatus":
        return GLib.Variant("s", state["status"])
    if name == "Position":
        return GLib.Variant("x", 83_000_000)
    if name == "Metadata":
        md = {"mpris:trackid": GLib.Variant("o", "/track/1"),
              "xesam:title": GLib.Variant("s", title),
              "xesam:artist": GLib.Variant("as", [artist]),
              "mpris:length": GLib.Variant("x", 214_000_000)}
        if art:
            md["mpris:artUrl"] = GLib.Variant("s", "file://" + art)
        return GLib.Variant("a{sv}", md)
    return GLib.Variant("b", name not in ("CanQuit", "CanRaise"))


def call(conn, _s, path, iface, method, _params, inv):
    if method in ("PlayPause", "Play", "Pause"):
        state["status"] = "Paused" if state["status"] == "Playing" and method != "Play" else "Playing"
        conn.emit_signal(None, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                         GLib.Variant("(sa{sv}as)", (iface, {"PlaybackStatus": GLib.Variant("s", state["status"])}, [])))
    inv.return_value(None)


conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
node = Gio.DBusNodeInfo.new_for_xml(XML)
for i in node.interfaces:
    conn.register_object("/org/mpris/MediaPlayer2", i, call, prop, None)
Gio.bus_own_name_on_connection(conn, "org.mpris.MediaPlayer2.shani", Gio.BusNameOwnerFlags.NONE, None, None)
GLib.MainLoop().run()
