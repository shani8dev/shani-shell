import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("launcher_entry", Path(__file__).parent.parent / "bridge" / "launcher-entry.py")
le = importlib.util.module_from_spec(spec)
spec.loader.exec_module(le)


def test_app_id_from_uri():
    assert le.app_id("application://org.telegram.desktop.desktop") == "org.telegram.desktop"
    assert le.app_id("application://firefox.desktop") == "firefox"


def test_entry_keeps_known_keys_only():
    got = le.entry("application://thunderbird.desktop", {"count": 4, "count-visible": True, "quicklist": "/x", "progress": 0.5})
    assert got == {"app": "thunderbird", "count": 4, "countVisible": True, "progress": 0.5}
