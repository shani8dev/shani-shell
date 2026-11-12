// The file chooser: pick a file or a folder, in the shell. The native dialog
// (a portal) held the whole shell while D-Bus waited for it; this one is the
// shell's own, over the same listing the file manager uses.
//
// The folder on screen, the places on the left, the files in the middle (a
// list, or a grid of tiles for pictures), and at the bottom the name to save
// under and the button that says what it does.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: FilePicker.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-file-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: FilePicker.cancel()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (FilePicker.mode === "save")
                    FilePicker.accept();
                event.accepted = true;
            }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: FilePicker.cancel() }

    onVisibleChanged: {
        // the name to save under comes from whoever asked for the chooser
        if (visible)
            nameField.text = FilePicker.typedName;
    }

    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(920, parent.width - 80)
        height: Math.min(620, parent.height - 80)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // the title
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Icon { name: "document-open"; size: 18; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: FilePicker.title !== "" ? FilePicker.title : Tr.t("Choose a file")
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontTitle * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "window-close"; size: 28; tip: Tr.t("Close (Esc)"); onClicked: FilePicker.cancel() }
            }

            // the path
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: win.crumbs
                        delegate: Row {
                            required property var modelData
                            required property int index
                            spacing: 2
                            Text {
                                text: modelData.name
                                color: index === win.crumbs.length - 1 ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: FilePicker.go(modelData.path)
                                }
                            }
                            Text {
                                visible: index < win.crumbs.length - 1
                                text: "›"
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // the places
                ColumnLayout {
                    Layout.preferredWidth: 160
                    Layout.fillHeight: true
                    spacing: 2
                    Repeater {
                        model: Files.places
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: 28
                            radius: 8
                            color: FilePicker.path === modelData.path ? Theme.accentSoft
                                 : (placeArea.containsMouse ? Theme.hover : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 8
                                Icon { name: modelData.icon; size: 15; color: Theme.dim }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 12 * Theme.fontScale
                                }
                            }
                            MouseArea {
                                id: placeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: FilePicker.go(modelData.path)
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // the files
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.alpha(Theme.bg, 0.35)
                    clip: true

                    ListView {
                        id: list
                        anchors.fill: parent
                        anchors.margins: 4
                        model: win.model
                        spacing: 1
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            width: list.width
                            height: 30
                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: FilePicker.isSelected(row.modelData.path) ? Theme.accentSoft
                                     : (rowArea.containsMouse ? Theme.hover : "transparent")
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 10
                                spacing: 10
                                FileIcon { entry: row.modelData; size: 18 }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    color: Theme.text
                                    elide: Text.ElideMiddle
                                    font.family: Theme.font
                                    font.pixelSize: 12 * Theme.fontScale
                                }
                                Text {
                                    Layout.preferredWidth: 78
                                    horizontalAlignment: Text.AlignRight
                                    text: row.modelData.isDir ? "" : Files.humanSize(row.modelData.size)
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 11 * Theme.fontScale
                                }
                            }
                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                    const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                    FilePicker.select(row.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"));
                                }
                                onDoubleClicked: FilePicker.activate(row.modelData.path)
                            }
                            KeyFocus {
                                name: row.modelData.name + (row.modelData.isDir ? ", " + Tr.t("folder") : "")
                                onActivated: FilePicker.activate(row.modelData.path)
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: row.modelData.name
                            Accessible.onPressAction: FilePicker.select(row.modelData.path, "single")
                        }
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        width: parent.width - 40
                        icon: "folder"
                        title: Tr.t("This folder is empty")
                        subtitle: Tr.t("Nothing to choose here")
                    }
                }
            }

            // the name to save under, and the button that does it
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    visible: FilePicker.mode === "save"
                    label: Tr.t("Name")
                    onTextChanged: FilePicker.typedName = text
                    onAccepted: FilePicker.accept()
                }
                Text {
                    Layout.fillWidth: true
                    visible: FilePicker.mode !== "save"
                    text: FilePicker.error !== "" ? FilePicker.error : Tr.t("%1 items").arg(list.count)
                    color: FilePicker.error !== "" ? Theme.red : Theme.faint
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Button { text: Tr.t("Cancel"); onClicked: FilePicker.cancel() }
                Button {
                    text: FilePicker.mode === "save" ? Tr.t("Save") : FilePicker.mode === "folder" ? Tr.t("Use this folder") : Tr.t("Open")
                    kind: "primary"
                    enabled: FilePicker.canAccept
                    onClicked: FilePicker.accept()
                }
            }
        }
    }

    // the model the list shows: the picker's own directory
    readonly property var model: FilePicker.directoryEntries
    readonly property var crumbs: {
        const p = FilePicker.path;
        if (!p || p === "/")
            return [{ name: "/", path: "/" }];
        const home = Files.home;
        const out = [];
        let rest = p;
        let at = "";
        if (home && p.indexOf(home + "/") === 0) {
            out.push({ name: Tr.t("Home"), path: home });
            rest = p.substring(home.length);
            at = home;
        }
        for (const part of rest.split("/").filter(x => x)) {
            at = at + "/" + part;
            out.push({ name: part, path: at });
        }
        if (out.length > 5)
            return out.slice(0, 1).concat(out.slice(-3));
        return out;
    }
}
