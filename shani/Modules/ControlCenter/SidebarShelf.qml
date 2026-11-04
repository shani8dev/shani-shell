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
                        // right-click: what to do with it (convert, shrink, read, share, ask Chronoa)
                        onClicked: e => {
                            if (e.button === Qt.RightButton) { Ui.closeAll(); FileActions.offer([shelfItem.modelData.path]); }
                            else Qt.openUrlExternally("file://" + shelfItem.modelData.path);
                        }
                    }
                    Hint { text: Tr.t("Click to open - right-click to convert, shrink or share") }
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
                    icon: "document-edit"
                    size: 24
                    tip: Tr.t("Convert, shrink, zip…")
                    onClicked: { Ui.closeAll(); FileActions.offer([shelfFile.modelData.path]); }
                }
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
