#!/usr/bin/env python3
"""Deterministic stand-in for the phone tools behind bridge/phone_tools.py.

One JSON object per call, like every bridge helper. bridge/phone_tools.py calls
this through its SHANI_* overrides, so the argv has the mode baked in:

  SHANI_MUSIC="python3 .../fake-phone-tools.py music"          music <action>
  SHANI_FILES_SEND="python3 .../fake-phone-tools.py files-send" files-send <path> [device]
  SHANI_PHONE_REMOTE="python3 .../fake-phone-tools.py remote"   remote <verb> [arg]
  SHANI_PHONE_LINK="python3 .../fake-phone-tools.py link"       link <verb> [arg]
  SHANI_AUDIO="python3 .../fake-phone-tools.py audio"           audio <verb>

Two commands are for the harness itself: `seed` resets the state file and the
real phone settings file (the bridge reads that one for background switches and
file receiving); `background <list|set KEY on|off>` can also be called directly
to check the same switch rows the bridge lists.

Env:
  SHANI_PHONE_TOOLS_STATE   state file (default /tmp/fake-phone-tools.json)
  SHANI_PHONE_TOOLS_LOG     call log (default /tmp/fake-phone-tools-calls)
  SHANI_PHONE_SETTINGS_FILE phone settings file (default XDG_CONFIG_HOME/shani-shell/settings.json)
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

TRACKS = (
    ("Mono Train", "The Signals"),
    ("Quiet Streets", "Night Bus"),
    ("Paper Kites", "Low Tide"),
)

DEFAULTS = {
    "music": {"index": 0, "playing": True},
    "remote": {"on": True},
    "link": {
        "paired": True,
        "name": "Pixel 8",
        "address": "192.168.1.42",
        "status": "paired",
        "findable": False,
        "note": "",
    },
    "audio": {"where": "pc"},
}

#: The switches the shell shows on Settings > Background services. The bridge
#: owns the real list; this fake only mirrors it for deterministic dev runs.
SEED_SETTINGS = {
    "phone-control-enabled": True,  # Receive files
    "phone-remote-enabled": True,  # Phone as a remote
    "watch-companion-enabled": True,
    "bluetooth-media-remote-enabled": True,
    "modem-call-enabled": True,
}

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


def state_path() -> Path:
    return Path(os.environ.get("SHANI_PHONE_TOOLS_STATE", "/tmp/fake-phone-tools.json"))


def log_path() -> Path:
    return Path(os.environ.get("SHANI_PHONE_TOOLS_LOG", "/tmp/fake-phone-tools-calls"))


def settings_path() -> Path:
    override = os.environ.get("SHANI_PHONE_SETTINGS_FILE", "")
    if override:
        return Path(override)
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "shani-shell" / "settings.json"


def load() -> dict:
    try:
        data = json.loads(state_path().read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    return json.loads(json.dumps(DEFAULTS))


def save(data: dict) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def note(argv: list[str]) -> None:
    try:
        path = log_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(" ".join(str(a) for a in argv) + "\n")
    except OSError:
        pass  # a log must never change the answer


def seed_settings() -> None:
    path = settings_path()
    try:
        data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
        if not isinstance(data, dict):
            data = {}
    except (OSError, ValueError):
        data = {}
    data.update(SEED_SETTINGS)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1, sort_keys=True), encoding="utf-8")


def music(data: dict, args: list[str]) -> dict:
    row = data.setdefault("music", dict(DEFAULTS["music"]))
    action = str(args[0] if args else "status").lower()
    if action == "play":
        row["playing"] = True
    elif action == "pause":
        row["playing"] = False
    elif action == "toggle":
        row["playing"] = not bool(row["playing"])
    elif action in ("next", "previous"):
        step = 1 if action == "next" else -1
        row["index"] = (int(row.get("index", 0)) + step) % len(TRACKS)
    title, artist = TRACKS[int(row.get("index", 0)) % len(TRACKS)]
    state = "Playing" if row["playing"] else "Paused"
    return {
        "ok": True,
        "error": "",
        "state": state,
        "title": title,
        "artist": artist,
        "player": "Phone",
        "summary": f"{state} {artist} - {title}",
    }


def remote(data: dict, args: list[str]) -> dict:
    row = data.setdefault("remote", dict(DEFAULTS["remote"]))
    verb = str(args[0] if args else "status").lower()
    arg = " ".join(str(a) for a in args[1:]).strip()
    answer = {"ok": True, "error": "", "on": False, "status": "off", "note": ""}
    if verb == "on":
        row["on"] = True
        answer["note"] = "Phone remote turned on."
    elif verb == "off":
        row["on"] = False
        answer["note"] = "Phone remote turned off."
    elif verb == "press":
        answer["note"] = f"Pressed {arg} on the phone." if arg else "No key was sent."
    elif verb == "type":
        answer["note"] = (
            f"Typed {len(arg)} characters on the phone."
            if arg
            else "Nothing was typed."
        )
    elif verb != "status":
        return {
            **answer,
            "ok": False,
            "error": "remote needs status, on, off, press or type",
        }
    answer["on"] = bool(row["on"])
    answer["status"] = "connected" if row["on"] else "off"
    if verb == "status":
        answer["note"] = (
            "The phone is listening." if row["on"] else "Remote control is off."
        )
    save(data)
    return answer


def link(data: dict, args: list[str]) -> dict:
    row = data.setdefault("link", dict(DEFAULTS["link"]))
    verb = str(args[0] if args else "state").lower()
    arg = " ".join(str(a) for a in args[1:]).strip()
    note_text = ""
    if verb == "pair":
        if not arg:
            return {"ok": False, "error": "pair needs the phone's address"}
        row["paired"] = True
        row["name"] = "Pixel 8"
        row["address"] = arg
        row["status"] = "paired"
        note_text = "Paired with the phone."
    elif verb == "forget":
        row.update({"paired": False, "name": "", "address": "", "status": "not paired"})
        note_text = "The phone link was forgotten."
    elif verb == "find":
        note_text = "Found 1 device on the Wi-Fi."
    elif verb == "findable":
        if arg.lower() not in ("on", "off"):
            return {"ok": False, "error": "findable needs on or off"}
        row["findable"] = arg.lower() == "on"
        note_text = (
            "This computer is announcing itself."
            if row["findable"]
            else "This computer is no longer announcing itself."
        )
    elif verb != "state":
        return {
            "ok": False,
            "error": "link needs state, pair, forget, find or findable",
        }
    row["note"] = note_text
    save(data)
    return {
        "ok": True,
        "error": "",
        "paired": bool(row["paired"]),
        "name": str(row["name"]),
        "address": str(row["address"]),
        "status": str(row["status"] or ("paired" if row["paired"] else "not paired")),
        "note": note_text,
        "findable": bool(row["findable"]),
    }


def audio(data: dict, args: list[str]) -> dict:
    row = data.setdefault("audio", dict(DEFAULTS["audio"]))
    verb = str(args[0] if args else "state").lower()
    if verb in ("pc", "phone"):
        row["where"] = verb
        save(data)
    elif verb != "state":
        return {
            "ok": False,
            "error": "audio needs state, pc or phone",
            "where": "",
            "note": "",
        }
    where = str(row["where"] or "pc")
    return {
        "ok": True,
        "error": "",
        "where": where,
        "note": f"Call sound goes to the {where}.",
    }


def background(args: list[str]) -> dict:
    verb = str(args[0] if args else "list").lower()
    path = settings_path()
    try:
        values = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
        if not isinstance(values, dict):
            values = {}
    except (OSError, ValueError):
        values = {}
    switches = [
        {
            "key": key,
            "label": label,
            "detail": detail,
            "on": bool(values.get(key, key in SEED_SETTINGS)),
        }
        for key, label, detail in SWITCH_ROWS
    ]
    if verb == "list":
        return {
            "ok": True,
            "error": "",
            "switches": switches,
            "on": sum(1 for row in switches if row["on"]),
            "total": len(switches),
        }
    if verb == "set":
        key = str(args[1] if len(args) > 1 else "")
        value = str(args[2] if len(args) > 2 else "").lower()
        keys = {row[0] for row in SWITCH_ROWS}
        if key not in keys or value not in ("on", "off"):
            return {
                "ok": False,
                "error": "background set needs a known key and on or off",
                "on": False,
            }
        values[key] = value == "on"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(values, indent=1, sort_keys=True), encoding="utf-8")
        return {"ok": True, "error": "", "on": values[key]}
    return {"ok": False, "error": "background needs list or set"}


def main(argv: list[str]) -> int:
    args = [str(a) for a in argv[1:]]
    note(args)
    mode = str(args[0] if args else "").lower()
    if mode in ("reset", "seed"):
        save(json.loads(json.dumps(DEFAULTS)))
        if mode == "seed":
            seed_settings()
        answer: dict = {"ok": True, "error": ""}
    else:
        data = load()
        if mode == "music":
            answer = music(data, args[1:])
            if answer.get("ok"):
                save(data)  # a skip must survive into the next status read
        elif mode == "files-send":
            # The bridge logs the path itself; success needs no words.
            answer = {"ok": True, "error": ""}
        elif mode == "remote":
            answer = remote(data, args[1:])
        elif mode == "link":
            answer = link(data, args[1:])
        elif mode == "audio":
            answer = audio(data, args[1:])
        elif mode == "background":
            answer = background(args[1:])
        else:
            answer = {"ok": False, "error": "unknown phone tool: " + mode}
    print(json.dumps(answer, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
