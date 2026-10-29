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
    // a section whose parts are all hidden takes no room (no double gap)
    visible: Array.from(children).some(c => c.visible)

    Calendar {
        Layout.fillWidth: true
        today: sidebarClock.date
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
