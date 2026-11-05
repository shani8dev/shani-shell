"""bridge/plugwatch.py on udev events recorded in dev/udev/: what is greeted, once."""
import io
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge" / "plugwatch.py"
UDEV = ROOT / "dev" / "udev"
sys.path.insert(0, str(BRIDGE.parent))
import plugwatch  # noqa: E402


def events(*names):
    out = io.StringIO()
    plugwatch.run(io.StringIO("".join((UDEV / f"{n}.txt").read_text() for n in names)), out)
    return [json.loads(x) for x in out.getvalue().splitlines()]


def test_a_tablet_is_one_greeting_for_its_pen_and_pad():
    assert events("tablet") == [{"event": "add", "kind": "tablet", "name": "Wacom Intuos S", "key": "3/56a/374/110/8GH0123456"}]


def test_a_controller_without_its_motion_sensors():
    e = events("controller")
    assert [(x["kind"], x["name"]) for x in e] == [("controller", "DualSense Wireless Controller")]


def test_a_security_key_and_a_scanner_by_udev_properties():
    assert [(x["kind"], x["name"]) for x in events("security-key", "scanner")] == [
        ("security-key", "YubiKey OTP+FIDO+CCID"), ("scanner", "Seiko Epson Corp. GT-F730 [GT-S630/Perfection V33/V330 Photo]")]


def test_a_monitor_is_a_screens_event():
    assert events("monitor") == [{"event": "screens"}]


def test_an_ordinary_mouse_is_not_news():
    assert events("mouse") == []


def test_a_keyboard_is_followed_as_input():
    rec = (UDEV / "mouse.txt").read_text().replace("ID_INPUT_MOUSE=1", "ID_INPUT_KEYBOARD=1").replace("Gaming Mouse", "Keyboard")
    out = io.StringIO()
    plugwatch.run(io.StringIO(rec), out)
    assert [json.loads(x)["kind"] for x in out.getvalue().splitlines()] == ["input"]


def test_once_per_device_and_its_removal_followed():
    e = events("controller", "controller-remove", "controller")
    assert [x["event"] for x in e] == ["add", "remove"]


def test_the_bridge_runs_the_monitor_and_says_ready(tmp_path):
    src = tmp_path / "events.txt"
    src.write_text((UDEV / "scanner.txt").read_text())
    p = subprocess.run([sys.executable, str(BRIDGE)], env=dict(os.environ, SHANI_UDEVADM=f"cat {src}"),
                       capture_output=True, text=True, timeout=10)
    lines = [json.loads(x) for x in p.stdout.splitlines()]
    assert lines[0] == {"event": "ready"} and lines[1]["kind"] == "scanner"


def test_more_kinds_each_by_its_udev_properties():
    got = [(x["kind"], x["name"]) for x in events("camera", "phone", "iphone", "clicker", "capture", "midi",
                                                  "serial", "cardreader", "braille", "egpu")]
    assert got == [
        ("camera", "Canon, Inc. EOS 250D"),
        ("phone", "Google Inc. Nexus/Pixel Device (MTP)"),
        ("iphone", "iPhone"),
        ("clicker", "USB Receiver"),                 # by its keys: page up / down, B, F5, Escape only
        ("clicker", "Wireless Presenter"),           # by its name
        ("capture", "Cam Link 4K: Cam Link 4K"),     # the webcam after it is not a capture card
        ("midi", "Launchkey Mini MK3"),
        ("serial", "Arduino SA Uno (CDC ACM) - /dev/ttyACM0"),
        ("cardreader", "Alcor Micro Corp. AU9540 Smartcard Reader"),
        ("braille", "HumanWare Brailliant BI 40X"),
        ("egpu", "Navi 23 [Radeon RX 6600]")]
