#!/usr/bin/env python3
"""agenda — the person's coming events, from Evolution Data Server, as JSON.

    agenda.py [DAYS]                    events from the start of today to DAYS
                                        ahead (7), sorted by start
    agenda.py calendars                 the calendars there are:
                                        [{"name", "uid", "color", "readOnly"}]
    agenda.py add '<json>'              create an event (see below)
    agenda.py edit '<json>'             change summary/location of an event
    agenda.py delete '<json>'           delete an event
    agenda.py import FILE [CALENDAR]    an .ics file's events added (an invitation, a timetable)
    agenda.py accounts                  online accounts: [{"uid", "name", "url", "user", "calendars"}]
    agenda.py account-add               {"name", "url", "user", "password"} on stdin: a CalDAV
                                        account (EDS finds its calendars)
    agenda.py account-remove UID        that account and its calendars, from this computer
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
import os
import subprocess
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
    location = (
        (payload.get("location") or "")
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )
    summary = (
        summary.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )
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
        # delivery reads these. Escaping like SUMMARY above.
        lines.append("METHOD:REQUEST")
    lines += [
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"SEQUENCE:{int(payload.get('sequence', 0))}",
        f"DTSTAMP:{stamp}",
        f"DTSTART;VALUE={'DATE' if all_day else 'DATE-TIME'}:{_fmt_local(start, all_day)}",
        f"DTEND;VALUE={'DATE' if all_day else 'DATE-TIME'}:{_fmt_local(end, all_day)}",
        f"SUMMARY:{summary}",
    ]
    if attendees:
        try:
            ECal, _, _ = bindings()
            name, addr = ECal.util_get_default_name_and_address()
        except Exception:  # noqa: BLE001
            name, addr = "", ""
        org = (";CN=" + name.replace(";", "\\;")) if name else ""
        lines.append(
            f"ORGANIZER{org}:mailto:{addr}"
            if addr
            else f"ORGANIZER:mailto:shani@localhost"
        )
        for a in attendees:
            esc = a.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
            lines.append(
                f"ATTENDEE;CN={esc};ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:{a}"
            )
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
