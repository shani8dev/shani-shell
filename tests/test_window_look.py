"""Settings > Windows > Look and motion (Services/WindowLook -> shani-look.kdl).

The live part (dev/shell-parts/window-look.sh) loads every style in niri,
checks its shaders compile and photographs windows mid-animation; these are
the contracts that keep it wired.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIGS = [ROOT / "dev/niri/session.kdl", ROOT.parent / "shani-pkgbuilds/shani-desktop-niri/etc/niri/config.kdl"]
LOOK = (ROOT / "shani/Services/WindowLook.qml").read_text()


def test_look_file_is_included_last():
    # its window rule (corners) and layout (shadow) must win over the config's
    # own, and niri lets the later one win
    for cfg in CONFIGS:
        if not cfg.exists():
            continue
        text = cfg.read_text()
        includes = re.findall(r'^include .*"(.*?)"', text, re.M)
        assert includes and includes[-1].endswith("shani-look.kdl"), cfg
        assert text.rstrip().endswith('include optional=true "~/.config/niri/shani-look.kdl"'), cfg


def test_every_style_has_both_shaders():
    for style in ("glide", "pop", "dissolve"):
        block = LOOK[LOOK.index(f"        {style}: {{"):]
        block = block[:block.index("\n        }")]
        assert "vec4 open_color(vec3 coords_geo, vec3 size_geo)" in block, style
        assert "vec4 close_color(vec3 coords_geo, vec3 size_geo)" in block, style
        for shader in re.findall(r"`([^`]*)`", block):
            assert '"' not in shader, f"{style}: a quote would end KDL's raw string"


def test_the_settings_it_reads_exist_with_defaults():
    settings = (ROOT / "shani/Common/Settings.qml").read_text()
    for key, default in (("winMotion", '"glide"'), ("winSpeed", "1.0"), ("winShadow", '"soft"'),
                         ("winCorners", "12"), ("blurStrength", '"medium"')):
        assert re.search(rf"property \w+ {key}: {re.escape(default)}", settings), key
        assert f"d.{key}" in LOOK, key


def test_reduce_motion_and_the_switch_turn_animations_off_here_only():
    assert "d.winAnimations && !d.reduceMotion" in LOOK
    # one writer of the animations block, or the two files would fight
    assert "animations {" not in (ROOT / "shani/Services/InputConfig.qml").read_text()


def test_settings_page_offers_every_choice():
    page = (ROOT / "shani/Modules/Settings/SettingsWindows.qml").read_text()
    for value in ('"glide"', '"pop"', '"dissolve"', '"plain"', '"off"', '"soft"', '"deep"', '"light"', '"medium"', '"strong"'):
        assert f"value: {value}" in page, value
