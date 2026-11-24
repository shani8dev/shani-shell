"""Static asserts for Tour/TvHome fixes (pass: tour/tvhome polish)."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def value_of(text, prop):
    m = re.search(r"(?<![\w.])" + re.escape(prop) + r"\s*:\s*([^\n]+)", text)
    assert m, f"{prop} is missing"
    return m.group(1).strip()


def test_tour_next_start_buttons_are_translated():
    text = source("shani/Modules/Tour/Tour.qml")
    assert 'Tr.t("Next")' in text
    assert 'Tr.t("Start")' in text
    # no raw Next/Start button labels
    assert (
        re.search(
            r'text:\s*win\.step < win\.cards\.length - 1 \? "Next" : "Start"', text
        )
        is None
    )


def test_tour_dialog_announces_step_position():
    text = source("shani/Modules/Tour/Tour.qml")
    desc = value_of(text, "Accessible.description")
    assert "Step %1 of %2" in desc
    assert "win.step + 1" in desc
    assert "win.cards.length" in desc


def test_tvhome_clamps_row_when_shelves_change():
    text = source("shani/Modules/TvHome/TvHome.qml")
    assert "onShelvesChanged:" in text
    assert "row >= shelves.length" in text
    assert "shelves.length - 1" in text


def test_tvhome_refocuses_when_keys_here_returns():
    text = source("shani/Modules/TvHome/TvHome.qml")
    assert re.search(
        r"onKeysHereChanged:\s*if\s*\(keysHere\s*&&\s*visible\)\s*Qt\.callLater\(\(\)\s*=>\s*keys\.forceActiveFocus\(\)\)",
        text,
    )


def test_tvhome_card_accessible_name_includes_subtitle():
    text = source("shani/Modules/TvHome/TvHome.qml")
    m = re.search(
        r"Accessible\.name:\s*modelData\.subtitle.*?modelData\.label", text, re.DOTALL
    )
    assert m, "Accessible.name should include subtitle when it differs from label"
    assert "modelData.subtitle !== modelData.label" in text


def test_tvhome_power_actions_hide_home_before_running():
    text = source("shani/Modules/TvHome/TvHome.qml")
    for key, call in [
        ("power:reboot", "Power.reboot()"),
        ("power:poweroff", "Power.poweroff()"),
        ("power:logout", "Power.logout()"),
    ]:
        block = re.search(r'key:\s*"' + re.escape(key) + r'"[^\n]*run:\s*\(\)\s*=>\s*\{([^}]+)\}', text)
        assert block, f"{key} missing"
        assert "Ui.tvHome = false" in block.group(1), f"{key} should hide home first"
        assert call in block.group(1)
