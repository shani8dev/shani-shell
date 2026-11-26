"""Provider keys reach Chronoa through the engine's SettingsSet, not GSettings.

The fake Agent owns the real Agent interface (its settings table comes from
dev/mock-chronoa.py); the real bridge answers the shell's socket request. A
refusal comes back ID-correlated so the shell can show it.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_chronoa_inventory import (  # noqa: E402
    ROOT,
    bus,
    start_agent,
    start_bridge,
    stop,
)


def test_key_write_reaches_the_engine_with_confirm(bus, tmp_path):
    agent = start_agent(tmp_path, bus)
    bridge, client = start_bridge(tmp_path, bus)
    key = "a-key-that-must-not-be-echoed"
    try:
        client.send(
            op="settings-set", id="k1", name="openai-api-key", value=key, confirm=True
        )
        reply = client.wait("settings", "k1")
        assert "error" not in reply, reply
        assert reply["name"] == "openai-api-key"
        assert reply["value"] == ""
        assert key not in json.dumps(reply)

        # the engine refuses a secret write without consent; the bridge says so
        client.send(
            op="settings-set", id="k2", name="openai-api-key", value=key, confirm=False
        )
        refused = client.wait("settings", "k2")
        assert "confirmation required" in refused["error"], refused
        assert key not in json.dumps(refused)
    finally:
        client.close()
        stop(bridge)
        stop(agent)


def test_no_agent_gives_a_plain_error(bus, tmp_path):
    bridge, client = start_bridge(tmp_path, bus)
    try:
        client.send(
            op="settings-set", id="off", name="openai-api-key", value="x", confirm=True
        )
        assert client.wait("settings", "off") == {
            "type": "settings",
            "op": "set",
            "id": "off",
            "name": "openai-api-key",
            "error": "Chronoa is not running",
        }
    finally:
        client.close()
        stop(bridge)


def test_the_shell_uses_the_engine_not_gsettings():
    providers = (ROOT / "shani/Services/AIProviders.qml").read_text(encoding="utf-8")
    assert 'op: "settings-set"' in providers
    assert "confirm: true" in providers
    assert "Bridge.send" in providers
    for bad in ("gsettings", "|| true", "execDetached"):
        assert bad not in providers, bad
    models = (ROOT / "shani/Modules/Models/ModelsWindow.qml").read_text(
        encoding="utf-8"
    )
    assert "AIProviders.syncError" in models
