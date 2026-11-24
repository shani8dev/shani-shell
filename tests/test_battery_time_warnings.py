"""One-shot battery time-to-empty warnings (5 min / 1 min).

Static guards pin the QML shape; a tiny model mirrors the gate so the one-shot
behaviour (no repeats from UPower jitter, re-arm on replug / battery change)
can be tested without a battery or a live D-Bus session.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POWER = ROOT / "shani" / "Services" / "Power.qml"
SETTINGS_BATTERY = ROOT / "shani" / "Modules" / "Settings" / "SettingsBattery.qml"
SHELL_PART = ROOT / "dev" / "shell-parts" / "battery.sh"


def read(path):
    return path.read_text(encoding="utf-8")


def thresholds():
    """Read the three numbers out of the QML so the model cannot drift."""
    t = read(POWER)
    five = int(re.search(r"s <= (\d+) && !told5min", t).group(1))
    one = int(re.search(r"s <= (\d+) && !told1min", t).group(1))
    rise = int(re.search(r"s > (\d+)\) \{", t).group(1))
    return five, one, rise


# ---- the QML ---------------------------------------------------------------


def test_upower_estimate_drives_the_warnings_without_a_new_timer():
    t = read(POWER)
    assert "battery.timeToEmpty" in t
    assert "readonly property real secondsLeft:" in t
    assert "onSecondsLeftChanged: root.checkTimeWarnings(secondsLeft)" in t
    assert t.count("Timer {") == 2  # slow charger + peripherals only
    assert "function checkTimeWarnings(s)" in t
    # percentage and startup are the two signals already known to fire
    assert (
        "root.checkTimeWarnings(root.secondsLeft);  // percentage is UPower's reliable tick"
        in t
    )
    assert (
        "Component.onCompleted: { PowerState.onBattery = onBattery; root.checkTimeWarnings(root.secondsLeft); }"
        in t
    )
    assert (
        "onBatteryChanged: { told5min = false; told1min = false; root.checkTimeWarnings(root.secondsLeft); }"
        in t
    )


def test_thresholds_and_urgency():
    assert thresholds() == (300, 60, 600)
    t = read(POWER)
    five = t[
        t.index("if (s <= 300 && !told5min)") : t.index("if (s <= 60 && !told1min)")
    ]
    assert 'execDetached(["notify-send", "-a", "Power"' in five
    assert '"-u"' not in five  # 5 min is held back by Do Not Disturb
    one = t[t.index("if (s <= 60 && !told1min)") : t.index("// battery saver")]
    assert '"-u", "critical"' in one  # 1 min passes DND, like 7 %
    assert '"notify-send", "-u", "critical"' in one


def test_flags_reset_on_charging_no_battery_and_a_new_run():
    t = read(POWER)
    assert re.search(
        r"if \(!hasBattery \|\| charging \|\| full \|\| !\(s > 0\) \|\| s > 600\) \{\s*"
        r"told5min = false;[^\n]*\n\s*told1min = false;",
        t,
    ), "both one-shots are re-armed on every reset path"
    assert "if (s <= 300 && !told5min)" in t and "if (s <= 60 && !told1min)" in t
    assert "told5min = true;" in t and "told1min = true;" in t


def test_existing_percent_warnings_are_untouched():
    t = read(POWER)
    assert "if (p <= 7 && warned > 7)" in t
    assert "if (p <= 15 && warned > 15)" in t
    assert '"Battery critically low"' in t
    assert "Battery low" in t
    assert '"-u", "critical", "-a", "Power"' in t
    assert "if (Settings.data.autoLockOnLowBattery && !Lock.locked)" in t


def test_time_left_has_an_honest_empty_state():
    t = read(POWER)
    block = t[
        t.index("readonly property string timeLeft:") : t.index(
            "readonly property string profileName:"
        )
    ]
    assert "battery.timeToFull : battery.timeToEmpty" in block
    assert "if (!hasBattery)" in block and 'return "";' in block
    assert "s <= 0" in block


def test_settings_power_and_the_shell_part_already_cover_the_display():
    # Settings > Power loads SettingsBattery, which shows the same UPower
    # estimate; the power shell-part renders that page for a visual check.
    t = read(SETTINGS_BATTERY)
    assert "page.info.timeToEmpty" in t and '"about %1 left"' in t
    assert SHELL_PART.exists()


# ---- the gate as a model ---------------------------------------------------


class Gate:
    """checkTimeWarnings(), with a list standing in for notify-send."""

    def __init__(self):
        self.told5 = self.told1 = False
        self.sent = []

    def check(self, s, has_battery=True, charging=False, full=False):
        five, one, rise = thresholds()
        if (
            not has_battery
            or charging
            or full
            or not (s is not None and s > 0)
            or (s is not None and s > rise)
        ):
            self.told5 = self.told1 = False
            return
        s = float(s)
        if s <= five and not self.told5:
            self.told5 = True
            self.sent.append("5min")
        if s <= one and not self.told1:
            self.told1 = True
            self.sent.append("1min")


def feed(gate, readings, **state):
    for s in readings:
        gate.check(s, **state)


def test_one_notice_per_threshold_on_a_normal_discharge():
    g = Gate()
    feed(g, [900, 400, 301, 300, 299, 120, 61, 60, 59, 30, 30, 15])
    assert g.sent == ["5min", "1min"]


def test_estimate_jitter_does_not_repeat_a_notice():
    g = Gate()
    feed(g, [300, 305, 298, 310, 302, 299, 60, 65, 58, 62, 59])
    assert g.sent == ["5min", "1min"]


def test_charging_and_no_battery_rearm_both_notices():
    g = Gate()
    feed(g, [240, 240])
    g.check(0, charging=True)
    feed(g, [220, 50])
    g.check(None, has_battery=False)
    feed(g, [180, 55])
    assert g.sent == ["5min", "5min", "1min", "5min", "1min"]


def test_battery_change_or_a_big_rise_rearms_both_notices():
    g = Gate()
    feed(g, [50])  # a big jump fires both at once
    feed(g, [3600, 300, 60])  # new battery, then a fresh discharge
    assert g.sent == ["5min", "1min", "5min", "1min"]


def test_unknown_estimate_never_warns():
    g = Gate()
    feed(g, [0, None, -1, float("nan")])
    assert g.sent == []
