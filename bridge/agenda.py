#!/usr/bin/env python3
"""agenda — the person's coming events, from Evolution Data Server, as JSON.

    agenda.py [DAYS]                    events from the start of today to DAYS
                                        ahead (7), sorted by start
    agenda.py range START END           events in [START, END], epoch seconds
                                        (the shell's loadRange; DAYS kept for
                                         the old callers)
    agenda.py calendars                 the calendars there are:
                                        [{"name", "uid", "color", "readOnly"}]
    agenda.py add '<json>'              create an event (see below)
    agenda.py edit '<json>'             change summary/location/description of an event
    agenda.py delete '<json>'           delete an event
    agenda.py import FILE [CALENDAR]    an .ics file's events added (an invitation, a timetable)
    agenda.py accounts                  online accounts: [{"uid", "name", "url", "user", "calendars"}]
    agenda.py account-add               {"name", "url", "user", "password"} on stdin: a CalDAV
                                        account (EDS finds its calendars)
    agenda.py account-remove UID        that account and its calendars, from this computer
    {"summary": "Standup", "start": 1761715800, "end": 1761719400,
     "location": "", "allDay": false, "calendar": "Personal", "uid": "...",
     "description": "agenda notes", "rrule": "FREQ=WEEKLY;BYDAY=MO",
     "alarm": 10, "timezone": "Europe/London"}

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
import os
import re
import subprocess
import sys
import time
from datetime import datetime

try:  # Python 3.9+; on older runtimes the chosen zone falls back to local
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None


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
            client = ECal.Client.connect_sync(
                source, ECal.ClientSourceType.EVENTS, timeout, None
            )
        except Exception:  # noqa: BLE001 - one broken account must not hide the others
            continue
        out.append((source.get_display_name(), client))
    return out


def calendars() -> list[dict]:
    """Every enabled calendar source, whether or not it has an event this week:
    what the Calendar's "show" and "new events go to" choices are made from."""
    _, EDataServer, _ = bindings()
    registry = EDataServer.SourceRegistry.new_sync(None)
    out = []
    for source in registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR):
        if not source.get_enabled():
            continue
        color = ""
        try:
            color = (
                source.get_extension(EDataServer.SOURCE_EXTENSION_CALENDAR).get_color()
                or ""
            )
        except Exception:  # noqa: BLE001 - a source without the extension's colour
            pass
        out.append(
            {
                "name": source.get_display_name() or "",
                "uid": source.get_uid() or "",
                "color": color,
                "readOnly": not source.get_writable(),
            }
        )
    return sorted(out, key=lambda c: c["name"].lower())


def events(start: float, end: float, timeout: int = 10) -> list[dict]:
    out: list[dict] = []
    for name, client in _clients(timeout):

        def collect(icomp, istart, iend, *_args, _name=name):
            extras = _event_extras(icomp)
            out.append(
                {
                    "start": timet(istart),
                    "end": timet(iend),
                    "summary": icomp.get_summary() or "(no title)",
                    "location": icomp.get_location() or "",
                    "calendar": _name,
                    "allDay": bool(getattr(istart, "is_date", lambda: False)()),
                    "uid": icomp.get_uid() or "",
                    "organizer": "",  # filled when libical exposes attendee data
                    "needsAction": False,
                    "description": extras["description"],
                    "rrule": extras["rrule"],
                    "alarm": extras["alarm"],
                    "timezone": extras["timezone"],
                }
            )
            return True

        try:
            client.generate_instances_sync(int(start), int(end), None, collect)
        except Exception:  # noqa: BLE001
            continue
    return sorted(out, key=lambda e: e["start"])


def _fmt_local(ts: float, all_day: bool) -> str:
    lt = time.localtime(int(ts))
    return time.strftime("%Y%m%d" if all_day else "%Y%m%dT%H%M%S", lt)


def _ical_escape(value: str) -> str:
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )


def _unfold_lines(text: str) -> list[str]:
    """Unfold iCalendar continuation lines, normalise newlines."""
    flat = text.replace("\r\n", "\n").replace("\r", "\n")
    return re.sub(r"\n[ \t]", "", flat).split("\n")


def _unescape_ical(value: str) -> str:
    return re.sub(
        r"\\([nN,;\\])",
        lambda m: "\n" if m.group(1) in "nN" else m.group(1),
        value,
    )


def _prop(text: str, name: str) -> str:
    """First property of this name in an iCalendar text, unescaped."""
    for line in _unfold_lines(text):
        key = line.split(";", 1)[0].split(":", 1)[0].strip().upper()
        if key == name:
            return _unescape_ical(line.partition(":")[2])
    return ""


def _event_extras(icomp) -> dict:
    """Read the fields the editor does not own, so a detail view can show
    them and an edit can keep them. String parsing keeps this independent of
    which ICalGLib getters a given version happens to expose."""
    out = {"description": "", "rrule": "", "alarm": 0, "timezone": ""}
    try:
        _, _, ICalGLib = bindings()
        text = ICalGLib.component_as_ical_string(icomp) or ""
    except Exception:  # noqa: BLE001 - extras are best-effort
        return out
    out["description"] = _prop(text, "DESCRIPTION")
    out["rrule"] = _prop(text, "RRULE")
    trigger = _prop(text, "TRIGGER").strip()
    m = re.fullmatch(r"-PT(?:(\d+)H)?(?:(\d+)M)?", trigger)
    if m:
        out["alarm"] = int(m.group(1) or 0) * 60 + int(m.group(2) or 0)
    for line in _unfold_lines(text):
        head = line.partition(":")[0]
        if head.upper().startswith("DTSTART"):
            z = re.search(r"TZID=([^;:]+)", head, re.I)
            if z:
                out["timezone"] = z.group(1).strip('"')
                break
    return out


def _safe_zone(value) -> str:
    zone = str(value or "").strip()
    return zone if len(zone) <= 64 and re.fullmatch(r"[A-Za-z0-9_+\-/]+", zone) else ""


def _safe_rrule(value) -> str:
    rule = str(value or "").strip().upper()
    if not re.fullmatch(r"[A-Z0-9,;=]+", rule) or len(rule) > 200:
        return ""
    return rule if rule.startswith("FREQ=") else ""


def _safe_alarm(value) -> int:
    try:
        return max(0, min(1440, int(value)))
    except (TypeError, ValueError):
        return 0


def _fmt_in_zone(ts: float, all_day: bool, zone: str) -> str:
    """Wall-clock time in the event's own zone; local when it has none."""
    if zone and ZoneInfo is not None and not all_day:
        try:
            return datetime.fromtimestamp(int(ts), ZoneInfo(zone)).strftime(
                "%Y%m%d" if all_day else "%Y%m%dT%H%M%S"
            )
        except Exception:  # noqa: BLE001 - unknown zone falls back to local
            pass
    return _fmt_local(ts, all_day)


def _valarm_lines(minutes: int, summary: str) -> list[str]:
    if minutes <= 0:
        return []
    if minutes % 60 == 0:
        trigger = "-PT%dH" % (minutes // 60)
    else:
        trigger = "-PT%dM" % minutes
    return [
        "BEGIN:VALARM",
        "TRIGGER:" + trigger,
        "ACTION:DISPLAY",
        "DESCRIPTION:" + _ical_escape(summary or "Event reminder"),
        "END:VALARM",
    ]


def _strip_valarms(lines: list[str]) -> list[str]:
    out: list[str] = []
    depth = 0
    for line in lines:
        head = line.strip().upper()
        if head.startswith("BEGIN:VALARM"):
            depth += 1
            continue
        if head.startswith("END:VALARM"):
            depth = max(0, depth - 1)
            continue
        if depth == 0:
            out.append(line)
    return out


def _insert_before_end(lines: list[str], new_lines: list[str]) -> None:
    idx = next(
        (i for i, line in enumerate(lines) if line.upper().startswith("END:VEVENT")),
        len(lines),
    )
    lines[idx:idx] = new_lines


def _replace_event_fields(text: str, payload: dict) -> str:
    """Change only the fields the editor owns, keeping RRULE, DESCRIPTION,
    attendees, alarms and every other line of an existing VEVENT intact.
    A field is touched only when its key is in the payload: an edit that does
    not offer it must not erase it."""
    start = int(payload["start"])
    end = int(payload["end"])
    if start >= end:
        raise ValueError("end must be after start")
    summary = (payload.get("summary") or "").strip()
    if not summary:
        raise ValueError("an event needs a title")
    all_day = bool(payload.get("allDay", False))
    value = "DATE" if all_day else "DATE-TIME"
    location = (payload.get("location") or "").strip()
    zone = _safe_zone(payload.get("timezone"))
    tz_param = f";TZID={zone}" if zone and not all_day else ""

    def dt(kind: str) -> str:
        return f"{kind};VALUE={value}{tz_param}:" + _fmt_in_zone(
            start if kind == "DTSTART" else end, all_day, zone
        )

    replacements = {
        "DTSTART": dt("DTSTART"),
        "DTEND": dt("DTEND"),
        "SUMMARY": f"SUMMARY:{_ical_escape(summary)}",
        "LOCATION": f"LOCATION:{_ical_escape(location)}",
    }
    if "description" in payload:
        desc = str(payload.get("description") or "").strip()
        replacements["DESCRIPTION"] = (
            ("DESCRIPTION:" + _ical_escape(desc)) if desc else ""
        )
    if "rrule" in payload:
        rule = _safe_rrule(payload.get("rrule"))
        replacements["RRULE"] = ("RRULE:" + rule) if rule else ""
    # editing the alarm rewrites just the VALARM blocks, never RRULE/attendees
    alarms = None
    if "alarm" in payload:
        alarms = _valarm_lines(_safe_alarm(payload.get("alarm")), summary)

    lines = _unfold_lines(text)
    if alarms is not None:
        lines = _strip_valarms(lines)
    out: list[str] = []
    seen: set[str] = set()
    for line in lines:
        key = line.split(";", 1)[0].split(":", 1)[0].strip().upper()
        if key in replacements:
            rep = replacements[key]
            if key not in seen and rep and (key != "LOCATION" or location):
                out.append(rep)
            seen.add(key)
        else:
            out.append(line)
    out = [line for line in out if line.strip()]
    if alarms is not None and alarms:
        _insert_before_end(out, alarms)
    for key in ("LOCATION", "DESCRIPTION"):
        rep = replacements.get(key, "")
        if key not in seen and rep:
            _insert_before_end(out, [rep])
    return "\r\n".join(out) + "\r\n"


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
    location = (payload.get("location") or "").strip()
    description = str(payload.get("description") or "").strip()
    zone = _safe_zone(payload.get("timezone"))
    tz_param = f";TZID={zone}" if zone and not all_day else ""
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    attendees = [
        str(a).strip() for a in (payload.get("attendees") or []) if str(a).strip()
    ]
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//ShaniOS//agenda//EN",
    ]
    if attendees:
        # METHOD:REQUEST + ORGANIZER + ATTENDEE lines: EDS/Evolution's iTIP
        # delivery reads these.
        lines.append("METHOD:REQUEST")
    lines += [
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"SEQUENCE:{int(payload.get('sequence', 0))}",
        f"DTSTAMP:{stamp}",
        f"DTSTART;VALUE={'DATE' if all_day else 'DATE-TIME'}{tz_param}:{_fmt_in_zone(start, all_day, zone)}",
        f"DTEND;VALUE={'DATE' if all_day else 'DATE-TIME'}{tz_param}:{_fmt_in_zone(end, all_day, zone)}",
        f"SUMMARY:{_ical_escape(summary)}",
    ]
    if attendees:
        try:
            ECal, _, _ = bindings()
            name, addr = ECal.util_get_default_name_and_address()
        except Exception:  # noqa: BLE001
            name, addr = "", ""
        org = (";CN=" + _ical_escape(name)) if name else ""
        lines.append(
            f"ORGANIZER{org}:mailto:{addr}"
            if addr
            else f"ORGANIZER:mailto:shani@localhost"
        )
        for a in attendees:
            esc = _ical_escape(a)
            lines.append(
                f"ATTENDEE;CN={esc};ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:{a}"
            )
    if location:
        lines.append(f"LOCATION:{_ical_escape(location)}")
    if description:
        lines.append(f"DESCRIPTION:{_ical_escape(description)}")
    rule = _safe_rrule(payload.get("rrule"))
    if rule:
        lines.append(f"RRULE:{rule}")
    lines += _valarm_lines(_safe_alarm(payload.get("alarm")), summary)
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
    """add / edit / delete over EDS. Edit replaces only the fields the
    editor owns (start/end, summary, location and, when supplied,
    description, repeat, alarm and timezone) and keeps the rest of the
    VEVENT, by UID. Raises RuntimeError without EDS."""
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
        result = {"ok": True, "uid": uid or payload.get("uid", "")}
        # Deliver meeting invitations via EDS's iTIP hook. Local calendars may
        # not support it: fall back to a mail draft with the .ics attached.
        attendees = [
            str(a).strip() for a in (payload.get("attendees") or []) if str(a).strip()
        ]
        if attendees:
            sent = False
            try:
                client.send_objects_sync(comp, ECal.OperationFlags.NONE, None)
                sent = True
            except Exception:  # noqa: BLE001
                pass
            if not sent:
                try:
                    import tempfile

                    fd, path = tempfile.mkstemp(suffix=".ics")
                    with os.fdopen(fd, "w") as fh:
                        fh.write(_ical_text(payload))
                    subprocess.Popen(
                        [
                            "xdg-email",
                            "--attach",
                            path,
                            "--subject",
                            "Invitation: " + (payload.get("summary") or ""),
                            "--body",
                            "You are invited.",
                            "--",
                        ]
                        + attendees
                    )
                    result["mailDraft"] = True
                except Exception:  # noqa: BLE001
                    result["inviteWarning"] = (
                        "Invitation stored, but no mail client opened"
                    )
        return result
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
        # Change only the fields the editor owns. Re-composing the whole
        # VEVENT from the payload would silently drop RRULE, DESCRIPTION,
        # ATTENDEE and VALARM lines on imported/recurring events.
        old_text = ICalGLib.component_as_ical_string(comp)
        text = _replace_event_fields(old_text, payload)
        new_comp = ICalGLib.component_new_from_ical_string(text)
        if new_comp is None:
            raise RuntimeError("ICalGLib has no from-string constructor")
        client.modify_object_sync(new_comp, False, None)
        return {"ok": True, "uid": uid}
    raise ValueError(f"unknown action {action}")


# ---- online calendar accounts (what GNOME Calendar was kept for): a CalDAV server -
#      Nextcloud, Fastmail, iCloud (app password), Radicale... - as an EDS WebDAV
#      collection: EDS itself finds the account's calendars (and address books)
#      and keeps them; the password is kept in the keyring by EDS's own call
def accounts() -> list[dict]:
    _, EDataServer, _ = bindings()
    registry = EDataServer.SourceRegistry.new_sync(None)
    out = []
    for s in registry.list_sources(EDataServer.SOURCE_EXTENSION_COLLECTION):
        col = s.get_extension(EDataServer.SOURCE_EXTENSION_COLLECTION)
        kids = [
            k.get_display_name()
            for k in registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)
            if k.get_parent() == s.get_uid()
        ]
        out.append(
            {
                "uid": s.get_uid(),
                "name": s.get_display_name(),
                "backend": col.get_backend_name() or "",
                "url": col.get_calendar_url() or "",
                "user": col.get_identity() or "",
                "calendars": kids,
            }
        )
    return out


def account_add(name: str, url: str, user: str, password: str) -> dict:
    from urllib.parse import urlsplit

    if not url.startswith(("https://", "http://")):
        raise ValueError("the address starts with https://")
    u = urlsplit(url)
    _, EDataServer, _ = bindings()
    registry = EDataServer.SourceRegistry.new_sync(None)
    src = EDataServer.Source.new(None, None)
    src.set_display_name(name or u.hostname or url)
    col = src.get_extension(EDataServer.SOURCE_EXTENSION_COLLECTION)
    col.set_backend_name("webdav")
    col.set_calendar_url(url)
    col.set_contacts_url(url)
    col.set_identity(user)
    col.set_calendar_enabled(True)
    col.set_contacts_enabled(True)
    auth = src.get_extension(EDataServer.SOURCE_EXTENSION_AUTHENTICATION)
    auth.set_host(u.hostname or "")
    auth.set_port(u.port or (443 if u.scheme == "https" else 80))
    auth.set_user(user)
    auth.set_method("plain/password")
    if u.scheme == "https":
        src.get_extension(EDataServer.SOURCE_EXTENSION_SECURITY).set_method("tls")
    # what the server says first: a wrong address or password is said now, not later
    if hasattr(EDataServer, "webdav_discover_sources_sync"):
        creds = EDataServer.NamedParameters.new()
        creds.set(EDataServer.SOURCE_CREDENTIAL_USERNAME, user)
        creds.set(EDataServer.SOURCE_CREDENTIAL_PASSWORD, password)
        try:
            found = EDataServer.webdav_discover_sources_sync(
                src, url, EDataServer.WebDAVDiscoverSupports.EVENTS, creds, None
            )
        except Exception as exc:  # noqa: BLE001 - the server's answer
            raise ValueError("the server said no: %s" % exc) from exc
        # PyGObject returns (ok, cert_pem, cert_errors, discovered_sources,
        # user_addresses): index 1 is the certificate, not the calendars.
        n = len(
            found[3] if isinstance(found, tuple) and len(found) > 3 and found[3] else []
        )
    else:
        n = -1
    # the password first: committed before it is kept, EDS can start the account,
    # find no password, and wait for a prompt nobody shows (seen: its calendars
    # never came). Stored under the new source's own uid, then committed.
    src.store_password_sync(password, True, None)
    registry.commit_source_sync(src, None)
    return {"ok": True, "uid": src.get_uid(), "found": n}


def import_ics(path: str, calendar: str = "") -> dict:
    """An .ics file's events (an invitation, a timetable) into a calendar - the one
    named, else the first writable (Personal). Each VEVENT is added as it is."""
    _, _, ICalGLib = bindings()
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    comp = ICalGLib.Component.new_from_string(text)
    if comp is None:
        raise ValueError("not a calendar file")
    events = []
    if comp.isa() == ICalGLib.ComponentKind.VEVENT_COMPONENT:
        events = [comp]
    else:
        sub = comp.get_first_component(ICalGLib.ComponentKind.VEVENT_COMPONENT)
        while sub is not None:
            events.append(sub)
            sub = comp.get_next_component(ICalGLib.ComponentKind.VEVENT_COMPONENT)
    if not events:
        raise ValueError("no events in it")
    # straight to the one it goes to - your own Personal calendar unless one is named
    # (connecting to every calendar first cost seconds, and an offline account more)
    ECal, EDataServer, _ = bindings()
    registry = EDataServer.SourceRegistry.new_sync(None)
    source = None
    if calendar:
        source = next(
            (
                s
                for s in registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)
                if s.get_display_name() == calendar
            ),
            None,
        )
    if source is None:
        source = registry.ref_builtin_calendar()
    if source is None:
        raise RuntimeError("no calendar to add them to")
    client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, 10, None)
    first = None
    for ev in events:
        client.create_object_sync(ev.clone() if hasattr(ev, "clone") else ev, 0, None)
        start = ev.get_dtstart()
        if start is not None and first is None:
            first = timet(start)
    return {"ok": True, "added": len(events), "first": first}


def account_remove(uid: str) -> dict:
    _, EDataServer, _ = bindings()
    registry = EDataServer.SourceRegistry.new_sync(None)
    s = registry.ref_source(uid)
    if s is None or not s.has_extension(EDataServer.SOURCE_EXTENSION_COLLECTION):
        raise ValueError("no such account")
    s.remove_sync(None)
    return {"ok": True}


def range_window(argv: list[str]) -> tuple[float, float]:
    """The [start, end) epoch-second window this invocation asks for.

    `range START END` is the shell's loadRange; the bare DAYS form (default 7)
    stays for the old callers. Kept separate from events() so it is testable
    without EDS bindings.
    """
    if len(argv) > 1 and argv[1] == "range":
        if len(argv) < 4:
            raise ValueError("usage: agenda.py range START END")
        start, end = float(argv[2]), float(argv[3])
        if not end > start:
            raise ValueError("end must be after start")
        return start, end
    days = int(argv[1]) if len(argv) > 1 and argv[1].isdigit() else 7
    now = time.localtime()
    today = time.mktime((now.tm_year, now.tm_mon, now.tm_mday, 0, 0, 0, 0, 0, -1))
    return today, today + days * 86400


def main(argv: list[str]) -> int:
    if len(argv) > 2 and argv[1] == "import":
        try:
            print(json.dumps(import_ics(argv[2], argv[3] if len(argv) > 3 else "")))
            return 0
        except (OSError, ValueError) as exc:
            print(json.dumps({"error": str(exc)}))
            return 3
        except Exception as exc:  # noqa: BLE001
            print(json.dumps({"error": "no calendar service (%s)" % exc}))
            return 2
    if len(argv) > 1 and argv[1] in ("accounts", "account-add", "account-remove"):
        try:
            if argv[1] == "accounts":
                r = accounts()
            elif argv[1] == "account-add":
                d = json.loads(
                    sys.stdin.read() or "{}"
                )  # the password on stdin, never a command line
                r = account_add(
                    d.get("name", ""),
                    d.get("url", ""),
                    d.get("user", ""),
                    d.get("password", ""),
                )
            else:
                r = account_remove(argv[2] if len(argv) > 2 else "")
        except ValueError as exc:
            print(json.dumps({"error": str(exc)}))
            return 3
        except Exception as exc:  # noqa: BLE001 - no bindings, or the registry did not answer
            print(json.dumps({"error": "no calendar service (%s)" % exc}))
            return 2
        print(json.dumps(r))
        return 0
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
    if len(argv) > 1 and argv[1] == "calendars":
        try:
            print(json.dumps(calendars()))
        except Exception as exc:  # noqa: BLE001 - no bindings, or the registry did not answer
            print(f"agenda: no calendar service ({exc})", file=sys.stderr)
            return 2
        return 0
    try:
        start, end = range_window(argv)
    except ValueError as exc:
        print(f"agenda: {exc}", file=sys.stderr)
        return 3
    try:
        print(json.dumps(events(start, end)))
    except Exception as exc:  # noqa: BLE001 - no bindings, or the registry did not answer
        print(f"agenda: no calendar service ({exc})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
