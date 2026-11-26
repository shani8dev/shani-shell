"""The one incoming call the shell may still need to answer.

The phone service writes this when a phone rings; the Calls window reads it
through ``bridge/link.py`` and sends its answer back with ``call-action``.
Both sides use the same small file, so a card never outlives its call. Nothing
here imports gi: the daemon and the bridge are separate processes.

    ring(call, name, number, line)  remember a ringing call (a repeat id is ignored)
    current()                       the call, or {} (anything older than 90 s is gone)
    clear(call=None)                forget it (with an id, only that call)
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

#: A ring nobody answered is not a call that can be answered later.
LIFETIME = 90


def path() -> Path:
    """The state file, resolved on every call so XDG homes can move."""
    try:
        from phone import paths

        base = paths.state_home()
    except Exception:  # noqa: BLE001 - a bridge with no phone package still has XDG
        base = Path(
            os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
        )
    return Path(base) / "shani-shell" / "incoming-call.json"


def _call_id(call: Any) -> str:
    """A ring's id, whether the caller passed an id, a row or a call object."""
    if isinstance(call, dict):
        return str(call.get("id") or call.get("call") or "")
    return str(getattr(call, "id", call) or "")


def _read() -> dict:
    try:
        row = json.loads(path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return row if isinstance(row, dict) else {}


def _fresh(row: dict) -> bool:
    try:
        return time.time() - float(row.get("when") or 0) <= LIFETIME
    except (TypeError, ValueError):
        return False


def current() -> dict:
    """The ringing call as {id, name, number, line, when}, or {}."""
    row = _read()
    if not row or not _fresh(row):
        if row:
            try:
                path().unlink()
            except OSError:
                pass
        return {}
    return {key: row.get(key, "") for key in ("id", "name", "number", "line", "when")}


def ring(call: Any, name: str = "", number: str = "", line: str = "") -> dict:
    """Write one ring atomically as the only call, mode 0600."""
    ident = _call_id(call)
    if not ident:
        return current()
    old = current()
    if old and str(old.get("id")) == ident:
        return old  # the same ring, with its original time
    row = {
        "id": ident,
        "name": str(name or ""),
        "number": str(number or ""),
        "line": str(line or ""),
        "when": int(time.time()),
    }
    target = path()
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".tmp")
        tmp.write_text(json.dumps(row, ensure_ascii=False), encoding="utf-8")
        os.chmod(tmp, 0o600)
        os.replace(tmp, target)
    except OSError:
        return {}
    return row


def clear(call: Any = None) -> bool:
    """Forget the call; with an id, only forget it when it is still that call."""
    ident = _call_id(call) if call is not None else ""
    if ident:
        now = current()
        if now and str(now.get("id")) != ident:
            return False
    try:
        path().unlink()
    except FileNotFoundError:
        return False
    except OSError:
        return False
    return True
