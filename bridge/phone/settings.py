"""shani-shell's own switches: what may run in the background without a click.

Not consent for an assistant - a person turns these on in the app, and nothing
here acts on its own beyond what they turned on (receiving files, keeping the
watch connected, showing the phone's texts, telling the watch about a call...).
Every service takes this object as its `config` and asks `get_bool(key)`, the
call it made of Chronoa's config before the move, with the same key names.

Kept in ~/.config/shani-shell/phone.json, a file of their own: the shell's
settings.json is written whole by the QML side (it keeps only its own keys),
and several processes here (the phone service, health.py, phone_tools.py) each
hold a Settings, so every read and write goes to the file, never to a copy
taken at start. A missing file is a fresh start.
"""
from __future__ import annotations

import json
import os
import threading

from phone import paths

#: the switches that moved with the devices, all off until turned on
KEYS = (
    "bluetooth-call-enabled", "bluetooth-gatt-enabled", "phone-control-enabled",
    "phone-remote-enabled", "phone-messages-read-enabled", "phone-messages-send-enabled",
    "watch-companion-enabled", "watch-nowplaying-enabled", "watch-weather-enabled",
    "landline-enabled", "bluetooth-media-remote-enabled", "modem-call-enabled",
    # files the paired phone sends over Wi-Fi (lan_receive.py): off by default,
    # since it opens KDE Connect's ports in the firewall while on
    "phone-lan-receive-enabled",
    # one clipboard with the paired phone (clipboard_sync.py): off by default -
    # a clipboard holds passwords and private things
    "phone-clipboard-sync-enabled",
)
#: the ones on unless turned off: music control from Bluetooth remotes, and the
#: computer's own mobile modem ringing (it is this computer's phone line, as
#: the landline is; with no voice modem it never rings at all)
DEFAULT_ON = {"bluetooth-media-remote-enabled", "modem-call-enabled"}


class Settings:
    def __init__(self, path=None):
        self.path = path or (paths.config_home() / "shani-shell" / "phone.json")
        self._lock = threading.Lock()

    def _load(self) -> dict:
        try:
            return json.loads(self.path.read_text())
        except (OSError, ValueError):
            return {}

    def _write(self, data: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_name(f".{self.path.name}.{os.getpid()}.{threading.get_ident()}.tmp")
        tmp.write_text(json.dumps(data, indent=1, sort_keys=True))
        os.chmod(tmp, 0o600)
        tmp.replace(self.path)

    def get_bool(self, key: str, default: bool = False) -> bool:
        with self._lock:
            return bool(self._load().get(key, default))

    def set_bool(self, key: str, value: bool) -> None:
        with self._lock:
            data = self._load()
            data[key] = bool(value)
            self._write(data)

    def all(self) -> dict:
        with self._lock:
            data = self._load()
            return {k: bool(data.get(k, k in DEFAULT_ON)) for k in KEYS}
