#!/usr/bin/env python3
"""Calls the file-chooser portal backend as xdg-desktop-portal does (dev/shell-parts/
file-portal.sh): METHOD HANDLE TITLE FOLDER [NAME] [FILTER_EXT]. `gdbus call` cannot
be used: it builds a byte-string inside a{sv} wrongly (garbage reached the bridge)."""
import sys
import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

method, handle, title, folder = sys.argv[1:5]
name = sys.argv[5] if len(sys.argv) > 5 else ""
ext = sys.argv[6] if len(sys.argv) > 6 else ""
opts = {}
if folder:
    opts["current_folder"] = GLib.Variant("ay", folder.encode() + b"\0")
if name:
    opts["current_name"] = GLib.Variant("s", name)
if ext:
    opts["filters"] = GLib.Variant("a(sa(us))", [("Files", [(0, "*." + ext)])])
c = Gio.bus_get_sync(Gio.BusType.SESSION, None)
r = c.call_sync("org.freedesktop.impl.portal.desktop.shani", "/org/freedesktop/portal/desktop", "org.freedesktop.impl.portal.FileChooser",
                method, GLib.Variant("(osssa{sv})", (handle, "org.example.App", "", title, opts)), GLib.VariantType("(ua{sv})"),
                Gio.DBusCallFlags.NONE, 120000, None)
code, results = r.unpack()
print(code, " ".join(results.get("uris", [])))
