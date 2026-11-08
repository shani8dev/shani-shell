// Disktree (disk treemap): rectangles whose area is their size —
// bigger files and folders get bigger blocks. Click a folder to walk
// into it, Esc or Back to go up; click a file to mark it for removal;
// review the marked list below, then move it to the trash. Nothing is
// deleted until that review is confirmed. In the QrView PanelWindow
// pattern; the sizes and layout live in Services/Disktree.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.disktree && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-disktree"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: { if (visible && Disktree.current === "") Disktree.open(""); }

    MouseArea { anchors.fill: parent; onClicked: Disktree.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        // Esc walks back out of a folder first; only at the root does it close
        Keys.onEscapePressed: Disktree.history.length > 0 ? Disktree.back() : Disktree.close()
    }

    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(920, parent.width - 80)
        height: Math.min(700, parent.height - 100)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "drive-harddisk"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Disktree") + (Disktree.current !== "" ? "  ·  " + Disktree.current : "")
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-previous"; size: 28; tip: Tr.t("Back (Esc)"); enabled: Disktree.history.length > 0; onClicked: Disktree.back() }
                IconButton { icon: "view-refresh"; size: 28; tip: Tr.t("Rescan"); onClicked: Disktree.refresh() }
                IconButton { icon: "window-close"; size: 28; tip: Tr.t("Close (Esc)"); onClicked: Disktree.close() }
            }

            // the treemap: area ~ size, weighted (Disktree.treemap)
            Rectangle {
                id: treemapArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true

                property var rects: Disktree.treemap(width, height)

                Repeater {
                    model: treemapArea.rects
                    Rectangle {
                        required property var modelData
                        required property int index
                        x: modelData.x
                        y: modelData.y
                        width: Math.max(2, modelData.w)
                        height: Math.max(2, modelData.h)
                        radius: 4
                        color: {
                            const marked = Disktree.isMarked(modelData.path);
                            if (marked) return Theme.alpha(Theme.red, 0.45);
                            if (modelData.isDir) return Theme.alpha(Theme.accent, 0.30);
                            return Theme.alpha(Theme.surface1, 0.85);
                        }
                        border.width: Disktree.isMarked(modelData.path) ? 2 : 1
                        border.color: Disktree.isMarked(modelData.path) ? Theme.red : Theme.stroke
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name + ", " + Disktree.humanSize(modelData.size) + (modelData.isDir ? ", folder" : "")
                        Accessible.onPressAction: modelData.isDir ? Disktree.enter(modelData.path) : Disktree.toggleMark(modelData.path)

                        Text {
                            anchors.fill: parent
                            anchors.margins: 6
                            visible: parent.width > 46 && parent.height > 28
                            text: (Disktree.isMarked(modelData.path) ? "✓ " : "") + modelData.name
                                + "\n" + Disktree.humanSize(modelData.size)
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // folders walk in on click; files toggle their mark
                            onClicked: modelData.isDir ? Disktree.enter(modelData.path) : Disktree.toggleMark(modelData.path)
                        }
                        KeyFocus {
                            name: modelData.name
                            onActivated: modelData.isDir ? Disktree.enter(modelData.path) : Disktree.toggleMark(modelData.path)
                        }
                    }
                }
                Text {
                    visible: Disktree.scanning
                    anchors.centerIn: parent
                    text: Tr.t("Scanning…")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
                Text {
                    visible: !Disktree.scanning && Disktree.entries.length === 0
                    anchors.centerIn: parent
                    text: Disktree.error !== "" ? Disktree.error : Tr.t("Nothing here")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
            }

            Text {
                Layout.fillWidth: true
                text: Disktree.entries.length
                    ? Tr.t("%1 shown · %2 total · larger blocks are larger").arg(Disktree.entries.length).arg(Disktree.humanSize(Disktree.totalSize))
                    : Tr.t("Click a folder to walk in · click a file to mark it")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }

            // review the marked list before anything is trashed
            SectionTitle {
                Layout.fillWidth: true
                text: Tr.t("Marked for removal (%1)").arg(Disktree.markedCount)
            }
            ListView {
                id: markedList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(132, Math.max(36, Disktree.markedCount * 32))
                visible: Disktree.markedCount > 0
                clip: true
                spacing: 2
                model: Disktree.marked
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
                            onClicked: Disktree.toggleMark(modelData)
                        }
                    }
                    KeyFocus {
                        name: Tr.t("Unmark") + " " + modelData
                        onActivated: Disktree.toggleMark(modelData)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: Disktree.markedCount === 0
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
                    enabled: Disktree.markedCount > 0
                    onClicked: Disktree.clearMarks()
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: Disktree.error !== ""
                    text: Disktree.error
                    color: Theme.red
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Button {
                    text: Tr.t("Move marked to trash (%1)").arg(Disktree.markedCount)
                    kind: "danger"
                    enabled: Disktree.markedCount > 0
                    onClicked: Disktree.trashMarked()
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
