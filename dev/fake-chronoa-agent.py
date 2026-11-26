#!/usr/bin/env python3
"""Stand-in for Chronoa's headless engine on a private session bus.

It owns dev.shani.chronoa.Agent and dev.shani.chronoa.Gateways. Inventory comes
from the fixture functions below: the shapes are Chronoa's inventory.py shapes
and the words are chosen so a shell screenshot can be checked. Turn, Approve,
Write, FindFiles and Submit go to dev/mock-chronoa.py's handlers, so the turn
tests keep working against this stand-in.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "bridge"))

from agent_contract import XML as AGENT_XML  # noqa: E402

GATEWAY_NAME = "dev.shani.chronoa.Gateways"
GATEWAY_PATH = "/dev/shani/chronoa/Gateways"
GATEWAY_IFACE = "dev.shani.chronoa.Gateways"

GATEWAY_XML = """
<node>
  <interface name="dev.shani.chronoa.Gateways">
    <method name="Submit">
      <arg name="gateway" type="s" direction="in"/>
      <arg name="text" type="s" direction="in"/>
      <arg name="reply" type="s" direction="out"/>
    </method>
  </interface>
</node>
"""

LIMIT = 100


def _conversations(limit=None):
    return [
        {
            "id": "trip-1",
            "title": "Trip planning",
            "updated": 1760000000,
            "created": 1759999000,
            "messages": 4,
            "active": True,
            "forked_from": "",
        }
    ]


def _models(limit=None):
    return [
        {
            "task": "chat",
            "model": "local-test-model",
            "why": "chosen for this machine",
        }
    ]


def _skills(limit=None):
    return [
        {
            "name": "check_weather",
            "description": "Look up the weather before a trip",
            "gate": None,
        }
    ]


def _routines(limit=None):
    return [{"name": "Good morning", "phrases": ["good morning", "morning brief"]}]


def _triggers(limit=None):
    return [
        {
            "name": "Low battery",
            "sense": "battery",
            "match_mode": "below",
            "substring": "",
            "keywords": [],
            "actuator": "notice",
            "arguments": {},
            "cooldown_seconds": 300,
            "enabled": True,
            "allow_destructive": False,
            "last_fired_at": None,
        }
    ]


def _privacy(limit=None):
    return {
        "privacy_mode": "private",
        "granted_consent_key": "senses.screen.read",
        "senses": [{"name": "screen", "key": "senses.screen.read", "enabled": True}],
        "recent_egress": 0,
    }


def _memory(limit=None):
    return [
        {
            "content": "Prefers trains to flights",
            "source": "conversation",
            "created_at": 1759999500,
            "metadata": {"topic": "travel"},
        }
    ]


def _senses(limit=None):
    return [{"name": "screen", "key": "senses.screen.read", "enabled": True}]


def _capabilities(limit=None):
    return [
        {
            "tool": "check_weather",
            "group": "information",
            "label": "Check the weather",
            "description": "Look up the weather before a trip",
            "consent_key": "tools.check_weather",
            "example": "What is the weather in Bengaluru?",
        }
    ]


def _status(limit=None):
    return {
        "llm_model": "local-test-model",
        "llm_installed": True,
        "stt_available": True,
        "tts_engine": "test-voice",
        "privacy_mode": "private",
    }


_SECTIONS = {
    "conversations": _conversations,
    "models": _models,
    "skills": _skills,
    "routines": _routines,
    "triggers": _triggers,
    "privacy": _privacy,
    "memory": _memory,
    "senses": _senses,
    "capabilities": _capabilities,
    "status": _status,
}

SECTIONS = tuple(sorted(_SECTIONS))


def describe(section: str, limit=None) -> dict:
    """Chronoa's inventory.describe shape, from fixture data, never a store."""
    fn = _SECTIONS.get(str(section or ""))
    if fn is None:
        return {
            "section": section,
            "error": "unknown section",
            "allowed": list(SECTIONS),
        }
    try:
        cap = LIMIT if limit is None else max(1, min(int(limit), LIMIT))
        return {"section": section, "items": fn(cap)}
    except Exception as exc:  # one broken section is one panel's message
        return {"section": section, "error": f"{type(exc).__name__}: {exc}"}


def _load_mock():
    path = HERE / "mock-chronoa.py"
    spec = importlib.util.spec_from_file_location("mock_chronoa", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_mock = _load_mock()


def on_agent_call(connection, sender, path, iface, method, params, invocation):
    if method == "Inventory":
        section = str(params.unpack()[0] or "")
        invocation.return_value(GLib.Variant("(s)", (json.dumps(describe(section)),)))
        return
    # Turn, Approve, Write and FindFiles stay the mock's, with our connection
    # so its printed turn events reach whoever is on this bus.
    _mock.on_agent_call(connection, sender, path, iface, method, params, invocation)


def on_gateway_call(connection, sender, path, iface, method, params, invocation):
    _mock.on_gateway_call(connection, sender, path, iface, method, params, invocation)


def main() -> int:
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    _mock.conn = conn
    node = Gio.DBusNodeInfo.new_for_xml(AGENT_XML)
    conn.register_object(
        _mock.AGENT_PATH, node.interfaces[0], on_agent_call, None, None
    )
    conn.register_object(
        GATEWAY_PATH,
        Gio.DBusNodeInfo.new_for_xml(GATEWAY_XML).interfaces[0],
        on_gateway_call,
        None,
        None,
    )
    for name in (_mock.AGENT_NAME, GATEWAY_NAME):
        Gio.bus_own_name_on_connection(
            conn, name, Gio.BusNameOwnerFlags.NONE, None, None
        )
    print("fake Chronoa agent up", flush=True)
    GLib.MainLoop().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
