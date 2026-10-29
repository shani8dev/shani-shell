// The control centre's calendar (one section of Sidebar.qml).
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
    required property var sidebarClock
    spacing: 14

    Calendar {
        Layout.fillWidth: true
        today: sidebarClock.date
    }
    // other cities, if any are picked (Settings > Date & language): where the
    // kernel keeps them, DST-proof
    Repeater {
        model: WorldClock.clocks
        ListRow {
            required property var modelData
            Layout.fillWidth: true
            icon: "preferences-system-time"
            title: modelData.city
            subtitle: modelData.time
            onClicked: Ui.closeAll()
        }
    }
    // what is coming, from the person's calendars (Agenda: EDS)
    ColumnLayout {
        Connections { target: Ui; function onControlCenterChanged() { if (Ui.controlCenter) Agenda.refresh(); } }
        visible: Agenda.upcoming.length > 0
        Layout.fillWidth: true
        spacing: 2
        Repeater {
            model: Agenda.upcoming
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "x-office-calendar"
                title: modelData.summary
                subtitle: Agenda.when(modelData) + (modelData.location ? " · " + modelData.location : "")
                onClicked: { Ui.closeAll(); Agenda.openCalendar(); }
            }
        }
    }
}
