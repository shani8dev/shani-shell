// Tasks: what is to be done, when, and ticked off - Reminders, To Do, Google
// Tasks. The lists are Evolution Data Server's (Services/Tasks), so a task
// added here is in Thunderbird and Chronoa too, and syncs with an online
// account's list. When it is due is a pick, not a date to type.
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Tasks"
    visible: Ui.tasks
    onGone: Ui.tasks = false
    implicitWidth: Theme.px(560)
    implicitHeight: Theme.px(640)

    property real dueChoice: 0        // seconds; 0 = no date
    property bool showDone: false
    property string smartList: "all"  // all | today | upcoming | overdue | completed | nodate
    property var repeatTask: null     // the task whose repeat rule is being picked
    property var editTask: null       // the task whose name is being renamed
    property var dueTask: null        // the task whose due date is being picked
    property real editDue: 0          // its current due, so the picker opens on it
    property string sortBy: "due"     // due | name | priority | list (the bridge's own order is by due)
    // planning additions: a project filter, quick find, a creation priority,
    // multi-select and a description editor (all local to this window/service)
    property string filterList: ""    // "" = every project
    property string search: ""        // case-insensitive, over summary + notes
    property int priorityChoice: 0    // 0 = none, 1..3 = P1..P3 for new tasks
    property bool selectMode: false
    property var selected: []         // uids, never row indexes
    property var noteTask: null
    readonly property var smartLists: [
        ["all", Tr.t("All")], ["today", Tr.t("Today")], ["upcoming", Tr.t("Upcoming")],
        ["overdue", Tr.t("Overdue")], ["completed", Tr.t("Completed")], ["nodate", Tr.t("No date")]
    ]
    readonly property var repeatRules: [
        ["", Tr.t("Never")], ["daily", Tr.t("Daily")], ["weekly", Tr.t("Weekly")], ["monthly", Tr.t("Monthly")]
    ]
    readonly property var priorityOptions: [
        [0, Tr.t("None")], [1, "P1 " + Tr.t("High")], [2, "P2 " + Tr.t("Medium")], [3, "P3 " + Tr.t("Low")]
    ]
    onVisibleChanged: if (visible) Tasks.refresh()

    function at(days, hour) { const d = new Date(); d.setDate(d.getDate() + days); d.setHours(hour, 0, 0, 0); return Math.floor(d.getTime() / 1000); }
    function inSmartList(t) {
        if (win.smartList === "completed") return t.done;
        if (t.done) return false;
        if (win.smartList === "nodate") return !t.due;
        if (win.smartList === "all") return true;
        if (win.smartList === "overdue") return t.due > 0 && t.due < win.at(0, 0);
        const end = Tasks.endOfToday();
        if (win.smartList === "upcoming") return t.due > 0 && t.due * 1000 > end;
        return t.due > 0 && t.due * 1000 <= end;   // today, overdue included
    }
    readonly property var dueOptions: [
        [Tr.t("No date"), 0], [Tr.t("Today"), at(0, 18)], [Tr.t("Tomorrow"), at(1, 9)],
        [Tr.t("This weekend"), at((6 - new Date().getDay() + 7) % 7 || 7, 10)], [Tr.t("Next week"), at(7, 9)]
    ]
    function matches(t) {
        if (win.filterList !== "" && t.list !== win.filterList) return false;
        if (win.search === "") return true;
        const q = win.search.toLowerCase();
        return String(t.summary || "").toLowerCase().indexOf(q) !== -1
            || String(t.notes || "").toLowerCase().indexOf(q) !== -1;
    }
    function addIt() {
        if (field.text.trim() === "")
            return;
        Tasks.add(field.text, win.dueChoice, win.priorityChoice);
        field.text = "";
    }

    // the bridge already orders by due; offer the two other useful orders locally
    function sorted(list) {
        const a = (list || []).slice();
        if (win.sortBy === "name")
            a.sort((x, y) => String(x.summary).localeCompare(String(y.summary)));
        if (win.sortBy === "priority")
            a.sort((x, y) => (y.priority || 0) - (x.priority || 0) || String(x.summary).localeCompare(String(y.summary)));
        if (win.sortBy === "list")
            a.sort((x, y) => String(x.list).localeCompare(String(y.list)) || (x.due || 0) - (y.due || 0));
        return a;
    }
    // what is on screen now: bulk actions must never reach a hidden task
    function visibleTasks() {
        return win.smartList === "all"
            ? win.sorted(win.showDone ? Tasks.open.concat(Tasks.done) : Tasks.open).filter(t => win.matches(t))
            : win.sorted(Tasks.tasks.filter(t => win.inSmartList(t))).filter(t => win.matches(t));
    }
    function editIt(t) {
        win.editTask = t;
        renameField.text = t.summary;
        Qt.callLater(() => { renameField.forceActiveFocus(); renameField.selectAll(); });
    }
    function saveRename() {
        if (!win.editTask) return;
        Tasks.rename(win.editTask, renameField.text);
        win.editTask = null;
    }
    function openNotes(t) {
        win.noteTask = t;
        noteField.text = t.notes || "";
        Qt.callLater(() => { noteField.forceActiveFocus(); });
    }
    function saveNotes() {
        if (!win.noteTask) return;
        Tasks.setNotes(win.noteTask, noteField.text);
        win.noteTask = null;
    }
    function clearSearch() { searchField.text = ""; win.search = ""; }
    function toggleSelected(uid) {
        const a = win.selected.slice();
        const i = a.indexOf(uid);
        if (i === -1) a.push(uid); else a.splice(i, 1);
        win.selected = a;
    }
    function selectAllNow() { win.selected = win.visibleTasks().map(t => t.uid); }
    function clearSelection() { win.selected = []; win.selectMode = false; }
    function activate(t) {
        if (win.selectMode) win.toggleSelected(t.uid);
        else Tasks.setDone(t, !t.done);
    }
    function bulkComplete() {
        Tasks.setDoneMany(win.visibleTasks().filter(t => !t.done), true);
        win.clearSelection();
    }
    function bulkDelete() {
        Tasks.removeMany(win.visibleTasks().filter(t => win.selected.indexOf(t.uid) !== -1));
        win.clearSelection();
    }
    function clearDone() { Tasks.removeMany(Tasks.done); }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.tasks = false
        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N) {
                field.forceActiveFocus();   // Ctrl+N starts the next task from anywhere
                e.accepted = true;
            }
            if (e.key === Qt.Key_Slash && !field.activeFocus && !renameField.activeFocus
                    && !noteField.activeFocus && !searchField.activeFocus) {
                searchField.forceActiveFocus();   // Todoist's / quick find
                e.accepted = true;
            }
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_A && win.selectMode) {
                win.selectAllNow();
                e.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: field
                    Layout.fillWidth: true
                    placeholder: Tr.t("Add a task — Call the bank, Buy milk…")
                    label: Tr.t("New task")
                    onAccepted: win.addIt()
                }
                Button { kind: "primary"; text: Tr.t("Add"); enabled: field.text.trim() !== "" && Tasks.available; onClicked: win.addIt() }
                // the same Ui path the shell's `scheduledOpen` IPC uses
                Button {
                    flat: true
                    text: Tr.t("Scheduled tasks")
                    Accessible.name: Tr.t("Open scheduled tasks")
                    onClicked: { Ui.closeAll(); Ui.scheduled = true; }
                }
            }
            // quick find: / from anywhere, Escape clears it (then closes the window)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Find a task ( / )")
                    label: Tr.t("Find")
                    onTextChanged: win.search = text
                    Keys.onEscapePressed: e => { if (text !== "") { win.clearSearch(); e.accepted = true; } }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.dueOptions
                    Choice {
                        required property var modelData
                        text: modelData[0]
                        selected: win.dueChoice === modelData[1]
                        onClicked: win.dueChoice = modelData[1]
                    }
                }
            }
            // the bridge writes PRIORITY on add; P1 is red, P3 is quiet
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("Priority:"); color: Theme.dim; height: Theme.px(30); verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: win.priorityOptions
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.priorityChoice === modelData[0]
                        onClicked: win.priorityChoice = modelData[0]
                    }
                }
            }
            // one row of project chips: filters the view and aims new tasks there.
            // Read-only lists can be viewed but stay read-only as a target.
            Flow {
                Layout.fillWidth: true
                visible: Tasks.lists.length > 1
                spacing: Theme.px(6)
                Text { text: Tr.t("Project:"); color: Theme.dim; height: Theme.px(30); verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Choice { text: Tr.t("All projects"); selected: win.filterList === ""; onClicked: { win.filterList = ""; Tasks.selectedList = ""; } }
                Repeater {
                    model: Tasks.lists
                    Choice {
                        required property var modelData
                        text: modelData.name
                        selected: win.filterList === modelData.name
                        onClicked: {
                            win.filterList = modelData.name;
                            if (!modelData.readOnly) Tasks.selectedList = modelData.name;
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: Tasks.error !== ""
                text: Tasks.error
                color: Theme.danger
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }

            // description/notes: bridge edit accepts DESCRIPTION but had no caller
            Flow {
                Layout.fillWidth: true
                visible: win.noteTask !== null
                spacing: Theme.px(6)
                Text { text: Tr.t("Notes:"); color: Theme.dim; height: Theme.px(30); verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextArea {
                    id: noteField
                    width: Theme.px(260)
                    height: Theme.px(48)
                    wrapMode: TextArea.Wrap
                    placeholderText: Tr.t("Notes for this task…")
                    Keys.onEscapePressed: e => { win.noteTask = null; e.accepted = true; }
                }
                Button { kind: "primary"; text: Tr.t("Save"); onClicked: win.saveNotes() }
                IconButton { size: Theme.px(24); icon: "window-close"; tip: Tr.t("Cancel"); onClicked: win.noteTask = null }
            }

            // the repeat picker for the task whose repeat button was tapped
            Flow {
                Layout.fillWidth: true
                visible: win.repeatTask !== null
                spacing: Theme.px(6)
                Text { text: Tr.t("Repeat:"); color: Theme.dim; height: Theme.px(30); verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: win.repeatRules
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: modelData[0] === (win.repeatTask ? (Tasks.repeats[win.repeatTask.uid] || "") : "")
                        onClicked: {
                            Tasks.setRepeat(win.repeatTask, modelData[0]);
                            win.repeatTask = null;
                        }
                    }
                }
                IconButton { size: Theme.px(24); icon: "window-close"; tip: Tr.t("Cancel"); onClicked: win.repeatTask = null }
            }

            // rename: opened from a row's pencil; the bridge's edit is otherwise uncalled
            Flow {
                Layout.fillWidth: true
                visible: win.editTask !== null
                spacing: Theme.px(6)
                Text { text: Tr.t("Rename:"); color: Theme.dim; height: Theme.px(30); verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField {
                    id: renameField
                    Layout.fillWidth: true
                    label: Tr.t("Task name")
                    onAccepted: win.saveRename()
                    Keys.onEscapePressed: e => { win.editTask = null; e.accepted = true; }
                }
                Button { kind: "primary"; text: Tr.t("Save"); enabled: renameField.text.trim() !== ""; onClicked: win.saveRename() }
                IconButton { size: Theme.px(24); icon: "window-close"; tip: Tr.t("Cancel"); onClicked: win.editTask = null }
            }

            // due date of an existing task: Tasks.setDue() had no caller, so a
            // task could only be given a date at creation time
            Flow {
                Layout.fillWidth: true
                visible: win.dueTask !== null
                spacing: Theme.px(6)
                Text { text: Tr.t("Due:"); color: Theme.dim; height: Theme.px(30); verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: win.dueOptions
                    Choice {
                        required property var modelData
                        text: modelData[0]
                        selected: win.editDue === modelData[1]
                        onClicked: { Tasks.setDue(win.dueTask, modelData[1]); win.dueTask = null; }
                    }
                }
                IconButton { size: Theme.px(24); icon: "window-close"; tip: Tr.t("Cancel"); onClicked: win.dueTask = null }
            }

            // sort: the bridge orders by due; these are the other useful views
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("Sort:"); color: Theme.dim; height: Theme.px(30); verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: [["due", Tr.t("Due")], ["name", Tr.t("Name")], ["priority", Tr.t("Priority")], ["list", Tr.t("Project")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.sortBy === modelData[0]
                        onClicked: win.sortBy = modelData[0]
                    }
                }
            }

            // smart lists: named views over the same tasks, no backend needed
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.smartLists
                    Choice {
                        required property var modelData
                        text: modelData[0] === "today" && Tasks.overdueCount > 0
                              ? modelData[1] + " (" + Tasks.overdueCount + ")" : modelData[1]
                        selected: win.smartList === modelData[0]
                        onClicked: win.smartList = modelData[0]
                    }
                }
            }

            // select mode + clear-completed: bulk planning actions, two taps for loss
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button {
                    flat: true
                    text: win.selectMode ? Tr.t("Cancel selection") : Tr.t("Select")
                    onClicked: win.selectMode ? win.clearSelection() : win.selectMode = true
                }
                Button {
                    visible: win.selectMode
                    flat: true
                    text: Tr.t("Select all")
                    onClicked: win.selectAllNow()
                }
                Button {
                    visible: win.selectMode
                    flat: true
                    enabled: win.selected.length > 0
                    text: Tr.t("Complete") + " (" + win.selected.length + ")"
                    onClicked: win.bulkComplete()
                }
                ConfirmButton {
                    id: bulkDeleteConfirm
                    visible: win.selectMode
                    enabled: win.selected.length > 0
                    implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                    implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    text: Tr.t("Delete")
                    armedText: Tr.t("Tap again to delete")
                    kind: bulkDeleteConfirm.armed ? "danger" : "plain"
                    interval: 4000
                    onConfirmed: win.bulkDelete()
                }
                ConfirmButton {
                    id: clearDoneConfirm
                    visible: !win.selectMode && Tasks.done.length > 0
                    implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                    implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    text: Tr.t("Clear done")
                    armedText: Tr.t("Tap again to clear done")
                    kind: clearDoneConfirm.armed ? "danger" : "plain"
                    interval: 4000
                    onConfirmed: win.clearDone()
                }
            }

            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: win.smartList === "all"
                       ? win.sorted(win.showDone ? Tasks.open.concat(Tasks.done) : Tasks.open).filter(t => win.matches(t))
                       : win.sorted(Tasks.tasks.filter(t => win.inSmartList(t))).filter(t => win.matches(t))
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool late: !modelData.done && modelData.due > 0 && modelData.due * 1000 < Date.now()
                    readonly property int prio: modelData.priority || 0
                    width: list.width
                    height: Theme.px(44)
                    radius: Theme.radiusSmall
                    color: win.selected.indexOf(modelData.uid) !== -1 ? Theme.hover : rowArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: row.modelData.summary + (row.prio > 0 ? ", P" + row.prio : "") + (row.late ? ", " + Tr.t("overdue") : "")
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    RowLayout {
                        anchors { fill: parent; leftMargin: Theme.px(6); rightMargin: Theme.px(6) }
                        spacing: Theme.px(10)
                        // multi-select checkbox: uids, never row indexes
                        Rectangle {
                            visible: win.selectMode
                            Layout.preferredWidth: Theme.px(22)
                            Layout.preferredHeight: Theme.px(22)
                            radius: Theme.px(11)
                            color: win.selected.indexOf(row.modelData.uid) !== -1 ? Theme.accent : "transparent"
                            border.width: 2
                            border.color: Theme.dim
                            Icon { anchors.centerIn: parent; visible: win.selected.indexOf(row.modelData.uid) !== -1; name: "object-select"; size: Theme.px(14); color: Theme.accentInk }
                            Accessible.role: Accessible.CheckBox
                            Accessible.checked: win.selected.indexOf(row.modelData.uid) !== -1
                            Accessible.name: Tr.t("Select") + " " + row.modelData.summary
                            Accessible.onToggleAction: win.toggleSelected(row.modelData.uid)
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.toggleSelected(row.modelData.uid) }
                        }
                        // the tick: done or not
                        Rectangle {
                            Layout.preferredWidth: Theme.px(22)
                            Layout.preferredHeight: Theme.px(22)
                            radius: Theme.px(11)
                            color: row.modelData.done ? Theme.accent : "transparent"
                            border.width: 2
                            border.color: row.modelData.done ? Theme.accent : row.late ? Theme.danger : Theme.dim
                            Icon { anchors.centerIn: parent; visible: row.modelData.done; name: "object-select"; size: Theme.px(14); color: Theme.accentInk }
                            Accessible.role: Accessible.CheckBox
                            Accessible.checked: row.modelData.done
                            Accessible.name: row.modelData.summary
                            Accessible.onToggleAction: Tasks.setDone(row.modelData, !row.modelData.done)
                            Accessible.onPressAction: Tasks.setDone(row.modelData, !row.modelData.done)
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Tasks.setDone(row.modelData, !row.modelData.done) }
                            KeyFocus { name: row.modelData.summary; onActivated: Tasks.setDone(row.modelData, !row.modelData.done) }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.activate(row.modelData) }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.summary
                                color: row.modelData.done ? Theme.faint : Theme.text
                                font.strikeout: row.modelData.done
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: Theme.px(13) * Theme.fontScale
                            }
                            Text {
                                visible: text !== ""
                                text: [Tasks.when(row.modelData), Tasks.lists.length > 1 ? row.modelData.list : "", row.modelData.notes ? String(row.modelData.notes).split("\n")[0].slice(0, 40) : ""].filter(x => x).join("  ·  ")
                                color: row.late ? Theme.danger : Theme.dim
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                        }
                        Text {
                            visible: row.prio > 0
                            text: "P" + row.prio
                            color: row.prio === 1 ? Theme.danger : row.prio === 2 ? Theme.accent : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                            Accessible.name: Tr.t("Priority %1").arg(row.prio)
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "text-x-generic"
                            tip: Tr.t("Notes") + " " + row.modelData.summary
                            Accessible.name: tip
                            onClicked: win.openNotes(row.modelData)
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "document-edit"
                            tip: Tr.t("Rename") + " " + row.modelData.summary
                            Accessible.name: tip
                            onClicked: win.editIt(row.modelData)
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "x-office-calendar"
                            tip: Tr.t("Change due date") + " " + row.modelData.summary
                            Accessible.name: tip
                            onClicked: { win.dueTask = row.modelData; win.editDue = row.modelData.due || 0; }
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "view-refresh"
                            on: (Tasks.repeats[row.modelData.uid] || "") !== ""
                            tip: (Tasks.repeats[row.modelData.uid] || "")
                                 ? Tr.t("Repeats %1").arg(Tasks.repeats[row.modelData.uid])
                                 : Tr.t("Repeat this task")
                            Accessible.name: tip
                            onClicked: win.repeatTask = row.modelData
                        }
                        ConfirmButton {
                            id: deleteTaskConfirm
                            size: Theme.px(28)
                            icon: "user-trash"
                            tip: Tr.t("Delete") + " " + row.modelData.summary
                            armedText: Tr.t("Tap again to delete this task")
                            value: row.modelData.uid
                            interval: 4000
                            Accessible.name: armed ? armedText : tip
                            onConfirmed: Tasks.remove(row.modelData)
                        }
                        Connections { target: row; function onModelDataChanged() { deleteTaskConfirm.disarm(); } }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    icon: Tasks.tasks.length > 0 ? "edit-find" : "emblem-ok"
                    title: !Tasks.available ? Tr.t("No task lists here")
                         : win.search !== "" ? Tr.t("No tasks match your search")
                         : Tasks.tasks.length > 0 ? Tr.t("No matching tasks")
                         : Tr.t("Nothing to do")
                    subtitle: !Tasks.available ? Tr.t("Evolution Data Server keeps them; it is not running")
                            : win.search !== "" ? Tr.t("Try a different word or clear the search")
                            : Tasks.tasks.length > 0 ? Tr.t("Try a different list or show done tasks")
                            : Tr.t("Add one above")
                    actionText: win.search !== "" ? Tr.t("Clear search")
                              : Tasks.available && Tasks.tasks.length === 0 ? Tr.t("Add a task") : ""
                    onAction: win.search !== "" ? win.clearSearch() : field.forceActiveFocus()
                }
            }
            Button {
                Layout.fillWidth: true
                visible: Tasks.done.length > 0 && win.smartList === "all"
                flat: true
                text: win.showDone ? Tr.t("Hide done") : Tr.t("Show done") + " (" + Tasks.done.length + ")"
                onClicked: win.showDone = !win.showDone
            }
        }
    }
}
