"""Static checks for the gaming/input service fixes.

QML services need a running shell, so these read the source the same way the
other service tests in this suite do. One test per fix.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICES = ROOT / "shani" / "Services"

GAMEMODE = (SERVICES / "GameMode.qml").read_text(encoding="utf-8")
GAMEPAD = (SERVICES / "GamepadNav.qml").read_text(encoding="utf-8")
KBD = (SERVICES / "KbdBacklight.qml").read_text(encoding="utf-8")


def test_gamemode_reports_activation_deactivation_and_refusal():
    """Game mode tells the user when it engages, restores, or cannot engage."""
    assert "function tell(" in GAMEMODE
    assert '"notify-send"' in GAMEMODE
    # critical is the only urgency fullscreen quiet lets through, and it is transient
    assert '"-u", "critical"' in GAMEMODE and '"-t", "1800"' in GAMEMODE
    assert 'Tr.t("Performance mode on")' in GAMEMODE
    assert 'Tr.t("Performance mode off")' in GAMEMODE
    assert 'Tr.t("Performance unavailable")' in GAMEMODE
    # claim vs actual change: verify PPD really took the profile before promising a restore
    assert "PowerProfiles.profile !== PowerProfile.Performance" in GAMEMODE
    assert "savedProfile = -1;" in GAMEMODE
    # live state for any UI/test that wants it, without adding a UI dependency
    assert "signal modeChanged(bool active)" in GAMEMODE
    assert "readonly property bool active: savedProfile >= 0" in GAMEMODE


def test_gamemode_reevaluates_when_power_saver_ends_or_ppd_appears():
    """The saver can release while `game` is unchanged; re-check then."""
    assert "onGameChanged: root.evaluate()" in GAMEMODE
    assert "function evaluate()" in GAMEMODE
    assert "function onSavedProfileChanged() { root.evaluate(); }" in GAMEMODE
    assert "function onHasPerformanceProfileChanged() { root.evaluate(); }" in GAMEMODE


def test_gamepad_nav_stops_while_session_locked():
    """A connected pad must not open the launcher/assistant over the lock screen."""
    wanted = next(l for l in GAMEPAD.splitlines() if "property bool wanted:" in l)
    for guard in (
        "Settings.loaded",
        "Settings.data.gamepadNav",
        "controllers > 0",
        "!fullscreen",
        "!InputPlumber.managing",
        "!Lock.locked",
    ):
        assert guard in wanted, guard


def test_kbd_backlight_auto_off_on_dim_or_lock_and_restores():
    """The light goes out with the dimmed/locked session and comes back on wake."""
    assert "readonly property bool resting: Lock.locked || Idle.dimmed" in KBD
    assert "function onLockedChanged() { root.applyRest(); }" in KBD
    assert "function onDimmedChanged() { root.applyRest(); }" in KBD
    assert "function applyRest()" in KBD
    assert "if (root.resting) root.setLevel(0);" in KBD
    assert "else root.apply();" in KBD
    # a light key or the 30 s timer must not re-light a resting session
    assert "if (level > 0 && root.resting) return;" in KBD


def test_kbd_backlight_level_choice_applies_immediately():
    """Settings' Dim/Medium/Bright/Full choice must move the light, not just store it."""
    conn = KBD[KBD.index("target: Settings.data") :]
    conn = conn[: conn.index("Connections { target: AmbientLight")]
    assert "function onKbdBacklightChanged() { root.apply(); }" in conn
    assert "function onKbdBacklightLevelChanged() { root.apply(); }" in conn
