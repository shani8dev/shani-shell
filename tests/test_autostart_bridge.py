"""bridge/autostart.py, run for real against a temporary XDG home."""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "bridge" / "autostart.py"


def run(env, *args):
    out = subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True, env=env, check=True)
    return json.loads(out.stdout)


def home(tmp_path):
    env = {"HOME": str(tmp_path), "XDG_CONFIG_HOME": str(tmp_path / "cfg"),
           "XDG_DATA_HOME": str(tmp_path / "data"), "XDG_DATA_DIRS": str(tmp_path / "sys")}
    apps = tmp_path / "data" / "applications"
    apps.mkdir(parents=True)
    (apps / "org.example.Notes.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Notes\nComment=Write things down\nExec=notes\n")
    return env


def test_add_by_id_turn_off_on_and_remove(tmp_path):
    env = home(tmp_path)
    assert run(env, "add", json.dumps({"id": "org.example.Notes"}))["ok"]
    [e] = [x for x in run(env, "list")["entries"] if x["file"] == "org.example.Notes.desktop"]
    assert e["name"] == "Notes" and e["desc"] == "Write things down" and e["on"] and e["mine"]
    run(env, "set", json.dumps({"file": e["file"], "on": False}))
    assert "Hidden=true" in (tmp_path / "cfg" / "autostart" / e["file"]).read_text()
    assert not [x for x in run(env, "list")["entries"] if x["file"] == e["file"]][0]["on"]
    run(env, "set", json.dumps({"file": e["file"], "on": True}))
    assert "Hidden=" not in (tmp_path / "cfg" / "autostart" / e["file"]).read_text()
    run(env, "remove", e["file"])
    assert not (tmp_path / "cfg" / "autostart" / e["file"]).exists()


def test_add_any_desktop_file_by_path(tmp_path):
    env = home(tmp_path)
    f = tmp_path / "my.desktop"
    f.write_text("[Desktop Entry]\nName=Mine\nExec=true\n")
    assert run(env, "add", json.dumps({"path": str(f)}))["file"] == "my.desktop"
    assert run(env, "add", json.dumps({"path": str(tmp_path / "x.txt")}))["error"]


def test_names_are_checked(tmp_path):
    env = home(tmp_path)
    assert run(env, "remove", "../../etc/passwd")["error"]
    assert run(env, "set", json.dumps({"file": "../x.desktop", "on": False}))["error"]
    assert run(env, "add", json.dumps({"id": "a/../../b"}))["error"]


def test_the_startup_page_is_the_one_place():
    page = (ROOT / "shani/Modules/Settings/SettingsStartup.qml").read_text()
    assert '"autostart.py"' in page and "addFile()" in page
    assert "sed -i" not in page          # the shell+sed copy is gone
