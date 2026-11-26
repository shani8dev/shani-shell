"""The phone backends keep their state in the shell's homes.

An upgrade from the old separate app must not lose contacts or call history,
so startup makes one quiet move. The marker makes it a single event, and an
existing file is never overwritten.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

from phone import paths  # noqa: E402


def test_one_time_move_keeps_contacts_and_history(tmp_path, monkeypatch):
    homes = {}
    for var, leaf in (
        ("XDG_CONFIG_HOME", "config"),
        ("XDG_DATA_HOME", "data"),
        ("XDG_STATE_HOME", "state"),
    ):
        homes[leaf] = tmp_path / leaf
        monkeypatch.setenv(var, str(homes[leaf]))

    old_config = homes["config"] / ("shani" + "-link")
    old_data = homes["data"] / ("shani" + "-link")
    old_state = homes["state"] / ("shani" + "-link")
    for old, name, body in (
        (old_config, "sip-accounts.json", '{"accounts": []}'),
        (old_data, "calls.json", '[{"number": "100"}]'),
        (old_data / "contacts", "ada.vcf", "BEGIN:VCARD\nEND:VCARD\n"),
        (old_state, "clipboard-origin.json", "{}"),
    ):
        old.mkdir(parents=True, exist_ok=True)
        (old / name).write_text(body, encoding="utf-8")

    paths.migrate_old_state()

    assert (
        homes["data"] / "shani-shell" / "calls.json"
    ).read_text() == '[{"number": "100"}]'
    assert (homes["data"] / "shani-shell" / "contacts" / "ada.vcf").is_file()
    assert (homes["config"] / "shani-shell" / "sip-accounts.json").is_file()
    assert (homes["state"] / "shani-shell" / "clipboard-origin.json").is_file()
    for old in (old_config, old_data, old_state):
        assert not any(old.rglob("*.*")) if old.exists() else True
    assert (homes["config"] / "shani-shell" / "phone-data-migrated").is_file()


def test_move_is_once_and_never_overwrites(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    new = tmp_path / "data" / "shani-shell"
    new.mkdir(parents=True)
    (new / "calls.json").write_text("new", encoding="utf-8")
    old = tmp_path / "data" / ("shani" + "-link")
    old.mkdir(parents=True)
    (old / "calls.json").write_text("old", encoding="utf-8")
    paths.migrate_old_state()
    assert (new / "calls.json").read_text() == "new"
    (old / "later.json").write_text("later", encoding="utf-8")
    paths.migrate_old_state()
    assert not (new / "later.json").exists()


def test_startup_calls_the_migration():
    source = (ROOT / "bridge" / "chronoa-bridge.py").read_text(encoding="utf-8")
    assert "migrate_old_state()" in source


def test_health_can_ring_a_paired_watch(monkeypatch):
    """Find my watch is a real action, not a note that says it cannot work."""
    import health

    class Watch:
        def run(self, arguments):
            assert arguments == {"action": "find"}
            return "Asha's watch is ringing."

    monkeypatch.setattr(health, "watch", Watch())
    assert health.cmd_find_watch() == {
        "ok": True,
        "error": "",
        "note": "Asha's watch is ringing.",
    }


def test_the_call_state_file_is_one_ring_and_the_shells_own(tmp_path, monkeypatch):
    from phone import call_state

    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    assert call_state.current() == {}
    row = call_state.ring("c1", "Asha Patil", "9844444444", "phone")
    assert row["id"] == "c1" and row["name"] == "Asha Patil"
    assert call_state.current()["number"] == "9844444444"
    assert call_state.ring("c2", "Someone else", "1", "modem")["id"] == "c2"
    assert call_state.clear("c1") is False  # the later ring is still up
    assert call_state.clear("c2") is True
    assert call_state.current() == {}
    assert call_state.path().parent.name == "shani-shell"


def test_every_ringing_line_writes_the_card_not_a_notification():
    for name in ("incoming_call.py", "landline/__init__.py", "sip_accounts.py"):
        source = (ROOT / "bridge" / "phone" / name).read_text(encoding="utf-8")
        assert "call_state.ring" in source, name
        assert "call.incoming" not in source, name
    # the modem reuses the phone watcher's card and only names its own line
    modem = (ROOT / "bridge" / "phone" / "mm_voice.py").read_text(encoding="utf-8")
    assert 'line = "modem"' in modem and "call.incoming" not in modem


def test_a_missed_call_opens_the_shells_own_window(tmp_path, monkeypatch):
    """The notification's buttons hand over to Calls/Messages, not another app."""
    from phone import missed_call

    log = tmp_path / "ipc.log"
    stub = tmp_path / "qs"
    stub.write_text(f'#! /bin/sh\nprintf "%s\\n" "$@" >> {log}\n', encoding="utf-8")
    stub.chmod(0o755)
    monkeypatch.setenv("SHANI_QS", str(stub))
    missed_call._launch_app(["--message", "+919900000000"])
    missed_call._launch_app(["--dial", "+919911111111"])
    got = log.read_text(encoding="utf-8").splitlines()
    assert "messagesOpen" in got and "+919900000000" in got
    assert "phoneOpen" in got and "+919911111111" in got
