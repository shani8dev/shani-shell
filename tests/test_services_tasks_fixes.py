"""Static checks for Services/Tasks window fixes (pass: service feedback, AT, stale/empty state)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_services_note_color_distinguishes_success_from_error():
    s = read("shani/Modules/Services/ServicesWindow.qml")
    # Success notes must not be painted as danger; errors remain danger.
    assert "noteOk" in s and 'win.noteOk ? "ok" : "error"' in s
    # The old always-danger binding must be gone.
    assert (
        'visible: SysServices.note !== ""\n            text: SysServices.note\n            color: Theme.danger'
        not in s
    )


def test_service_action_buttons_disabled_while_busy_and_accessible():
    s = read("shani/Modules/Services/ServicesWindow.qml")
    # Row actions should not fire while a write is in flight.
    assert s.count("enabled: !SysServices.busy") >= 5
    # Screen readers get unit context, not just "Stop"/"Start".
    assert (
        'Accessible.name: (modelData.active === "active" ? Tr.t("Stop") : Tr.t("Start")) + " " + modelData.unit'
        in s
    )
    assert (
        'Accessible.name: (modelData.enabled === "enabled" ? Tr.t("Disable") : Tr.t("Enable")) + " " + modelData.unit'
        in s
    )
    # Rows with no row-click action must not be keyboard/AT traps.
    assert s.count("interactive: false") >= 3


def test_services_windows_show_empty_states():
    s = read("shani/Modules/Services/ServicesWindow.qml")
    assert 'title: Tr.t("No services")' in s
    assert 'title: Tr.t("No timers")' in s
    assert 'title: Tr.t("No scheduled jobs")' in s
    assert "visible: serviceList.count === 0 && !SysServices.busy" in s
    assert "visible: timerList.count === 0 && !SysServices.busy" in s
    assert "visible: cronList.count === 0 && !SysServices.busy" in s


def test_cron_remove_requires_two_tap_confirmation():
    s = read("shani/Modules/Services/ServicesWindow.qml")
    assert "property int confirmCron: -1" in s
    assert (
        "Timer { id: cronConfirmTimer; interval: 4000; onTriggered: win.confirmCron = -1 }"
        in s
    )
    assert (
        'win.confirmCron === modelData.index ? Tr.t("Tap again to remove") : Tr.t("Remove")'
        in s
    )
    assert "SysServices.cronRemove(modelData.index);" in s
    assert "win.confirmCron = modelData.index;" in s
    assert "cronConfirmTimer.restart();" in s


def test_tasks_empty_state_is_filter_aware_and_show_done_scoped():
    s = read("shani/Modules/Tasks/TasksWindow.qml")
    # Empty state distinguishes filter-empty from truly empty.
    assert 'Tasks.tasks.length > 0 ? Tr.t("No matching tasks")' in s
    assert (
        'Tasks.tasks.length > 0 ? Tr.t("Try a different list or show done tasks")' in s
    )
    assert 'icon: Tasks.tasks.length > 0 ? "edit-find" : "emblem-ok"' in s
    # "Show done" only makes sense on the All list.
    assert 'visible: Tasks.done.length > 0 && win.smartList === "all"' in s
