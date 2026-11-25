"""Static checks for the Tasks "projects & planning" upgrade.

Evolution Data Server is not in the container, so what is pinned here is the
shipped QML wiring: project filtering, creation priorities, an overdue view,
notes, quick find, bulk actions, sorting, accessibility and empty states, plus
the service helpers those actions call. Behaviour is compared with Todoist,
GNOME Todo and Things 3; none of these tests needs the bridge or EDS.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW = "shani/Modules/Tasks/TasksWindow.qml"
SERVICE = "shani/Services/Tasks.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def window():
    return read(WINDOW)


def service():
    return read(SERVICE)


def section(text, start, end):
    return text[text.index(start) : text.index(end)]


def test_project_chips_filter_the_view_and_aim_new_tasks():
    # Todoist/GNOME Todo/Things 3 all let a project be both a view and a target.
    s = window()
    assert 'property string filterList: ""' in s
    assert 'if (win.filterList !== "" && t.list !== win.filterList) return false;' in s
    assert ".filter(t => win.matches(t))" in s  # both the All and the smart-list branch
    assert s.count(".filter(t => win.matches(t))") >= 2
    assert 'Choice { text: Tr.t("All projects"); selected: win.filterList === "";' in s
    assert 'win.filterList = ""; Tasks.selectedList = "";' in s
    assert "win.filterList = modelData.name;" in s
    # Read-only lists can be viewed but must not become a write target.
    assert "if (!modelData.readOnly) Tasks.selectedList = modelData.name;" in s
    assert "model: Tasks.lists" in s  # read-only projects are no longer hidden
    assert "function visibleTasks()" in s  # bulk actions use the same filter


def test_priority_is_chosen_at_creation_and_marked_on_rows():
    # The bridge writes PRIORITY on add but not on edit, so priority is a
    # creation-time pick; existing tasks still show the level EDS reports.
    s = window()
    assert "property int priorityChoice: 0" in s
    assert "readonly property var priorityOptions: [" in s
    assert '[1, "P1 " + Tr.t("High")]' in s
    assert "Tasks.add(field.text, win.dueChoice, win.priorityChoice);" in s
    assert "readonly property int prio: modelData.priority || 0" in s
    assert 'text: "P" + row.prio' in s
    assert 'Tr.t("Priority %1").arg(row.prio)' in s
    f = service()
    assert "function add(summary, due, priority) {" in f
    assert "const p = Number(priority) > 0 ? Number(priority) : 0;" in f
    assert "priority: p }" in f
    # A bare two-argument add (shell.qml) still writes an ordinary task.
    assert "Number(priority) > 0" in f


def test_overdue_has_its_own_view_and_live_count():
    # Todoist has an Overdue filter; Things 3 and GNOME Todo separate late
    # tasks from today. The previous Today view folded them together.
    s = window()
    assert '["overdue", Tr.t("Overdue")]' in s
    assert (
        'if (win.smartList === "overdue") return t.due > 0 && t.due < win.at(0, 0);'
        in s
    )
    assert 'text: modelData[0] === "today" && Tasks.overdueCount > 0' in s
    assert '? modelData[1] + " (" + Tasks.overdueCount + ")" : modelData[1]' in s
    f = service()
    assert "function startOfToday()" in f
    assert "function isOverdue(t) {" in f
    assert (
        "readonly property int overdueCount: open.filter(t => isOverdue(t)).length" in f
    )


def test_notes_editor_calls_the_bridges_unused_description_field():
    # bridge edit accepts DESCRIPTION but nothing in the shell ever called it.
    s = window()
    assert "property var noteTask: null" in s
    assert "function openNotes(t) {" in s
    assert 'noteField.text = t.notes || "";' in s
    assert "function saveNotes() {" in s
    assert "Tasks.setNotes(win.noteTask, noteField.text);" in s
    assert 'icon: "text-x-generic"' in s
    assert "win.openNotes(row.modelData)" in s
    assert 'String(row.modelData.notes).split("\\n")[0].slice(0, 40)' in s
    f = service()
    assert "function setNotes(t, notes) {" in f
    assert 'notes: String(notes || "") }' in f
    assert 'run(["edit"' in f


def test_quick_find_searches_summary_and_notes():
    # Todoist's / quick find; ours must reach notes too, not just the title.
    s = window()
    assert 'property string search: ""' in s
    assert "const q = win.search.toLowerCase();" in s
    assert 'String(t.summary || "").toLowerCase().indexOf(q) !== -1' in s
    assert 'String(t.notes || "").toLowerCase().indexOf(q) !== -1' in s
    assert "onTextChanged: win.search = text" in s
    assert 'function clearSearch() { searchField.text = ""; win.search = ""; }' in s
    keys = section(s, "Keys.onPressed: e => {", "ColumnLayout {")
    assert "e.key === Qt.Key_Slash" in keys
    assert "searchField.forceActiveFocus();" in keys
    assert "e.key === Qt.Key_A && win.selectMode" in keys
    assert "win.selectAllNow();" in keys


def test_bulk_actions_are_uid_keyed_and_never_touch_hidden_tasks():
    s = window()
    assert "property bool selectMode: false" in s
    assert "property var selected: []" in s
    assert "function toggleSelected(uid) {" in s
    assert "const i = a.indexOf(uid);" in s
    assert (
        "function selectAllNow() { win.selected = win.visibleTasks().map(t => t.uid); }"
        in s
    )
    assert "function activate(t) {" in s
    assert "win.toggleSelected(t.uid);" in s
    assert "Tasks.setDoneMany(win.visibleTasks().filter(t => !t.done), true);" in s
    assert (
        "Tasks.removeMany(win.visibleTasks().filter(t => win.selected.indexOf(t.uid) !== -1));"
        in s
    )
    assert "row.index" not in s  # a refresh between two taps cannot retarget a row
    f = service()
    assert "function setDoneMany(list, on) {" in f
    assert "for (const t of a) setDone(t, on);" in f
    assert "function removeMany(list) {" in f
    assert "for (const t of a) remove(t);" in f
    assert f.count("const a = Array.isArray(list) ? list : [];") >= 2


def test_clear_and_bulk_delete_use_confirm_button():
    s = window()
    assert "id: clearDoneConfirm" in s
    assert 'text: Tr.t("Clear done")' in s
    assert 'armedText: Tr.t("Tap again to clear done")' in s
    assert "onConfirmed: win.clearDone()" in s
    assert "id: bulkDeleteConfirm" in s
    assert 'text: Tr.t("Delete")' in s
    assert 'armedText: Tr.t("Tap again to delete")' in s
    assert "onConfirmed: win.bulkDelete()" in s
    assert "Tasks.removeMany(Tasks.done);" in s
    for stale in ("confirmClear", "confirmBulk", "clearTimer", "bulkTimer"):
        assert stale not in s


def test_sort_by_project_is_available_and_stable():
    s = window()
    assert 'property string sortBy: "due"' in s  # comment keeps this pinned
    assert "function sorted(list)" in s
    assert 'if (win.sortBy === "list")' in s
    assert (
        "String(x.list).localeCompare(String(y.list)) || (x.due || 0) - (y.due || 0)"
        in s
    )
    assert (
        '["due", Tr.t("Due")], ["name", Tr.t("Name")], ["priority", Tr.t("Priority")], ["list", Tr.t("Project")]'
        in s
    )


def test_row_actions_have_accessible_names():
    s = window()
    assert s.count("Accessible.name: tip") >= 5  # notes, rename, due, repeat, delete
    assert (
        'Accessible.name: row.modelData.summary + (row.prio > 0 ? ", P" + row.prio : "")'
        in s
    )
    assert 'Accessible.name: Tr.t("Select") + " " + row.modelData.summary' in s
    assert "Accessible.role: Accessible.ListItem" in s


def test_empty_state_distinguishes_search_from_filter_and_error():
    s = window()
    assert ': win.search !== "" ? Tr.t("No tasks match your search")' in s
    assert 'Tr.t("Try a different word or clear the search")' in s
    assert 'actionText: win.search !== "" ? Tr.t("Clear search")' in s
    assert (
        'onAction: win.search !== "" ? win.clearSearch() : field.forceActiveFocus()'
        in s
    )
    # existing filter/unavailable cases remain distinct
    assert 'Tasks.tasks.length > 0 ? Tr.t("No matching tasks")' in s
    assert 'icon: Tasks.tasks.length > 0 ? "edit-find" : "emblem-ok"' in s
    assert 'visible: Tasks.done.length > 0 && win.smartList === "all"' in s


def test_service_rejects_malformed_json_shapes():
    # GAPS.md: a JSON.parse of {} used to replace lists/repeats wholesale.
    f = service()
    assert (
        'function asObject(v) { return v && typeof v === "object" && !Array.isArray(v) ? v : {}; }'
        in f
    )
    assert "const p = JSON.parse(text); root.lists = Array.isArray(p) ? p : [];" in f
    assert "root.repeats = asObject(JSON.parse(text));" in f
    assert "if (!Array.isArray(list)) return;" in f
    assert "if (!t || !t.uid) return;" in f


def test_legacy_wiring_still_present():
    # The new features must not break the already-tested fixes.
    s = window()
    assert 'property string confirmTask: ""' in s
    assert "win.confirmTask === row.modelData.uid" in s
    assert "win.confirmTask = row.modelData.uid; taskTimer.restart();" in s
    assert "property var dueTask: null" in s
    assert "win.dueTask = row.modelData; win.editDue = row.modelData.due || 0;" in s
    picker = section(s, "// due date of an existing task", "// sort:")
    assert "model: win.dueOptions" in picker
    assert "Tasks.setDue(win.dueTask, modelData[1])" in picker
    assert "win.dueTask = null" in picker
    assert "property var editTask: null" in s
    assert "Tasks.rename(win.editTask, renameField.text)" in s
    keys = section(s, "Keys.onPressed: e => {", "ColumnLayout {")
    assert "(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N" in keys
    assert "field.forceActiveFocus();" in keys
    assert "win.sorted(win.showDone ?" in s
    assert "win.sorted(Tasks.tasks.filter" in s
    f = service()
    for name in (
        "loadList",
        "endOfToday",
        "refresh",
        "add",
        "setDone",
        "remove",
        "rename",
        "setDue",
        "setRepeat",
        "run",
        "next",
        "when",
    ):
        assert f"function {name}(" in f
