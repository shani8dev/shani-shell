// Window layout palette: a popup that shows the available grid layouts
// (half, thirds, quarters, big-left, big-right, stack, plus custom ones)
// as clickable tiles. Clicking one applies it to the focused window via
// niri actions. Ctrl+Z undoes the last arrangement.
//
// Opened with Super+Z, by holding the bar's maximise button, from a window's
// menu, the launcher, or `qs ipc call shani windowLayoutsToggle`.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Common
import qs.Services

PanelWindow {
    id: win
    property bool arrangeAllMode: false     // apply the layout to every column, not just focus
    property bool customEditing: false
    property string customName: ""
    function applyLayout(id) {
        if (arrangeAllMode) WindowLayouts.arrangeAll(id);
        else WindowLayouts.apply(id, Niri.focusedOutput);
        Ui.windowLayouts = false;
    }
    // custom-layout deletion is a per-row ConfirmButton keyed by the layout id,
    // which stays stable across refreshes; hiding the palette disarms it
    onVisibleChanged: if (!visible) { customEditing = false; customName = "" }
    visible: Ui.windowLayouts && !Lock.locked && !Polkit.active
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    // appear near the center of the screen, not full-screen
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
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
        readonly property real usableHeight: Math.max(0, parent.height - Osk.heightOn(win.screen ? win.screen.name : ""))
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(0, (usableHeight - height) / 2)
        width: Math.max(0, Math.min(Theme.px(500), parent.width - Theme.space(6)))
        height: Math.max(0, Math.min(usableHeight - Theme.space(6), col.implicitHeight + Theme.space(6)))
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent; objectName: "nav:pointer" }

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: Theme.space(3) }
            spacing: Theme.px(12)

            // title row
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Tr.t("Window layout")
                    Accessible.role: Accessible.Heading
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type("heading")
                    font.weight: Font.DemiBold
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

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: win.arrangeAllMode ? Tr.t("Apply to all windows") : Tr.t("Apply to the focused window")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                    elide: Text.ElideRight
                }
                Choice {
                    text: Tr.t("All windows")
                    selected: win.arrangeAllMode
                    onClicked: win.arrangeAllMode = !win.arrangeAllMode
                }
            }

            Flickable {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                contentWidth: width
                contentHeight: content.implicitHeight + Theme.space(2)
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

                ColumnLayout {
                    id: content
                    width: Math.max(0, scroller.width - Theme.space(2))
                    spacing: Theme.space(3)
                    // layout tiles
                    GridLayout {
                        id: layoutsGrid
                        Layout.fillWidth: true
                        columns: width < Theme.px(240) ? 1 : 2
                        rowSpacing: Theme.space(2)
                        columnSpacing: Theme.space(2)
                        Repeater {
                            model: WindowLayouts.layouts
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool current: WindowLayouts.appliedOn(Niri.focusedOutput) === modelData.id
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                implicitHeight: Math.max(Theme.touchTarget, Theme.px(72))
                                radius: Theme.radiusSmall
                                color: current ? Theme.alpha(Theme.accent, 0.18) : (area.containsMouse ? Theme.hover : Theme.surface1)
                                border.width: current ? 2 : 1
                                border.color: current ? Theme.accent : Theme.border
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.name
                                Accessible.onPressAction: win.applyLayout(modelData.id)

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
                                                Layout.preferredWidth: modelData * Theme.px(56)
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
                                        font.pixelSize: Theme.type("small")
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: modelData.cols > 1 || modelData.rows > 1
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.cols + "×" + modelData.rows
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.type("caption")
                                    }
                                }
                                MouseArea {
                                    id: area
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.applyLayout(modelData.id)
                                }
                                KeyFocus {
                                    columns: layoutsGrid.columns
                                    onActivated: win.applyLayout(modelData.id)
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
                                Text { text: Tr.t("Your layouts"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body"); font.weight: Font.DemiBold }
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
                                    id: customNameField
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
                                        height: Math.max(Theme.touchTarget, Theme.px(28))
                                        radius: Theme.px(12)
                                        color: Theme.hover
                                        Text {
                                            id: customLabel
                                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                            text: modelData.name
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: Theme.type("caption")
                                        }
                                        ConfirmButton {
                                            id: deleteLayoutConfirm
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            implicitWidth: Math.max(Theme.touchTarget, armedText.length * 6 + 16)
                                            implicitHeight: Math.max(Theme.touchTarget, Theme.px(28))
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
                        text: Tr.t("Choose a layout to apply it.")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("caption")
                    }
                }
            }
        }
    }
}
