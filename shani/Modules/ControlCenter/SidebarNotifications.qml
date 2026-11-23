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
    spacing: Theme.px(14)

    // search/filter state
    property string filter: ""

    SectionTitle {
        Layout.fillWidth: true
        text: Notifs.count > 0 ? "Notifications · " + Notifs.count : "Notifications"
        IconButton {
            icon: Notifs.dnd ? "notifications-disabled" : "preferences-system-notifications"
            tip: Notifs.dnd ? Tr.t("Do not disturb") : Tr.t("Notification settings")
            size: Theme.px(26)
            on: Notifs.dnd
            onClicked: Notifs.setDnd(!Notifs.dnd)
        }
        IconButton { visible: Notifs.count > 1; icon: "chat-message-new"; tip: Tr.t("Summarise"); size: Theme.px(26); onClicked: { Ui.closeAll(); Notifs.summarize(); } }
        IconButton { visible: Notifs.count > 0 || Notifs.earlier.length > 0; icon: "edit-clear-all"; tip: Tr.t("Clear all"); size: Theme.px(26); onClicked: Notifs.clearAll() }
    }
    // search field — shown when there are enough notifications to warrant it
    TextField {
        visible: Notifs.count + Notifs.earlier.length > 5
        Layout.fillWidth: true
        placeholder: Tr.t("Search notifications")
        label: Tr.t("Search notifications")
        text: filter
        onTextChanged: filter = text
        // the field hides itself when the total drops to five or fewer; without
        // this the old query keeps hiding rows with no field left to clear it
        onVisibleChanged: if (!visible) filter = ""
    }
    Text {
        visible: Notifs.count === 0 && Notifs.earlier.length === 0
        Layout.fillWidth: true
        Layout.topMargin: Theme.px(6)
        horizontalAlignment: Text.AlignHCenter
        text: Tr.t("You're all caught up")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    Text {
        visible: filter !== "" && Notifs.count + Notifs.earlier.length > 5
            && Notifs.list.filter(n => (n.appName + " " + n.summary + " " + n.body).toLowerCase().indexOf(filter.toLowerCase()) >= 0).length === 0
            && Notifs.earlier.filter(e => (e.app + " " + e.summary + " " + e.body).toLowerCase().indexOf(filter.toLowerCase()) >= 0).length === 0
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: Tr.t("No notifications match %1", filter)
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    // grouped by app, newest group first; the app is named once
    Repeater {
        model: {
            const q = filter.toLowerCase();
            const groups = [];
            for (const n of Notifs.list) {
                if (q && (n.appName + " " + n.summary + " " + n.body).toLowerCase().indexOf(q) < 0) continue;
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
            spacing: Theme.px(6)
            RowLayout {
                Layout.fillWidth: true
                visible: group.modelData.items.length > 1
                Text {
                    Layout.fillWidth: true
                    text: group.modelData.app + " · " + group.modelData.items.length
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Button {
                    text: Tr.t("Clear")
                    // every group has a "Clear" button; name the app so a screen
                    // reader can tell which stack a press will empty
                    Accessible.name: Tr.t("Clear all from %1").arg(group.modelData.app)
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
        visible: Notifs.earlier.filter(e => filter === "" || (e.app + " " + e.summary + " " + (e.body || "")).toLowerCase().indexOf(filter.toLowerCase()) >= 0).length > 0
        Layout.fillWidth: true
        Layout.topMargin: Theme.px(6)
        Text {
            Layout.fillWidth: true
            text: Tr.t("Earlier") + " · " + Notifs.earlier.filter(e => filter === "" || (e.app + " " + e.summary + " " + (e.body || "")).toLowerCase().indexOf(filter.toLowerCase()) >= 0).length
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Button {
            text: Tr.t("Clear")
            Accessible.name: Tr.t("Clear all earlier notifications")
            onClicked: Notifs.forgetEarlier()
        }
    }
    Repeater {
        model: Notifs.earlier.filter(e => filter === "" || (e.app + " " + e.summary + " " + (e.body || "")).toLowerCase().indexOf(filter.toLowerCase()) >= 0)
        ListRow {
            required property var modelData
            Layout.fillWidth: true
            icon: "preferences-system-notifications"
            title: modelData.summary
            subtitle: modelData.app + " · " + Qt.formatDateTime(new Date(modelData.time), Settings.data.use24h ? "ddd HH:mm" : "ddd h:mm AP")
                + (modelData.body ? " - " + modelData.body : "")
            // a tap forgets this row; say so to a screen reader, not just in the Hint
            Accessible.description: subtitle + ". " + Tr.t("Click to clear it")
            onClicked: Notifs.forgetEarlier(modelData)
            Hint { text: Tr.t("From before the restart - click to clear it") }
        }
    }
}
