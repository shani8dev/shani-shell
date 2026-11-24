// Clocks: the world's time, alarms, a stopwatch and a timer in one window.
// The clocks themselves are Services/WorldClock's and FocusTimer's - the same
// alarms and stopwatch the sidebar shows, so one started here is running there.
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Clocks"
    visible: Ui.clocks
    onGone: Ui.clocks = false
    implicitWidth: Theme.px(460)
    implicitHeight: Theme.px(520)

    property string tab: Ui.clocksTab || "world"      // world | alarms | stopwatch | timer
    onTabChanged: Ui.clocksTab = tab
    property string alarmTime: Qt.formatTime(new Date(Date.now() + 3600000), "HH:mm")
    property string alarmLabel: ""
    property var alarmDays: []             // empty = every day; 0=Sun .. 6=Sat
    property int lastTimerMinutes: 0
    readonly property var alarms: Array.from(WorldClock.alarms || [])
    // an alarm removed elsewhere shifts every index: drop a pending confirmation
    // so the second tap cannot delete a different alarm
    onAlarmsChanged: win.confirmAlarm = -1
    // a row asks before it removes an alarm: two taps, the second within 4 s
    property int confirmAlarm: -1
    Timer { id: alarmTimer; interval: 4000; onTriggered: win.confirmAlarm = -1 }

    // flip an alarm on/off without losing its label or repeat days: the
    // service's addAlarm() takes both, removeAlarm() takes only an index.
    function toggleAlarm(index) {
        const list = Array.from(win.alarms || []);
        if (index < 0 || index >= list.length) return;
        const item = list[index];
        list.splice(index, 1);
        WorldClock.addAlarm(item.time, item.label, Array.isArray(item.days) ? item.days : [], item.enabled === false);
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.clocks = false
        Keys.onSpacePressed: { if (win.tab === "stopwatch") WorldClock.swToggle(); }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(12)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
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
                font.pixelSize: Theme.px(40) * Theme.fontScale
                font.weight: Font.DemiBold
                SystemClock { id: clock; precision: SystemClock.Seconds; enabled: win.visible }
            }

            // ---- world ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "world"
                spacing: Theme.px(4)
                Repeater {
                    model: WorldClock.clocks
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: "preferences-system-time"
                        title: modelData.city
                        subtitle: modelData.zone
                        trailing: modelData.time
                        interactive: false
                    }
                }
                EmptyState {
                    visible: WorldClock.clocks.length === 0
                    icon: "preferences-system-time"
                    title: Tr.t("No other cities yet")
                    subtitle: Tr.t("Add the places you keep time with")
                    actionText: Tr.t("Choose cities…")
                    onAction: Ui.openSettings("time")
                }
            }

            // ---- alarms ----
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "alarms"
                // the time picker is tall: the Add button must stay reachable
                contentWidth: width
                contentHeight: alarmsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: alarmsCol
                    width: parent.width
                    spacing: Theme.px(6)
                Repeater {
                    model: win.alarms
                    ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        icon: "alarm"
                        title: modelData.time + (modelData.label ? " — " + modelData.label : "")
                        subtitle: (Array.isArray(modelData.days) && modelData.days.length ? Tr.t("Repeats") : Tr.t("Daily")) + " · " + (modelData.enabled === false ? Tr.t("Off") : Tr.t("On"))
                        // tapping the row asks first: a stray click must not lose an alarm
                        trailing: win.confirmAlarm === index ? Tr.t("Tap again to remove") : Tr.t("Remove")
                        onClicked: {
                            if (win.confirmAlarm === index) { WorldClock.removeAlarm(index); win.confirmAlarm = -1; alarmTimer.restart(); }
                            else { win.confirmAlarm = index; alarmTimer.restart(); }
                        }
                        Button {
                            text: modelData.enabled === false ? Tr.t("On") : Tr.t("Off")
                            onClicked: win.toggleAlarm(index)
                        }
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
                    spacing: Theme.px(6)
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
                        onClicked: {
                            if (WorldClock.addAlarm(win.alarmTime, win.alarmLabel, win.alarmDays)) {
                                labelField.text = "";
                                win.alarmDays = [];
                            }
                        }
                    }
                }
                // CoreTime-style weekday repeat: nothing selected means every day
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Text { text: Tr.t("Repeat on"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    Repeater {
                        model: [{ n: 0, l: "S" }, { n: 1, l: "M" }, { n: 2, l: "T" }, { n: 3, l: "W" }, { n: 4, l: "T" }, { n: 5, l: "F" }, { n: 6, l: "S" }]
                        Button {
                            required property var modelData
                            Layout.preferredWidth: Theme.px(34)
                            text: modelData.l
                            checked: win.alarmDays.indexOf(modelData.n) >= 0
                            onClicked: {
                                const d = Array.from(win.alarmDays);
                                const i = d.indexOf(modelData.n);
                                if (i >= 0) d.splice(i, 1); else d.push(modelData.n);
                                win.alarmDays = d;
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text { text: win.alarmDays.length === 0 ? Tr.t("Every day") : Tr.t("Selected days"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                }
                Button {
                    Layout.fillWidth: true
                    text: Tr.t("Snooze 9 minutes")
                    enabled: WorldClock.snoozes.length === 0
                    onClicked: WorldClock.snooze(win.alarmLabel || win.alarmTime, 9)
                }
                }
            }

            // ---- stopwatch ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "stopwatch"
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: WorldClock.swDisplay
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(48) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Button { Layout.fillWidth: true; kind: "primary"; text: WorldClock.swRunning ? Tr.t("Pause") : Tr.t("Start"); onClicked: WorldClock.swToggle() }
                    Button { Layout.fillWidth: true; text: Tr.t("Lap"); enabled: WorldClock.swRunning; onClicked: WorldClock.swLap() }
                    Button { Layout.fillWidth: true; text: Tr.t("Reset"); onClicked: WorldClock.swReset() }
                }
                ListView {
                    reuseItems: true
                    cacheBuffer: 400
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
                        interactive: false
                    }
                }
            }

            // ---- timer: pick how long, no typing ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "timer"
                spacing: Theme.px(10)
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: FocusTimer.running ? FocusTimer.label : "0:00"
                    color: FocusTimer.running ? Theme.accent : Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(48) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(6)
                    radius: Theme.px(3)
                    color: Theme.surface3
                    visible: FocusTimer.running
                    Rectangle {
                        width: FocusTimer.total > 0 ? parent.width * (1 - FocusTimer.left / FocusTimer.total) : 0
                        height: parent.height
                        radius: Theme.px(3)
                        color: Theme.accent
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: [1, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90]
                        Choice {
                            required property int modelData
                            text: modelData + " " + Tr.t("min")
                            selected: FocusTimer.running && FocusTimer.total === modelData * 60
                            onClicked: { win.lastTimerMinutes = modelData; FocusTimer.start(modelData); }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Button {
                        Layout.fillWidth: true
                        visible: win.lastTimerMinutes > 0
                        text: Tr.t("Restart %1 min").arg(win.lastTimerMinutes)
                        onClicked: FocusTimer.start(win.lastTimerMinutes)
                    }
                    Button {
                        Layout.fillWidth: true
                        visible: FocusTimer.running
                        kind: "danger"
                        text: Tr.t("Stop the timer")
                        onClicked: FocusTimer.stop()
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("It counts down in the Island too, and tells you when it is done.")
                    color: Theme.faint
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
