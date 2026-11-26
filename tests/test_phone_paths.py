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

    old_config = homes["config"] / "shani" + "-link"
    old_data = homes["data"] / "shani" + "-link"
    old_state = homes["state"] / "shani" + "-link"
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
    old = tmp_path / "data" / "shani" + "-link"
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
