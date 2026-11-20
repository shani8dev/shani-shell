#!/usr/bin/env python3
"""portal — the file-chooser portal backend for the niri session: a sandboxed
app's Open and Save dialogs (org.freedesktop.portal.FileChooser, through
xdg-desktop-portal) are the shell's own file picker, not Nautilus.

Owns org.freedesktop.impl.portal.desktop.shani on the session bus (started by
D-Bus activation, data/dbus/...shani.service; named in shani.portal; chosen for
FileChooser in shani-desktop-niri's niri-portals.conf) and implements
org.freedesktop.impl.portal.FileChooser OpenFile and SaveFile, and
org.freedesktop.impl.portal.Request.Close for the dialog it shows. Each ask goes
to the shell (`qs ipc call shani portalPick ID OPTIONS`) and the answer is
fetched by its id until the person has chosen; the method answers then.
SHANI_QS_CONFIG: a checkout's shani/ (tests run the shell with `qs -p`).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
import uuid
from urllib.parse import quote, unquote

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "org.freedesktop.impl.portal.desktop.shani"
PATH = "/org/freedesktop/portal/desktop"
XML = """<node>
<interface name='org.freedesktop.impl.portal.FileChooser'>
 <method name='OpenFile'><arg type='o' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='in'/>
  <arg type='a{sv}' direction='in'/><arg type='u' direction='out'/><arg type='a{sv}' direction='out'/></method>
 <method name='SaveFile'><arg type='o' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='in'/>
  <arg type='a{sv}' direction='in'/><arg type='u' direction='out'/><arg type='a{sv}' direction='out'/></method>
 <property name='version' type='u' access='read'/>
</interface>
<interface name='org.freedesktop.impl.portal.Request'><method name='Close'/></interface>
</node>"""
NODE = Gio.DBusNodeInfo.new_for_xml(XML)


def qs(*args, timeout=10) -> str:
    where = (
        ["-p", os.environ["SHANI_QS_CONFIG"]]
        if os.environ.get("SHANI_QS_CONFIG")
        else ["-c", "shani"]
    )
    r = subprocess.run(
        ["qs", *where, "ipc", "call", "shani", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return r.stdout.strip()


def _bytes_path(v) -> str:
    """current_folder / current_file: a NUL-ended byte string (copied at once)."""
    if v is None:
        return ""
    if isinstance(v, str):
        v = v.encode("latin-1", errors="replace")
    return bytes(bytearray(v)).split(b"\0", 1)[0].decode("utf-8", errors="replace")


def options_for(method: str, title: str, opts: dict) -> dict:
    """What the shell's picker is told: mode, title, multiple, the extensions to
    show (the filter the app chose, else all its filters' *.ext globs), a name and
    a folder to start in."""
    exts = []
    filters = (
        opts.get("current_filter")
        and [opts["current_filter"]]
        or opts.get("filters")
        or []
    )
    for _name, patterns in filters:
        for kind, pat in patterns:
            if kind == 0 and pat.startswith("*.") and "*" not in pat[2:]:
                exts.append(pat[2:].lower())
            elif kind == 1:  # a mime type: its extensions
                import mimetypes

                exts += [e.lstrip(".") for e in mimetypes.guess_all_extensions(pat)]
    folder = _bytes_path(opts.get("current_folder"))
    name = opts.get("current_name") or ""
    cur = _bytes_path(opts.get("current_file"))
    if cur:
        folder, name = os.path.dirname(cur), os.path.basename(cur)
    return {
        "mode": "save" if method == "SaveFile" else "open",
        "title": title,
        "multiple": bool(opts.get("multiple")),
        "directory": bool(opts.get("directory")),
        "filters": sorted(set(exts)),
        "name": name,
        "folder": folder,
    }


def uri(p: str) -> str:
    return "file://" + quote(p)


class Backend:
    def __init__(self, conn):
        self.conn = conn
        self.requests = {}  # handle -> pick id

    def call(self, conn, sender, path, iface, method, params, inv):
        if iface == "org.freedesktop.impl.portal.Request" and method == "Close":
            pid = self.requests.pop(path, None)
            if pid:
                try:
                    qs("portalCancel", pid)
                except (OSError, subprocess.TimeoutExpired):
                    pass
            inv.return_value(None)
            return
        handle, app_id, parent, title, opts = params.unpack()
        # a byte array inside the options dictionary unpacks as garbage (PyGObject:
        # the inner variant is freed under it - reproduced over a real bus); read
        # those two from the GVariant itself, copied
        raw = params.get_child_value(4)
        for key in ("current_folder", "current_file"):
            v = raw.lookup_value(key, GLib.VariantType("ay"))
            if v is not None:
                opts[key] = bytes(v.get_data_as_bytes().get_data())
        # read here, in the handler: PyGObject unpacks a byte array (current_folder)
        # without copying it, and the call's arguments are freed once this returns -
        # read on the thread, the folder came out as garbage
        wanted = options_for(method, title, opts)
        pid = uuid.uuid4().hex
        self.requests[handle] = pid
        reg = (
            conn.register_object(handle, NODE.interfaces[1], self.call, None, None)
            if handle and handle != "/"
            else 0
        )
        threading.Thread(
            target=self.ask, args=(inv, wanted, pid, handle, reg), daemon=True
        ).start()

    def ask(self, inv, wanted, pid, handle, reg):
        # base64: `qs ipc call` splits its arguments at commas, and JSON is full of them
        import base64

        want = base64.b64encode(json.dumps(wanted).encode()).decode()
        try:
            # the picker may be busy (another app asked): ask again until it takes
            # this one. A bound matters: an answer that stays busy forever must
            # fail the request, not hang the app's Open dialog indefinitely.
            picked = False
            for _ in range(600):
                qs("portalPick", pid, want)
                time.sleep(0.15)
                got = qs("portalResult", pid)
                if got and json.loads(got).get("busy"):
                    time.sleep(0.5)
                    continue
                picked = True
                break
            if not picked:
                answer = {"failed": True}
            else:
                while True:
                    if handle not in self.requests:
                        answer = {"cancelled": True}
                        break
                    got = qs("portalResult", pid)
                    if got:
                        answer = json.loads(got)
                        if not answer.get("busy"):
                            break
                    time.sleep(0.2)
        except (OSError, subprocess.TimeoutExpired, ValueError):
            answer = {"failed": True}
        self.requests.pop(handle, None)
        if reg:
            GLib.idle_add(lambda: self.conn.unregister_object(reg) and False)
        if answer.get("paths"):
            inv.return_value(
                GLib.Variant(
                    "(ua{sv})",
                    (
                        0,
                        {"uris": GLib.Variant("as", [uri(p) for p in answer["paths"]])},
                    ),
                )
            )
        else:
            inv.return_value(
                GLib.Variant("(ua{sv})", (2 if answer.get("failed") else 1, {}))
            )

    def prop(self, conn, sender, path, iface, name):
        return GLib.Variant("u", 3) if name == "version" else None


def main() -> int:
    loop = GLib.MainLoop()

    def acquired(conn, name):
        b = Backend(conn)
        conn.register_object(PATH, NODE.interfaces[0], b.call, b.prop, None)

    Gio.bus_own_name(
        Gio.BusType.SESSION,
        NAME,
        Gio.BusNameOwnerFlags.NONE,
        acquired,
        None,
        lambda *a: loop.quit(),
    )
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
