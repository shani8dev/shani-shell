#!/usr/bin/env python3
"""phone — calls, messages and devices for the shell's own windows.

Each command prints one JSON answer, as every other bridge here does. Reads
come from the same vendored backends the daemon uses, so a window and the
service never disagree about what a device is called or what was said.

    link.py state                     {backend, placesCalls, lines, devices}
    link.py devices                   [{id, name, paired, reachable, battery}]
    link.py calls                     [{id, line, number, name, direction, missed, when, seconds}]
    link.py contacts [query]          [{name, numbers, emails}]
    link.py messages [device]         [{thread, name, number, text, when, unread}]
    link.py thread <thread> [device]  [{text, when, incoming}]
    link.py read <thread>            {ok}
    link.py send <thread> <text>      {ok}
    link.py dial <number> [line]      {ok, line, error}
    link.py hangup [line]             {ok}
    link.py ring [device]             {ok, error}
    link.py share <device> <path>     {ok, error}

The phone backends are optional: every command that needs them answers
{"error": "…not installed"} rather than failing, so the window can say so.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

NOT_INSTALLED = "the phone backends are not installed"


def _module(name: str):
    """Import one piece of phone, or None when the package is not there."""
    try:
        return __import__(name, fromlist=["*"])
    except Exception:  # noqa: BLE001 - any import failure means "no link here"
        return None


phone = _module("phone.phone")
calls_log = _module("phone.calls_log")
contacts_mod = _module("phone.contacts")
lines = _module("phone.lines")


def _ok(error: str | None = None) -> dict:
    return {"ok": not error, "error": error or ""}


def _device(device) -> dict:
    battery = -1
    charging = False
    try:
        got = phone.battery(device)
        if got:
            battery, charging = int(got[0]), bool(got[1])
    except Exception:  # noqa: BLE001 - a battery that cannot be read is -1
        pass
    return {
        "id": device.id,
        "name": device.name,
        "paired": bool(device.paired),
        "reachable": bool(device.reachable),
        "battery": battery,
        "charging": charging,
    }


def _devices() -> list[dict]:
    if phone is None:
        return []
    try:
        return [_device(d) for d in phone.devices()]
    except Exception:  # noqa: BLE001
        return []


def _by_id(device_id: str):
    """The device with this id, from the same list the app shows."""
    for d in phone.devices() if phone else []:
        if d.id == device_id:
            return d
    return None


def _first_device() -> Any:
    """The first paired, reachable device — "the phone" when nothing is named."""
    for d in _devices():
        if d["paired"] and d["reachable"]:
            return _by_id(d["id"])
    return None


def cmd_state() -> dict:
    got_lines = []
    if lines is not None:
        try:
            got_lines = [
                str(x.get("id") or x.get("name") or "") for x in lines.available()
            ]
        except Exception:  # noqa: BLE001
            got_lines = []
    devices = _devices()
    return {
        "backend": (phone.backend() if phone else "") or "",
        "placesCalls": bool(phone.places_calls()) if phone else False,
        "lines": got_lines,
        "devices": len(devices),
        "phone": next(
            (d["name"] for d in devices if d["paired"] and d["reachable"]), ""
        ),
    }


def cmd_devices() -> list[dict]:
    return _devices()


def cmd_calls() -> list[dict]:
    if calls_log is None:
        return []
    try:
        rows = calls_log.rows()
    except Exception:  # noqa: BLE001
        return []
    out = []
    for r in rows:
        out.append(
            {
                "id": r.get("id", ""),
                "line": r.get("line", ""),
                "number": r.get("number", ""),
                "name": r.get("name", ""),
                "direction": r.get("direction", ""),
                "missed": bool(r.get("missed")),
                "when": int(r.get("when") or 0),
                "seconds": int(r.get("seconds") or 0),
            }
        )
    return out


def _book() -> list:
    if contacts_mod is None:
        return []
    try:
        return list(contacts_mod.book().all())
    except Exception:  # noqa: BLE001
        return []


def cmd_contacts(query: str = "") -> list[dict]:
    if contacts_mod is not None:
        try:
            found = (
                contacts_mod.search(query) if query else list(contacts_mod.book().all())
            )
        except Exception:  # noqa: BLE001
            found = []
        return [
            {
                "name": c.name,
                "numbers": list(getattr(c, "numbers", []) or []),
                "emails": list(getattr(c, "emails", []) or []),
            }
            for c in found
        ]
    # no address book module: fall back to what the phone last told us
    if phone is None:
        return []
    dev = _first_device()
    if dev is None:
        return []
    try:
        return [
            {"name": n, "numbers": list(nums), "emails": []}
            for n, nums in phone.contacts(dev)
        ]
    except Exception:  # noqa: BLE001
        return []


def _read_state_path() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "shani-shell" / "link-read.json"


def _read_state() -> set[str]:
    """Threads the shell has marked read, persisted across bridge invocations."""
    try:
        data = json.loads(_read_state_path().read_text(encoding="utf-8"))
        return {str(t) for t in data} if isinstance(data, list) else set()
    except (OSError, ValueError):  # noqa: BLE001 - first run / unreadable state
        return set()


def cmd_read(thread: str) -> dict:
    if phone is None:
        return _ok(NOT_INSTALLED)
    try:
        path = _read_state_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        seen = _read_state()
        seen.add(str(thread))
        path.write_text(json.dumps(sorted(seen)), encoding="utf-8")
    except Exception as exc:  # noqa: BLE001 - a full disk must not read as a crash
        return _ok(str(exc)[:160])
    return _ok()


def cmd_messages(device_id: str = "") -> list[dict]:
    if phone is None:
        return []
    dev = _by_id(device_id) if device_id else _first_device()
    if dev is None:
        return []
    try:
        rows = phone.conversations(dev)
        book = contacts_mod.book() if contacts_mod else None
    except Exception:  # noqa: BLE001
        return []
    read_threads = _read_state()
    out = []
    for m in rows:
        number = (m.addresses or [""])[0]
        name = ""
        if book is not None and number:
            try:
                name = contacts_mod.name_for(number, book) or ""
            except Exception:  # noqa: BLE001
                name = ""
        out.append(
            {
                "thread": m.thread,
                "name": name,
                "number": number,
                "text": (m.body or "").replace("\n", " ")[:200],
                "when": int((m.date or 0) / 1000),
                "unread": (not bool(m.read)) and str(m.thread) not in read_threads,
            }
        )
    return out


def cmd_thread(thread: str, device_id: str = "") -> list[dict]:
    if phone is None:
        return []
    dev = _by_id(device_id) if device_id else _first_device()
    if dev is None:
        return []
    try:
        rows = phone.thread_messages(dev, thread)
    except Exception:  # noqa: BLE001
        return []
    return [
        {
            "text": m.body,
            "when": int((m.date or 0) / 1000),
            "incoming": bool(m.incoming),
        }
        for m in rows
    ]


def cmd_send(thread: str, text: str) -> dict:
    if phone is None:
        return _ok(NOT_INSTALLED)
    dev = _first_device()
    if dev is None:
        return _ok("no phone is connected")
    try:
        phone.send_sms(dev, (thread,), text, thread)
    except Exception as exc:  # noqa: BLE001
        return _ok(str(exc)[:160])
    return _ok()


def cmd_dial(number: str, line: str = "") -> dict:
    if lines is not None:
        try:
            which = lines.pick(line)
            lines.dial(which, number)
            return {"ok": True, "line": which, "error": ""}
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "line": line, "error": str(exc)[:160]}
    if phone is None:
        return {"ok": False, "line": line, "error": NOT_INSTALLED}
    dev = _first_device()
    if dev is None:
        return {"ok": False, "line": line, "error": "no phone is connected"}
    try:
        lines_dialled = phone.dial(dev, number)
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "line": line, "error": str(exc)[:160]}
    return {"ok": True, "line": lines_dialled, "error": ""}


def cmd_hangup(line: str = "") -> dict:
    if lines is not None:
        try:
            lines.hangup(lines.pick(line))
            return _ok()
        except Exception as exc:  # noqa: BLE001
            return _ok(str(exc)[:160])
    return _ok(NOT_INSTALLED)


def cmd_ring(device_id: str = "") -> dict:
    if phone is None:
        return _ok(NOT_INSTALLED)
    dev = _by_id(device_id) if device_id else _first_device()
    if dev is None:
        return _ok("no phone is connected")
    try:
        ok, why = phone.act(dev, "ring")
    except Exception as exc:  # noqa: BLE001
        return _ok(str(exc)[:160])
    return _ok(None if ok else (why or "the phone did not answer"))


def cmd_share(device_id: str, path: str) -> dict:
    if phone is None:
        return _ok(NOT_INSTALLED)
    dev = _by_id(device_id)
    if dev is None:
        return _ok("no such device")
    try:
        ok, why = phone.act(dev, "share", path)
    except Exception as exc:  # noqa: BLE001
        return _ok(str(exc)[:160])
    return _ok(None if ok else (why or "the phone did not answer"))


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage: link.py <command> [args]"}))
        return 2
    cmd, args = sys.argv[1], sys.argv[2:]

    if cmd == "state":
        print(json.dumps(cmd_state()))
    elif cmd == "devices":
        print(json.dumps(cmd_devices(), ensure_ascii=False))
    elif cmd == "calls":
        print(json.dumps(cmd_calls(), ensure_ascii=False))
    elif cmd == "contacts":
        print(json.dumps(cmd_contacts(args[0] if args else ""), ensure_ascii=False))
    elif cmd == "messages":
        print(json.dumps(cmd_messages(args[0] if args else ""), ensure_ascii=False))
    elif cmd == "thread":
        if not args:
            print(json.dumps([]))
            return 2
        print(
            json.dumps(
                cmd_thread(args[0], args[1] if len(args) > 1 else ""),
                ensure_ascii=False,
            )
        )
    elif cmd == "read":
        if not args:
            print(json.dumps(_ok("read needs a thread")))
            return 2
        print(json.dumps(cmd_read(args[0]), ensure_ascii=False))
    elif cmd == "send":
        if len(args) < 2:
            print(json.dumps(_ok("send needs a thread and the text")))
            return 2
        print(json.dumps(cmd_send(args[0], args[1]), ensure_ascii=False))
    elif cmd == "dial":
        if not args:
            print(json.dumps({"ok": False, "line": "", "error": "dial needs a number"}))
            return 2
        print(
            json.dumps(
                cmd_dial(args[0], args[1] if len(args) > 1 else ""), ensure_ascii=False
            )
        )
    elif cmd == "hangup":
        print(json.dumps(cmd_hangup(args[0] if args else ""), ensure_ascii=False))
    elif cmd == "ring":
        print(json.dumps(cmd_ring(args[0] if args else ""), ensure_ascii=False))
    elif cmd == "share":
        if len(args) < 2:
            print(json.dumps(_ok("share needs a device and a file")))
            return 2
        print(json.dumps(cmd_share(args[0], args[1]), ensure_ascii=False))
    else:
        print(json.dumps({"error": "unknown command: " + cmd}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
