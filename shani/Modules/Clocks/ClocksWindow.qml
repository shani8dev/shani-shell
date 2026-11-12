// Clocks: the world's time, alarms, a stopwatch and a timer in one window.
// The clocks themselves are Services/WorldClock's and FocusTimer's - the same
// alarms and stopwatch the sidebar shows, so one started here is running there.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Clocks"
    visible: Ui.clocks
    onGone: Ui.clocks = false
    implicitWidth: 460
    implicitHeight: 520

    property string tab: Ui.clocksTab || "world"      // world | alarms | stopwatch | timer
    onTabChanged: Ui.clocksTab = tab
    property string alarmTime: Qt.formatTime(new Date(Date.now() + 3600000), "HH:mm")
    property string alarmLabel: ""
    readonly property var alarms: Array.from(WorldClock.alarms || [])

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.clocks = false
        Keys.onSpacePressed: { if (win.tab === "stopwatch") WorldClock.swToggle(); }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [["world", Tr.t("World")], ["alarms", Tr.t("Alarms")], ["stopwatch", Tr.t("Stopwatch")], ["timer", Tr.t("Timer")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.tab === modelData[0]
                        onClicked: win.tab = modelData[0]
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // ---- the time here, always on top ----
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: win.tab === "world" || win.tab === "alarms"
                text: Qt.formatTime(clock.date, Settings.data.use24h ? "HH:mm:ss" : "h:mm:ss AP")
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: 40 * Theme.fontScale
                font.weight: Font.DemiBold
                SystemClock { id: clock; precision: SystemClock.Seconds; enabled: win.visible }
            }

            // ---- world ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "world"
                spacing: 4
                Repeater {
                    model: WorldClock.clocks
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: "preferences-system-time"
                        title: modelData.city
                        subtitle: modelData.zone
                        trailing: modelData.time
                        onClicked: {}
                    }
                }
                EmptyState {
                    visible: WorldClock.clocks.length === 0
                    icon: "preferences-system-time"
                    title: Tr.t("No other cities yet")
                    subtitle: Tr.t("Add the places you keep time with")
                }
                Item { Layout.fillHeight: true }
                Button {
                    Layout.fillWidth: true
                    text: Tr.t("Choose cities…")
                    onClicked: Ui.openSettings("time")
                }
            }

            // ---- alarms ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "alarms"
                spacing: 6
                Repeater {
                    model: win.alarms
                    ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        icon: "alarm"
                        title: modelData.time + (modelData.label ? " — " + modelData.label : "")
                        subtitle: Tr.t("Daily · rings once at this time")
                        trailing: Tr.t("Remove")
                        onClicked: WorldClock.removeAlarm(index)
                    }
                }
                EmptyState {
                    visible: win.alarms.length === 0
                    icon: "alarm"
                    title: Tr.t("No alarms")
                    subtitle: Tr.t("Pick a time below — it rings once, with a notification")
                }
                Item { Layout.fillHeight: true }
                TimePicker {
                    Layout.fillWidth: true
                    label: Tr.t("Alarm time")
                    value: win.alarmTime
                    onPicked: t => win.alarmTime = t
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField {
                        id: labelField
                        Layout.fillWidth: true
                        placeholder: Tr.t("Label — Wake up, …")
                        label: Tr.t("Alarm label")
                        onTextChanged: win.alarmLabel = text
                        onAccepted: addAlarm.clicked()
                    }
                    Button {
                        id: addAlarm
                        kind: "primary"
                        text: Tr.t("Add alarm at %1").arg(win.alarmTime)
                        onClicked: { if (WorldClock.addAlarm(win.alarmTime, win.alarmLabel)) labelField.text = ""; }
                    }
                }
            }

            // ---- stopwatch ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "stopwatch"
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: WorldClock.swDisplay
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: 48 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Button { Layout.fillWidth: true; kind: "primary"; text: WorldClock.swRunning ? Tr.t("Pause") : Tr.t("Start"); onClicked: WorldClock.swToggle() }
                    Button { Layout.fillWidth: true; text: Tr.t("Lap"); enabled: WorldClock.swRunning; onClicked: WorldClock.swLap() }
                    Button { Layout.fillWidth: true; text: Tr.t("Reset"); onClicked: WorldClock.swReset() }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: WorldClock.swLaps
                    delegate: ListRow {
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        icon: "alarm"
                        title: Tr.t("Lap %1").arg(index + 1)
                        trailing: modelData
                        onClicked: {}
                    }
                }
            }

            // ---- timer: pick how long, no typing ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "timer"
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: FocusTimer.running ? FocusTimer.label : "0:00"
                    color: FocusTimer.running ? Theme.accent : Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 48 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Theme.surface3
                    visible: FocusTimer.running
                    Rectangle {
                        width: FocusTimer.total > 0 ? parent.width * (1 - FocusTimer.left / FocusTimer.total) : 0
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [1, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90]
                        Choice {
                            required property int modelData
                            text: modelData + " " + Tr.t("min")
                            selected: FocusTimer.running && FocusTimer.total === modelData * 60
                            onClicked: FocusTimer.start(modelData)
                        }
                    }
                }
                Button {
                    Layout.fillWidth: true
                    visible: FocusTimer.running
                    kind: "danger"
                    text: Tr.t("Stop the timer")
                    onClicked: FocusTimer.stop()
                }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("It counts down in the Island too, and tells you when it is done.")
                    color: Theme.faint
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
