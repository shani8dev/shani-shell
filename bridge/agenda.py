#!/usr/bin/env python3
"""agenda — the person's coming events, from Evolution Data Server, as JSON.

    agenda.py [DAYS]          events from the start of today to DAYS ahead (7)

[{"start": 1761715800, "end": 1761719400, "summary": "Standup", "location": "",
  "calendar": "Personal", "allDay": false}, …] sorted by start; [] when there
is nothing. Exit 2 when there is no calendar service at all (no EDS bindings
or registry) — not the same as an empty calendar.

The same calendars GNOME Calendar and Chronoa use: every enabled EDS calendar
source (the local "Personal" one, and any online account). Recurring events
are expanded into their occurrences (generate_instances), so the weekly
meeting shows on the day it happens. The approach is Chronoa's eds_calendar.
"""

from __future__ import annotations

import json
import sys
import time


def bindings():
    import gi
    gi.require_version("ECal", "2.0")
    gi.require_version("EDataServer", "1.2")
    for v in ("4.0", "3.0"):
        try:
            gi.require_version("ICalGLib", v)
            break
        except ValueError:
            continue
    from gi.repository import ECal, EDataServer  # noqa: E402
    return ECal, EDataServer


def timet(t) -> float:
    for name in ("as_timet", "as_timet_with_zone"):
        fn = getattr(t, name, None)
        if fn is None:
            continue
        try:
            return float(fn() if name == "as_timet" else fn(t.get_timezone()))
        except TypeError:
            continue
    return 0.0


def events(start: float, end: float, timeout: int = 10) -> list[dict]:
    ECal, EDataServer = bindings()
    registry = EDataServer.SourceRegistry.new_sync(None)
    out: list[dict] = []
    for source in registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR):
        if not source.get_enabled():
            continue
        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, timeout, None)
        except Exception:  # noqa: BLE001 - one broken account must not hide the others
            continue

        def collect(icomp, istart, iend, *_args, _name=source.get_display_name()):
            out.append({"start": timet(istart), "end": timet(iend), "summary": icomp.get_summary() or "(no title)",
                        "location": icomp.get_location() or "", "calendar": _name,
                        "allDay": bool(getattr(istart, "is_date", lambda: False)())})
            return True
        try:
            client.generate_instances_sync(int(start), int(end), None, collect)
        except Exception:  # noqa: BLE001
            continue
    return sorted(out, key=lambda e: e["start"])


def main(argv: list[str]) -> int:
    days = int(argv[1]) if len(argv) > 1 and argv[1].isdigit() else 7
    now = time.localtime()
    today = time.mktime((now.tm_year, now.tm_mon, now.tm_mday, 0, 0, 0, 0, 0, -1))
    try:
        print(json.dumps(events(today, today + days * 86400)))
    except Exception as exc:  # noqa: BLE001 - no bindings, or the registry did not answer
        print(f"agenda: no calendar service ({exc})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
