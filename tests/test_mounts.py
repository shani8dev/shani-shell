"""bridge/mounts.py with dev/fake-gio.sh: a camera's, a phone's, an iPhone's files opened."""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "bridge" / "mounts.py"


def run(tmp_path, scheme):
    env = dict(os.environ, SHANI_GIO=str(ROOT / "dev/fake-gio.sh"), FAKE_GIO_LOG=str(tmp_path / "log"),
               FAKE_GIO_MOUNTED=str(tmp_path / "mounted"))
    return subprocess.run([sys.executable, str(TOOL), "open", scheme], env=env, capture_output=True, text=True).returncode


def test_a_camera_is_mounted_then_opened(tmp_path):
    assert run(tmp_path, "gphoto2") == 0
    log = (tmp_path / "log").read_text().splitlines()
    assert log == ["mount -li", "mount gphoto2://Canon_Inc._Canon_Digital_Camera/", "open gphoto2://Canon_Inc._Canon_Digital_Camera/"]


def test_already_mounted_is_just_opened(tmp_path):
    (tmp_path / "mounted").write_text("mtp://Google_Pixel_8_3A1B/\n")
    assert run(tmp_path, "mtp") == 0
    assert (tmp_path / "log").read_text().splitlines() == ["mount -li", "open mtp://Google_Pixel_8_3A1B/"]


def test_only_the_three_schemes(tmp_path):
    assert run(tmp_path, "file") == 2
