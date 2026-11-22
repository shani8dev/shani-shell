#!/usr/bin/env python3
"""Own com.canonical.AppMenu.Registrar so apps export their menus at startup.

Qt 5, LibreOffice and XWayland apps register their menu object with this
name when it exists when they start. shani-shell's one-shot appmenu.py then
reads the registrations (GetMenus) to show a real global menu in the bar.
Native Wayland Qt 6 and Chromium do not register (they need KWin's appmenu
protocol, which niri has not merged) — for those the AT-SPI fallback is used.

Adapted from the Noctalia global-menu plugin's resolver.py. python-dbus is a
shani-shell dependency. Uses do_not_queue=True so it never conflicts with
another registrar; if the name is taken we simply read that owner's GetMenus,
and we take ownership back when it disappears.
"""

from __future__ import annotations

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

NAME = "com.canonical.AppMenu.Registrar"
PATH = "/com/canonical/AppMenu/Registrar"
menus: dict[int, tuple[str, str]] = {}
held = None


class Registrar(dbus.service.Object):
    def __init__(self, name):
        super().__init__(name, PATH)

    @dbus.service.method(NAME, in_signature="uo", sender_keyword="sender")
    def RegisterWindow(self, window_id, menu_path, sender=None):
        menus[int(window_id)] = (str(sender), str(menu_path))
        self.WindowRegistered(window_id, menu_path)

    @dbus.service.method(NAME, in_signature="u")
    def UnregisterWindow(self, window_id):
        menus.pop(int(window_id), None)
        self.WindowUnregistered(window_id)

    @dbus.service.method(NAME, in_signature="u", out_signature="so")
    def GetMenuForWindow(self, window_id):
        entry = menus.get(int(window_id))
        if not entry:
            raise dbus.exceptions.DBusException(
                "no menu for that window", name=NAME + ".Error.NoMenuForWindow"
            )
        return entry

    @dbus.service.method(NAME, out_signature="a{u(so)}")
    def GetMenus(self):
        return {
            dbus.UInt32(w): dbus.Struct((dbus.String(s), dbus.ObjectPath(p)))
            for w, (s, p) in menus.items()
        }

    @dbus.service.signal(NAME, signature="uo")
    def WindowRegistered(self, w, p):
        pass

    @dbus.service.signal(NAME, signature="u")
    def WindowUnregistered(self, w):
        pass


def own(bus):
    global held
    try:
        held = dbus.service.BusName(NAME, bus, do_not_queue=True)
        Registrar(held)  # keep the object alive with the name
    except dbus.exceptions.DBusException:
        held = None  # someone else owns it; appmenu.py reads their GetMenus


def on_owner_changed(name, old, new):
    if name == NAME and not new and held is None:
        own(dbus.SessionBus())


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    bus.add_signal_receiver(
        on_owner_changed,
        "NameOwnerChanged",
        "org.freedesktop.DBus",
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
    )
    own(bus)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
