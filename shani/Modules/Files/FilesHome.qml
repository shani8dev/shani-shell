// Files on a narrow window (a phone): where the app opens, as phone file
// managers do - a search bar, the kinds of files as tiles, how full the
// device is, then the places, drives and cloud drives. A tap opens the place
// in the folder view; Back from the first folder comes here again.
// (docs/DESIGN.md; the wide window keeps its places column instead.)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Services

Flickable {
    id: home
    signal opened(string path)
    signal searchRequested()

    contentWidth: width
    contentHeight: col.implicitHeight + Theme.space(8)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Component.onCompleted: { Files.loadHomeFree(); Files.loadDevices(); }

    readonly property var categories: [
        { path: "recent:", label: Tr.t("Recent"), icon: "document-open-recent" },
        { path: "kind:pictures", label: Tr.t("Pictures"), icon: "image-x-generic" },
        { path: "kind:videos", label: Tr.t("Videos"), icon: "video-x-generic" },
        { path: "kind:music", label: Tr.t("Music"), icon: "audio-x-generic" },
        { path: "kind:documents", label: Tr.t("Documents"), icon: "x-office-document" },
        { path: Files.home + "/Downloads", label: Tr.t("Downloads"), icon: "folder-download" },
        { path: "kind:archives", label: Tr.t("Archives"), icon: "package-x-generic" },
        { path: "starred:", label: Tr.t("Starred"), icon: "starred" }
    ]

    ColumnLayout {
        id: col
        x: Theme.space(4)
        y: Theme.space(3)
        width: home.width - Theme.space(8)
        spacing: Theme.space(5)

        // the search bar: a tap opens search over every folder in home
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(Theme.px(48), Theme.touchTarget)
            radius: height / 2
            color: searchArea.containsMouse ? Theme.surface2 : Theme.card
            border.width: 1
            border.color: Theme.cardBorder
            Accessible.role: Accessible.Button
            Accessible.name: Tr.t("Search your files")
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space(4)
                anchors.rightMargin: Theme.space(4)
                spacing: Theme.space(3)
                Icon { name: "system-search"; size: Theme.px(18); color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Search your files")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                }
            }
            MouseArea { id: searchArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: home.searchRequested() }
            KeyFocus { name: Tr.t("Search your files"); onActivated: home.searchRequested() }
        }

        // the kinds of files, as tiles: four across, two on a narrow phone
        TileGrid {
            Layout.fillWidth: true
            minTileWidth: Theme.px(64)
            columnSpacing: Theme.space(2)
            rowSpacing: Theme.space(3)
            Repeater {
                model: home.categories
                Item {
                    id: tile
                    required property var modelData
                    implicitHeight: tileCol.implicitHeight + Theme.space(2)
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                    ColumnLayout {
                        id: tileCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.space(1)
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: Math.max(Theme.px(52), Theme.touchTarget)
                            implicitHeight: implicitWidth
                            radius: Theme.radiusLarge
                            color: tileArea.containsMouse ? Theme.accentHover : Theme.accentSoft
                            Icon { anchors.centerIn: parent; name: tile.modelData.icon; size: Theme.px(24); color: Theme.accent }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.modelData.label
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.type("small")
                        }
                    }
                    MouseArea { id: tileArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: home.opened(tile.modelData.path) }
                    KeyFocus { name: tile.modelData.label; columns: 4; onActivated: home.opened(tile.modelData.path) }
                }
            }
        }

        // how full this device is
        StatTile {
            Layout.fillWidth: true
            interactive: true
            icon: "drive-harddisk"
            label: Tr.t("This device")
            value: Files.homeFree >= 0 ? Tr.t("%1 free", Theme.bytes(Files.homeFree)) : Tr.t("Your files")
            detail: Files.homeTotal > 0 ? Tr.t("%1 used of %2", Theme.bytes(Files.homeTotal - Files.homeFree), Theme.bytes(Files.homeTotal)) : ""
            readonly property real used: Files.homeTotal > 0 ? (Files.homeTotal - Files.homeFree) / Files.homeTotal : -1
            progress: used
            // nearly full is something to look at, not an accent
            tint: Theme.toneColor(used > 0.97 ? "error" : used > 0.9 ? "warn" : "")
            onClicked: home.opened(Files.home)
        }

        Card {
            Layout.fillWidth: true
            title: Tr.t("Places")
            spacing: 0
            Repeater {
                model: Files.places
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.name
                    onClicked: home.opened(modelData.path)
                }
            }
            ListRow {
                Layout.fillWidth: true
                icon: "user-trash"
                title: Tr.t("Trash")
                onClicked: home.opened(Files.home + "/.local/share/Trash/files")
            }
        }

        Card {
            Layout.fillWidth: true
            visible: Files.devices.some(d => !d.internal)
            title: Tr.t("Drives and phones")
            spacing: 0
            Repeater {
                model: Files.devices.filter(d => !d.internal)
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon || "drive-removable-media"
                    title: modelData.name
                    subtitle: modelData.mounted ? "" : Tr.t("Tap to open")
                    onClicked: Files.openDevice(modelData)
                }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: Files.clouds.length > 0
            title: Tr.t("Cloud drives")
            spacing: 0
            Repeater {
                model: Files.clouds
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "folder-cloud"
                    title: modelData.name
                    onClicked: Files.openCloud(modelData)
                }
            }
        }
    }
}
