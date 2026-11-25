// Window layout palette: a popup that shows the available grid layouts
// (half, thirds, quarters, big-left, big-right, stack, plus custom ones)
// as clickable tiles. Clicking one applies it to the focused window via
// niri actions. Ctrl+Z undoes the last arrangement.
//
// Opened from the launcher, Super+Shift+L, or `qs ipc call shell windowLayouts`.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    property bool arrangeAllMode: false     // apply the layout to every column, not just focus
    property bool customEditing: false
    property string customName: ""
    // custom-layout deletion is a per-row ConfirmButton keyed by the layout id,
    // which stays stable across refreshes; hiding the palette disarms it
    onVisibleChanged: if (!visible) { customEditing = false; customName = "" }
    visible: Ui.windowLayouts && !Lock.locked && !Polkit.active
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    // appear near the center of the screen, not full-screen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-window-layouts"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // keyboard: Esc closes, Ctrl+Z undoes
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Ui.windowLayouts = false
        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_Z) {
                WindowLayouts.undo();
                e.accepted = true;
            }
        }
    }

    // click outside the card to close
    MouseArea {
        anchors.fill: parent
        onClicked: Ui.windowLayouts = false
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(440, parent.width - 48)
        implicitHeight: col.implicitHeight + 40
        strong: true
        radius: Theme.radiusLarge

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: Theme.px(20) }
            spacing: Theme.px(12)

            // title row
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Tr.t("Window layout")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(15) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: WindowLayouts.undoStack.length >= 2
                    text: Tr.t("Ctrl+Z to undo")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                IconButton {
                    icon: "edit-undo"
                    size: Theme.px(26)
                    tip: Tr.t("Undo last layout")
                    enabled: WindowLayouts.undoStack.length >= 2
                    onClicked: WindowLayouts.undo()
                }
                Choice {
                    text: Tr.t("All windows")
                    selected: win.arrangeAllMode
                    onClicked: win.arrangeAllMode = !win.arrangeAllMode
                }
                IconButton {
                    icon: "window-close"
                    size: Theme.px(26)
                    tip: Tr.t("Close")
                    onClicked: Ui.windowLayouts = false
                }
            }

            // layout tiles
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Repeater {
                    model: WindowLayouts.layouts
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool current: WindowLayouts.appliedOn(Niri.focusedOutput) === modelData.id
                        width: Math.floor((card.width - 40 - 16) / 2) - 8
                        height: Theme.px(72)
                        radius: Theme.radiusSmall
                        color: current ? Theme.alpha(Theme.accent, 0.18) : (area.containsMouse ? Theme.hover : Theme.surface1)
                        border.width: current ? 2 : 1
                        border.color: current ? Theme.accent : Theme.border
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name

                        ColumnLayout {
                            anchors { fill: parent; margins: Theme.px(10) }
                            spacing: Theme.px(2)
                            // mini grid preview
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: Theme.px(2)
                                Repeater {
                                    model: modelData.ratios
                                    Rectangle {
                                        required property real modelData
                                        Layout.preferredWidth: modelData * 48
                                        Layout.preferredHeight: Theme.px(16)
                                        radius: Theme.px(2)
                                        color: Theme.alpha(Theme.accent, 0.4)
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.name
                                color: current ? Theme.accent : Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: modelData.cols > 1 || modelData.rows > 1
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.cols + "×" + modelData.rows
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: Theme.px(9) * Theme.fontScale
                            }
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (win.arrangeAllMode) WindowLayouts.arrangeAll(modelData.id);
                                else WindowLayouts.apply(modelData.id, Niri.focusedOutput);
                                Ui.windowLayouts = false;
                            }
                        }
                        KeyFocus {
                            onActivated: {
                                if (win.arrangeAllMode) WindowLayouts.arrangeAll(modelData.id);
                                else WindowLayouts.apply(modelData.id, Niri.focusedOutput);
                                Ui.windowLayouts = false;
                            }
                        }
                    }
                }
            }

            // custom layout authoring
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: customCol.implicitHeight + 12
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                ColumnLayout {
                    id: customCol
                    anchors { fill: parent; margins: Theme.px(6) }
                    spacing: Theme.px(4)
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: Tr.t("Your layouts"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: win.customEditing ? Tr.t("Cancel") : Tr.t("New layout…")
                            flat: true
                            onClicked: { win.customEditing = !win.customEditing; win.customName = ""; }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: win.customEditing
                        TextField {
                            id: customName
                            Layout.fillWidth: true
                            placeholder: Tr.t("Layout name")
                            text: win.customName
                            onTextChanged: win.customName = text
                        }
                        Button {
                            text: Tr.t("Add")
                            kind: "primary"
                            enabled: win.customName.trim() !== ""
                            onClicked: {
                                WindowLayouts.addCustom(win.customName.trim(), 2, 1, [0.6, 0.4]);
                                win.customEditing = false;
                                win.customName = "";
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        Repeater {
                            model: Settings.data.windowLayouts || []
                            Rectangle {
                                required property var modelData
                                implicitWidth: customLabel.implicitWidth + 28
                                height: Theme.px(24)
                                radius: Theme.px(12)
                                color: Theme.hover
                                Text {
                                    id: customLabel
                                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                    text: modelData.name
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(10) * Theme.fontScale
                                }
                                ConfirmButton {
                                    id: deleteLayoutConfirm
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    implicitWidth: Math.max(Theme.touchTarget, armedText.length * 6 + 16)
                                    implicitHeight: Theme.px(24)
                                    value: String(modelData.id)
                                    text: Tr.t("Delete")
                                    armedText: Tr.t("Click again to delete")
                                    kind: deleteLayoutConfirm.armed ? "danger" : "plain"
                                    interval: 3000
                                    Accessible.name: deleteLayoutConfirm.armed ? Tr.t("Click again to delete") : Tr.t("Delete layout")
                                    onConfirmed: WindowLayouts.removeCustom(modelData.id)
                                    Connections {
                                        target: win
                                        function onVisibleChanged() { if (!win.visible) deleteLayoutConfirm.disarm() }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // hint
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("Click a layout to apply it to the focused window. Niri handles the actual tiling — this sends the right actions.")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
