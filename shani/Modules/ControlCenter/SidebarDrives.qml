// The control centre's drives (one section of Sidebar.qml).
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

    ColumnLayout {
        id: drivesList
        visible: Drives.drives.length > 0
        Layout.fillWidth: true
        spacing: 2
        SectionTitle { text: Tr.t("Drives") }
        property string asking: ""          // the locked drive whose passphrase is being typed
        Repeater {
            model: Drives.drives
            ColumnLayout {
                id: driveRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 2
                ListRow {
                    Layout.fillWidth: true
                    icon: driveRow.modelData.luks ? (driveRow.modelData.locked ? "changes-prevent" : "changes-allow") : "drive-removable-media"
                    title: driveRow.modelData.label
                    subtitle: driveRow.modelData.size + (driveRow.modelData.locked ? " · locked — click to unlock"
                        : driveRow.modelData.mount ? " · " + driveRow.modelData.mount : " · not mounted")
                    onClicked: driveRow.modelData.locked ? drivesList.asking = driveRow.modelData.dev
                        : driveRow.modelData.mount ? Drives.open(driveRow.modelData) : Drives.mount(driveRow.modelData)
                    IconButton {
                        icon: "media-eject"
                        size: 26
                        Accessible.name: "Eject " + driveRow.modelData.label
                        onClicked: Drives.eject(driveRow.modelData)
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    visible: driveRow.modelData.locked && drivesList.asking === driveRow.modelData.dev
                    placeholder: Drives.unlockError || "Passphrase for " + driveRow.modelData.label
                    secret: true
                    onAccepted: { Drives.unlock(driveRow.modelData, text); text = ""; }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        SectionTitle { text: Tr.t("Storage") }
        ListRow {
            Layout.fillWidth: true
            icon: "drive-harddisk"
            title: Drives.scanning ? Tr.t("Scanning…") : Tr.t("Disk usage")
            subtitle: Tr.t("Largest folders in home")
            onClicked: { if (!Drives.scanning) { Drives.scanStorage(); } }
        }
        Repeater {
            model: Drives.storage || []
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "folder"
                title: modelData.path || ""
                subtitle: {
                    const kb = modelData.size || 0;
                    if (kb > 1024 * 1024) return Math.round(kb / 1024 / 1024 * 10) / 10 + " GB";
                    if (kb > 1024) return Math.round(kb / 1024 * 10) / 10 + " MB";
                    return kb + " KB";
                }
            }
        }
    }
}
