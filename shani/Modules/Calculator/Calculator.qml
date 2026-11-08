// The calculator (Calculator): a keypad panel over the Calculator service.
// The service owns the display string and evaluation (the safe Calc.js calc());
// this surface only draws it and sends keys to it.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services as Services

PanelWindow {
    id: win
    visible: Services.Calculator.shown && !Services.Lock.locked
    screen: Quickshell.screens.find(s => s.name === Services.Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-calculator"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // the keypad: digits, + − × ÷ ( ), √, %, π, =, C, copy and backspace.
    // `key` is what the service hears; `label` is what is drawn.
    readonly property var keys: [
        { label: "C", key: "C", kind: "danger" }, { label: "(", key: "(" }, { label: ")", key: ")" }, { label: "√", key: "sqrt" }, { label: "⌫", key: "Backspace" },
        { label: "7", key: "7" }, { label: "8", key: "8" }, { label: "9", key: "9" }, { label: "÷", key: "/" }, { label: "%", key: "%" },
        { label: "4", key: "4" }, { label: "5", key: "5" }, { label: "6", key: "6" }, { label: "×", key: "*" }, { label: "π", key: "pi" },
        { label: "1", key: "1" }, { label: "2", key: "2" }, { label: "3", key: "3" }, { label: "−", key: "-" }, { label: "+", key: "+" },
        { label: "0", key: "0" }, { label: ".", key: "." }, { label: "Copy", key: "copy" }, { label: "=", key: "=", kind: "primary" }
    ]

    MouseArea { anchors.fill: parent; onClicked: Services.Calculator.close() }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Services.Calculator.close(); Keys.onReturnPressed: Services.Calculator.evaluate(); Keys.onEnterPressed: Services.Calculator.evaluate(); Keys.onBackspacePressed: Services.Calculator.backspace(); Keys.onDeletePressed: Services.Calculator.clear() }

    Glass {
        id: card
        anchors.centerIn: parent
        width: 360
        implicitHeight: col.implicitHeight + 40
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Calculator")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "edit-copy"; size: 28; tip: Tr.t("Copy result"); onClicked: Services.Calculator.copyResult() }
                IconButton { icon: "window-close"; size: 28; onClicked: Services.Calculator.close() }
            }

            Rectangle {
                radius: Theme.radiusSmall
                color: Theme.hover
                implicitHeight: 72
                Layout.fillWidth: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideLeft
                        text: Services.Calculator.error !== "" ? Services.Calculator.error : Services.Calculator.display
                        color: Services.Calculator.error !== "" ? Theme.danger : Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 26 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: Services.Calculator.error !== "" ? "" : Services.Calculator.preview !== "" ? "= " + Services.Calculator.preview : ""
                        color: Theme.dim
                        elide: Text.ElideLeft
                        font.family: Theme.mono
                        font.pixelSize: 13 * Theme.fontScale
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 5
                columnSpacing: 6
                rowSpacing: 6
                Repeater {
                    model: win.keys
                    Button {
                        required property var modelData
                        text: modelData.label
                        kind: modelData.kind || "plain"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 46
                        Layout.columnSpan: modelData.label === "=" ? 2 : 1
                        onClicked: {
                            if (modelData.key === "copy")
                                Services.Calculator.copyResult();
                            else
                                Services.Calculator.press(modelData.key);
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Esc closes · Enter = · Ctrl+C copies")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: Services.Calculator.close() }
    Shortcut { sequence: "Return"; onActivated: Services.Calculator.evaluate() }
    Shortcut { sequence: "Enter"; onActivated: Services.Calculator.evaluate() }
    Shortcut { sequence: "Ctrl+C"; onActivated: Services.Calculator.copyResult() }
}
