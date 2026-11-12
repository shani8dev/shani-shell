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
    implicitWidth: 560
    implicitHeight: 640

    property real dueChoice: 0        // seconds; 0 = no date
    property bool showDone: false
    onVisibleChanged: if (visible) Tasks.refresh()

    function at(days, hour) { const d = new Date(); d.setDate(d.getDate() + days); d.setHours(hour, 0, 0, 0); return Math.floor(d.getTime() / 1000); }
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

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.tasks = false

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
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
                spacing: 6
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
                spacing: 6
                Text { text: Tr.t("Into:"); color: Theme.dim; height: 30; verticalAlignment: Text.AlignVCenter; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
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
                font.pixelSize: 11 * Theme.fontScale
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: win.showDone ? Tasks.open.concat(Tasks.done) : Tasks.open
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool late: !modelData.done && modelData.due > 0 && modelData.due * 1000 < Date.now()
                    width: list.width
                    height: 44
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        spacing: 10
                        // the tick: done or not
                        Rectangle {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            radius: 11
                            color: row.modelData.done ? Theme.accent : "transparent"
                            border.width: 2
                            border.color: row.modelData.done ? Theme.accent : row.late ? Theme.danger : Theme.dim
                            Icon { anchors.centerIn: parent; visible: row.modelData.done; name: "object-select"; size: 14; color: Theme.accentInk }
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
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.summary
                                color: row.modelData.done ? Theme.faint : Theme.text
                                font.strikeout: row.modelData.done
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 13 * Theme.fontScale
                            }
                            Text {
                                visible: text !== ""
                                text: [Tasks.when(row.modelData), Tasks.lists.length > 1 ? row.modelData.list : ""].filter(x => x).join("  ·  ")
                                color: row.late ? Theme.danger : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 11 * Theme.fontScale
                            }
                        }
                        IconButton { size: 28; icon: "user-trash"; tip: Tr.t("Delete") + " " + row.modelData.summary; onClicked: Tasks.remove(row.modelData) }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    icon: "emblem-ok"
                    title: !Tasks.available ? Tr.t("No task lists here") : Tr.t("Nothing to do")
                    subtitle: !Tasks.available ? Tr.t("Evolution Data Server keeps them; it is not running") : Tr.t("Add one above")
                }
            }
            Button {
                Layout.fillWidth: true
                visible: Tasks.done.length > 0
                flat: true
                text: win.showDone ? Tr.t("Hide done") : Tr.t("Show done") + " (" + Tasks.done.length + ")"
                onClicked: win.showDone = !win.showDone
            }
        }
    }
}
