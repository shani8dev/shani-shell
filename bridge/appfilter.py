#!/usr/bin/env python3
"""appfilter — the apps parental controls block for this person (malcontent).

malcontent keeps each account's app filter in AccountsService; GNOME's Parental
Controls (malcontent-control) sets it, and the desktop is the one to honour
it for apps that are not Flatpaks - GNOME Shell hides them, and so does this
shell's launcher and dock. Prints one JSON line:

  {"available": true, "blocked": ["foot", "org.mozilla.firefox"]}

(desktop ids, without ".desktop"), and with --watch another each time the
filter changes, waiting on the system bus in between. Without malcontent:
{"available": false, "blocked": []}.
"""

from __future__ import annotations

import json
import os
import sys


def blocked_ids(app_filter, apps) -> list[str]:
    out = []
    for a in apps:
        if not app_filter.is_appinfo_allowed(a):
            i = a.get_id() or ""
            out.append(i[:-len(".desktop")] if i.endswith(".desktop") else i)
    return sorted(set(out))


def main(argv: list[str]) -> int:
    try:
        import gi
        gi.require_version("Malcontent", "0")
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib, Malcontent
    except (ImportError, ValueError):
        print(json.dumps({"available": False, "blocked": []}), flush=True)
        return 0
    try:
        manager = Malcontent.Manager.new(Gio.bus_get_sync(Gio.BusType.SYSTEM))
    except GLib.Error as e:
        print(json.dumps({"available": False, "blocked": [], "error": e.message}), flush=True)
        return 0
    uid = os.getuid()
    last = [None]

    def report(*_args) -> None:
        try:
            f = manager.get_app_filter(uid, Malcontent.ManagerGetValueFlags.NONE, None)
            out = {"available": True, "blocked": blocked_ids(f, Gio.AppInfo.get_all())}
        except GLib.Error as e:
            # no filter stored, or AccountsService away: nothing is blocked
            out = {"available": True, "blocked": [], "error": e.message}
        # AccountsService tells of one change several times: say it once
        if out != last[0]:
            last[0] = out
            print(json.dumps(out), flush=True)

    report()
    if "--watch" not in argv:
        return 0
    manager.connect("app-filter-changed", lambda _m, changed_uid: changed_uid == uid and report())
    GLib.MainLoop().run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
