"""Static assertions for the pass-22 desktop-widget fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESKTOP = ROOT / "shani/Modules/Background/DesktopWidgets.qml"
MORE = ROOT / "shani/Modules/Background/MoreWidgets.qml"
WORLDCLOCK = ROOT / "shani/Services/WorldClock.qml"


def test_cards_drag_only_when_unlocked():
    desktop = DESKTOP.read_text()
    more = MORE.read_text()
    for text, expected in ((desktop, 4), (more, 1)):
        targets = [l.strip() for l in text.splitlines() if "drag.target:" in l]
        assert len(targets) == expected
        assert all("widgetsLocked ? null :" in t for t in targets)
    flag = "property bool widgetsLocked: Settings.data.widgetsLocked === true"
    assert flag in desktop and flag in more


def test_worldclock_polls_only_while_a_clock_surface_visible():
    s = WORLDCLOCK.read_text()
    assert "readonly property bool wanted:" in s
    assert 'indexOf("clocks") >= 0' in s
    assert "Ui.clocks" in s and "Ui.calendar" in s and "Ui.controlCenter" in s
    assert "running: root.wanted" in s
    assert "onTriggered: read.running = root.wanted" in s
    assert "if (root.wanted) read.running = true" in s


def test_stats_widget_shows_cpu_history_and_temperature():
    s = DESKTOP.read_text()
    assert "Sparkline {" in s
    assert "values: SysStats.cpuHistory" in s
    assert "visible: SysStats.temp > 0" in s
    assert 'Tr.t("CPU %1°C", Math.round(SysStats.temp))' in s
