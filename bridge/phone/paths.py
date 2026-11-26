"""Where shani-shell keeps things, and an honest sentence for a missing helper.

The XDG homes are resolved per call, never at import, so a test (or a sandbox)
relocates everything by setting the variable. The phone link's identity lives
in the generic ~/.local/state/kdeconnect, where it always did: the phones that
paired with this computer know it by that, so it never moves.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

# the helper binaries this package runs, and the Arch package that has each
_PACKAGES = {
    "rtl_fm": "rtl-sdr",
    "rtl_test": "rtl-sdr",
    "ir-ctl": "v4l-utils",
    "ir-keytable": "v4l-utils",
    "nfc-list": "libnfc",
    "nfc-scan-device": "libnfc",
    "nfc-mfultralight": "libnfc",
    "nfc-emulate-forum-tag4": "libnfc",
    "adb": "android-tools",
    "scrcpy": "scrcpy",
    "bluetoothctl": "bluez-utils",
    "busctl": "systemd",
    "wpctl": "wireplumber",
    "pw-cat": "pipewire",
    "pw-play": "pipewire",
    "irsend": "lirc",
    "ffmpeg": "ffmpeg",
    "gatttool": "bluez-deprecated-tools",
}


def _home(var: str, *fallback: str) -> Path:
    configured = os.environ.get(var, "")
    if configured and os.path.isabs(configured):
        return Path(configured)
    return Path.home().joinpath(*fallback)


def data_home() -> Path:
    return _home("XDG_DATA_HOME", ".local", "share")


def state_home() -> Path:
    return _home("XDG_STATE_HOME", ".local", "state")


def config_home() -> Path:
    return _home("XDG_CONFIG_HOME", ".config")


def migrate_old_state() -> None:
    """Move the old companion's files into the shell's homes, once, quietly.

    This is the only place the old path may appear: people upgrading must keep
    their contacts, call history and line accounts. Nothing is overwritten,
    and a marker makes every later startup a no-op.
    """
    marker = config_home() / "shani-shell" / "phone-data-migrated"
    if marker.exists():
        return
    try:
        for home in (config_home(), data_home(), state_home()):
            old = home / "shani-link"
            new = home / "shani-shell"
            if not old.is_dir():
                continue
            new.mkdir(parents=True, exist_ok=True)
            for entry in old.iterdir():
                target = new / entry.name
                if not target.exists():
                    shutil.move(str(entry), str(target))
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.touch()
    except OSError:
        pass  # a migration must never stop the shell from starting


def tool_missing(binary: str, purpose: str) -> str:
    """What could not be done, and which package would do it."""
    return f"Cannot {purpose}: `{binary}` is not installed (package: {_PACKAGES.get(binary, 'the one that provides it')})."
