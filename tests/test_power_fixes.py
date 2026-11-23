"""Static guards for the pass-19 power / battery / lid fixes.

Each fix changes source only (no logind, hardware or a live session here): a
refused power action must be reported, idle sleep must give a cancellable
warning, lid-open must count as presence, and the charge limit must reach the
whole 50-100 range the firmware accepts.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POWER = ROOT / "shani" / "Services" / "Power.qml"
IDLE = ROOT / "shani" / "Services" / "Idle.qml"
KEYS = ROOT / "shani" / "Modules" / "Settings" / "SettingsPowerKeys.qml"


def test_power_actions_report_failures():
    """Refused suspend/hibernate/reboot say why instead of silently doing nothing."""
    t = POWER.read_text(encoding="utf-8")
    # every action goes through one stderr-collecting Process, none is detached
    for name in ("suspend", "hibernate", "rebootToFirmware", "reboot", "poweroff"):
        line = re.search(r"function " + name + r"\([^)]*\)\s*\{([^\n]*)", t).group(1)
        assert "runAction(" in line, f"{name} is not tracked"
    assert 'execDetached(["systemctl"' not in t, "no fire-and-forget systemctl"
    body = t[t.index("id: powerAction") : t.index("function runAction(")]
    assert "stderr: StdioCollector" in body, "stderr is captured"
    assert "onExited: code =>" in body and "code === 0" in body, (
        "only a non-zero exit is reported"
    )
    assert "powerErr.text.trim()" in body, "the reason comes from stderr"
    assert "notify-send" in body and "dialog-error" in body, (
        "the reason is shown to the user"
    )


def test_idle_warns_before_autosuspend_with_cancel():
    """A cancellable notice fires 30 s before the idle suspend."""
    t = IDLE.read_text(encoding="utf-8")
    warn = t[t.index("id: suspendWarnMon") :]
    assert "root.suspendAfter - 30" in warn, "the warning stage runs 30 s earlier"
    assert 'cancel=" + Tr.t("Cancel suspend")' in warn, (
        "the notice offers a Cancel action"
    )
    assert re.search(
        r'stdout: StdioCollector \{ onStreamFinished: if \(text\.trim\(\) === "cancel"\) root\.activity\(\) \}',
        warn,
    ), "Cancel re-arms the idle stages"


def test_lid_open_rearms_idle():
    """Opening the lid is presence, fed by TabletMode's switch-event state."""
    t = IDLE.read_text(encoding="utf-8")
    assert re.search(
        r"Connections\s*\{\s*target: TabletMode\s*"
        r"function onLidClosedChanged\(\)\s*\{\s*if \(!TabletMode\.lidClosed\) root\.activity\(\);",
        t,
    ), "lid-open calls Idle.activity()"


def test_charge_limit_covers_the_supported_range():
    """Every integer 50-100 is reachable, not just 60/80/90/100."""
    t = KEYS.read_text(encoding="utf-8")
    assert '"60 %"' not in t and '"90 %"' not in t, "the four fixed steps are gone"
    assert "IntValidator { bottom: 50; top: 100 }" in t, "the field accepts 50-100"
    assert "text: String(page.limit)" in t, "the field follows the read-back value"
    assert re.search(r"v >= 50 && v <= 100[^\n]*page\.saveLimit\(v\)", t), (
        "only valid values are saved"
    )
