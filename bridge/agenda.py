#!/usr/bin/env python3
"""agenda — the person's coming events, from Evolution Data Server, as JSON.

    agenda.py [DAYS]                    events from the start of today to DAYS
                                        ahead (7), sorted by start
    agenda.py add '<json>'              create an event (see below)
    agenda.py edit '<json>'             change summary/location of an event
    agenda.py delete '<json>'           delete an event
    {"summary": "Standup", "start": 1761715800, "end": 1761719400,
     "location": "", "allDay": false, "calendar": "Personal", "uid": "..."}

The first form prints a list like
    [{"start": 1761715800, "end": 1761719400, "summary": "Standup",
      "location": "", "calendar": "Personal", "allDay": false,
      "uid": "..."}, …] sorted by start; [] when there is nothing.
Exit 2 when there is no calendar service at all (no EDS bindings or
registry) — not the same as an empty calendar. Exit 3 on bad input.
The write forms print {"ok": true} on success.

The same calendars GNOME Calendar and Chronoa use: every enabled EDS calendar
source (the local "Personal" one, and any online account). Recurring events
are expanded into their occurrences (generate_instances), so the weekly
meeting shows on the day it happens. Writing uses ECal.Client.create_object_
sync / modify_object_sync / remove_object_sync, contructing the VEVENT from
an iCalendar string (no TZID: floating local times, like a wall clock).
This is the same approach as Chronoa's eds_calendar.

When EDS bindings or the registry are unavailable (exit 2), callers fall
back to Chronoa's calendar_edit skill via a Bridge "ask" (see Agenda.qml);
this script never shells out to GNOME Calendar.
"""

from __future__ import annotations

import json
import sys
import time


def bindings():
    import gi
    try:
        gi.require_version("ECal", "2.0")
        gi.require_version("EDataServer", "1.2")
    except ValueError as exc:
        # No EDS bindings in this environment: that is "no calendar service"
        # (exit 2), not bad input, so main() must not see a ValueError here.
        raise RuntimeError(f"ECal/EDataServer bindings unavailable: {exc}") from exc
    for v in ("4.0", "3.0"):
        try:
            gi.require_version("ICalGLib", v)
            break
        except ValueError:
            continue
    from gi.repository import ECal, EDataServer, ICalGLib  # noqa: E402
    return ECal, EDataServer, ICalGLib


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


def _clients(timeout: int = 10):
    ECal, EDataServer, _ = bindings()
    registry = EDataServer.SourceRegistry.new_sync(None)
    out = []
    for source in registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR):
        if not source.get_enabled():
            continue
        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, timeout, None)
        except Exception:  # noqa: BLE001 - one broken account must not hide the others
            continue
        out.append((source.get_display_name(), client))
    return out


def events(start: float, end: float, timeout: int = 10) -> list[dict]:
    out: list[dict] = []
    for name, client in _clients(timeout):
        def collect(icomp, istart, iend, *_args, _name=name):
            out.append({"start": timet(istart), "end": timet(iend), "summary": icomp.get_summary() or "(no title)",
                        "location": icomp.get_location() or "", "calendar": _name,
                        "allDay": bool(getattr(istart, "is_date", lambda: False)()),
                        "uid": icomp.get_uid() or ""})
            return True
        try:
            client.generate_instances_sync(int(start), int(end), None, collect)
        except Exception:  # noqa: BLE001
            continue
    return sorted(out, key=lambda e: e["start"])


def _fmt_local(ts: float, all_day: bool) -> str:
    lt = time.localtime(int(ts))
    return time.strftime("%Y%m%d" if all_day else "%Y%m%dT%H%M%S", lt)


def _ical_text(payload: dict) -> str:
    start = int(payload["start"])
    end = int(payload["end"])
    if start >= end:
        raise ValueError("end must be after start")
    summary = (payload.get("summary") or "").strip()
    if not summary:
        raise ValueError("an event needs a title")
    all_day = bool(payload.get("allDay", False))
    uid = payload.get("uid") or f"shani-{time.time_ns()}@shanios"
    location = (payload.get("location") or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")
    summary = summary.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//ShaniOS//agenda//EN",
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"DTSTAMP:{stamp}",
        f"DTSTART;VALUE={'DATE' if all_day else 'DATE-TIME'}:{_fmt_local(start, all_day)}",
        f"DTEND;VALUE={'DATE' if all_day else 'DATE-TIME'}:{_fmt_local(end, all_day)}",
        f"SUMMARY:{summary}",
    ]
    if location:
        lines.append(f"LOCATION:{location}")
    lines += ["END:VEVENT", "END:VCALENDAR"]
    return "\r\n".join(lines) + "\r\n"


def _pick_client(payload: dict):
    clients = _clients()
    if not clients:
        raise RuntimeError("no calendar source")
    want = (payload.get("calendar") or "").strip()
    if want:
        for name, client in clients:
            if name == want:
                return client
    return clients[0][1]


def write_event(action: str, payload: dict) -> dict:
    """add / edit / delete over EDS. Edit re-composes the whole event from
    the payload (start/end, summary, location) and modifies by UID (a
    recurring series is replaced as a series). Raises RuntimeError without
    EDS."""
    _, _, ICalGLib = bindings()
    client = _pick_client(payload)
    if action == "add":
        text = _ical_text(payload)
        # ICalGLib's from-string constructor is the portable way to build an
        # event with DTSTART/DTEND without guessing TimeT construction.
        comp = ICalGLib.component_new_from_ical_string(text)
        if comp is None:
            raise RuntimeError("ICalGLib has no from-string constructor")
        uid = client.create_object_sync(comp, True, None)
        return {"ok": True, "uid": uid or payload.get("uid", "")}
    # edit / delete need the existing component, by UID
    uid = (payload.get("uid") or "").strip()
    if not uid:
        raise ValueError("edit and delete need a uid")
    comp = client.get_object_sync(uid, None)
    if comp is None:
        raise ValueError(f"no event with uid {uid}")
    if action == "delete":
        client.remove_object_sync(comp, False, None)
        return {"ok": True}
    if action == "edit":
        # Re-compose the whole event: start/end and summary/location all
        # come from the payload, so the iCalendar text is the source of
        # truth and modify_object_sync just stores it.
        merged = dict(payload)
        merged["uid"] = uid
        text = _ical_text(merged)
        new_comp = ICalGLib.component_new_from_ical_string(text)
        if new_comp is None:
            raise RuntimeError("ICalGLib has no from-string constructor")
        client.modify_object_sync(new_comp, False, None)
        return {"ok": True, "uid": uid}
    raise ValueError(f"unknown action {action}")


def main(argv: list[str]) -> int:
    if len(argv) > 1 and argv[1] in ("add", "edit", "delete"):
        if len(argv) < 3:
            print("usage: agenda.py add|edit|delete '<json>'", file=sys.stderr)
            return 3
        try:
            payload = json.loads(argv[2])
            if not isinstance(payload, dict):
                raise ValueError("expected a JSON object")
        except (json.JSONDecodeError, ValueError) as exc:
            print(f"Invalid argument: {exc}", file=sys.stderr)
            return 3
        try:
            print(json.dumps(write_event(argv[1], payload)))
        except ValueError as exc:
            print(f"agenda: {exc}", file=sys.stderr)
            return 3
        except Exception as exc:  # noqa: BLE001 - no bindings, or the registry did not answer
            print(f"agenda: no calendar service ({exc})", file=sys.stderr)
            return 2
        return 0
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
