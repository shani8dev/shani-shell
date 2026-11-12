// DiskUsage (disk treemap): rectangles whose area is their size —
// bigger files and folders get bigger blocks. Click a folder to walk
// into it, Esc or Back to go up; click a file to mark it for removal;
// review the marked list below, then move it to the trash. Nothing is
// deleted until that review is confirmed. In the QrView PanelWindow
// pattern; the sizes and layout live in Services/DiskUsage.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Disk Usage"
    visible: Ui.diskUsage
    onGone: DiskUsage.close()
    margins: 0
    implicitWidth: 920
    implicitHeight: 700

    onVisibleChanged: { if (visible && DiskUsage.current === "") DiskUsage.open(""); }

    Item {
        anchors.fill: parent
        focus: win.visible
        // Esc walks back out of a folder first; only at the root does it close
        Keys.onEscapePressed: DiskUsage.history.length > 0 ? DiskUsage.back() : DiskUsage.close()
    }

    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "drive-harddisk"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: DiskUsage.current !== "" ? DiskUsage.current.replace(Quickshell.env("HOME"), "~") : ""
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-previous"; size: 28; tip: Tr.t("Back (Esc)"); enabled: DiskUsage.history.length > 0; onClicked: DiskUsage.back() }
                IconButton { icon: "view-refresh"; size: 28; tip: Tr.t("Rescan"); onClicked: DiskUsage.refresh() }
            }

            // the treemap: area ~ size, weighted (DiskUsage.treemap)
            Rectangle {
                id: treemapArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: "transparent"
                clip: true

                property var rects: DiskUsage.treemap(width, height)

                Repeater {
                    model: treemapArea.rects
                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        // a hair of desktop between tiles, so each reads as its own block
                        x: modelData.x + 1.5
                        y: modelData.y + 1.5
                        width: Math.max(2, modelData.w - 3)
                        height: Math.max(2, modelData.h - 3)
                        radius: 6
                        readonly property bool marked: DiskUsage.isMarked(modelData.path)
                        readonly property bool big: width > 160 && height > 90
                        // each its own colour (the accent's hue, stepped by the golden angle,
                        // as Baobab and Filelight do); files a quieter shade than folders
                        readonly property color hue: Qt.hsla((Theme.hue + index * 0.381966) % 1, modelData.isDir ? 0.55 : 0.32, Theme.dark ? 0.38 : 0.62, 1)
                        color: marked ? Theme.alpha(Theme.red, 0.5) : hover.containsMouse ? Qt.lighter(hue, 1.18) : hue
                        border.width: marked ? 2 : 0
                        border.color: Theme.red
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name + ", " + DiskUsage.humanSize(modelData.size) + (modelData.isDir ? ", folder" : "")
                        Accessible.onPressAction: modelData.isDir ? DiskUsage.enter(modelData.path) : DiskUsage.toggleMark(modelData.path)

                        Column {
                            anchors.fill: parent
                            anchors.margins: tile.big ? 12 : 6
                            spacing: 2
                            visible: tile.width > 46 && tile.height > 28
                            Row {
                                width: parent.width
                                spacing: 6
                                Icon {
                                    visible: tile.big
                                    name: modelData.isDir ? "folder" : "text-x-generic"
                                    size: 16
                                }
                                Text {
                                    width: parent.width - (tile.big ? 22 : 0)
                                    text: (tile.marked ? "✓ " : "") + modelData.name
                                    color: Theme.dark ? "#ffffff" : "#1a1a1a"
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.weight: Font.DemiBold
                                    font.pixelSize: (tile.big ? 14 : 11) * Theme.fontScale
                                }
                            }
                            Text {
                                width: parent.width
                                text: DiskUsage.humanSize(modelData.size)
                                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.78) : Qt.rgba(0, 0, 0, 0.7)
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: (tile.big ? 12 : 10) * Theme.fontScale
                            }
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // folders walk in on click; files toggle their mark
                            onClicked: modelData.isDir ? DiskUsage.enter(modelData.path) : DiskUsage.toggleMark(modelData.path)
                        }
                        KeyFocus {
                            name: modelData.name
                            onActivated: modelData.isDir ? DiskUsage.enter(modelData.path) : DiskUsage.toggleMark(modelData.path)
                        }
                    }
                }
                Text {
                    visible: DiskUsage.scanning
                    anchors.centerIn: parent
                    text: Tr.t("Scanning…")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
                Text {
                    visible: !DiskUsage.scanning && DiskUsage.entries.length === 0
                    anchors.centerIn: parent
                    text: DiskUsage.error !== "" ? DiskUsage.error : Tr.t("Nothing here")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
            }

            Text {
                Layout.fillWidth: true
                text: DiskUsage.entries.length
                    ? Tr.t("%1 shown · %2 total · larger blocks are larger").arg(DiskUsage.entries.length).arg(DiskUsage.humanSize(DiskUsage.totalSize))
                    : Tr.t("Click a folder to walk in · click a file to mark it")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }

            // review the marked list before anything is trashed
            SectionTitle {
                Layout.fillWidth: true
                text: Tr.t("Marked for removal (%1)").arg(DiskUsage.markedCount)
            }
            ListView {
                id: markedList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(132, Math.max(36, DiskUsage.markedCount * 32))
                visible: DiskUsage.markedCount > 0
                clip: true
                spacing: 2
                model: DiskUsage.marked
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: markedRow
                    required property var modelData
                    required property int index
                    width: markedList.width
                    height: 30
                    radius: 8
                    color: "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 4
                        spacing: 6
                        Icon { name: "edit-delete"; size: 14; color: Theme.red }
                        Text {
                            Layout.fillWidth: true
                            text: modelData
                            color: Theme.text
                            elide: Text.ElideMiddle
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }
                        IconButton {
                            icon: "window-close"
                            size: 24
                            tip: Tr.t("Unmark")
                            onClicked: DiskUsage.toggleMark(modelData)
                        }
                    }
                    KeyFocus {
                        name: Tr.t("Unmark") + " " + modelData
                        onActivated: DiskUsage.toggleMark(modelData)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: DiskUsage.markedCount === 0
                text: Tr.t("Nothing marked — click a file block to mark it for removal")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    text: Tr.t("Clear marks")
                    kind: "outline"
                    enabled: DiskUsage.markedCount > 0
                    onClicked: DiskUsage.clearMarks()
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: DiskUsage.error !== ""
                    text: DiskUsage.error
                    color: Theme.red
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Button {
                    text: Tr.t("Move marked to trash (%1)").arg(DiskUsage.markedCount)
                    kind: "danger"
                    enabled: DiskUsage.markedCount > 0
                    onClicked: DiskUsage.trashMarked()
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Click a folder to walk in · Esc goes back · nothing is deleted until you review the marked list")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
