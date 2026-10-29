// The control centre's shelf: the newest screenshots, recordings, downloads (one section of Sidebar.qml).
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
    // a section whose parts are all hidden takes no room (no double gap)
    visible: Array.from(children).some(c => c.visible)

    ColumnLayout {
        visible: Shelf.items.length > 0
        Layout.fillWidth: true
        spacing: 4
        Component.onCompleted: Shelf.refresh()
        Connections { target: Ui; function onControlCenterChanged() { if (Ui.controlCenter) Shelf.refresh(); } }
        SectionTitle { text: Tr.t("Shelf") }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: Shelf.items.filter(x => x.image).slice(0, 6)
                ClippingRectangle {
                    id: shelfItem
                    required property var modelData
                    width: 120
                    height: 72
                    radius: 10
                    color: Theme.hover
                    Image {
                        anchors.fill: parent
                        source: "file://" + shelfItem.modelData.path
                        sourceSize: Qt.size(240, 144)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        // right-click: share it (phone, Bluetooth, nearby, email, clipboard)
                        onClicked: e => {
                            if (e.button === Qt.RightButton) { Ui.closeAll(); Share.open(shelfItem.modelData.path); }
                            else Qt.openUrlExternally("file://" + shelfItem.modelData.path);
                        }
                    }
                }
            }
        }
        Repeater {
            model: Shelf.items.filter(x => !x.image).slice(0, 4)
            ListRow {
                id: shelfFile
                required property var modelData
                Layout.fillWidth: true
                icon: /\.(mp4|mkv|webm)$/i.test(modelData.name) ? "video-x-generic" : "text-x-generic"
                title: modelData.name
                onClicked: Qt.openUrlExternally("file://" + modelData.path)
                IconButton {
                    icon: "emblem-shared"
                    size: 24
                    Accessible.name: "Share " + shelfFile.modelData.name
                    onClicked: { Ui.closeAll(); Share.open(shelfFile.modelData.path); }
                }
            }
        }
    }
}
