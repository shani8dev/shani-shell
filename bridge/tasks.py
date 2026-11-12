#!/usr/bin/env python3
"""tasks — the person's to-do lists, from Evolution Data Server, as JSON.

    tasks.py                    [{"uid", "summary", "due", "done", "list", "priority", "notes"}]
                                every task of every enabled task list; due is
                                seconds since the epoch (0: none)
    tasks.py lists              [{"name", "uid", "readOnly"}]
    tasks.py add '<json>'       {"summary", "due"?, "list"?, "notes"?, "priority"?}
    tasks.py done '<json>'      {"uid", "list", "done": true|false}
    tasks.py edit '<json>'      {"uid", "list", "summary"?, "due"?, "notes"?}
    tasks.py delete '<json>'    {"uid", "list"}

The same task lists GNOME's Endeavour, Thunderbird and Chronoa use: EDS's
"Personal" one and any online account's. Writes print {"ok": true, "uid": …}.
Exit 2: no task service here (no EDS bindings or registry); exit 3: bad input.
"""
from __future__ import annotations

import json
import sys
import time
import uuid


def bindings():
    import gi
    try:
        gi.require_version("ECal", "2.0")
        gi.require_version("EDataServer", "1.2")
    except ValueError as exc:
        raise RuntimeError(f"ECal/EDataServer bindings unavailable: {exc}") from exc
    for v in ("4.0", "3.0"):
        try:
            gi.require_version("ICalGLib", v)
            break
        except ValueError:
            continue
    from gi.repository import ECal, EDataServer, ICalGLib  # noqa: E402
    return ECal, EDataServer, ICalGLib


def _sources():
    _, EDataServer, _ = bindings()
    registry = EDataServer.SourceRegistry.new_sync(None)
    return [s for s in registry.list_sources(EDataServer.SOURCE_EXTENSION_TASK_LIST) if s.get_enabled()]


def _clients(timeout: int = 10):
    ECal, _, _ = bindings()
    out = []
    for source in _sources():
        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.TASKS, timeout, None)
        except Exception:  # noqa: BLE001 - one broken account must not hide the others
            continue
        out.append((source.get_display_name(), source, client))
    return out


def _client(name: str):
    clients = _clients()
    if not clients:
        raise RuntimeError("no task list")
    for n, _source, c in clients:
        if n == name:
            return c
    return clients[0][2]


def _timet(t) -> float:
    if t is None:
        return 0.0
    try:
        if hasattr(t, "is_null_time") and t.is_null_time():
            return 0.0
    except Exception:  # noqa: BLE001
        pass
    for name in ("as_timet", "as_timet_with_zone"):
        fn = getattr(t, name, None)
        if fn is None:
            continue
        try:
            return float(fn() if name == "as_timet" else fn(t.get_timezone()))
        except TypeError:
            continue
    return 0.0


def _status_done(icomp, ICalGLib) -> bool:
    try:
        return icomp.get_status() == ICalGLib.PropertyStatus.COMPLETED
    except Exception:  # noqa: BLE001
        return False


def _prop_text(icomp, ICalGLib, kind) -> str:
    prop = icomp.get_first_property(kind)
    return prop.get_value_as_string() if prop is not None else ""


def tasks() -> list[dict]:
    _, _, ICalGLib = bindings()
    out = []
    for name, _source, client in _clients():
        try:
            ok, comps = client.get_object_list_sync("#t", None)
        except Exception:  # noqa: BLE001
            continue
        for icomp in comps or []:
            due = icomp.get_due() if hasattr(icomp, "get_due") else None
            prio = icomp.get_first_property(ICalGLib.PropertyKind.PRIORITY_PROPERTY)
            out.append({
                "uid": icomp.get_uid() or "", "summary": icomp.get_summary() or "(no title)",
                "due": _timet(due), "done": _status_done(icomp, ICalGLib), "list": name,
                "priority": int(prio.get_priority()) if prio is not None else 0,
                "notes": icomp.get_description() or "",
            })
    # open first, then by due date (none last), then by name
    return sorted(out, key=lambda t: (t["done"], t["due"] == 0, t["due"], t["summary"].lower()))


def task_lists() -> list[dict]:
    return sorted(({"name": s.get_display_name() or "", "uid": s.get_uid() or "", "readOnly": not s.get_writable()} for s in _sources()),
                  key=lambda x: x["name"].lower())


def _ical_due(ts: float) -> str:
    # a date-time due in local wall-clock time (floating), like the agenda's events
    return time.strftime("%Y%m%dT%H%M%S", time.localtime(ts))


def _esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def write(action: str, p: dict) -> dict:
    _, _, ICalGLib = bindings()
    if action == "add":
        summary = str(p.get("summary") or "").strip()
        if not summary:
            raise ValueError("a task needs a summary")
        uid = str(uuid.uuid4())
        lines = ["BEGIN:VTODO", f"UID:{uid}", "DTSTAMP:" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()),
                 f"SUMMARY:{_esc(summary)}", "STATUS:NEEDS-ACTION"]
        if float(p.get("due") or 0) > 0:
            lines.append("DUE:" + _ical_due(float(p["due"])))
        if p.get("notes"):
            lines.append("DESCRIPTION:" + _esc(str(p["notes"])))
        if int(p.get("priority") or 0) > 0:
            lines.append(f"PRIORITY:{int(p['priority'])}")
        lines.append("END:VTODO")
        comp = ICalGLib.Component.new_from_string("\r\n".join(lines))
        client = _client(str(p.get("list") or ""))
        ok, new_uid = client.create_object_sync(comp, 0, None)
        return {"ok": True, "uid": new_uid or uid}
    uid = str(p.get("uid") or "")
    if not uid:
        raise ValueError("which task? (uid)")
    client = _client(str(p.get("list") or ""))
    if action == "delete":
        ECal = bindings()[0]
        client.remove_object_sync(uid, None, ECal.ObjModType.THIS, 0, None)
        return {"ok": True, "uid": uid}
    ok, comp = client.get_object_sync(uid, None, None)
    if action == "done":
        done = bool(p.get("done", True))
        comp.set_status(ICalGLib.PropertyStatus.COMPLETED if done else ICalGLib.PropertyStatus.NEEDSACTION)
        old = comp.get_first_property(ICalGLib.PropertyKind.COMPLETED_PROPERTY)
        if old is not None:
            comp.remove_property(old)
        if done:
            comp.add_property(ICalGLib.Property.new_from_string("COMPLETED:" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())))
    elif action == "edit":
        if p.get("summary"):
            comp.set_summary(str(p["summary"]))
        if "notes" in p:
            comp.set_description(str(p["notes"]))
        if "due" in p:
            old = comp.get_first_property(ICalGLib.PropertyKind.DUE_PROPERTY)
            if old is not None:
                comp.remove_property(old)
            if float(p["due"] or 0) > 0:
                comp.add_property(ICalGLib.Property.new_from_string("DUE:" + _ical_due(float(p["due"]))))
    else:
        raise ValueError(f"unknown action {action}")
    ECal = bindings()[0]
    client.modify_object_sync(comp, ECal.ObjModType.THIS, 0, None)
    return {"ok": True, "uid": uid}


def main(argv: list[str]) -> int:
    try:
        if len(argv) > 1 and argv[1] in ("add", "done", "edit", "delete"):
            try:
                payload = json.loads(argv[2]) if len(argv) > 2 else None
                if not isinstance(payload, dict):
                    raise ValueError("expected a JSON object")
            except (json.JSONDecodeError, ValueError) as exc:
                print(f"tasks: {exc}", file=sys.stderr)
                return 3
            try:
                print(json.dumps(write(argv[1], payload)))
            except ValueError as exc:
                print(f"tasks: {exc}", file=sys.stderr)
                return 3
            return 0
        print(json.dumps(task_lists() if len(argv) > 1 and argv[1] == "lists" else tasks()))
        return 0
    except Exception as exc:  # noqa: BLE001 - no bindings, or the registry did not answer
        print(f"tasks: no task service ({exc})", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
