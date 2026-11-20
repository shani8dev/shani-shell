"""bridge/lighting.py and shani-admin.py's `lighting`: coloured lights through the
kernel's multicolour LED class (Documentation/leds/leds-class-multicolor.rst).

The fake /sys/class/leds has a DualSense light bar (input12:rgb:indicator,
channels red green blue), a handheld's stick rings whose channel order is NOT
red-green-blue (go_s:rgb:joystick_rings, blue green red here), and a plain
single-colour LED that is not a coloured light.
"""
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

import pytest

BRIDGE = Path(__file__).resolve().parent.parent / "bridge"


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, BRIDGE / file)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def led(root, name, index=None, intensity=None, top=255, level=0):
    d = root / name
    d.mkdir(parents=True)
    (d / "max_brightness").write_text(f"{top}\n")
    (d / "brightness").write_text(f"{level}\n")
    if index:
        (d / "multi_index").write_text(index + "\n")
        (d / "multi_intensity").write_text(intensity + "\n")
    return d


@pytest.fixture
def leds(tmp_path, monkeypatch):
    root = tmp_path / "leds"
    bar = led(root, "input12:rgb:indicator", "red green blue", "0 0 255", 255, 255)
    rings = led(root, "go_s:rgb:joystick_rings", "blue green red", "100 0 50", 100, 50)
    led(root, "input3::capslock")
    monkeypatch.setenv("SHANI_LEDS_DIR", str(root))
    return root, bar, rings


def test_list_reads_colour_in_channel_order(leds, capsys):
    w = load("lighting", "lighting.py")
    assert w.main(["x", "list"]) == 0
    assert json.loads(capsys.readouterr().out) == [
        {"led": "go_s:rgb:joystick_rings", "label": "Stick lights", "color": "#8000ff", "level": 50},  # blue 100/100, red 50/100
        {"led": "input12:rgb:indicator", "label": "Controller light", "color": "#0000ff", "level": 100},
    ]


def test_set_writes_channels_in_the_lights_own_order(leds, tmp_path, monkeypatch):
    root, bar, rings = leds
    sa = load("sa_lighting", "shani-admin.py")
    monkeypatch.setattr(sa, "LEDS", root)
    conf = tmp_path / "50-shani-lighting.conf"
    monkeypatch.setattr(sa, "LIGHTING_TMPFILES", conf)
    # orange on the rings (blue green red, max 100): blue 0, green 65, red 100
    assert sa.lighting({"led": "go_s:rgb:joystick_rings", "color": "#ffa500", "level": 80}) == {}
    assert (rings / "multi_intensity").read_text() == "0 65 100\n"
    assert (rings / "brightness").read_text() == "80\n"
    assert conf.read_text().splitlines()[1:] == [
        f"w {rings}/multi_intensity - - - - 0 65 100",
        f"w {rings}/brightness - - - - 80",
    ]
    # the controller's bar: set now, not kept for a boot (its name changes each connection)
    sa.lighting({"led": "input12:rgb:indicator", "color": "#00ff00", "level": 100})
    assert (bar / "multi_intensity").read_text() == "0 255 0\n"
    assert "input12" not in conf.read_text()


@pytest.mark.skipif(not shutil.which("systemd-tmpfiles"), reason="no systemd-tmpfiles")
def test_the_boot_lines_restore_it(leds, tmp_path, monkeypatch):
    """systemd-tmpfiles itself applies the generated lines (a value with spaces)."""
    root, bar, rings = leds
    sa = load("sa_lighting2", "shani-admin.py")
    monkeypatch.setattr(sa, "LEDS", root)
    conf = tmp_path / "l.conf"
    monkeypatch.setattr(sa, "LIGHTING_TMPFILES", conf)
    sa.lighting({"led": "go_s:rgb:joystick_rings", "color": "#ffa500", "level": 80})
    (rings / "multi_intensity").write_text("1 1 1\n")      # a boot: the driver's default back
    (rings / "brightness").write_text("0\n")
    subprocess.run(["systemd-tmpfiles", "--create", str(conf)], check=False, capture_output=True)
    assert (rings / "multi_intensity").read_text().strip() == "0 65 100"
    assert (rings / "brightness").read_text().strip() == "80"


@pytest.mark.parametrize("req,why", [
    ({"led": "../../../etc/x", "color": "#ffffff", "level": 50}, "not a light"),
    ({"led": "input3::capslock", "color": "#ffffff", "level": 50}, "no colour"),
    ({"led": "missing", "color": "#ffffff", "level": 50}, "no colour"),
    ({"led": "input12:rgb:indicator", "color": "red", "level": 50}, "#rrggbb"),
    ({"led": "input12:rgb:indicator", "color": "#ffffff", "level": 101}, "between 0 and 100"),
    ({"led": "input12:rgb:indicator", "color": "#ffffff", "level": True}, "between 0 and 100"),
])
def test_refused(leds, tmp_path, monkeypatch, req, why):
    root, bar, rings = leds
    sa = load("sa_lighting3", "shani-admin.py")
    monkeypatch.setattr(sa, "LEDS", root)
    monkeypatch.setattr(sa, "LIGHTING_TMPFILES", tmp_path / "x.conf")
    with pytest.raises(sa.Refused, match=why):
        sa.lighting(req)
    assert (bar / "multi_intensity").read_text() == "0 0 255\n"
