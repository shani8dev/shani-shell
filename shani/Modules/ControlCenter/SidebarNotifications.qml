// The control centre's notifications (one section of Sidebar.qml).
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
    spacing: 14

    SectionTitle {
        Layout.fillWidth: true
        text: Notifs.count > 0 ? "Notifications · " + Notifs.count : "Notifications"
        IconButton {
            icon: Notifs.dnd ? "notifications-disabled" : "preferences-system-notifications"
            size: 26
            on: Notifs.dnd
            onClicked: Notifs.setDnd(!Notifs.dnd)
        }
        IconButton { visible: Notifs.count > 1; icon: "chat-message-new"; size: 26; onClicked: { Ui.closeAll(); Notifs.summarize(); } }
        IconButton { visible: Notifs.count > 0 || Notifs.earlier.length > 0; icon: "edit-clear-all"; size: 26; onClicked: Notifs.clearAll() }
    }
    Text {
        visible: Notifs.count === 0 && Notifs.earlier.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 6
        horizontalAlignment: Text.AlignHCenter
        text: Tr.t("You're all caught up")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    // grouped by app, newest group first; the app is named once
    Repeater {
        model: {
            const groups = [];
            for (const n of Notifs.list) {
                const key = n.appName || "Notifications";
                let g = groups.find(x => x.app === key);
                if (!g)
                    groups.push(g = { app: key, items: [] });
                g.items.push(n);
            }
            return groups;
        }
        ColumnLayout {
            id: group
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                visible: group.modelData.items.length > 1
                Text {
                    Layout.fillWidth: true
                    text: group.modelData.app + " · " + group.modelData.items.length
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Button {
                    text: Tr.t("Clear")
                    onClicked: group.modelData.items.slice().forEach(n => n.dismiss())
                }
            }
            Repeater {
                model: group.modelData.items
                NotificationCard {
                    required property var modelData
                    Layout.fillWidth: true
                    notification: modelData
                    showApp: group.modelData.items.length === 1
                }
            }
        }
    }

    // from before the restart: read here, cleared one by one or all at once
    RowLayout {
        visible: Notifs.earlier.length > 0
        Layout.fillWidth: true
        Layout.topMargin: 6
        Text {
            Layout.fillWidth: true
            text: Tr.t("Earlier") + " · " + Notifs.earlier.length
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Button { text: Tr.t("Clear"); onClicked: Notifs.forgetEarlier() }
    }
    Repeater {
        model: Notifs.earlier
        ListRow {
            required property var modelData
            Layout.fillWidth: true
            icon: "preferences-system-notifications"
            title: modelData.summary
            subtitle: modelData.app + " · " + Qt.formatDateTime(new Date(modelData.time), Settings.data.use24h ? "ddd HH:mm" : "ddd h:mm AP")
                + (modelData.body ? " - " + modelData.body : "")
            onClicked: Notifs.forgetEarlier(modelData)
            Hint { text: Tr.t("From before the restart - click to clear it") }
        }
    }
}
