"""The phone switches keep a file of their own, and nobody works from a stale copy.

They used to share ~/.config/shani-shell/settings.json with the shell's QML
settings. Both sides wrote the whole file: the QML side keeps only its own keys
(the phone switches vanished on its next save), and the phone side wrote back
the copy it read at start (a shell setting changed since was undone). Several
processes also each held a Settings, so one never saw another's switch.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bridge"))

from phone import settings  # noqa: E402


def test_not_the_shells_settings_file(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    st = settings.Settings()
    assert st.path == tmp_path / "shani-shell" / "phone.json"
    shell = tmp_path / "shani-shell" / "settings.json"
    shell.parent.mkdir(parents=True)
    shell.write_text('{"blur": false}')
    st.set_bool("phone-control-enabled", True)
    assert json.loads(shell.read_text()) == {"blur": False}


def test_a_switch_written_elsewhere_is_seen_and_kept(tmp_path):
    path = tmp_path / "phone.json"
    service = settings.Settings(path)          # the phone service, started first
    other = settings.Settings(path)            # health.py, a later process
    other.set_bool("watch-companion-enabled", True)
    assert service.get_bool("watch-companion-enabled") is True
    service.set_bool("phone-control-enabled", True)
    assert json.loads(path.read_text()) == {"watch-companion-enabled": True,
                                            "phone-control-enabled": True}
    assert service.all()["watch-companion-enabled"] is True


def test_no_temporary_file_left_behind(tmp_path):
    settings.Settings(tmp_path / "phone.json").set_bool("landline-enabled", True)
    assert [p.name for p in tmp_path.iterdir()] == ["phone.json"]
