"""Static checks for the notification-sound/flash fixes.

These are live-driven QML surfaces, so the assertions pin the wiring (DND
gate, flash rate ceiling, scaled border) without a running shell.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_system_sounds_are_silenced_by_dnd_or_quiet():
    q = read("shani/Services/SystemSounds.qml")
    play = q.split("function play(name) {")[1].split("played++;")[0]
    # the gate lives inside play(), before the sound is counted and played
    assert "Notifs.dnd || Notifs.quiet" in play


def test_flash_has_a_rate_ceiling_and_dims_repeats():
    q = read("shani/Modules/Flash/FlashAlert.qml")
    alerted = q.split("function onAlerted(n) {")[1].split("pulse.restart();")[0]
    assert "now - win.lastFlashAt < 1000" in alerted  # no rapid restarts
    assert "win.flashesThisMinute >= 12" in alerted  # hard per-minute cap
    assert (
        "glow.peak = win.flashesThisMinute > 3 ? 0.35 : 0.9" in alerted
    )  # dim repeats
    assert "property real peak: 0.9" in q
    assert "to: glow.peak" in q  # animation uses the dimmed peak


def test_flash_border_scales_with_theme():
    q = read("shani/Modules/Flash/FlashAlert.qml")
    assert "border.width: Theme.px(14)" in q
    assert "border.width: 14\n" not in q
