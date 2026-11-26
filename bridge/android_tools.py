#!/usr/bin/env python3
"""android_tools — an Android phone with no app installed: adb and built-in profiles.

One JSON line per call, always {"ok","error", ...}; a missing backend or a
refusal is an honest answer, never a traceback in the UI. Media comes from adb
pull, contacts/texts/calls from `content query` (PBAP/MAP when there is no adb),
files back with adb push or Bluetooth OBEX, and internet sharing from the
phone's own switches. Nothing here installs or needs an app on the phone.

    android_tools.py state
        {"ok","error","paired","name","serial","via","battery","note"}
        via is "adb", "bluetooth" or "".

    android_tools.py backup <folder> [all|photos|downloads|documents|contacts|messages]
        {"ok","error","copied":[{"name","size","when"}],"skipped","contacts",
         "messages","calls","folder","summary","cancelled"}
        Media keeps its path under the phone's shared storage. A file is copied
        only when its (name, size, date) is not in <folder>/.android-backup.json.
        The manifest is written at the end; SHANI_BACKUP_CANCEL names a stop file
        checked between files.

    android_tools.py restore <folder> [vcf|file <relative-path>]
        {"ok","error","pushed":[...],"contacts":bool,"note"}
        adb push for files, back to their /sdcard paths; with no mode, every
        file in the folder goes back. `vcf` only imports the contacts file with
        a VIEW intent, so the phone's own contacts app handles it.

    android_tools.py import-photos <dest>
        {"ok","error","copied":[...],"note"}
        New photos only, into <dest>/<phone>/<year>/<month> from file dates.

    android_tools.py auto-import <state|on|off|check [serial]>
        {"ok","error","on"} (check also answers {"run":bool})
        "Every time this phone connects", kept in phone.settings like the other
        switches; a connection is only acted on once.

    android_tools.py contacts <list|send> [file.vcf]
        {"ok","error","contacts":[{"name","number"}],"sent","note"}
    android_tools.py copy <file> <dest folder>   {"ok","error","sent","via"}
        A bare folder such as "Music" means "/sdcard/Music".
    android_tools.py install <apk>               {"ok","error","result"}
    android_tools.py tether <usb|bt|state>       {"ok","error","on","note"}
    android_tools.py calendar                    {"ok","error","note"}
    android_tools.py pair bluetooth <address>    {"ok","error","paired","name","address"}
    android_tools.py pair wifi <host:port> <code> {"ok","error","paired","name","address"}
    android_tools.py forget                      {"ok","error","paired"}
    android_tools.py find                        {"ok","error","devices":[{name,address,kind}],"note"}
    android_tools.py findable <on|off|state>     {"ok","error","on"}
    android_tools.py cancel                      {"ok","error","cancelled"}
        cancel writes the stop file and works with no backend.

Every subprocess is overridable for the fakes next to dev/fake-*.py:
SHANI_ADB, SHANI_ADB_LOG, SHANI_BTCTL, SHANI_OBEX, SHANI_DBUS,
SHANI_BT_AGENT, SHANI_FAKE_PHONE_DIR (the adb stand-in's phone tree) and
SHANI_BACKUP_CANCEL. Standard library only.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

NOT_INSTALLED = "the phone backends are not installed"
NO_ADB = "no Android phone is connected - plug it in with USB debugging on"
MANIFEST = ".android-backup.json"
PHOTO_MANIFEST = ".android-photos.json"
AUTO_KEY = "android-auto-import-enabled"
LAST_STATE = "android-auto-import.json"

MEDIA_ROOTS = ("/sdcard/DCIM", "/sdcard/Pictures", "/sdcard/Movies")
ROOTS = {
    "photos": MEDIA_ROOTS,
    "downloads": ("/sdcard/Download",),
    "documents": ("/sdcard/Documents",),
}
CONTACTS_URI = "content://com.android.contacts/data/phones"
SMS_URI = "content://sms/inbox"
CALLS_URI = "content://call_log/calls"
USB_HELP = (
    "Turn on USB tethering on the phone: Settings > Network > Hotspot & "
    "tethering > USB tethering, then plug it in."
)
BT_HELP = (
    "Turn on Bluetooth tethering on the phone: Settings > Network > "
    "Hotspot & tethering > Bluetooth tethering."
)
CALENDAR_NOTE = (
    "Android keeps its calendar in an account (Google or CalDAV). "
    "Add the same account in Calendar > Accounts. There is no direct sync."
)

BLANKS = {
    "state": {
        "paired": False,
        "name": "",
        "serial": "",
        "via": "",
        "battery": "",
        "note": "",
    },
    "backup": {
        "copied": [],
        "skipped": 0,
        "contacts": 0,
        "messages": 0,
        "calls": 0,
        "folder": "",
        "summary": "",
        "cancelled": False,
    },
    "restore": {"pushed": [], "contacts": False, "note": ""},
    "import-photos": {"copied": [], "note": ""},
    "auto-import": {"on": False},
    "contacts": {"contacts": [], "sent": False, "note": ""},
    "copy": {"sent": False, "via": ""},
    "install": {"result": ""},
    "tether": {"on": False, "note": ""},
    "calendar": {"note": ""},
    "pair": {"paired": False, "name": "", "address": ""},
    "forget": {"paired": False},
    "find": {"devices": [], "note": ""},
    "findable": {"on": False},
    "cancel": {"cancelled": False},
}


def _answer(error="", **fields) -> dict:
    """One answer: ok is the opposite of an error, error is always a string.

    A helper's traceback is never shown in the UI: only its last useful line.
    """
    text = str(error or "")
    if "Traceback" in text:
        lines = [
            line.strip()
            for line in text.splitlines()
            if line.strip() and not line.strip().startswith(("File ", "  File"))
        ]
        text = lines[-1] if lines else "the helper did not answer"
    out = {"ok": not bool(text), "error": text[:200]}
    out.update(fields)
    return out


def _module(name: str):
    try:
        return __import__(name, fromlist=["*"])
    except Exception:  # noqa: BLE001 - any import failure means "not installed"
        return None


def _call(fn, *args, default=None):
    if not callable(fn):
        return default
    try:
        return fn(*args)
    except Exception:  # noqa: BLE001 - one engine's failure is one honest answer
        return default


def _argv(var: str) -> list[str]:
    try:
        return shlex.split(os.environ.get(var) or "")
    except ValueError:
        return []


def _log(var: str, args) -> None:
    path = os.environ.get(var, "")
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(" ".join(str(a) for a in args) + "\n")
    except OSError:
        pass


def _run(var: str, binary: str, args, log: str = "", timeout: int = 60):
    """A SHANI_* stand-in, else the tool on PATH. (code, stdout, stderr).

    code 127 with an empty stdout means the tool is simply not here; callers
    turn that into a plain sentence. No call here ever reaches a device when a
    test has pointed the override at a fake.
    """
    cmd = _argv(var) or ([binary] if shutil.which(binary) else [])
    if not cmd:
        return 127, "", binary + " is not installed"
    argv = list(cmd) + [str(a) for a in args]
    if log:
        _log(log, argv)
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return 127, "", cmd[0] + " is not installed"
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 124, "", str(exc)[:160]
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def _adb(*args, serial: str = "", timeout: int = 60):
    return _run(
        "SHANI_ADB",
        "adb",
        (["-s", serial] if serial else []) + list(args),
        log="SHANI_ADB_LOG",
        timeout=timeout,
    )


def _bt(*args, timeout: int = 30):
    return _run("SHANI_BTCTL", "bluetoothctl", list(args), timeout=timeout)


def _gdbus(*args, timeout: int = 30):
    return _run("SHANI_DBUS", "gdbus", list(args), timeout=timeout)


def _settings():
    module = _module("phone.settings")
    return _call(getattr(module, "Settings", None)) if module else None


# --- connection ---------------------------------------------------------------


def _bt_phones() -> list[dict]:
    """Paired phones Bluetooth knows: address, name, connected. Best effort."""
    code, out, _err = _bt("paired-devices")
    if code != 0 or not out.strip():
        code, out, _err = _bt("devices", "Paired")
    rows = []
    for line in (out or "").splitlines():
        found = re.match(r"^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$", line.strip())
        if found:
            rows.append(
                {
                    "address": found.group(1),
                    "name": found.group(2).strip(),
                    "connected": False,
                }
            )
    for row in rows:
        _code, info, _err = _bt("info", row["address"])
        if not info.strip():  # some stand-ins answer `show` instead
            _code, info, _err = _bt("show", row["address"])
        row["connected"] = bool(re.search(r"^\s*Connected:\s*yes", info, re.M))
        icon = re.search(r"^\s*Icon:\s*(\w+)", info, re.M)
        row["phone"] = bool(icon and icon.group(1).lower() == "phone") or bool(
            row["name"]
        )
    return rows


def _forgotten_file() -> Path:
    return Path(os.environ.get("SHANI_ADB_FORGOTTEN", "/tmp/shani-android-forgotten"))


def _is_forgotten(serial: str) -> bool:
    try:
        return _forgotten_file().read_text(encoding="utf-8").strip() == serial
    except OSError:
        return False


def _connected() -> tuple[str, str, str, str]:
    """(serial, name, via, problem): the one reachable phone, or why there is none."""
    code, out, err = _adb("devices", "-l")
    if code == 0:
        rows = []
        for line in out.splitlines()[1:]:
            parts = line.split()
            if len(parts) < 2 or not parts[1].strip("()").startswith(
                ("device", "unauth", "offline")
            ):
                continue
            model = next(
                (p.split(":", 1)[1] for p in parts[2:] if p.startswith("model:")), ""
            )
            rows.append((parts[0], parts[1].strip("()"), model.replace("_", " ")))
        ready = [r for r in rows if r[1] == "device"]
        if len(ready) == 1:
            serial = ready[0][0]
            if _is_forgotten(serial):
                return "", "", "", "This phone was forgotten. Pair it again to use it."
            _code, prop, _err = _adb(
                "shell", "getprop", "ro.product.model", serial=serial
            )
            return serial, (prop.strip() or ready[0][2] or "Android phone"), "adb", ""
        if len(ready) > 1:
            return (
                "",
                "",
                "",
                "more than one phone is connected; pair only one or say which serial",
            )
        if rows:
            return (
                "",
                "",
                "",
                "the phone is not ready yet: "
                + rows[0][1]
                + " - unlock it and allow debugging",
            )
    phone = next((p for p in _bt_phones() if p["connected"]), None)
    if phone:
        return phone["address"], phone["name"], "bluetooth", ""
    return "", "", "", (err.strip() or NO_ADB)


def _battery(serial: str) -> str:
    _code, out, _err = _adb("shell", "dumpsys", "battery", serial=serial)
    level = re.search(r"^\s*level:\s*(\d+)", out, re.M)
    charging = re.search(r"^\s*(?:AC|USB|Wireless) powered:\s*true", out, re.M)
    if not level:
        return ""
    return level.group(1) + "%" + (", charging" if charging else "")


def cmd_state() -> dict:
    serial, name, via, problem = _connected()
    battery = _battery(serial) if via == "adb" else ""
    return _answer(
        "",
        paired=bool(serial),
        name=name,
        serial=serial,
        via=via,
        battery=battery,
        note="" if serial else problem,
    )


# --- file listing -------------------------------------------------------------


def _parse_ls(text: str) -> list[dict]:
    """`ls -lR` lines as {name, size, when, path}; directories are left out."""
    files, current = [], ""
    for line in (text or "").splitlines():
        row = line.strip()
        if not row:
            continue
        if row.startswith("/") and row.endswith(":"):
            current = row[:-1]
            continue
        if row.startswith("total "):
            continue
        found = re.match(
            r"^([-d])\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+"
            r"(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+(.+)$",
            row,
        )
        if not found:
            continue
        kind, size, date, clock, name = found.groups()
        if kind == "d":
            continue
        files.append(
            {
                "name": name.strip(),
                "size": int(size),
                "when": date + " " + clock,
                "path": (current.rstrip("/") + "/" + name.strip()),
            }
        )
    return files


def _list_files(serial: str, roots) -> tuple[list[dict], str]:
    code, out, err = _adb("shell", "ls", "-lR", *roots, serial=serial, timeout=120)
    if code != 0:
        return [], (err.strip() or out.strip() or "the phone would not list its files")
    return _parse_ls(out), ""


def _relative(row: dict) -> str:
    return row["path"].split("/sdcard/", 1)[-1].lstrip("/")


def _load_manifest(path: Path) -> dict:
    try:
        row = json.loads(path.read_text(encoding="utf-8"))
        return row if isinstance(row, dict) else {}
    except (OSError, ValueError):
        return {}


def _save_manifest(path: Path, data: dict) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=1, sort_keys=True), encoding="utf-8")
    except OSError:
        pass


def _seen(row: dict, manifest: dict) -> bool:
    return any(
        entry.get("name") == row.get("name")
        and entry.get("size") == row.get("size")
        and entry.get("when") == row.get("when")
        for entry in manifest.get("files", [])
    )


def _cancel_path() -> Path | None:
    stop = os.environ.get("SHANI_BACKUP_CANCEL", "").strip()
    return Path(stop) if stop else None


def _cancelled() -> bool:
    stop = _cancel_path()
    return bool(stop and stop.exists())


def _clear_cancel() -> None:
    stop = _cancel_path()
    if stop is not None:
        try:
            stop.unlink()
        except OSError:
            pass


def cmd_cancel() -> dict:
    """Ask an in-progress copy to stop after the file it is on now."""
    stop = _cancel_path()
    if stop is None:
        return _answer("no backup is running that can be stopped", cancelled=False)
    try:
        stop.parent.mkdir(parents=True, exist_ok=True)
        stop.write_text("stop\n", encoding="utf-8")
    except OSError as exc:
        return _answer(str(exc)[:160], cancelled=False)
    return _answer("", cancelled=True)


def _pull(serial: str, row: dict, dest: Path) -> str:
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return str(exc)[:160]
    code, out, err = _adb("pull", row["path"], str(dest), serial=serial, timeout=180)
    if code != 0 or not dest.is_file():
        return err.strip() or out.strip() or "the phone would not send " + row["name"]
    return ""


# --- contacts / texts / calls -------------------------------------------------


def _rows(text: str) -> list[dict]:
    """`content query` rows: everything after `Row: n`, as key=value pairs."""
    out = []
    for line in (text or "").splitlines():
        row = re.sub(r"^Row:\s*\d+\s*", "", line.strip())
        if not row or "=" not in row:
            continue
        fields = {}
        for piece in row.split(", "):
            key, _, value = piece.partition("=")
            if key.strip():
                fields[key.strip()] = value.strip()
        if fields:
            out.append(fields)
    return out


def _pbap(module_name: str, fn_name: str) -> list | None:
    """The Bluetooth profile when there is no adb; None means no such engine."""
    module = _module(module_name)
    if module is None or not getattr(module, fn_name, None):
        return None
    address = next((p["address"] for p in _bt_phones() if p["connected"]), "")
    if not address:
        return None
    return _call(getattr(module, fn_name), address, default=None)


def _contacts(serial: str) -> tuple[list[dict], str]:
    code, out, err = _adb(
        "shell",
        "content",
        "query",
        "--uri",
        CONTACTS_URI,
        "--projection",
        "display_name:data1",
        serial=serial,
    )
    low = (out + err).lower()
    if code != 0 or "error" in low or "exception" in low:
        rows = _pbap("phone.phone_bluez", "contacts")
        if rows is None:
            return [], (
                err.strip() or out.strip() or "the phone refused to share contacts"
            )
        return [
            {"name": str(name), "number": str(nums[0] if nums else "")}
            for name, nums in rows
        ], ""
    people = []
    for row in _rows(out):
        name = row.get("display_name", "")
        number = row.get("data1", "")
        if name or number:
            people.append({"name": name, "number": number})
    return people, ""


def _messages(serial: str) -> tuple[list[dict], str]:
    code, out, err = _adb(
        "shell",
        "content",
        "query",
        "--uri",
        SMS_URI,
        "--projection",
        "address:date:body",
        serial=serial,
    )
    if code != 0 or "error" in (out + err).lower():
        rows = _pbap("phone.phone_bluez", "message_rows")
        if rows is None:
            return [], (
                err.strip() or out.strip() or "the phone refused to share texts"
            )
        return [
            {
                "address": str(r.get("sender") or r.get("number") or ""),
                "date": str(r.get("date") or ""),
                "body": str(r.get("body") or ""),
            }
            for r in rows
            if isinstance(r, dict)
        ], ""
    return [
        {
            "address": r.get("address", ""),
            "date": r.get("date", ""),
            "body": r.get("body", ""),
        }
        for r in _rows(out)
    ], ""


def _calls(serial: str) -> tuple[list[dict], str]:
    code, out, err = _adb(
        "shell",
        "content",
        "query",
        "--uri",
        CALLS_URI,
        "--projection",
        "name:number:date:type",
        serial=serial,
    )
    if code != 0 or "error" in (out + err).lower():
        rows = _pbap("phone.phone_bluez", "call_history")
        if rows is None:
            return [], (
                err.strip() or out.strip() or "the phone refused to share its call log"
            )
        return [
            {
                "name": str(r.get("name") or ""),
                "number": str(r.get("number") or ""),
                "date": str(r.get("date") or ""),
                "type": str(r.get("kind") or ""),
            }
            for r in rows
            if isinstance(r, dict)
        ], ""
    return [
        {
            "name": r.get("name", ""),
            "number": r.get("number", ""),
            "date": r.get("date", ""),
            "type": r.get("type", ""),
        }
        for r in _rows(out)
    ], ""


def _write_vcf(path: Path, people: list[dict]) -> None:
    lines: list[str] = []
    for person in people:
        lines += [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "FN:" + str(person.get("name", "")).replace("\n", " "),
            "TEL;TYPE=CELL:" + str(person.get("number", "")).replace("\n", " "),
            "END:VCARD",
        ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")


def _write_rows(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )


# --- the commands -------------------------------------------------------------


def cmd_backup(folder: str, category: str = "all") -> dict:
    folder = str(folder or "").strip()
    category = str(category or "all").strip().lower()
    choices = ("all", "photos", "downloads", "documents", "contacts", "messages")
    if not folder:
        return _answer("backup needs a folder to copy into", folder="", copied=[])
    if category not in choices:
        return _answer("backup needs " + ", ".join(choices), folder=folder, copied=[])
    try:
        base = Path(folder).expanduser()
        base.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return _answer(str(exc)[:160], folder=folder, copied=[])
    serial, _name, _via, problem = _connected()
    if not serial:
        return _answer(problem, folder=str(base), copied=[])

    _clear_cancel()  # a previous stop must never cancel a new run
    manifest = _load_manifest(base / MANIFEST)
    manifest.setdefault("files", [])
    copied, skipped, errors = [], 0, []
    if category in ("all", "photos", "downloads", "documents"):
        roots = (
            MEDIA_ROOTS + ROOTS["downloads"] + ROOTS["documents"]
            if category == "all"
            else ROOTS[category]
        )
        found, why = _list_files(serial, roots)
        if why:
            errors.append(why)
        seen_here = set()
        for row in found:
            if _cancelled():
                break
            key = (row["name"], row["size"], row["when"])
            if key in seen_here or _seen(row, manifest):
                skipped += 1
                continue
            seen_here.add(key)
            entry = {
                "name": row["name"],
                "size": row["size"],
                "when": row["when"],
                "path": _relative(row),
            }
            why = _pull(serial, row, base / entry["path"])
            if why:
                errors.append(why)
                continue
            copied.append({k: entry[k] for k in ("name", "size", "when")})
            manifest["files"].append(entry)

    contacts = messages = calls = 0
    if category in ("all", "contacts") and not manifest.get("contacts_written"):
        people, why = _contacts(serial)
        if why:
            errors.append(why)
        else:
            _write_vcf(base / "contacts.vcf", people)
            manifest["contacts_written"] = len(people)
            contacts = len(people)
    if category in ("all", "messages") and not manifest.get("messages_written"):
        texts, why = _messages(serial)
        if why:
            errors.append(why)
        history, why2 = _calls(serial)
        if why2:
            errors.append(why2)
        if not why or not why2:
            _write_rows(base / "messages.txt", texts)
            _write_rows(base / "calls.txt", history)
            manifest["messages_written"] = len(texts)
            manifest["calls_written"] = len(history)
        messages, calls = len(texts), len(history)

    _save_manifest(base / MANIFEST, manifest)
    cancelled = _cancelled()
    summary = (
        f"Copied {len(copied)} file(s), skipped {skipped}; {contacts} contact(s), "
        f"{messages} text(s), {calls} call(s)."
        + (" Stopped at your request." if cancelled else "")
    )
    return _answer(
        "; ".join(dict.fromkeys(e for e in errors if e))[:200],
        copied=copied,
        skipped=skipped,
        contacts=contacts,
        messages=messages,
        calls=calls,
        folder=str(base),
        summary=summary,
        cancelled=cancelled,
    )


def cmd_restore(folder: str, mode: str = "", value: str = "") -> dict:
    """Put backed-up files back at their /sdcard paths, optional vcf by intent.

    With no mode, every file in the folder is pushed back where it came from.
    `file <relative-path>` pushes just that one file; `vcf` only imports the
    contacts file. A .vcf given as the second word is treated as `vcf`.
    """
    folder = str(folder or "").strip()
    if not folder or not Path(folder).expanduser().is_dir():
        return _answer("restore needs a folder that is here", pushed=[], contacts=False)
    serial, _name, _via, problem = _connected()
    if not serial:
        return _answer(problem, pushed=[], contacts=False)
    base = Path(folder).expanduser().resolve()
    mode, value = str(mode or "").strip(), str(value or "").strip()
    pushed, errors, imported = [], [], False

    def push(path: Path, relative: str) -> bool:
        code, out, err = _adb(
            "push", str(path), "/sdcard/" + relative, serial=serial, timeout=180
        )
        if code == 0:
            pushed.append(relative)
            return True
        errors.append(err.strip() or out.strip() or "could not send " + relative)
        return False

    def import_vcf(chosen: Path) -> None:
        nonlocal imported
        if not chosen.is_file():
            return
        relative = "Download/" + chosen.name
        if not push(chosen, relative):
            errors.append("could not send the contacts file")
            return
        _adb(
            "shell",
            "am",
            "start",
            "-a",
            "android.intent.action.VIEW",
            "-d",
            "file:///sdcard/" + relative,
            "-t",
            "text/vcard",
            serial=serial,
        )
        imported = True

    if mode == "file":
        relative = value.lstrip("/")
        chosen = (base / relative).resolve() if relative else base
        if not relative or not chosen.is_relative_to(base) or not chosen.is_file():
            return _answer(
                "file needs a path inside the backup folder", pushed=[], contacts=False
            )
        push(chosen, relative)
        return _answer(
            "; ".join(dict.fromkeys(errors))[:200],
            pushed=pushed,
            contacts=False,
            note=f"Put {relative} back on the phone.",
        )
    if mode == "vcf" or mode.lower().endswith(".vcf"):
        chosen = (
            Path(value).expanduser()
            if value
            else (
                Path(mode).expanduser()
                if mode.lower().endswith(".vcf")
                else base / "contacts.vcf"
            )
        )
        import_vcf(chosen)
        note = (
            "The phone's contacts app will ask before importing."
            if imported
            else "No contacts file was found to import."
        )
        return _answer(
            "; ".join(dict.fromkeys(errors))[:200],
            pushed=pushed,
            contacts=imported,
            note=note,
        )

    files = sorted(
        p
        for p in base.rglob("*")
        if p.is_file()
        and not any(part.startswith(".") for part in p.relative_to(base).parts)
    )
    for path in files:
        push(path, path.relative_to(base).as_posix())
    import_vcf(base / "contacts.vcf")
    note = f"Put {len(files)} file(s) back in the phone's folders."
    if imported:
        note += " The phone's contacts app will ask before importing contacts."
    return _answer(
        "; ".join(dict.fromkeys(errors))[:200],
        pushed=pushed,
        contacts=imported,
        note=note,
    )


def cmd_import_photos(dest: str) -> dict:
    dest = str(dest or "").strip()
    if not dest:
        return _answer("import-photos needs a folder to copy into", copied=[])
    base = Path(dest).expanduser()
    serial, name, _via, problem = _connected()
    if not serial:
        return _answer(problem, copied=[])
    found, why = _list_files(serial, MEDIA_ROOTS)
    if why:
        return _answer(why, copied=[])
    _clear_cancel()  # a previous stop must never cancel a new run
    manifest = _load_manifest(base / PHOTO_MANIFEST)
    manifest.setdefault("files", [])
    phone = re.sub(r"[^A-Za-z0-9_-]+", "-", name or serial).strip("-") or "phone"
    copied, errors = [], []
    stopped = False
    for row in found:
        if _cancelled():
            stopped = True
            break
        if _seen(row, manifest):
            continue
        match = re.match(r"(\d{4})-(\d{2})", row["when"])
        year, month = (
            (match.group(1), match.group(2)) if match else ("unknown", "unknown")
        )
        target = base / phone / year / month / Path(_relative(row)).name
        why = _pull(serial, row, target)
        if why:
            errors.append(why)
            continue
        entry = {
            "name": row["name"],
            "size": row["size"],
            "when": row["when"],
            "path": str(target.relative_to(base)),
        }
        copied.append({k: entry[k] for k in ("name", "size", "when")})
        manifest["files"].append(entry)
    _save_manifest(base / PHOTO_MANIFEST, manifest)
    note = (
        f"Put {len(copied)} new photo(s) in {base / phone}."
        if copied
        else "No new photos to import."
    )
    if stopped:
        note += " Stopped at your request."
    return _answer("; ".join(errors)[:200], copied=copied, note=note)


def _last_state_path() -> Path:
    root = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(root) / "shani-shell" / LAST_STATE


def _last_connection() -> str:
    try:
        row = json.loads(_last_state_path().read_text(encoding="utf-8"))
        return str(row.get("serial", "")) if isinstance(row, dict) else ""
    except (OSError, ValueError):
        return ""


def _remember_connection(serial: str) -> None:
    path = _last_state_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"serial": serial}), encoding="utf-8")
    except OSError:
        pass


def auto_import_pending(serial: str = "") -> bool:
    """True once for a connection when "every time" is on. For the service."""
    settings = _settings()
    if settings is None or not _call(settings.get_bool, AUTO_KEY, False):
        return False
    serial = str(serial or _connected()[0])
    if not serial or serial == _last_connection():
        return False
    _remember_connection(serial)
    return True


def cmd_auto_import(verb: str, serial: str = "") -> dict:
    verb = str(verb or "state").strip().lower()
    if verb not in ("state", "on", "off", "check"):
        return _answer("auto-import needs state, on, off or check", on=False)
    settings = _settings()
    if verb == "state":
        return _answer(
            "",
            on=bool(_call(settings.get_bool, AUTO_KEY, False)) if settings else False,
        )
    if settings is None:
        return _answer(NOT_INSTALLED, on=False)
    if verb in ("on", "off"):
        on = verb == "on"
        _call(settings.set_bool, AUTO_KEY, on)
        return _answer("", on=bool(_call(settings.get_bool, AUTO_KEY, on)))
    run = auto_import_pending(str(serial or "").strip())
    answer = _answer("", on=bool(_call(settings.get_bool, AUTO_KEY, False)))
    answer["run"] = run
    return answer


def cmd_contacts(verb: str, vcf: str = "") -> dict:
    verb = str(verb or "list").strip().lower()
    if verb == "list":
        serial = _connected()[0]
        people, why = (
            _contacts(serial) if serial else ([], "no Android phone is connected")
        )
        return _answer(why, contacts=people, sent=False, note="" if not why else why)
    if verb == "send":
        path = Path(str(vcf or "").strip()).expanduser()
        if not path.is_file():
            return _answer("give a .vcf file that is here", contacts=[], sent=False)
        serial, _name, _via, problem = _connected()
        if not serial:
            return _answer(problem, contacts=[], sent=False)
        code, out, err = _adb(
            "push",
            str(path),
            "/sdcard/Download/" + path.name,
            serial=serial,
            timeout=180,
        )
        if code != 0:
            return _answer(
                err.strip() or out.strip() or "the phone would not take the file",
                contacts=[],
                sent=False,
            )
        _adb(
            "shell",
            "am",
            "start",
            "-a",
            "android.intent.action.VIEW",
            "-d",
            "file:///sdcard/Download/" + path.name,
            "-t",
            "text/vcard",
            serial=serial,
        )
        return _answer(
            "",
            contacts=[],
            sent=True,
            note="The phone's contacts app will ask before importing "
            + path.name
            + ".",
        )
    return _answer("contacts needs list or send", contacts=[], sent=False)


def _obex(path: Path, address: str) -> bool:
    if _argv("SHANI_OBEX"):
        code, out, err = _run(
            "SHANI_OBEX", "", ["send", str(path), address], timeout=120
        )
        return code == 0 and "error" not in (out + err).lower()
    module = _module("phone.phone_bluez")
    if module is not None:
        failed = object()
        return _call(module.send_file, address, str(path), default=failed) is not failed
    return False


def cmd_copy(path: str, dest: str = "") -> dict:
    source = Path(str(path or "").strip()).expanduser()
    if not source.is_file():
        return _answer("copy needs a file that is here", sent=False, via="")
    serial, _name, via, _problem = _connected()
    if via == "adb":
        target = str(dest or "").strip() or "/sdcard/Download/"
        if target.startswith("/"):
            if not target.startswith("/sdcard/"):
                return _answer(
                    "files go under /sdcard/ on the phone", sent=False, via="adb"
                )
        else:
            target = "/sdcard/" + target  # "Music" means "/sdcard/Music"
        code, out, err = _adb(
            "push",
            str(source),
            target.rstrip("/") + "/" + source.name,
            serial=serial,
            timeout=180,
        )
        if code != 0:
            return _answer(
                err.strip() or out.strip() or "the phone would not take the file",
                sent=False,
                via="adb",
            )
        return _answer("", sent=True, via="adb")
    phone = next((p for p in _bt_phones() if p["connected"]), None)
    if phone and _obex(source, phone["address"]):
        return _answer("", sent=True, via="bluetooth")
    return _answer("no phone is connected to send a file to", sent=False, via="")


def cmd_install(apk: str) -> dict:
    source = Path(str(apk or "").strip()).expanduser()
    if not source.is_file():
        return _answer("install needs an apk file that is here", result="")
    serial, _name, _via, problem = _connected()
    if not serial:
        return _answer(problem, result="")
    code, out, err = _adb("install", "-r", str(source), serial=serial, timeout=300)
    lines = [
        re.sub(r"\x1b\[[0-9;]*m", "", line).strip()
        for line in (out + "\n" + err).splitlines()
        if line.strip()
    ]
    result = (lines[-1] if lines else "the phone did not answer")[:200]
    ok = code == 0 and "fail" not in result.lower()
    return _answer("" if ok else result, result=result)


def cmd_tether(verb: str) -> dict:
    verb = str(verb or "state").strip().lower()
    if verb not in ("usb", "bt", "state"):
        return _answer("tether needs usb, bt or state", on=False)
    if verb in ("usb", "state"):
        code, out, _err = _adb("shell", "svc", "usb", "getFunctions")
        usb_on = code == 0 and "rndis" in out.lower()
    else:
        usb_on = False
    if verb == "usb":
        if not _connected()[0]:
            return _answer("", on=usb_on, note=USB_HELP)
        code, out, err = _adb("shell", "svc", "usb", "setFunctions", "rndis")
        _code, check, _err = _adb("shell", "svc", "usb", "getFunctions")
        on = code == 0 and "rndis" in check.lower()
        note = (
            "The phone is sharing its internet over the cable."
            if on
            else USB_HELP + (" " + (err.strip() or out.strip())[:80] if not on else "")
        )
        return _answer("", on=on, note=note)
    if verb in ("bt", "state"):
        address = next((p["address"] for p in _bt_phones() if p["connected"]), "")
        bt_on = False
        if address:
            object_path = "/org/bluez/hci0/dev_" + address.replace(":", "_").upper()
            if verb == "bt":
                code, out, err = _gdbus(
                    "call",
                    "--system",
                    "--dest",
                    "org.bluez",
                    "--object-path",
                    object_path,
                    "--method",
                    "org.bluez.Network1.Connect",
                    "nap",
                )
                bt_on = code == 0
            else:
                code, out, err = _gdbus(
                    "call",
                    "--system",
                    "--dest",
                    "org.bluez",
                    "--object-path",
                    object_path,
                    "--method",
                    "org.freedesktop.DBus.Properties.Get",
                    "org.bluez.Network1",
                    "Connected",
                )
                bt_on = code == 0 and "true" in out.lower()
        on = usb_on or bt_on
        if on:
            note = "The phone is sharing its internet with this computer."
        elif verb == "bt":
            note = BT_HELP if address else "Pair the phone over Bluetooth first."
        else:
            note = "The phone is not sharing its internet right now."
        return _answer("", on=on, note=note)
    return _answer("tether needs usb, bt or state", on=False)


def cmd_calendar() -> dict:
    return _answer("", note=CALENDAR_NOTE)


# --- pairing: Bluetooth and adb Wi-Fi debugging --------------------------------


def _pair_bluetooth(address: str) -> tuple[bool, str, str, str]:
    """Pair and connect a phone over BlueZ. (ok, why, name, address)."""
    address = str(address or "").strip()
    if not re.match(r"^[0-9A-Fa-f:]{17}$", address):
        return False, "give the phone's Bluetooth address", "", ""
    code, out, err = _bt("pair", address)
    said = (out + "\n" + err).lower()
    paired = code == 0 and ("pairing successful" in said or "already exists" in said)
    if paired:
        _bt("connect", address)
    _code, info, _err = _bt("info", address)
    if not info.strip():
        _code, info, _err = _bt("show", address)
    name_match = re.search(r"^\s*Name:\s*(.+)$", info, re.M)
    name = name_match.group(1).strip() if name_match else ""
    if not paired:
        return (
            False,
            (err.strip() or out.strip() or "the phone did not answer"),
            name,
            address,
        )
    return True, "", name, address


def _pair_wifi(host: str, code: str) -> tuple[bool, str, str, str]:
    """`adb pair <host:port> <code>` then `adb connect`. (ok, why, name, address)."""
    host = str(host or "").strip()
    code = re.sub(r"\s", "", str(code or ""))
    if not re.match(r"^[\w.\-\[\]:]+:\d+$", host):
        return (
            False,
            "that is not an address - it looks like 192.168.1.20:37099",
            "",
            "",
        )
    if not code.isdigit():
        return False, "the pairing code is the digits the phone shows", "", host
    rc, out, err = _adb("pair", host, code, timeout=30)
    said = out + "\n" + err
    if rc != 0 or "successfully paired" not in said.lower():
        return (
            False,
            (err.strip() or out.strip() or "the phone did not answer"),
            "",
            host,
        )
    _adb("connect", host.rsplit(":", 1)[0] + ":5555", timeout=20)
    return True, "", "Android phone", host


def cmd_pair(kind: str, value: str = "", code: str = "") -> dict:
    kind = str(kind or "").strip().lower()
    if kind == "bluetooth":
        ok, why, name, address = _pair_bluetooth(value)
    elif kind == "wifi":
        ok, why, name, address = _pair_wifi(value, code)
    else:
        return _answer("pair needs bluetooth or wifi", paired=False)
    if ok:
        try:
            _forgotten_file().unlink(missing_ok=True)
        except OSError:
            pass
    return _answer("" if ok else why, paired=ok, name=name, address=address)


def _known_wifi() -> list[str]:
    """Addresses with a `host:port` serial that adb still lists."""
    code, out, _err = _adb("devices")
    if code != 0:
        return []
    return [
        line.split()[0]
        for line in out.splitlines()[1:]
        if line.strip() and re.match(r"^[\d.:]+:\d+\s+device$", line.strip())
    ]


def cmd_forget() -> dict:
    """Forget the phone over Bluetooth, and any Wi-Fi debugging connection."""
    errors = []
    for phone in _bt_phones():
        code, out, err = _bt("remove", phone["address"])
        if code != 0 and "not found" not in (out + err).lower():
            errors.append(
                err.strip() or out.strip() or "could not forget " + phone["address"]
            )
    for device in _known_wifi():
        _adb("disconnect", device, timeout=20)
    serial, _name, _via, _problem = _connected()
    if serial:
        try:
            _forgotten_file().write_text(serial + "\n", encoding="utf-8")
        except OSError:
            pass
    paired = bool(_bt_phones()) or bool(_known_wifi()) or bool(serial)
    return _answer("; ".join(errors)[:200], paired=paired)


def cmd_find() -> dict:
    """Phones nearby over Bluetooth and phones adb can already reach. No sweep."""
    _bt("scan", "on")  # best effort: a stand-in or an adapter may refuse
    devices, seen = [], set()
    for phone in _bt_phones():
        address = phone["address"]
        if address in seen:
            continue
        seen.add(address)
        devices.append({"name": phone["name"], "address": address, "kind": "bluetooth"})
    code, out, _err = _adb("devices", "-l")
    if code == 0:
        for line in out.splitlines()[1:]:
            parts = line.split()
            if len(parts) < 2 or parts[1] != "device":
                continue
            serial = parts[0]
            model = next(
                (p.split(":", 1)[1] for p in parts[2:] if p.startswith("model:")), ""
            )
            name = (
                (model.replace("_", " ") or "Android phone")
                if ":" not in serial
                else serial
            )
            if serial in seen:
                continue
            seen.add(serial)
            devices.append(
                {
                    "name": name,
                    "address": serial,
                    "kind": "wifi" if ":" in serial else "adb",
                }
            )
    note = (
        "Found " + str(len(devices)) + " phone(s)."
        if devices
        else "No phones are nearby. Open Bluetooth pairing on the phone and try again."
    )
    return _answer("", devices=devices, note=note)


def cmd_findable(verb: str) -> dict:
    verb = str(verb or "state").strip().lower()
    if verb not in ("on", "off", "state"):
        return _answer("findable needs on, off or state", on=False)
    override = _argv("SHANI_BT_AGENT")
    if override:
        code, out, err = _run("SHANI_BT_AGENT", "", [verb], timeout=30)
        if code != 0:
            return _answer(
                err.strip() or out.strip() or "could not change discoverability",
                on=False,
            )
        try:
            row = json.loads(out)
            on = bool(row.get("on", False)) if isinstance(row, dict) else False
        except ValueError:
            on = "yes" in out.lower() or "true" in out.lower()
        return _answer("", on=on)
    if verb != "state":
        _bt("discoverable", verb)
        if verb == "on":
            _bt("pairable", "on")
    _code, info, _err = _bt("show")
    match = re.search(r"^\s*Discoverable:\s*(yes|no)", info, re.M)
    return _answer("", on=bool(match and match.group(1).lower() == "yes"))


# --- dispatch -----------------------------------------------------------------

HANDLERS = {
    "state": cmd_state,
    "backup": lambda *a: cmd_backup(*a),
    "restore": lambda *a: cmd_restore(*a),
    "import-photos": lambda *a: cmd_import_photos(*a),
    "auto-import": lambda *a: cmd_auto_import(*a),
    "contacts": lambda *a: cmd_contacts(*a),
    "copy": lambda *a: cmd_copy(*a),
    "install": lambda *a: cmd_install(*a),
    "tether": lambda *a: cmd_tether(*a),
    "calendar": cmd_calendar,
    "pair": lambda *a: cmd_pair(*a),
    "forget": cmd_forget,
    "find": cmd_find,
    "findable": lambda *a: cmd_findable(*a),
    "cancel": cmd_cancel,
}


def main(argv: list[str]) -> int:
    command = str(argv[1] if len(argv) > 1 else "")
    args = [str(a) for a in argv[2:]]
    blank = dict(BLANKS.get(command, {}))
    handler = HANDLERS.get(command)
    if handler is None:
        answer = _answer("usage: android_tools.py <" + "|".join(HANDLERS) + ">")
    else:
        try:
            answer = handler(*args)
        except Exception as exc:  # noqa: BLE001 - never a traceback to the UI
            answer = _answer(f"{type(exc).__name__}: {exc}")
    if not isinstance(answer, dict):
        answer = {}
    out = dict(blank)
    out.update(answer)
    out.setdefault("ok", not bool(out.get("error")))
    try:
        line = json.dumps(out, ensure_ascii=False)
    except (TypeError, ValueError):
        line = json.dumps(
            _answer("android tools could not encode the answer", **blank),
            ensure_ascii=False,
        )
    print(line, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
