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
                                WindowLayouts.apply(modelData.id, Niri.focusedOutput);
                                Ui.windowLayouts = false;
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