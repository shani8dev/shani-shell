"""logind for the shell: lock requests in, lock state and sleep readiness out.

Quickshell has no system-bus client, so the bridge carries these:

  in   Session.Lock / Session.Unlock   `loginctl lock-session`, lid scripts, sshd
       Manager.PrepareForSleep(true)   about to suspend or hibernate
  out  Session.SetLockedHint(b)        so `loginctl` and other tools see the lock
       a "delay" sleep inhibitor       held while awake, released only once the
                                       shell reports the lock surface is up, so
                                       the machine never sleeps unlocked

The session is resolved with GetSession("auto"): the bridge runs as a systemd
user service, outside the login session's scope, and "auto" falls back to the
user's display session in that case. Without a system bus or logind (a
container), `start()` returns False and nothing else happens.
"""

from __future__ import annotations

import os

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

LOGIND = "org.freedesktop.login1"
MANAGER_PATH = "/org/freedesktop/login1"
MANAGER_IFACE = "org.freedesktop.login1.Manager"
SESSION_IFACE = "org.freedesktop.login1.Session"


class Logind:
    def __init__(self, emit) -> None:
        self.emit = emit            # emit(dict) -> the shell
        self.conn = None
        self.session = None
        self.inhibit_fd = -1
        self.sleeping = False

    def start(self) -> bool:
        try:
            self.conn = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            r = self.conn.call_sync(LOGIND, MANAGER_PATH, MANAGER_IFACE, "GetSession",
                                    GLib.Variant("(s)", ("auto",)), GLib.VariantType("(o)"),
                                    Gio.DBusCallFlags.NONE, 2000, None)
            self.session = r.unpack()[0]
        except GLib.Error as error:
            print(f"logind: unavailable ({error.message})", flush=True)
            self.conn = None
            return False
        for signal in ("Lock", "Unlock"):
            self.conn.signal_subscribe(LOGIND, SESSION_IFACE, signal, self.session, None,
                                       Gio.DBusSignalFlags.NONE, self._on_session, None)
        self.conn.signal_subscribe(LOGIND, MANAGER_IFACE, "PrepareForSleep", MANAGER_PATH,
                                   None, Gio.DBusSignalFlags.NONE, self._on_sleep, None)
        self._inhibit()
        print(f"logind: session {self.session}", flush=True)
        return True

    # ---- in ----------------------------------------------------------------
    def _on_session(self, _conn, _sender, _path, _iface, signal, _params, _data) -> None:
        self.emit({"type": "logind", "op": signal.lower()})

    def _on_sleep(self, _conn, _sender, _path, _iface, _signal, params, _data) -> None:
        going = params.unpack()[0]
        self.sleeping = going
        if going:
            self.emit({"type": "logind", "op": "sleep"})
        else:
            self._inhibit()         # awake again: hold the delay for next time

    # ---- out ---------------------------------------------------------------
    def locked(self, on: bool) -> None:
        if self.conn is None:
            return
        try:
            self.conn.call_sync(LOGIND, self.session, SESSION_IFACE, "SetLockedHint",
                                GLib.Variant("(b)", (on,)), None, Gio.DBusCallFlags.NONE,
                                2000, None)
        except GLib.Error as error:
            print(f"logind: SetLockedHint failed ({error.message})", flush=True)
        if on:
            self._release()         # the lock is up: sleep may proceed

    def release_sleep(self) -> None:
        """Let a pending sleep proceed without a lock (the setting is off)."""
        if self.sleeping:
            self._release()

    def _inhibit(self) -> None:
        if self.conn is None or self.inhibit_fd >= 0:
            return
        try:
            r, fds = self.conn.call_with_unix_fd_list_sync(
                LOGIND, MANAGER_PATH, MANAGER_IFACE, "Inhibit",
                GLib.Variant("(ssss)", ("sleep", "shani-shell", "Lock the screen before sleep", "delay")),
                GLib.VariantType("(h)"), Gio.DBusCallFlags.NONE, 2000, None, None)
            self.inhibit_fd = fds.get(r.unpack()[0])
        except GLib.Error as error:
            print(f"logind: no sleep delay ({error.message})", flush=True)

    def _release(self) -> None:
        if self.inhibit_fd >= 0:
            os.close(self.inhibit_fd)
            self.inhibit_fd = -1
