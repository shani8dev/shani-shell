"""Touch auto-detection already exists in Shani — pin the existing chain, do not add a second one.

CuboCore/CoreApps v2.7's signature feature ("auto detect touch screens and enable
the touchMode", maximized windows, collapsed side views, bigger targets) is here,
spread over three existing pieces instead of one uiMode toggle:

  bridge/input-kinds.py + Services/InputKinds.qml  - udev touch detection, event driven
  Services/FormFactor.qml + Common/FormFactor.js   - touch -> tablet/board profile + larger scale
  Common/Theme.qml touchTarget / WindowRules.qml   - bigger targets, fullscreen/compact policy

These tests pin that those pieces still exist, stay event-driven (no idle poller),
and that the detection parser and profile rules stay correct.
"""

import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge"
TOOL = BRIDGE / "input-kinds.py"


# ---- the detection parser, loaded as a module so we test its pure logic ----
_spec = importlib.util.spec_from_file_location("shani_input_kinds", TOOL)
kinds_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kinds_mod)
kinds = kinds_mod.kinds


def dev(name, **props):
    lines = [
        "P: /devices/virtual/input/input",
        "U: input",
        "E: SUBSYSTEM=input",
        'E: NAME="%s"' % name,
    ]
    lines += ["E: %s=%s" % (k, v) for k, v in props.items()]
    return "\n".join(lines)


def test_touchscreen_is_detected_from_a_udev_input_device():
    db = dev("GoodTouch Screen", ID_INPUT=1, ID_INPUT_TOUCHSCREEN=1)
    assert kinds(db) == {"keyboard": False, "touchscreen": True, "tabletSwitch": False}


def test_quoted_udev_values_are_accepted():
    # real udevadm --export-db may quote the value; the parser strips quotes
    db = 'E: SUBSYSTEM=input\nE: NAME="ELAN9008"\nE: ID_INPUT_TOUCHSCREEN="1"'
    assert kinds(db)["touchscreen"] is True


def test_non_touch_and_non_input_devices_are_ignored():
    off = dev("A Mouse", ID_INPUT=1, ID_INPUT_TOUCHSCREEN=0)
    assert kinds(off)["touchscreen"] is False
    # SUBSYSTEM=input is required: a display/drm node with the flag is not a touchscreen
    other = (
        'P: /x\nU: drm\nE: SUBSYSTEM=drm\nE: NAME="panel"\nE: ID_INPUT_TOUCHSCREEN=1'
    )
    assert kinds(other)["touchscreen"] is False


def test_parser_is_pure_argv_only_no_shell():
    src = TOOL.read_text(encoding="utf-8")
    assert "shell=True" not in src  # no shell interpolation
    assert '["udevadm", "info", "--export-db"]' in src  # one argv call, not per device
    assert "def kinds(text)" in src  # pure, testable with a DB string


# ---- the QML wiring: detection is event driven, never polled ----
def test_inputkinds_is_event_driven_not_a_poller():
    q = (ROOT / "shani/Services/InputKinds.qml").read_text(encoding="utf-8")
    assert 'command: ["python3", root.tool]' in q  # argv only, no shell
    assert (
        "Connections { target: Plugged; function onInputRevChanged() { root.refresh(); } }"
        in q
    )
    assert "interval:" not in q  # no idle timer: read on start + udev events
    assert (
        "root.touchscreen = k.touchscreen;" in q
    )  # the parsed flag reaches the service


def test_formfactor_consumes_the_touch_signal():
    q = (ROOT / "shani/Services/FormFactor.qml").read_text(encoding="utf-8")
    assert "touch: InputKinds.touchscreen" in q
    assert "tabletMode: TabletMode.known && TabletMode.on" in q


def test_big_targets_are_keyed_to_touch_form_factors():
    t = (ROOT / "shani/Common/Theme.qml").read_text(encoding="utf-8")
    assert (
        'readonly property int touchTarget: ["phone", "tablet", "handheld", "board"].indexOf(formFactor)'
        in t
    )
    assert "px(44)" in t


# ---- pure profile rules: touch yields a bigger, finger-friendly profile ----
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")
JS = ROOT / "shani" / "Common" / "FormFactor.js"


def call(fn, *args):
    prog = JS.read_text(encoding="utf-8").replace(
        ".pragma library", ""
    ) + "\nprocess.stdout.write(JSON.stringify(%s(...%s)));" % (
        fn,
        json.dumps(list(args)),
    )
    return json.loads(
        subprocess.run(
            [node, "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def mm(inches, ratio=(16, 9)):
    w, h = ratio
    k = inches * 25.4 / (w * w + h * h) ** 0.5
    return [round(w * k), round(h * k)]


def detect(name, inches, **inp):
    return call(
        "detect", {"name": name, "physical": mm(inches) if inches else [0, 0]}, inp, ""
    )


def test_a_touchscreen_makes_a_tablet_or_board_with_bigger_targets():
    assert detect("eDP-1", 13, touch=True, tabletMode=True, keyboard=True) == "tablet"
    assert detect("eDP-1", 13, touch=True, keyboard=False) == "tablet"
    assert detect("HDMI-A-1", 75, touch=True) == "board"
    # same hardware without the detected touch is an ordinary laptop/TV
    assert detect("eDP-1", 13, keyboard=True) == "laptop"
    assert detect("HDMI-A-1", 75) == "tv"
    assert call("scale", "tablet") > call("scale", "computer")
    assert call("scale", "board") > call("scale", "computer")
