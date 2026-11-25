"""Static checks for four pass-22 utility-app fixes.

Each fix lives in a QML singleton/panel that needs a running shell, so these
assert the source carries the exact wiring (the style of test_utility_fixes.py).
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_calculator_trig_respects_angle_unit():
    # the evaluator is Common/Calc.js, shared with the launcher; the service passes its angle unit
    q = read("shani/Services/Calculator.qml") + read("shani/Common/Calc.js")
    assert 'property string angleUnit: "deg"' in q
    assert "function setAngleUnit(u)" in q
    assert '["deg", "rad", "grad"].indexOf(s) >= 0' in q
    # trig names rewrite to angle-aware wrappers, never a bare Math.sin/cos/tan
    assert 'm => "_" + m.toLowerCase()' in q
    assert "Math.sin(toRad(x))" in q
    assert "Math.asin(x)" in q and "fromRad(" in q
    assert '"_sin", "_cos", "_tan", "_asin", "_acos", "_atan"' in q


def test_characters_keeps_a_capped_recent_list():
    q = read("shani/Services/Characters.qml")
    assert "property var recents: []" in q
    assert "readonly property int recentLimit:" in q
    assert "recents = [entry].concat(recents.filter" in q
    assert ".slice(0, root.recentLimit)" in q


def test_characters_panel_covers_all_indexed_blocks():
    q = read("shani/Modules/Characters/CharactersPanel.qml")
    m = re.search(r"model: \[([^\]]*)\]", q)
    assert m is not None
    chips = re.findall(r'"([^"]+)"', m.group(1))
    for block in (
        "Symbols",
        "Arrows",
        "Math",
        "Greek",
        "Cyrillic",
        "Hebrew",
        "Arabic",
        "Devanagari",
        "Bengali",
        "Tamil",
        "Telugu",
        "Malayalam",
        "Emoji",
    ):
        assert block in chips, block
    assert len(chips) >= 12


def test_qr_uses_unique_paths_and_can_save_png():
    svc = read("shani/Services/Qr.qml")
    assert "property int seq: 0" in svc
    assert '"/shani-qr-" + root.seq + "-" + Date.now() + ".png"' in svc
    assert '"/shani-qr.png"' not in svc
    assert "function saveTo(path)" in svc
    assert '["cp", "-f", image, path]' in svc

    view = read("shani/Modules/QrView/QrView.qml")
    assert 'Tr.t("Save PNG…")' in view
    assert 'mode: "save"' in view
    assert 'defaultName: "shani-qr.png"' in view
    assert "Qr.saveTo(paths[0])" in view
