#!/usr/bin/env python3
"""phone_tools — the phone's own music, files, remote, link, switches and sound.

One JSON answer per call, even when a backend is missing. The phone engines are
imported lazily, so a machine without them still gets an honest answer.

    phone_tools.py music <status|play|pause|toggle|next|previous>
        {"ok","error","state","title","artist","player","summary"}
    phone_tools.py files received [limit]
        {"ok","error","folder","files":[{"path","name","size","when"}]}
    phone_tools.py files send <path> [device]          {"ok","error"}
    phone_tools.py files receive <state|on|off>        {"ok","error","on"}
    phone_tools.py remote <status|on|off|press KEY|type TEXT>
        {"ok","error","on","status","note"}
    phone_tools.py link <state|pair HOST|forget|find|findable on|off>
        {"ok","error","paired","name","address","status","note","findable"}
    phone_tools.py background <list|set KEY on|off>
        {"ok","error","switches":[{key,label,detail,on}],"on","total"}
    phone_tools.py audio <state|pc|phone>              {"ok","error","where","note"}

Stand-ins for tests, as in containers.py and devices.py: SHANI_MUSIC is called
with the action, SHANI_FILES_SEND with the path (calls in SHANI_FILES_LOG),
SHANI_PHONE_REMOTE and SHANI_PHONE_LINK with the verb and its argument (calls in
SHANI_PHONE_REMOTE_LOG / SHANI_PHONE_LINK_LOG), SHANI_AUDIO with the verb (calls
in SHANI_AUDIO_LOG). Each stand-in prints one JSON object. SHANI_FILES_DIR picks
the download folder, SHANI_DBUS the gdbus binary. Standard library only.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from datetime import datetime
from pathlib import Path

NOT_INSTALLED = "the phone backends are not installed"
MUSIC_ACTIONS = ("status", "play", "pause", "toggle", "next", "previous")
REMOTE_KEYS = (
    "shutter",
    "play_pause",
    "next",
    "previous",
    "stop",
    "volume_up",
    "volume_down",
    "mute",
)
RECEIVE_KEY = "phone-control-enabled"
REMOTE_KEY = "phone-remote-enabled"
FINDABLE_KEY = "phone-link-findable"
DBUS_DEST = "dev.shani.Shell.Phone"
DBUS_PATH = "/dev/shani/Shell/Phone"
DEFAULT_ON = ("bluetooth-media-remote-enabled", "modem-call-enabled")

#: The 14 background switches, in the order they appear in settings.KEYS.
#: Plain words: no product names, no protocol names.
SWITCH_ROWS = (
    (
        "bluetooth-call-enabled",
        "Calls with a headset",
        "Use a headset or a paired phone for calls.",
    ),
    (
        "bluetooth-gatt-enabled",
        "Phone buttons",
        "Let a paired phone send button presses to this computer.",
    ),
    ("phone-control-enabled", "Receive files", "Accept a file sent by a paired phone."),
    (
        "phone-remote-enabled",
        "Phone as a remote",
        "Use the phone as a camera remote and a keyboard.",
    ),
    (
        "phone-messages-read-enabled",
        "Read phone messages",
        "Show the phone's messages on this computer.",
    ),
    (
        "phone-messages-send-enabled",
        "Send phone messages",
        "Send messages from this computer through the phone.",
    ),
    (
        "watch-companion-enabled",
        "Watch companion",
        "Keep the watch connected and up to date.",
    ),
    (
        "watch-nowplaying-enabled",
        "Music on the watch",
        "Show what is playing on the watch.",
    ),
    (
        "watch-weather-enabled",
        "Weather on the watch",
        "Send the local weather to the watch.",
    ),
    ("landline-enabled", "Home phone line", "Answer calls on the home phone line."),
    (
        "bluetooth-media-remote-enabled",
        "Music buttons",
        "Let a paired remote control music on this computer.",
    ),
    (
        "modem-call-enabled",
        "Mobile modem calls",
        "Let this computer's mobile modem take calls.",
    ),
    (
        "phone-lan-receive-enabled",
        "Receive files over Wi-Fi",
        "Let a paired phone send files over the same Wi-Fi.",
    ),
    (
        "phone-clipboard-sync-enabled",
        "Shared clipboard",
        "Copy and paste between this computer and the phone.",
    ),
)
SWITCH_KEYS = tuple(row[0] for row in SWITCH_ROWS)

#: The fields each command keeps, so a failed call still has the same shape.
BLANKS = {
    "music": {"state": "", "title": "", "artist": "", "player": "", "summary": ""},
    "files": {"folder": "", "files": [], "on": False},
    "remote": {"on": False, "status": "", "note": ""},
    "link": {
        "paired": False,
        "name": "",
        "address": "",
        "status": "",
        "note": "",
        "findable": False,
    },
    "background": {"switches": [], "on": 0, "total": 0},
    "audio": {"where": "", "note": ""},
}


def _answer(error="", **fields) -> dict:
    """One answer: ok is the opposite of an error, error is always a string."""
    out = {"ok": not bool(error), "error": str(error or "")[:200]}
    out.update(fields)
    return out


def _module(name: str):
    """Import one vendored engine, or None when it is not usable here."""
    try:
        return __import__(name, fromlist=["*"])
    except Exception:  # noqa: BLE001 - any import failure means "not installed"
        return None


def _call(fn, *args, default=None):
    """Call a backend; its refusal or absence becomes a value, not a traceback."""
    if not callable(fn):
        return default
    try:
        return fn(*args)
    except Exception:  # noqa: BLE001 - one engine's failure is one honest answer
        return default


def _argv(var: str) -> list[str]:
    """A SHANI_* binary, as argv. [] means no stand-in was named."""
    try:
        return shlex.split(os.environ.get(var) or "")
    except ValueError:
        return []


def _log(var: str, args) -> None:
    """Remember a stand-in call for the tests, without failing the command."""
    path = os.environ.get(var, "")
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(" ".join(str(a) for a in args) + "\n")
    except OSError:
        pass


def _script(var: str, args, log: str = "", timeout: int = 30):
    """Ask a stand-in. (its JSON object, "") or (None, why-it-failed).

    None means there is no stand-in; an empty object means it answered with no
    words, which is success for a send. Non-JSON words are only an error when
    the script itself failed.
    """
    cmd = _argv(var)
    if not cmd:
        return None, ""
    if log:
        _log(log, args)
    argv = cmd + [str(a) for a in args]
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return None, f"{cmd[0]} is not installed"
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)[:160]
    data = {}
    text = (proc.stdout or "").strip()
    if text:
        try:
            parsed = json.loads(text)
            if isinstance(parsed, dict):
                data = parsed
        except ValueError:
            pass
    said = ((proc.stdout or "") + (proc.stderr or "")).strip()
    error = str(data.get("error") or "")
    if not error and proc.returncode != 0:
        error = (said.splitlines() or ["the helper did not answer"])[-1][:200]
    return data, error


def _settings():
    module = _module("phone.settings")
    return _call(getattr(module, "Settings", None)) if module else None


def _dbus_set(key: str, on: bool) -> None:
    """Tell the running phone service too, when it is there. Best effort."""
    argv = (_argv("SHANI_DBUS") or ["gdbus"]) + [
        "call",
        "--session",
        "--dest",
        DBUS_DEST,
        "--object-path",
        DBUS_PATH,
        "--method",
        DBUS_DEST + ".SetSetting",
        key,
        "true" if on else "false",
    ]
    try:
        subprocess.run(argv, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass  # no gdbus, no service: the settings file is the source of truth


# --- music ------------------------------------------------------------------


def _music_summary(state, title, artist) -> str:
    now = " - ".join(x for x in (artist, title) if x)
    kind = str(state or "").lower()
    if kind == "playing":
        return f"Playing {now}" if now else "Music is playing"
    if kind == "paused":
        return f"Paused {now}" if now else "Music is paused"
    return "Nothing is playing right now."


def _music_answer(
    state="", title="", artist="", player="", summary="", error=""
) -> dict:
    return _answer(
        error,
        state=str(state or ""),
        title=str(title or ""),
        artist=str(artist or ""),
        player=str(player or ""),
        summary=str(summary or ""),
    )


def _from_mpris(action: str, mpris):
    """The answer from a desktop player, or None when there is no player."""
    player = _call(mpris.current, default=None)
    if not player:
        return None
    error = ""
    if action != "status":
        said = str(_call(mpris.control, action, default="") or "")
        if said.startswith(("No media player", "The player did not", "Unknown media")):
            error = said
    state = str(_call(mpris.status, player, default="Stopped") or "Stopped")
    meta = _call(mpris.metadata, player, default={}) or {}
    title = str(meta.get("xesam:title") or "")
    artists = meta.get("xesam:artist") or []
    artist = str(artists[0]) if artists else ""
    name = str(_call(mpris.identity, player, default="") or "")
    name = name or str(player).replace("org.mpris.MediaPlayer2.", "")
    return _music_answer(
        state, title, artist, name, _music_summary(state, title, artist), error
    )


def _from_bluez(action: str, bluez):
    """The answer from the phone's own player, or None when there is none."""
    found = _call(bluez.avrcp_players, default=[]) or []
    if not found:
        return None
    entry = found[0]
    path, name = (
        (entry[0], entry[1]) if isinstance(entry, (list, tuple)) else (entry, "")
    )
    error = ""
    if action != "status":
        done, why = _call(
            bluez.avrcp,
            path,
            action,
            default=(False, "the phone's player did not answer"),
        )
        if not done:
            error = str(why or "the phone's player did not answer")
    state, now = _call(bluez.avrcp_status, path, default=("Stopped", ""))
    now = str(now or "")
    title, artist = now.split(" by ", 1) if " by " in now else (now, "")
    return _music_answer(
        state, title, artist, name, _music_summary(state, title, artist), error
    )


def cmd_music(*args) -> dict:
    action = str(args[0] if args else "status").strip().lower()
    if action not in MUSIC_ACTIONS:
        return _music_answer(error=f"music needs {', '.join(MUSIC_ACTIONS)}")
    data, error = _script("SHANI_MUSIC", [action])
    if data is not None:
        return _music_answer(
            data.get("state", ""),
            data.get("title", ""),
            data.get("artist", ""),
            data.get("player", ""),
            data.get("summary", ""),
            error,
        )
    mpris = _module("phone.mpris")
    if mpris is not None:
        got = _call(_from_mpris, action, mpris)
        if got is not None:
            return got
    bluez = _module("phone.phone_bluez")
    if bluez is not None:
        got = _call(_from_bluez, action, bluez)
        if got is not None:
            return got
    return _music_answer(summary="Nothing is playing right now.")


# --- files ------------------------------------------------------------------


def _download_folder() -> Path:
    override = os.environ.get("SHANI_FILES_DIR", "").strip()
    if override:
        return Path(override).expanduser()
    module = _module("phone.obex_receive")
    folder = _call(getattr(module, "downloads", None)) if module else None
    if folder:
        return Path(str(folder)).expanduser()
    xdg = os.environ.get("XDG_DOWNLOAD_DIR", "").strip()
    return Path(xdg).expanduser() if xdg else Path.home() / "Downloads"


def cmd_files_received(*args) -> dict:
    try:
        limit = int(str(args[0] if args else "20"))
    except (TypeError, ValueError):
        return _answer(
            "limit must be a number", folder=str(_download_folder()), files=[]
        )
    folder = _download_folder()
    try:
        rows = sorted(
            (p for p in folder.iterdir() if p.is_file()),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
    except OSError:
        return _answer(
            "the download folder could not be read", folder=str(folder), files=[]
        )
    files = []
    for path in rows[: max(1, min(limit, 200))]:
        try:
            stat = path.stat()
        except OSError:
            continue
        files.append(
            {
                "path": str(path),
                "name": path.name,
                "size": int(stat.st_size),
                "when": datetime.fromtimestamp(stat.st_mtime).strftime(
                    "%Y-%m-%d %H:%M"
                ),
            }
        )
    return _answer("", folder=str(folder), files=files)


def cmd_files_send(*args) -> dict:
    path = str(args[0] if args else "").strip()
    if not path:
        return _answer("send needs a file path")
    device = str(args[1] if len(args) > 1 else "").strip()
    data, error = _script(
        "SHANI_FILES_SEND", [path] + ([device] if device else []), log="SHANI_FILES_LOG"
    )
    if data is not None:
        return _answer(error)
    full = Path(path).expanduser()
    if not full.is_file():
        return _answer("that file is not here")
    phone = _module("phone.phone")
    if phone is not None:
        devices = _call(phone.devices, default=[]) or []
        match = None
        if device:
            match = next(
                (
                    d
                    for d in devices
                    if getattr(d, "id", "") == device
                    or getattr(d, "name", "") == device
                ),
                None,
            )
            if match is None:
                return _answer("no paired phone by that name")
        else:
            match = next(
                (
                    d
                    for d in devices
                    if getattr(d, "paired", False) and getattr(d, "reachable", False)
                ),
                None,
            )
            match = match or next(
                (d for d in devices if getattr(d, "paired", False)), None
            )
        if match is not None:
            done, why = _call(
                phone.act,
                match,
                "share",
                str(full),
                default=(False, "the phone did not answer"),
            )
            return _answer("" if done else str(why or "the phone did not answer"))
    lan = _module("phone.lan_link")
    if lan is not None:
        paired = _call(lan.paired_device, default={}) or {}
        host = device or str(paired.get("address") or "")
        if host:
            sent, why = _call(
                lan.send_file,
                host,
                str(full),
                default=(False, "the phone did not answer"),
            )
            return _answer("" if sent else str(why or "not sent"))
    bluez = _module("phone.phone_bluez")
    if bluez is not None:
        phones = _call(bluez.phones, default=[]) or []
        address = device or next(
            (
                row[0]
                for row in phones
                if isinstance(row, (list, tuple)) and len(row) > 2 and row[2]
            ),
            "",
        )
        if address:
            why = _call(bluez.send_file, address, str(full), default="")
            return _answer(str(why or ""))
    return _answer("no paired phone is connected")


def cmd_files_receive(*args) -> dict:
    verb = str(args[0] if args else "state").strip().lower()
    if verb not in ("state", "on", "off"):
        return _answer("files receive needs state, on or off", on=False)
    settings = _settings()
    if settings is None:
        return _answer(NOT_INSTALLED, on=False)
    if verb == "state":
        return _answer("", on=bool(_call(settings.get_bool, RECEIVE_KEY, False)))
    on = verb == "on"
    _call(settings.set_bool, RECEIVE_KEY, on)
    _dbus_set(RECEIVE_KEY, on)
    return _answer("", on=bool(_call(settings.get_bool, RECEIVE_KEY, on)))


# --- remote -----------------------------------------------------------------


def cmd_remote(*args) -> dict:
    verb = str(args[0] if args else "status").strip().lower()
    arg = " ".join(str(a) for a in args[1:]).strip()
    data, error = _script(
        "SHANI_PHONE_REMOTE",
        [verb] + ([arg] if arg else []),
        log="SHANI_PHONE_REMOTE_LOG",
    )
    if data is not None:
        return _answer(
            error,
            on=bool(data.get("on", False)),
            status=str(data.get("status") or ""),
            note=str(data.get("note") or ""),
        )
    if verb not in ("status", "on", "off", "press", "type"):
        return _answer("remote needs status, on, off, press or type")
    settings = _settings()
    if settings is None:
        return _answer(NOT_INSTALLED)
    on = bool(_call(settings.get_bool, REMOTE_KEY, False))
    status = "on" if on else "off"
    note = ""
    module = _module("phone.phone_remote")
    if verb in ("on", "off"):
        on = verb == "on"
        _call(settings.set_bool, REMOTE_KEY, on)
        status = "on" if on else "off"
        note = f"Phone remote turned {'on' if on else 'off'}."
    elif verb == "status":
        if module is None:
            note = NOT_INSTALLED + "."
        else:
            connected, why = _call(module.status, default=(False, ""))
            status = "connected" if connected else ("not connected" if on else "off")
            note = str(why or "")
    elif verb == "press":
        key = arg.lower().replace(" ", "_")
        keys = tuple(getattr(module, "KEYS", REMOTE_KEYS)) if module else REMOTE_KEYS
        if key not in keys:
            return _answer(f"press needs one of {', '.join(keys)}")
        note = (
            str(
                _call(
                    getattr(module, "press", None),
                    key,
                    default="No phone is listening.",
                )
            )
            if module
            else NOT_INSTALLED + "."
        )
    else:
        if not arg:
            return _answer("type needs some text")
        note = (
            str(
                _call(
                    getattr(module, "type_text", None),
                    arg,
                    default="Nothing was typed.",
                )
            )
            if module
            else NOT_INSTALLED + "."
        )
    return _answer("", on=on, status=status, note=note)


# --- link -------------------------------------------------------------------


def _link_answer(data: dict, error="") -> dict:
    return _answer(
        error,
        paired=bool(data.get("paired", False)),
        name=str(data.get("name") or ""),
        address=str(data.get("address") or ""),
        status=str(data.get("status") or ""),
        note=str(data.get("note") or ""),
        findable=bool(data.get("findable", False)),
    )


def cmd_link(*args) -> dict:
    verb = str(args[0] if args else "state").strip().lower()
    arg = " ".join(str(a) for a in args[1:]).strip()
    data, error = _script(
        "SHANI_PHONE_LINK", [verb] + ([arg] if arg else []), log="SHANI_PHONE_LINK_LOG"
    )
    if data is not None:
        return _link_answer(data, error)
    lan = _module("phone.lan_link")
    helper = _module("phone.lan_phone")
    settings = _settings()
    paired = _call(lan.paired_device, default={}) if lan else {}
    paired = paired if isinstance(paired, dict) else {}
    status = _call(getattr(lan, "pairing_status", None), default=("not paired", ""))
    if not isinstance(status, (list, tuple)) or len(status) < 2:
        status = ("not paired", "")
    state, why = str(status[0] or ""), str(status[1] or "")
    name = str(paired.get("deviceName") or "")
    address = str(paired.get("address") or "")
    note = why
    findable = (
        bool(_call(settings.get_bool, FINDABLE_KEY, False)) if settings else False
    )
    error = "" if lan is not None else NOT_INSTALLED
    if verb == "state":
        pass
    elif verb == "forget":
        _call(lan.forget_pairing)
        paired, name, address = {}, "", ""
        state, note = "not paired", "The phone link was forgotten."
    elif verb == "pair":
        if not arg:
            error = "pair needs the phone's address"
        elif helper is not None:
            note = str(
                _call(helper.pair, arg, default="Could not pair with that phone.")
            )
            if note.startswith("Paired:"):
                state = "paired"
                paired = _call(lan.paired_device, default={}) if lan else {}
                paired = paired if isinstance(paired, dict) else {}
                name = str(paired.get("deviceName") or "")
                address = str(paired.get("address") or arg)
        else:
            error = NOT_INSTALLED
    elif verb == "find":
        found = _call(lan.listen_once, default=[]) if lan else []
        found = found if isinstance(found, list) else []
        if found:
            first = found[0] if isinstance(found[0], dict) else {}
            name = str(first.get("deviceName") or "")
            address = str(first.get("address") or "")
            if address:
                _call(helper.remember, address) if helper else None
            note = f"Found {len(found)} device(s) on the Wi-Fi."
        else:
            note = "No device announced itself on the Wi-Fi. Open the phone's link app and try again."
    elif verb == "findable":
        if arg.lower() not in ("on", "off"):
            error = "findable needs on or off"
        else:
            findable = arg.lower() == "on"
            if settings:
                _call(settings.set_bool, FINDABLE_KEY, findable)
            if findable:
                note = (
                    str(
                        _call(
                            helper.announce, default="Could not announce this computer."
                        )
                    )
                    if helper
                    else NOT_INSTALLED
                )
            else:
                note = "This computer is no longer announcing itself."
    else:
        error = "link needs state, pair, forget, find or findable"
    return _link_answer(
        {
            "paired": bool(paired),
            "name": name,
            "address": address,
            "status": state,
            "note": note,
            "findable": findable,
        },
        error,
    )


# --- background switches ----------------------------------------------------


def cmd_background(*args) -> dict:
    verb = str(args[0] if args else "list").strip().lower()
    settings = _settings()
    if settings is None:
        return _answer(NOT_INSTALLED)
    if verb == "set":
        key = str(args[1] if len(args) > 1 else "").strip()
        value = str(args[2] if len(args) > 2 else "").strip().lower()
        if key not in SWITCH_KEYS:
            return _answer(f"unknown switch: {key}", on=False)
        if value not in ("on", "off"):
            return _answer("set needs on or off", on=False)
        _call(settings.set_bool, key, value == "on")
        return _answer("", on=bool(_call(settings.get_bool, key, False)))
    if verb == "list":
        values = _call(settings.all, default={}) or {}
        switches = []
        for key, label, detail in SWITCH_ROWS:
            switches.append(
                {
                    "key": key,
                    "label": label,
                    "detail": detail,
                    "on": bool(values.get(key, key in DEFAULT_ON)),
                }
            )
        return _answer(
            "",
            switches=switches,
            on=sum(1 for row in switches if row["on"]),
            total=len(switches),
        )
    return _answer("background needs list or set")


# --- call audio -------------------------------------------------------------


def _gateway(module) -> str:
    """The connected phone's audio gateway path, or "" when none is connected."""
    found = _call(module.gateways, default=[]) or []
    if found:
        first = found[0]
        return str(first[0] if isinstance(first, (list, tuple)) else first)
    phones = _call(module.phones, default=[]) or [] if hasattr(module, "phones") else []
    for row in phones:
        item = row[0] if isinstance(row, (list, tuple)) else row
        if item:
            return str(item)
    return ""


def cmd_audio(*args) -> dict:
    verb = str(args[0] if args else "state").strip().lower()
    if verb not in ("state", "pc", "phone"):
        return _answer("audio needs state, pc or phone")
    data, error = _script("SHANI_AUDIO", [verb], log="SHANI_AUDIO_LOG")
    if data is not None:
        return _answer(
            error, where=str(data.get("where") or ""), note=str(data.get("note") or "")
        )
    module = _module("phone.bt_telephony")
    if module is None:
        return _answer(NOT_INSTALLED)
    gateway = _gateway(module)
    if not gateway:
        return _answer("", where="", note="No phone is connected for call audio.")
    if verb == "state":
        where, _state = _call(module.audio_route, gateway, default=("", ""))
        where = str(where or "")
        if where not in ("pc", "phone"):
            return _answer(
                "", where="", note="The phone did not say where the sound goes."
            )
        return _answer("", where=where, note=f"Call sound goes to the {where}.")
    done, why = _call(
        module.set_audio_route,
        gateway,
        verb,
        default=(False, "could not move the sound"),
    )
    if not done:
        return _answer(str(why or "could not move the sound"))
    where, _state = _call(module.audio_route, gateway, default=(verb, ""))
    where = str(where or verb)
    return _answer("", where=where, note=f"Call sound now goes to the {where}.")


# --- dispatch ----------------------------------------------------------------

HANDLERS = {
    "music": cmd_music,
    "files": None,  # the second word chooses received / send / receive
    "remote": cmd_remote,
    "link": cmd_link,
    "background": cmd_background,
    "audio": cmd_audio,
}


def _files(*args) -> dict:
    verb = str(args[0] if args else "").strip().lower()
    if verb == "received":
        return cmd_files_received(*args[1:])
    if verb == "send":
        return cmd_files_send(*args[1:])
    if verb == "receive":
        return cmd_files_receive(*args[1:])
    return _answer(
        "files needs received, send or receive", folder="", files=[], on=False
    )


def main(argv: list[str]) -> int:
    command = str(argv[1] if len(argv) > 1 else "")
    args = argv[2:]
    blank = dict(BLANKS.get(command, {}))
    handler = _files if command == "files" else HANDLERS.get(command)
    if handler is None:
        answer = _answer("usage: phone_tools.py <" + "|".join(HANDLERS) + ">")
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
            _answer("phone tools could not encode the answer", **blank),
            ensure_ascii=False,
        )
    print(line, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
