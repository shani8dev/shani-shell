// Tasks: what is to be done, when, and ticked off - Reminders, To Do, Google
// Tasks. The lists are Evolution Data Server's (Services/Tasks), so a task
// added here is in Thunderbird and Chronoa too, and syncs with an online
// account's list. When it is due is a pick, not a date to type.
import Quickshell
import QtQuick
import QtQuick.Layouts
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
    property string smartList: "all"  // all | today | upcoming | completed | nodate
    property var repeatTask: null     // the task whose repeat rule is being picked
    property var editTask: null       // the task whose name is being renamed
    property var dueTask: null        // the task whose due date is being picked
    property real editDue: 0          // its current due, so the picker opens on it
    property string sortBy: "due"     // due | name | priority (the bridge's own order is by due)
    readonly property var smartLists: [
        ["all", Tr.t("All")], ["today", Tr.t("Today")], ["upcoming", Tr.t("Upcoming")],
        ["completed", Tr.t("Completed")], ["nodate", Tr.t("No date")]
    ]
    readonly property var repeatRules: [
        ["", Tr.t("Never")], ["daily", Tr.t("Daily")], ["weekly", Tr.t("Weekly")], ["monthly", Tr.t("Monthly")]
    ]
    // delete asks first: two taps, the second within 4 s. Keyed by uid, not row
    // index: a refresh or a filter change between the taps reorders the rows.
    property string confirmTask: ""
    Timer { id: taskTimer; interval: 4000; onTriggered: win.confirmTask = "" }
    onVisibleChanged: if (visible) Tasks.refresh()

    function at(days, hour) { const d = new Date(); d.setDate(d.getDate() + days); d.setHours(hour, 0, 0, 0); return Math.floor(d.getTime() / 1000); }
    function inSmartList(t) {
        if (win.smartList === "completed") return t.done;
        if (t.done) return false;
        if (win.smartList === "nodate") return !t.due;
        if (win.smartList === "all") return true;
        const end = Tasks.endOfToday();
        if (win.smartList === "upcoming") return t.due > 0 && t.due * 1000 > end;
        return t.due > 0 && t.due * 1000 <= end;   // today, overdue included
    }
    readonly property var dueOptions: [
        [Tr.t("No date"), 0], [Tr.t("Today"), at(0, 18)], [Tr.t("Tomorrow"), at(1, 9)],
        [Tr.t("This weekend"), at((6 - new Date().getDay() + 7) % 7 || 7, 10)], [Tr.t("Next week"), at(7, 9)]
    ]
    function addIt() {
        if (field.text.trim() === "")
            return;
        Tasks.add(field.text, win.dueChoice);
        field.text = "";
    }

    // the bridge already orders by due; offer the two other useful orders locally
    function sorted(list) {
        const a = (list || []).slice();
        if (win.sortBy === "name")
            a.sort((x, y) => String(x.summary).localeCompare(String(y.summary)));
        if (win.sortBy === "priority")
            a.sort((x, y) => (y.priority || 0) - (x.priority || 0) || String(x.summary).localeCompare(String(y.summary)));
        return a;
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

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.tasks = false
        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N) {
                field.forceActiveFocus();   // Ctrl+N starts the next task from anywhere
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
            Flow {
                Layout.fillWidth: true
                visible: Tasks.lists.length > 1
                spacing: Theme.px(6)
                Text { text: Tr.t("Into:"); color: Theme.dim; height: Theme.px(30); verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: Tasks.lists.filter(l => !l.readOnly)
                    Choice {
                        required property var modelData
                        required property int index
                        text: modelData.name
                        selected: Tasks.selectedList === modelData.name || (Tasks.selectedList === "" && index === 0)
                        onClicked: Tasks.selectedList = modelData.name
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
                    model: [["due", Tr.t("Due")], ["name", Tr.t("Name")], ["priority", Tr.t("Priority")]]
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
                        text: modelData[1]
                        selected: win.smartList === modelData[0]
                        onClicked: win.smartList = modelData[0]
                    }
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
                       ? win.sorted(win.showDone ? Tasks.open.concat(Tasks.done) : Tasks.open)
                       : win.sorted(Tasks.tasks.filter(t => win.inSmartList(t)))
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool late: !modelData.done && modelData.due > 0 && modelData.due * 1000 < Date.now()
                    width: list.width
                    height: Theme.px(44)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    RowLayout {
                        anchors { fill: parent; leftMargin: Theme.px(6); rightMargin: Theme.px(6) }
                        spacing: Theme.px(10)
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
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Tasks.setDone(row.modelData, !row.modelData.done) }
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
                                text: [Tasks.when(row.modelData), Tasks.lists.length > 1 ? row.modelData.list : ""].filter(x => x).join("  ·  ")
                                color: row.late ? Theme.danger : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "document-edit"
                            tip: Tr.t("Rename") + " " + row.modelData.summary
                            onClicked: win.editIt(row.modelData)
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "x-office-calendar"
                            tip: Tr.t("Change due date") + " " + row.modelData.summary
                            onClicked: { win.dueTask = row.modelData; win.editDue = row.modelData.due || 0; }
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "view-refresh"
                            on: (Tasks.repeats[row.modelData.uid] || "") !== ""
                            tip: (Tasks.repeats[row.modelData.uid] || "")
                                 ? Tr.t("Repeats %1").arg(Tasks.repeats[row.modelData.uid])
                                 : Tr.t("Repeat this task")
                            onClicked: win.repeatTask = row.modelData
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "user-trash"
                            tip: win.confirmTask === row.modelData.uid
                                ? Tr.t("Tap again to delete this task")
                                : (Tr.t("Delete") + " " + row.modelData.summary)
                            onClicked: {
                                if (win.confirmTask === row.modelData.uid) { Tasks.remove(row.modelData); win.confirmTask = ""; }
                                else { win.confirmTask = row.modelData.uid; taskTimer.restart(); }
                            }
                        }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    icon: Tasks.tasks.length > 0 ? "edit-find" : "emblem-ok"
                    title: !Tasks.available ? Tr.t("No task lists here")
                         : Tasks.tasks.length > 0 ? Tr.t("No matching tasks")
                         : Tr.t("Nothing to do")
                    subtitle: !Tasks.available ? Tr.t("Evolution Data Server keeps them; it is not running")
                            : Tasks.tasks.length > 0 ? Tr.t("Try a different list or show done tasks")
                            : Tr.t("Add one above")
                    actionText: Tasks.available && Tasks.tasks.length === 0 ? Tr.t("Add a task") : ""
                    onAction: field.forceActiveFocus()
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
