"""The shell's Chronoa settings page reads and writes through the engine ops.

The fake Agent owns the real Agent interface; the real bridge answers the
shell's socket requests. A static check keeps the page on the engine's rows
and off another product's labels.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_chronoa_inventory import (  # noqa: E402
    ROOT,
    bus,
    start_agent,
    start_bridge,
    stop,
)


def test_list_get_write_and_preset_over_the_socket(bus, tmp_path):
    agent = start_agent(tmp_path, bus)
    bridge, client = start_bridge(tmp_path, bus)
    try:
        client.send(op="settings-list", id="l1")
        listed = client.wait("settings", "l1")
        assert "error" not in listed, listed
        rows = listed["data"]
        assert len(rows) >= 5
        assert {"name", "kind", "value", "secret"} <= set(rows[0])
        assert all(r["value"] == "" for r in rows if r["secret"])

        client.send(op="settings-get", id="g1", name="privacy-mode")
        got = client.wait("settings", "g1")
        assert got["name"] == "privacy-mode"
        assert got["data"]["value"] == "private"

        client.send(
            op="settings-set",
            id="s1",
            name="privacy-mode",
            value="balanced",
            confirm=False,
        )
        assert "error" not in client.wait("settings", "s1")

        client.send(op="settings-preset", id="p1", name="chat", confirm=False)
        assert "confirmation required" in client.wait("settings", "p1")["error"]
        client.send(op="settings-preset", id="p2", name="chat", confirm=True)
        assert client.wait("settings", "p2")["data"]["preset"] == "chat"
    finally:
        client.close()
        stop(bridge)
        stop(agent)


def test_no_agent_is_a_plain_error(bus, tmp_path):
    bridge, client = start_bridge(tmp_path, bus)
    try:
        for op, req_id in (("settings-list", "l0"), ("settings-preset", "p0")):
            client.send(op=op, id=req_id, name="chat", confirm=True)
            assert client.wait("settings", req_id)["error"] == "Chronoa is not running"
    finally:
        client.close()
        stop(bridge)


def test_the_page_uses_the_engine_rows_and_plain_words():
    page = (ROOT / "shani/Modules/Settings/SettingsChronoa.qml").read_text()
    assert "ChronoaSettingsEditor" in page

    service = (ROOT / "shani/Services/ChronoaSettings.qml").read_text()
    for op in ("settings-list", "settings-get", "settings-set", "settings-preset"):
        assert 'op: "' + op + '"' in service, op
    assert "confirm: true" in service
    assert "secretsHidden" in service

    words = (ROOT / "shani/Services/ChronoaSettings.js").read_text()
    for bad in ("OpenAI", "Anthropic", "Google", "Groq", "OpenRouter"):
        assert bad not in words, bad

    mock = (ROOT / "dev/mock-chronoa.py").read_text()
    for method in ("SettingsList", "SettingsGet", "SettingsSet", "SettingsPreset"):
        assert 'method == "' + method + '"' in mock, method

    bridge = (ROOT / "bridge/chronoa-bridge.py").read_text()
    for op in ("settings-list", "settings-get", "settings-preset"):
        assert 'op == "' + op + '"' in bridge, op
