"""bridge/launch-app.py: the graphics card an app gets, and real launches
through GLib of a throwaway desktop file that writes down its environment."""
import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

BRIDGE = Path(__file__).parent.parent / "bridge" / "launch-app.py"
spec = importlib.util.spec_from_file_location("launch_app", BRIDGE)
la = importlib.util.module_from_spec(spec)
spec.loader.exec_module(la)


def fake_switcheroo(tmp_path, two=True):
    out = "Device: 0\n  Name: Intel\n  Default: yes\n  Environment: DRI_PRIME=pci-0000_00_02_0\n"
    if two:
        out += "\nDevice: 1\n  Name: NVIDIA RTX\n  Default: no\n  Environment: __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia\n"
    f = tmp_path / "switcherooctl"
    f.write_text(f"#!/bin/sh\ncat <<'X'\n{out}X\n")
    f.chmod(0o755)
    return f


def test_switcheroo_gives_the_other_cards_environment(tmp_path, monkeypatch):
    monkeypatch.setenv("SHANI_SWITCHEROOCTL", str(fake_switcheroo(tmp_path)))
    env, how = la.discrete_env()
    assert how == "switcheroo-control"
    assert env == {"__NV_PRIME_RENDER_OFFLOAD": "1", "__GLX_VENDOR_LIBRARY_NAME": "nvidia"}


def test_nvidia_offload_without_switcheroo(tmp_path, monkeypatch):
    monkeypatch.setenv("SHANI_SWITCHEROOCTL", str(fake_switcheroo(tmp_path, two=False)))
    (tmp_path / "nv").write_text("NVRM version: 570")
    monkeypatch.setenv("SHANI_NVIDIA_PROC", str(tmp_path / "nv"))
    env, how = la.discrete_env()
    assert how == "nvidia-prime" and env["__NV_PRIME_RENDER_OFFLOAD"] == "1" and env["__GLX_VENDOR_LIBRARY_NAME"] == "nvidia"


def test_dri_prime_with_two_render_nodes(tmp_path, monkeypatch):
    monkeypatch.setenv("SHANI_SWITCHEROOCTL", str(fake_switcheroo(tmp_path, two=False)))
    monkeypatch.setenv("SHANI_NVIDIA_PROC", str(tmp_path / "none"))
    dri = tmp_path / "dri"
    dri.mkdir()
    (dri / "renderD128").touch()
    (dri / "renderD129").touch()
    monkeypatch.setenv("SHANI_DRI_DIR", str(dri))
    assert la.discrete_env() == ({"DRI_PRIME": "1"}, "dri-prime")


@pytest.fixture
def app(tmp_path):
    """A desktop file whose program writes its environment and arguments to a file."""
    data = tmp_path / "share"
    (data / "applications").mkdir(parents=True)
    out = tmp_path / "ran.json"
    prog = tmp_path / "prog.py"
    prog.write_text(f"#!{sys.executable}\nimport json, os, sys\njson.dump({{'env': dict(os.environ), 'argv': sys.argv[1:]}}, open('{out}', 'w'))\n")
    prog.chmod(0o755)

    def make(name, extra=""):
        (data / "applications" / f"{name}.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName={name}\nExec={prog} %F\n{extra}")
        return name

    # a terminal that only runs what follows -e: nothing here may reach the real desktop
    term = tmp_path / "myterm"
    term.write_text("#!/bin/sh\nshift\nexec \"$@\"\n")
    term.chmod(0o755)
    env = {**os.environ, "XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(data),
           "SHANI_SWITCHEROOCTL": str(fake_switcheroo(tmp_path)), "SHANI_TERMINAL": str(term)}

    def run(*args):
        if out.exists():
            out.unlink()
        r = subprocess.run([sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env, timeout=20)
        for _ in range(40):
            if out.exists() and out.stat().st_size:
                break
            time.sleep(0.1)
        return json.loads(r.stdout.splitlines()[-1]), (json.loads(out.read_text()) if out.exists() else None)
    return make, run


def test_an_app_that_prefers_the_other_card_gets_it(app):
    make, run = app
    make("game", "PrefersNonDefaultGPU=true\n")
    res, ran = run("game")
    assert res["ok"] and res["gpu"] == "switcheroo-control"
    assert ran["env"].get("__NV_PRIME_RENDER_OFFLOAD") == "1"


def test_default_overrides_the_apps_wish_and_own_env_reaches_it(app):
    make, run = app
    make("game2", "PrefersNonDefaultGPU=true\n")
    res, ran = run("game2", "--gpu", "default", "--env", "MANGOHUD=1")
    assert "__NV_PRIME_RENDER_OFFLOAD" not in ran["env"] and ran["env"]["MANGOHUD"] == "1"


def test_terminal_apps_run_in_the_terminal(app):
    make, run = app
    make("tui", "Terminal=true\n")
    res, ran = run("tui", "--args", "--hello")
    assert res["how"] == "terminal" and ran["argv"] == ["--hello"]
