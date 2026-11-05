"""org.freedesktop.ScreenSaver for the shell: apps asking to keep the screen awake.

Video players and browsers (Firefox, Chromium, mpv, VLC, Kodi, Steam ...) call
this session-bus interface while something plays; Quickshell cannot export a
D-Bus object, so the bridge owns the name and tells the shell:

  Inhibit(app, reason) -> cookie   kept until UnInhibit(cookie), or until the
                                   caller leaves the bus (a crash, a closed tab
                                   that never said so)
  UnInhibit(cookie)
  GetActive() -> b                 whether the lock screen is up
  SimulateUserActivity()           the shell treats it as input: idle starts over

  out  {"type": "screensaver", "inhibitors": [{"app", "reason"}]}   on every change
       {"type": "screensaver", "op": "activity"}

The object is served at both paths apps use (/org/freedesktop/ScreenSaver and
/ScreenSaver). If another program already owns the name (a full desktop's own
service), nothing is taken from it.
"""

from __future__ import annotations

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "org.freedesktop.ScreenSaver"
PATHS = ("/org/freedesktop/ScreenSaver", "/ScreenSaver")
XML = """
<node>
  <interface name="org.freedesktop.ScreenSaver">
    <method name="Inhibit">
      <arg type="s" name="application_name" direction="in"/>
      <arg type="s" name="reason_for_inhibit" direction="in"/>
      <arg type="u" name="cookie" direction="out"/>
    </method>
    <method name="UnInhibit"><arg type="u" name="cookie" direction="in"/></method>
    <method name="GetActive"><arg type="b" direction="out"/></method>
    <method name="GetActiveTime"><arg type="u" direction="out"/></method>
    <method name="SetActive">
      <arg type="b" name="e" direction="in"/><arg type="b" direction="out"/>
    </method>
    <method name="SimulateUserActivity"/>
    <signal name="ActiveChanged"><arg type="b"/></signal>
  </interface>
</node>
"""


class ScreenSaver:
    def __init__(self, emit) -> None:
        self.emit = emit                 # emit(dict) -> the shell
        self.conn = None
        self.inhibitors: dict[int, dict] = {}   # cookie -> {app, reason, sender}
        self.next_cookie = 1
        self.active = False

    def start(self, conn) -> None:
        self.conn = conn
        iface = Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0]
        for path in PATHS:
            conn.register_object(path, iface, self._call, None, None)
        # a caller that leaves the bus takes its inhibitions with it
        conn.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                              "/org/freedesktop/DBus", None, Gio.DBusSignalFlags.NONE,
                              self._owner_changed, None)
        Gio.bus_own_name_on_connection(conn, NAME, Gio.BusNameOwnerFlags.NONE, None, None)

    # ---- what the shell says -------------------------------------------------
    def locked(self, on: bool) -> None:
        on = bool(on)
        if on != self.active:
            self.active = on
            if self.conn is not None:
                for path in PATHS:
                    self.conn.emit_signal(None, path, NAME, "ActiveChanged", GLib.Variant("(b)", (on,)))

    def announce(self) -> None:
        self.emit({"type": "screensaver",
                   "inhibitors": [{"app": i["app"], "reason": i["reason"]} for i in list(self.inhibitors.values())]})

    # ---- D-Bus ----------------------------------------------------------------
    def _call(self, _conn, sender, _path, _iface, method, params, inv):
        if method == "Inhibit":
            app, reason = params.unpack()
            cookie = self.next_cookie
            self.next_cookie += 1
            self.inhibitors[cookie] = {"app": app or sender, "reason": reason or "", "sender": sender}
            inv.return_value(GLib.Variant("(u)", (cookie,)))
            self.announce()
        elif method == "UnInhibit":
            (cookie,) = params.unpack()
            # only the one who asked can take it back
            held = self.inhibitors.get(cookie)
            if held and held["sender"] == sender:
                del self.inhibitors[cookie]
                self.announce()
            inv.return_value(None)
        elif method == "GetActive":
            inv.return_value(GLib.Variant("(b)", (self.active,)))
        elif method == "GetActiveTime":
            inv.return_value(GLib.Variant("(u)", (0,)))
        elif method == "SetActive":
            # turning the screen saver on is locking: asked of the shell; off is refused
            if params.unpack()[0]:
                self.emit({"type": "screensaver", "op": "lock"})
            inv.return_value(GLib.Variant("(b)", (False,)))
        elif method == "SimulateUserActivity":
            self.emit({"type": "screensaver", "op": "activity"})
            inv.return_value(None)
        else:
            inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

    def _owner_changed(self, _conn, _sender, _path, _iface, _signal, params, _data):
        name, _old, new = params.unpack()
        if new or not name.startswith(":"):
            return
        gone = [c for c, i in self.inhibitors.items() if i["sender"] == name]
        for c in gone:
            del self.inhibitors[c]
        if gone:
            self.announce()
