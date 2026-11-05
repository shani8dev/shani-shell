#!/usr/bin/env python3
"""A stand-in app asking to keep the screen awake: Inhibit(app, reason) on
org.freedesktop.ScreenSaver, then holds it until killed (leaving the bus
without UnInhibit, as a crashed player does) or, with --release N, calls
UnInhibit after N seconds and stays.
usage: fake-inhibit.py APP [REASON] [--release SECONDS]"""
import sys
import time

from gi.repository import Gio, GLib

args = [a for a in sys.argv[1:] if not a.startswith("--")]
app = args[0] if args else "Firefox"
reason = args[1] if len(args) > 1 else "video-playing"
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
(cookie,) = bus.call_sync("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver",
                          "Inhibit", GLib.Variant("(ss)", (app, reason)), None, Gio.DBusCallFlags.NONE, 3000, None).unpack()
print(cookie, flush=True)
if "--release" in sys.argv:
    time.sleep(float(sys.argv[sys.argv.index("--release") + 1]))
    bus.call_sync("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver",
                  "UnInhibit", GLib.Variant("(u)", (cookie,)), None, Gio.DBusCallFlags.NONE, 3000, None)
time.sleep(3600)
