import importlib.util, json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_groups_list_shape():
    r = subprocess.run([sys.executable, str(ROOT / "bridge/groups.py"), "list"], capture_output=True, text=True)
    d = json.loads(r.stdout)
    assert "groups" in d and "people" in d
    for g in d["groups"]:
        assert {"name", "desc", "members"} <= set(g)


def test_shani_admin_rejects_unknown_group(monkeypatch):
    spec = importlib.util.spec_from_file_location("shani_admin", ROOT / "bridge/shani-admin.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    monkeypatch.setattr(mod, "person", lambda n: type("P", (), {"pw_name": "alice"})())
    import pytest
    with pytest.raises(mod.Refused, match="not a group this tool manages"):
        mod.user_group({"username": "alice", "group": "wheel", "member": True})
