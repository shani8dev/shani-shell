#!/usr/bin/env python3
"""search-providers — ask apps' search providers (GNOME's SearchProvider2 over
D-Bus) for results, so the launcher shows what Files, Settings, Characters,
Calculator … find, the way GNOME's overview does.

    search-providers.py query TERMS...     JSON: [{app, icon, bus, path, id, name, description}]
    search-providers.py activate BUS PATH ID TERMS...

Providers are the *.ini files in */gnome-shell/search-providers/ whose desktop
entry is installed. Each is asked with a short timeout; a slow or absent one
is skipped, never waited on.
"""
from __future__ import annotations

import configparser
import glob
import json
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

IFACE = "org.gnome.Shell.SearchProvider2"
DIRS = [os.path.join(d, "gnome-shell/search-providers")
        for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")]


def providers():
    seen = set()
    for d in DIRS:
        for ini in sorted(glob.glob(os.path.join(d, "*.ini"))):
            c = configparser.ConfigParser()
            c.read(ini)
            s = c["Shell Search Provider"] if c.has_section("Shell Search Provider") else None
            if not s or s.get("Version", "2") != "2" or s.get("DefaultDisabled", "false") == "true":
                continue
            app = Gio.DesktopAppInfo.new(s["DesktopId"]) if s.get("DesktopId") else None
            if app is None or s["BusName"] in seen:
                continue
            seen.add(s["BusName"])
            yield app, s["BusName"], s["ObjectPath"]


def query(terms):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    out = []
    for app, name, path in providers():
        try:
            ids = bus.call_sync(name, path, IFACE, "GetInitialResultSet", GLib.Variant("(as)", (terms,)),
                                GLib.VariantType("(as)"), Gio.DBusCallFlags.NONE, 1500, None).unpack()[0][:5]
            if not ids:
                continue
            metas = bus.call_sync(name, path, IFACE, "GetResultMetas", GLib.Variant("(as)", (ids,)),
                                  GLib.VariantType("(aa{sv})"), Gio.DBusCallFlags.NONE, 1500, None).unpack()[0]
        except GLib.Error:
            continue
        icon = app.get_icon().to_string() if app.get_icon() else ""
        for m in metas:
            out.append({"app": app.get_name(), "icon": icon, "bus": name, "path": path, "id": m.get("id", ""),
                        "name": m.get("name", ""), "description": m.get("description", "")})
    return out


def main(argv):
    if len(argv) >= 3 and argv[1] == "query":
        json.dump(query(argv[2:]), sys.stdout, ensure_ascii=False)
        return 0
    if len(argv) >= 5 and argv[1] == "activate":
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call_sync(argv[2], argv[3], IFACE, "ActivateResult", GLib.Variant("(sasu)", (argv[4], argv[5:], 0)),
                      None, Gio.DBusCallFlags.NONE, 3000, None)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
