"""What kind of screen each output is (shani/Common/FormFactor.js), run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Common" / "FormFactor.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def call(fn, *args):
    prog = JS.read_text().replace(".pragma library", "") + "\nprocess.stdout.write(JSON.stringify(%s(...%s)));" % (fn, json.dumps(list(args)))
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def mm(inches, ratio=(16, 9)):
    """physical size in mm of a screen of this diagonal and aspect"""
    w, h = ratio
    k = inches * 25.4 / (w * w + h * h) ** 0.5
    return [round(w * k), round(h * k)]


def detect(name, inches, chosen="", ratio=(16, 9), **inp):
    return call("detect", {"name": name, "physical": mm(inches, ratio) if inches else [0, 0]}, inp, chosen)


def test_a_laptop_panel_and_a_desk_monitor():
    assert detect("eDP-1", 14, keyboard=True) == "laptop"
    assert detect("DP-2", 27) == "computer"


def test_a_tv_on_hdmi_beside_the_laptop_is_a_tv():
    assert detect("HDMI-A-1", 55) == "tv"
    assert detect("eDP-1", 14, keyboard=True) == "laptop"      # the same machine's panel is unchanged


def test_a_big_touch_panel_is_a_classroom_board():
    assert detect("HDMI-A-1", 75, touch=True) == "board"
    assert detect("HDMI-A-1", 75) == "tv"                      # the same size without touch is a TV


def test_handhelds_by_their_built_in_pad():
    assert detect("eDP-1", 7.4, ratio=(16, 10), touch=True, builtinPad=True, keyboard=False) == "handheld"   # Deck
    assert detect("eDP-1", 8.8, ratio=(16, 10), touch=True, builtinPad=True) == "handheld"                  # Legion Go
    assert detect("eDP-1", 8.8, ratio=(16, 10), touch=True, keyboard=False) == "tablet"                     # no pad: a tablet


def test_tablets_and_2_in_1s():
    assert detect("eDP-1", 13, touch=True, tabletMode=True, keyboard=True) == "tablet"   # folded
    assert detect("eDP-1", 13, touch=True, tabletMode=False, keyboard=True) == "laptop"  # unfolded


def test_a_phone():
    assert detect("DSI-1", 6.4, ratio=(9, 20), touch=True, keyboard=False) == "phone"


def test_an_unknown_size_is_never_guessed_to_be_a_tv():
    assert detect("HDMI-A-1", 0) == "computer"                 # many 4K monitors and some TVs report 0x0


def test_the_owners_choice_wins_and_auto_is_no_choice():
    assert detect("DP-2", 27, chosen="tv") == "tv"
    assert detect("HDMI-A-1", 55, chosen="auto") == "tv"
    assert detect("HDMI-A-1", 55, chosen="nonsense") == "tv"


def test_each_profile_has_a_scale_and_a_name():
    for p in ["computer", "laptop", "tablet", "handheld", "phone", "tv", "board"]:
        assert call("scale", p) >= 1.0 and call("label", p) not in ("", "Automatic")
    assert call("scale", "tv") > call("scale", "handheld") > call("scale", "computer")
    assert call("scale", "unknown") == 1.0


def turn(product, name, native, profile):
    return call("panelTurn", product, {"name": name, "nativeMode": native}, profile)


def test_sideways_handheld_panels_are_turned():
    assert turn("Jupiter", "eDP-1", [800, 1280], "handheld") == "270"          # Steam Deck LCD
    assert turn("Galileo", "eDP-1", [800, 1280], "handheld") == "270"          # Steam Deck OLED
    assert turn("83E1", "eDP-1", [1600, 2560], "handheld") == "90"             # Legion Go
    assert turn("Some Handheld", "eDP-1", [1080, 1920], "handheld") == "270"   # unknown, portrait-made
    assert turn("RC71L", "eDP-1", [1920, 1080], "handheld") == ""              # ROG Ally: made landscape


def test_nothing_else_is_turned():
    assert turn("Jupiter", "DP-1", [1080, 1920], "handheld") == ""             # a plugged-in screen, even on a Deck
    assert turn("Some Tablet", "eDP-1", [1200, 1920], "tablet") == ""          # a tablet turns by its accelerometer
    assert turn("ThinkPad", "eDP-1", [1920, 1200], "laptop") == ""


def test_a_boards_bar_is_at_the_bottom_and_the_owners_choice_wins():
    assert call("barEdge", "board", "auto") == "bottom"
    assert call("barEdge", "computer", "auto") == "top"
    assert call("barEdge", "tv", "auto") == "top"
    assert call("barEdge", "board", "top") == "top"
    assert call("barEdge", "computer", "bottom") == "bottom"
    assert call("barEdge", "board", "nonsense") == "bottom"


def named(name, label, physical, **inp):
    return call("detect", {"name": name, "physical": physical, "label": label}, inp, "")


def test_a_tv_that_says_so_in_its_name():
    assert named("HDMI-A-1", "LG Electronics LG TV SSCR2", [0, 0]) == "tv"
    assert named("HDMI-A-1", "Samsung Electric Company SAMSUNG", [0, 0]) == "computer"   # a monitor's name: no
    assert named("HDMI-A-1", "Samsung Electric Company SAMSUNG TV", [700, 390]) == "tv"   # "TV" wins over a 32" size
    assert named("DP-1", "Dell Inc. DELL U2723QE", [600, 340]) == "computer"
    assert named("DP-1", "TVLogic LVM-170A", [370, 230]) == "computer"                    # TV inside a word: no


def test_a_size_that_is_only_a_shape_is_no_size():
    assert named("HDMI-A-1", "Some Brand", [160, 90]) == "computer"       # 16:9 in cm, not a 7" screen
    assert named("HDMI-A-1", "Some Brand TV", [160, 90]) == "tv"
