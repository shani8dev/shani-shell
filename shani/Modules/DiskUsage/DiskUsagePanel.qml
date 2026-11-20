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
    implicitWidth: Theme.px(920)
    implicitHeight: Theme.px(700)

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
            anchors.margins: Theme.px(16)
            spacing: Theme.px(10)

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "drive-harddisk"; size: Theme.px(20); color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: DiskUsage.current !== "" ? DiskUsage.current.replace(Quickshell.env("HOME"), "~") : ""
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.px(15) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: [["map", Tr.t("Map")], ["big", Tr.t("Biggest files")], ["dupes", Tr.t("Duplicates")]]
                    Choice { required property var modelData; text: modelData[1]; selected: DiskUsage.view === modelData[0]; onClicked: DiskUsage.setView(modelData[0]) }
                }
                IconButton { icon: "go-previous"; size: Theme.px(28); tip: Tr.t("Back (Esc)"); enabled: DiskUsage.history.length > 0; onClicked: DiskUsage.back() }
                IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Rescan"); onClicked: DiskUsage.refresh() }
            }

            // the biggest files, or the duplicates: a list, each line marked with a click
            ColumnLayout {
                visible: DiskUsage.view !== "map"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(6)
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: DiskUsage.scanning ? Tr.t("Looking…")
                            : DiskUsage.view === "dupes" ? (DiskUsage.dupes.length ? Tr.t("%1 sets of identical files · %2 could be freed", DiskUsage.dupes.length, DiskUsage.humanSize(DiskUsage.wasted)) : Tr.t("No duplicates here"))
                            : Tr.t("The biggest files in this folder and the ones in it")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    Button { visible: DiskUsage.view === "dupes" && DiskUsage.dupes.length > 0; text: Tr.t("Mark every copy but the oldest"); kind: "outline"; onClicked: DiskUsage.markAllExtras() }
                }
                ListView {
                    id: moreList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.px(2)
                    // one row per file; a duplicate set's rows follow its header
                    model: DiskUsage.view === "big" ? DiskUsage.big.map(e => ({ path: e.path, size: e.size }))
                         : [].concat(...DiskUsage.dupes.map((g, i) => [{ head: true, size: g.size, n: g.paths.length, g: i }]
                                                              .concat(g.paths.map((p, j) => ({ path: p, size: g.size, first: j === 0 })))))
                    delegate: Rectangle {
                        required property var modelData
                        width: moreList.width
                        height: Theme.px(modelData.head ? 26 : 30)
                        radius: Theme.px(6)
                        color: !modelData.head && DiskUsage.isMarked(modelData.path) ? Qt.alpha(Theme.danger, 0.18) : (rowArea.containsMouse && !modelData.head ? Theme.hover : "transparent")
                        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; enabled: !parent.modelData.head; onClicked: DiskUsage.toggleMark(parent.modelData.path) }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(modelData.head ? 4 : 16)
                            anchors.rightMargin: Theme.px(6)
                            spacing: Theme.px(8)
                            Icon { visible: !modelData.head; name: DiskUsage.isMarked(modelData.path || "") ? "edit-delete" : "text-x-generic"; size: Theme.px(14); color: DiskUsage.isMarked(modelData.path || "") ? Theme.red : Theme.dim }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.head ? Tr.t("%1 copies of %2", modelData.n, DiskUsage.humanSize(modelData.size))
                                    : (modelData.path || "").replace(Quickshell.env("HOME"), "~") + (modelData.first ? "  ·  " + Tr.t("oldest") : "")
                                elide: Text.ElideMiddle
                                color: modelData.head ? Theme.faint : Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(modelData.head ? 11 : 12) * Theme.fontScale
                            }
                            Text { visible: !modelData.head && DiskUsage.view === "big"; text: DiskUsage.humanSize(modelData.size || 0); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: modelData.path || ""
                        Accessible.checked: !modelData.head && DiskUsage.isMarked(modelData.path)
                        Accessible.onToggleAction: if (!modelData.head) DiskUsage.toggleMark(modelData.path)
                        Accessible.onPressAction: if (!modelData.head) DiskUsage.toggleMark(modelData.path)
                    }
                }
            }

            // the treemap: area ~ size, weighted (DiskUsage.treemap)
            Rectangle {
                id: treemapArea
                visible: DiskUsage.view === "map"
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
                        radius: Theme.px(6)
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
                                spacing: Theme.px(6)
                                Icon {
                                    visible: tile.big
                                    name: modelData.isDir ? "folder" : "text-x-generic"
                                    size: Theme.px(16)
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
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
                Text {
                    visible: !DiskUsage.scanning && DiskUsage.entries.length === 0
                    anchors.centerIn: parent
                    text: DiskUsage.error !== "" ? DiskUsage.error : Tr.t("Nothing here")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
            }

            Text {
                Layout.fillWidth: true
                text: DiskUsage.entries.length
                    ? Tr.t("%1 shown · %2 total · larger blocks are larger").arg(DiskUsage.entries.length).arg(DiskUsage.humanSize(DiskUsage.totalSize))
                    : Tr.t("Click a folder to walk in · click a file to mark it")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
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
                    height: Theme.px(30)
                    radius: Theme.px(8)
                    color: "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(8)
                        anchors.rightMargin: Theme.px(4)
                        spacing: Theme.px(6)
                        Icon { name: "edit-delete"; size: Theme.px(14); color: Theme.red }
                        Text {
                            Layout.fillWidth: true
                            text: modelData
                            color: Theme.text
                            elide: Text.ElideMiddle
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        IconButton {
                            icon: "window-close"
                            size: Theme.px(24)
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
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
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
                    font.pixelSize: Theme.px(11) * Theme.fontScale
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
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
