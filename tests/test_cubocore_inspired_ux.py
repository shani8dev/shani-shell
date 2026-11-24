"""Low-risk UX ideas researched from the CuboCore/C-Suite desktop suite."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_files_keyboard_shortcuts():
    q = read("shani/Modules/Files/FilesPanel.qml")
    assert "Qt.Key_F4" in q                      # open terminal here
    assert "beginBatchRename(Files.selected.slice())" in q  # Shift+Ctrl+F2
    assert "Files.setViewMode(Files.viewMode === \"grid\" ? \"list\" : \"grid\")" in q
    assert "Files.setSort(keys[(keys.indexOf(Files.sortKey) + 1) % keys.length])" in q
    assert "win.openWithPaths = Files.selected.slice()" in q  # Ctrl+Return
    assert "Files.back()" in q and "Files.up()" in q


def test_editor_insert_datetime():
    q = read("shani/Modules/TextEditor/TextEditorPanel.qml")
    assert "function insertDateTime()" in q
    assert "Qt.formatDateTime(new Date()" in q
    assert "Insert date and time" in q


def test_alarm_weekday_and_snooze_ui():
    q = read("shani/Modules/Clocks/ClocksWindow.qml")
    assert "property var alarmDays" in q
    assert "WorldClock.addAlarm(win.alarmTime, win.alarmLabel, win.alarmDays)" in q
    assert "Every day" in q
    assert "Snooze" in q
    assert "WorldClock.snooze(" in q
    # service already supports days + snooze
    s = read("shani/Services/WorldClock.qml")
    assert "function addAlarm(time, label, days, enabled)" in s
    assert "function snooze(label, minutes)" in s


def test_severity_tint_matches_bar_chip():
    q = read("shani/Modules/Background/DesktopWidgets.qml")
    assert "SysStats.cpu > 0.85 ? Theme.amber" in q
    assert "SysStats.mem > 0.9 ? Theme.amber" in q
    bar = read("shani/Modules/Bar/Bar.qml")
    assert "SysStats.cpu > 0.85 || SysStats.mem > 0.9" in bar
