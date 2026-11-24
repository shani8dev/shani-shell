"""The CuboCore blue accent preset, added without a second theme system.

paperde's Dark.conf blue (accent #12608a, highlight #0986d3) is a colour fact,
not copyrighted expression. It lives in Common/Accents.js as a preset fed
through the existing HCT derive(); SettingsPage shows it as a swatch next to
the adwaita accents. The wallpapers are deliberately NOT bundled: the repo they
came from has no licence file and an empty README, so redistribution terms are
unknown.
"""

import importlib.util
import json
import shutil
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
ACCENTS = ROOT / "shani/Common/Accents.js"
SETTINGS = ROOT / "shani/Modules/Settings/SettingsPage.qml"
I18N = ROOT / "shani/i18n"
LABEL = "CuboCore blue"


def read(path):
    return path.read_text(encoding="utf-8")


# ---- static: the preset and its one swatch -----------------------------------


def test_the_preset_uses_paperde_dark_colours_and_the_existing_engine():
    src = read(ACCENTS)
    assert '"CuboCore blue"' in src
    assert "#0986d3" in src  # Dark.conf highlight -> primary
    assert "#12608a" in src  # Dark.conf accent -> blue slot override
    assert "var PRESETS" in src
    assert "function derivePreset(name, isLight)" in src
    assert "function accentInk(name, isLight)" in src
    # it is a preset for derive(), not a new palette type
    assert "derive(Qt.color(p.primary), isLight, p.overrides)" in src


def test_the_swatch_is_added_to_the_accent_list_only():
    qml = read(SETTINGS)
    assert 'import "../../Common/Accents.js" as Accents' in qml
    assert 'Accents.derivePreset("CuboCore blue", Theme.dark)' in qml
    assert f'Tr.t("{LABEL}")' in qml
    # the shipped accent map still owns selection; the swatch picks its blue
    assert 'page.d.accentName = "blue"' in qml


def test_the_label_is_in_the_template_and_both_catalogs():
    template = json.loads(read(I18N / "template.json"))
    assert LABEL in template and template[LABEL] == ""
    for lang in ("hi", "mr"):
        cat = json.loads(read(I18N / f"{lang}.json"))
        assert LABEL in cat
        assert cat[LABEL].strip() and cat[LABEL].strip() != LABEL
    assert "नीला" in json.loads(read(I18N / "hi.json"))[LABEL]
    assert "निळा" in json.loads(read(I18N / "mr.json"))[LABEL]


def test_no_wallpaper_asset_was_bundled():
    """Licensing was unclear, so only the colour fact was taken."""
    for name in ("curvy_3d_vector.svg", "default.svg"):
        assert not list(ROOT.rglob(name)), f"{name} must not be bundled"


# ---- pure logic: run Accents.js in node ---------------------------------------


def _helpers():
    spec = importlib.util.spec_from_file_location(
        "shell_helpers", ROOT / "tests/test_shell_helpers.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.mark.skipif(shutil.which("node") is None, reason="node is not installed")
def test_derive_of_the_preset_gives_a_readable_accent_ink():
    helpers = _helpers()
    out = helpers.run(
        helpers.ACCENT_MODS,
        """
    var res = {};
    for (const light of [false, true]) {
        var slots = Accents.derivePreset("CuboCore blue", light);
        var blue = slots.blue;
        res[light] = {
            names: Object.keys(slots),
            ratio: Contrast.ratio(Accents.accentInk("CuboCore blue", light), blue.container),
            inkIsBlueSlotInk: JSON.stringify(Accents.accentInk("CuboCore blue", light)) === JSON.stringify(blue.onContainer)
        };
    }
    process.stdout.write(JSON.stringify(res));""",
    )
    for light in ("false", "true"):
        case = out[light]
        assert set(case["names"]) == {
            "red",
            "orange",
            "yellow",
            "green",
            "teal",
            "blue",
            "purple",
            "pink",
        }
        assert case["inkIsBlueSlotInk"]
        assert case["ratio"] >= 4.5, case
