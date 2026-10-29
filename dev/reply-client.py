#!/usr/bin/env python3
"""An app that posts a replyable notification and waits for the reply on the same
connection, as Chronoa's message watcher does. Prints the reply, or nothing."""
import sys
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
nid = bus.call_sync("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                    "Notify", GLib.Variant("(susssasa{sv}i)", ("Shani Chronoa", 0, "mail-message-new", sys.argv[1], "Reached the station",
                                                             ["inline-reply", "Reply"], {"x-kde-reply-placeholder-text": GLib.Variant("s", "Reply…")}, -1)),
                    None, 0, 5000, None).unpack()[0]
loop = GLib.MainLoop()


def replied(_c, _s, _p, _i, _sig, params):
    got_id, text = params.unpack()
    if got_id == nid:
        print(text, flush=True)
        loop.quit()


bus.signal_subscribe(None, "org.freedesktop.Notifications", "NotificationReplied", "/org/freedesktop/Notifications", None,
                     Gio.DBusSignalFlags.NONE, replied)
GLib.timeout_add_seconds(15, loop.quit)
loop.run()
