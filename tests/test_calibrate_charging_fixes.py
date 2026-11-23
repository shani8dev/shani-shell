"""Static guards for the two layer-shell overlays with no bridge of their own.

A charging card that lingers after the cable is pulled, an icon frozen at 100 %
and a calibration with no way out on a touch-only device are all invisible to a
unit test of the services behind them. These check the wiring in the QML source.

Five fixes, one test each.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAL = ROOT / "shani" / "Modules" / "Calibrate" / "CalibrateOverlay.qml"
CHARGE = ROOT / "shani" / "Modules" / "Charging" / "ChargeFx.qml"


def cal():
    return CAL.read_text(encoding="utf-8")


def charge():
    return CHARGE.read_text(encoding="utf-8")


def body_of(text, signature):
    m = re.search(re.escape(signature) + r"\s*\{([^}]*)\}", text)
    assert m, f"{signature} is missing"
    return m.group(1)


def test_unplugging_stops_the_charging_animation():
    """Pulling the cable mid-play hides the card instead of leaving a 2 s lie."""
    t = charge()
    stop = body_of(t, "function stop()")
    assert "shown = false" in stop, "the card is not hidden"
    assert "fill.stop()" in stop and "away.stop()" in stop, "timers keep running"
    handler = body_of(t, "function onOnBatteryChanged()")
    assert "win.armed" in handler and "Power.hasBattery" in handler
    assert "if (Power.onBattery) win.stop();" in handler, "no unplug branch"
    assert "else win.play();" in handler, "plug-in still plays"


def test_the_battery_icon_follows_the_actual_charge():
    """The glyph is the service's state-accurate icon, not a hard-coded full one."""
    t = charge()
    assert "name: Power.batteryIcon" in t
    assert "battery-level-100-charged" not in t, "icon is frozen at 100 %"


def test_time_left_is_not_shown_when_the_battery_is_not_charging():
    """On a plugged-but-not-charging battery, 'time to empty' must not read as 'to full'."""
    t = charge()
    line = next(l for l in t.splitlines() if "Power.timeLeft" in l)
    assert "Power.charging && Power.timeLeft ? Power.timeLeft" in line, line
    assert line.rstrip().endswith(': Tr.t("Charging")'), line


def test_calibration_can_be_cancelled_by_the_device_being_calibrated():
    """A touch-only device gets an on-screen Cancel, not just the Escape key."""
    t = cal()
    tap_cancel = re.search(
        r"TapHandler\s*\{\s*onTapped:\s*Calibrate\.cancel\(\"cancelled\"\)\s*\}", t
    )
    assert tap_cancel, "no tap-to-cancel"
    # the full-screen calibration handler must be declared first: the Cancel
    # button's own handler is later, so it wins the grab on that spot
    assert t.index("Calibrate.touched(") < tap_cancel.start()
    # a real finger target on board/tablet/handheld, sized like other controls
    assert "Math.max(Theme.px(36), Theme.touchTarget)" in t
    assert 'Tr.t("Cancel")' in t


def test_cancel_is_available_to_assistive_tech_and_the_keyboard():
    """The touch Cancel announces its role/name; Escape still works as before."""
    t = cal()
    assert "Accessible.role: Accessible.Button" in t
    assert 'Accessible.name: Tr.t("Cancel")' in t
    assert 'Keys.onEscapePressed: Calibrate.cancel("cancelled")' in t
