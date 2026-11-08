// The control centre's clock extras (one section of Sidebar.qml): alarms
// and the stopwatch (WorldClock). Alarms ring through notify-send once,
// and are kept in Settings; the stopwatch is start / pause / reset / laps.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import Quickshell.Bluetooth
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Notifications

ColumnLayout {
    id: root
    spacing: 10
    property string alarmTime: Qt.formatTime(new Date(Date.now() + 3600000), "HH:mm")
    property string alarmLabel: ""
    readonly property var alarms: Array.from(WorldClock.alarms || [])

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        SectionTitle { Layout.fillWidth: true; text: Tr.t("Alarms & stopwatch") }
        IconButton {
            icon: "alarm"
            size: 28
            tip: Tr.t("Open the character browser")
            onClicked: { Ui.closeAll(); Ui.characters = true; }
        }
    }

    // ---- alarms -------------------------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Repeater {
            model: root.alarms
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
    }
    EmptyState {
        visible: root.alarms.length === 0
        icon: "alarm"
        title: Tr.t("No alarms")
        subtitle: Tr.t("Add one below — it rings once, with a notification")
    }
    TimePicker {
        id: picker
        Layout.fillWidth: true
        label: Tr.t("Alarm time")
        value: root.alarmTime
        onPicked: t => root.alarmTime = t
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            Layout.fillWidth: true
            placeholder: Tr.t("Label — Wake up, …")
            label: Tr.t("Alarm label")
            onTextChanged: root.alarmLabel = text
            onAccepted: {
                if (WorldClock.addAlarm(root.alarmTime, text)) { text = ""; root.alarmLabel = ""; }
            }
        }
        Button {
            text: Tr.t("Add")
            onClicked: {
                if (WorldClock.addAlarm(root.alarmTime, root.alarmLabel)) root.alarmLabel = "";
            }
        }
    }

    // ---- stopwatch ----------------------------------------------------------
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 56
        radius: Theme.radiusSmall
        color: Theme.surface1
        Text {
            anchors.centerIn: parent
            text: WorldClock.swDisplay
            color: Theme.text
            font.family: Theme.mono
            font.pixelSize: 22 * Theme.fontScale
            font.weight: Font.DemiBold
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Button { Layout.fillWidth: true; text: WorldClock.swRunning ? Tr.t("Pause") : Tr.t("Start"); onClicked: WorldClock.swToggle() }
        Button { Layout.fillWidth: true; text: Tr.t("Lap"); enabled: WorldClock.swRunning; onClicked: WorldClock.swLap() }
        Button { Layout.fillWidth: true; text: Tr.t("Reset"); onClicked: WorldClock.swReset() }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Repeater {
            model: WorldClock.swLaps
            ListRow {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                icon: "chronometer"
                title: Tr.t("Lap %1").arg(index + 1)
                trailing: modelData
                onClicked: {}
            }
        }
    }
}
