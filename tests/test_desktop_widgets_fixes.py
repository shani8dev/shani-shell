"""Static checks for DesktopWidgets/MoreWidgets gaps.

These widgets are layer-shell QML surfaces; tests assert source wiring.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESKTOP = ROOT / "shani/Modules/Background/DesktopWidgets.qml"
MORE = ROOT / "shani/Modules/Background/MoreWidgets.qml"


def test_loadpos_guards_missing_deskpos():
    s = DESKTOP.read_text(encoding="utf-8")
    assert "(Settings.data.deskPos || {})[id] || defaults[id]" in s


def test_media_controls_null_guard_player():
    s = DESKTOP.read_text(encoding="utf-8")
    assert "onClicked: if (mediaWin.player) mediaWin.player.togglePlaying()" in s
    assert "if (mediaWin.player && mediaWin.player.length > 0)" in s
    assert (
        "mediaWin.player.position = mediaWin.player.length * (me.x / parent.width);"
        in s
    )


def test_weather_accessible_name_reflects_action():
    s = DESKTOP.read_text(encoding="utf-8")
    assert (
        'Weather.enabled ? Tr.t("Weather, opens the weather app") : Tr.t("Weather, opens personalisation settings")'
        in s
    )
    # the press action must match the same enabled split
    assert (
        'Accessible.onPressAction: Weather.enabled ? Ui.openWeather() : Ui.openSettings("personal")'
        in s
    )


def test_desktop_widget_accessible_names_are_localized():
    s = DESKTOP.read_text(encoding="utf-8")
    for name in [
        'Tr.t("Clock, opens the control centre")',
        'Tr.t("Now playing, opens the control centre")',
        'Tr.t("Play or pause")',
        'Tr.t("System monitor, opens processes")',
    ]:
        assert name in s


def test_more_widgets_card_drag_uses_scope_locked_flag():
    s = MORE.read_text(encoding="utf-8")
    assert "drag.target: scr.widgetsLocked ? null : glass" in s
