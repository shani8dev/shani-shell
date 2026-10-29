#!/usr/bin/env python3
"""launcher-entry — apps' own counts and progress, for the dock.

Apps announce an unread count, a progress bar or urgency for their launcher
with the LauncherEntry API (``com.canonical.Unity.LauncherEntry.Update``, a
session-bus signal: Telegram, Thunderbird, Firefox's downloads, Fractal; what
Pantheon's, KDE's and Dash to Dock read). This listens for it and prints one
JSON line per update:

  {"app": "org.telegram.desktop", "count": 3, "countVisible": true,
   "progress": 0.4, "progressVisible": false, "urgent": false}

"app" is the desktop id, from the ``application://ID.desktop`` URI the app
sends. It waits on the bus (no polling) until the shell closes its stdout.
"""

from __future__ import annotations

import json
import sys

KEYS = {"count": "count", "count-visible": "countVisible", "progress": "progress",
        "progress-visible": "progressVisible", "urgent": "urgent"}


def app_id(uri: str) -> str:
    """application://org.telegram.desktop.desktop -> org.telegram.desktop"""
    s = uri.split("://", 1)[-1]
    return s[:-len(".desktop")] if s.endswith(".desktop") else s


def entry(uri: str, props: dict) -> dict:
    out = {"app": app_id(uri)}
    for k, v in props.items():
        if k in KEYS:
            out[KEYS[k]] = v
    return out


def main() -> int:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    loop = GLib.MainLoop()

    def on_update(_conn, _sender, _path, _iface, _signal, params):
        uri, props = params.unpack()
        try:
            print(json.dumps(entry(uri, props)), flush=True)
        except BrokenPipeError:
            loop.quit()

    bus.signal_subscribe(None, "com.canonical.Unity.LauncherEntry", "Update", None, None,
                         Gio.DBusSignalFlags.NONE, on_update)
    print(json.dumps({"ready": True}), flush=True)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
