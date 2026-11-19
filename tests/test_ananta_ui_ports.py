"""The Ananta UI pieces borrowed into Common, and where they are wired.

They came from ananta-os/apps/ui because the shell had no status ring, no
segmented control, no status pill and no inline banner. These checks pin the
bits that are easy to lose when they are edited, and that the surfaces still
use them.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

SHANI = Path(__file__).resolve().parent.parent / "shani"
COMMON = SHANI / "Common"


def test_status_ring_animates_and_has_a_centre_slot():
    t = (COMMON / "StatusRing.qml").read_text()
    assert "default property alias content: centre.data" in t
    assert (
        "Behavior on value" in t and "Theme.animEnter" in t
    )  # Reduce motion = instant
    assert "Accessible.role: Accessible.ProgressBar" in t
    assert "PathAngleArc" in t


def test_segmented_tabs_answer_pointer_and_keyboard():
    t = (COMMON / "SegmentedTabs.qml").read_text()
    assert "signal activated(int index)" in t
    assert "KeyFocus" in t
    assert "Accessible.role: Accessible.PageTab" in t
    assert "Behavior on x" in t  # the sliding thumb


def test_status_pill_maps_every_tone_to_a_palette_token():
    t = (COMMON / "StatusPill.qml").read_text()
    for token in ("Theme.accent", "Theme.amber", "Theme.danger", "Theme.dim"):
        assert token in t
    assert "Accessible.name: pill.text" in t


def test_battery_settings_uses_the_ported_widgets():
    t = (SHANI / "Modules/Settings/SettingsBattery.qml").read_text()
    for widget in ("StatusRing", "StatusPill", "SegmentedTabs"):
        assert widget + " {" in t
    assert "page.span = index === 0 ? 86400 : 604800" in t


def test_desktop_battery_widget_reuses_the_ring():
    t = (SHANI / "Modules/Background/MoreWidgets.qml").read_text()
    assert "StatusRing {" in t
    assert "PathAngleArc" not in t  # the hand-drawn copy is gone


def test_status_glyph_draws_all_four_states():
    t = (COMMON / "StatusGlyph.qml").read_text()
    assert t.count("ShapePath {") >= 4  # check, cross, ! stem, i stem
    assert "Accessible.ignored: true" in t
    assert "QtQuick.Shapes" in t


def test_info_banner_carries_an_icon_a_glyph_and_actions():
    t = (COMMON / "InfoBanner.qml").read_text()
    assert "default property alias actions: actionRow.data" in t
    assert "StatusGlyph" in t and "Icon {" in t
    assert "Accessible.name" in t


def test_drop_zone_has_a_visible_dashed_target():
    t = (COMMON / "DropZone.qml").read_text()
    assert "signal fileDropped(url file)" in t
    assert "ShapePath.DashLine" in t
    assert "DropArea {" in t


def test_battery_empty_history_and_converter_drop_use_the_new_widgets():
    battery = (SHANI / "Modules/Settings/SettingsBattery.qml").read_text()
    assert "InfoBanner {" in battery
    converter = (SHANI / "Modules/Converter/ConverterWindow.qml").read_text()
    assert "DropZone {" in converter
    assert "EmptyState {" not in converter


def test_secret_fields_can_be_revealed_to_check_typos():
    t = (COMMON / "TextField.qml").read_text()
    assert "property bool revealed" in t
    assert "echoMode: root.secret && !root.revealed" in t
    assert '"view-reveal"' in t and '"view-conceal"' in t
    assert "ImhSensitiveData" in t
    assert "Accessible.onPressAction" in t


def test_problem_report_opens_in_the_text_editor():
    about = (SHANI / "Modules/Settings/SettingsAbout.qml").read_text()
    assert "system-report.py" in about
    assert "TextDocs.newDoc()" in about and "TextDocs.setText(text)" in about
    assert "Ui.textEditor = true" in about
    session = (Path(__file__).resolve().parent.parent / "dev/session.sh").read_text()
    assert "SHANI_REPORT_TOOL=/work/bridge/system-report.py" in session


def test_busy_buttons_show_a_spinner_that_respects_reduce_motion():
    btn = (COMMON / "Button.qml").read_text()
    assert "property bool busy" in btn
    assert "Spinner {" in btn and "visible: !root.busy" in btn
    spinner = (COMMON / "Spinner.qml").read_text()
    assert "RotationAnimator" in spinner and "Settings.data.reduceMotion" in spinner
    converter = (SHANI / "Modules/Converter/ConverterWindow.qml").read_text()
    assert "busy: win.running >= 0" in converter


def test_search_brings_the_found_setting_into_view():
    page = (SHANI / "Modules/Settings/SettingsPage.qml").read_text()
    assert 'Ui.settingsSection = "label:"' in page
    window = (SHANI / "Modules/Settings/SettingsWindow.qml").read_text()
    assert "byLabel" in window
    assert "it.Accessible.name" in window


def test_health_check_is_shown_in_about():
    about = (SHANI / "Modules/Settings/SettingsAbout.qml").read_text()
    assert "health-check.py" in about
    assert "healthProc.running = true" in about
    assert "page.healthScore" in about
    session = (Path(__file__).resolve().parent.parent / "dev/session.sh").read_text()
    assert "SHANI_HEALTH_TOOL=/work/bridge/health-check.py" in session


def test_gamepad_visual_uses_the_shells_native_feed():
    t = (COMMON / "GamepadVisual.qml").read_text()
    assert "property var held" in t and "property var axes" in t
    assert '"left-trigger"' in t and '"right-trigger"' in t  # analogue gauges
    assert "MultiEffect" in t
    assert "Accessible.role" in t


def test_controller_settings_shows_the_drawn_pad():
    t = (SHANI / "Modules/Settings/SettingsControllers.qml").read_text()
    assert "GamepadVisual {" in t
    assert "held: page.held" in t and "axes: page.axes" in t
    assert 'model: ["A", "B"' not in t  # the old chip list is gone


def test_network_usage_uses_the_shared_byte_formatter():
    t = (SHANI / "Modules/Settings/SettingsNetwork.qml").read_text()
    assert "Theme.bytes(day)" in t and "Theme.bytes(month)" in t
    assert "function bytes(" not in t


@pytest.mark.skipif(shutil.which("node") is None, reason="node is not installed")
def test_theme_bytes_formats_sizes_like_ananta():
    """Run the real function out of Theme.qml — a regex check would miss a broken body."""
    source = (COMMON / "Theme.qml").read_text()
    start = source.index("function bytes(n) {")
    depth = 0
    for end in range(start, len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
            if depth == 0:
                break
    fn = source[start : end + 1]
    prog = (
        fn
        + "\nprocess.stdout.write(JSON.stringify([bytes(0), bytes(999), bytes(1000), bytes(1500000), bytes(-1)]));"
    )
    got = json.loads(
        subprocess.run(
            ["node", "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )
    assert got == ["0 B", "999 B", "1.0 KB", "1.5 MB", "–"]
