"""bridge/ratbag.py against dev/fake-ratbagctl.py (ratbagctl 0.18's output): what the
gaming-mouse page offers, and the ratbagctl commands its choices become."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge" / "ratbag.py"


@pytest.fixture
def env(tmp_path):
    return dict(os.environ, SHANI_RATBAGCTL=f"{sys.executable} {ROOT / 'dev/fake-ratbagctl.py'}",
                FAKE_RATBAG_STATE=str(tmp_path / "state.json"), FAKE_RATBAG_LOG=str(tmp_path / "log"))


def run(env, *args):
    p = subprocess.run([sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env, timeout=30)
    return p.returncode, json.loads(p.stdout)


def test_probe_reads_the_active_profile(env):
    _, r = run(env, "probe")
    (d,) = r["devices"]
    assert d["id"] == "singing-gundi" and d["name"] == "Logitech G502 HERO Gaming Mouse"
    assert d["dpi"] == 1600 and d["rate"] == 1000 and d["rates"] == [125, 250, 500, 1000]
    # 510 steps from the mouse: the usual ones offered, the current one among them
    assert d["dpis"] == [400, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000, 6400, 8000, 12000, 16000, 25600]
    assert [b["action"] for b in d["buttons"]] == ["left", "right", "middle", "back", "forward", "back", "forward", "disabled"]


def test_choices_become_ratbagctl_commands(env, tmp_path):
    assert run(env, "dpi", "singing-gundi", "3200")[0] == 0
    assert run(env, "rate", "singing-gundi", "500")[0] == 0
    assert run(env, "button", "singing-gundi", "5", "middle")[0] == 0
    assert run(env, "button", "singing-gundi", "6", "key:KEY_VOLUMEUP")[0] == 0
    assert run(env, "button", "singing-gundi", "7", "disabled")[0] == 0
    log = (tmp_path / "log").read_text().splitlines()
    assert "singing-gundi dpi set 3200" in log and "singing-gundi rate set 500" in log
    assert "singing-gundi button 5 action set button 3" in log
    assert "singing-gundi button 6 action set key KEY_VOLUMEUP" in log
    assert "singing-gundi button 7 action set disabled" in log
    _, r = run(env, "probe")
    d = r["devices"][0]
    assert d["dpi"] == 3200 and d["rate"] == 500
    assert [b["action"] for b in d["buttons"]][5:] == ["middle", "key:KEY_VOLUMEUP", "disabled"]


def test_nothing_else_reaches_ratbagctl(env, tmp_path):
    assert run(env, "button", "singing-gundi", "1", "macro +KEY_A")[0] == 1
    assert run(env, "dpi", "singing-gundi", "12; rm -rf /")[0] == 1
    assert not (tmp_path / "log").exists()


def test_no_mouse_no_devices(env):
    env["FAKE_RATBAG_NONE"] = "1"
    assert run(env, "probe") == (0, {"devices": []})


def test_without_libratbag(env):
    env["SHANI_RATBAGCTL"] = "/nonexistent/ratbagctl"
    assert run(env, "probe")[1]["devices"] == []
