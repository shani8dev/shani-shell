"""Static checks for the Tasks fixes that are not listed in docs/GAPS*.md.

Evolution Data Server is not in the container, so what is pinned here is the
QML wiring: a delete that cannot hit the wrong row, reminders that re-arm, a
due-at-start notification, an editor for the service's otherwise uncalled
edit, and a local sort control.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = "shani/Services/Tasks.qml"
WINDOW = "shani/Modules/Tasks/TasksWindow.qml"


def read(rel):
    return (ROOT / rel).read_text()


def test_delete_confirmation_is_keyed_by_uid_not_row_index():
    s = read(WINDOW)
    assert 'property string confirmTask: ""' in s
    assert 'onTriggered: win.confirmTask = ""' in s
    assert "win.confirmTask === row.modelData.uid" in s
    assert "win.confirmTask = row.modelData.uid; taskTimer.restart()" in s
    # a refresh between the two taps must not make the second tap delete
    # whichever task now occupies the same row
    assert "row.index" not in s


def test_a_changed_due_rearms_the_reminder():
    s = read(SERVICE)
    assert "property var _dueSeen: ({})" in s
    assert "function loadList(list)" in s
    assert "_dueSeen[t.uid] !== t.due" in s
    assert (
        "const seen = {}" in s and "_dueSeen = seen" in s
    )  # vanishers drop their flag
    assert "root.loadList(JSON.parse(text))" in s
    # re-opening a task also re-arms it
    assert "if (!on) delete root.told[t.uid]" in s


def test_a_task_already_due_at_start_is_told_immediately():
    s = read(SERVICE)
    timer = next(b for b in s.split("Timer {") if "root.open.length > 0" in b)
    assert "triggeredOnStart: true" in timer
    assert "notify-send" in timer


def test_rename_is_reachable_by_mouse_and_keyboard():
    s = read(WINDOW)
    assert "property var editTask: null" in s
    assert "function editIt(t)" in s
    assert 'icon: "document-edit"' in s
    assert "Tasks.rename(win.editTask, renameField.text)" in s
    assert "onAccepted: win.saveRename()" in s
    assert "Keys.onEscapePressed: e => { win.editTask = null; e.accepted = true; }" in s
    assert "function rename(t, summary)" in read(SERVICE)


def test_sort_is_a_local_window_choice():
    s = read(WINDOW)
    assert 'property string sortBy: "due"' in s
    assert "function sorted(list)" in s
    assert "win.sorted(win.showDone ?" in s
    assert "win.sorted(Tasks.tasks.filter" in s
    assert '["due", Tr.t("Due")]' in s
    assert '["priority", Tr.t("Priority")]' in s
