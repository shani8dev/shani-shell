// The writing tools' card (Services/WritingTools): the selected text, what to
// do with it (one click each; typing an instruction is only the optional
// extra), and Chronoa's version with Replace and Copy.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: WritingTools.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-writing-tools"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }

    MouseArea { anchors.fill: parent; onClicked: WritingTools.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: WritingTools.close()
        Keys.onReturnPressed: if (WritingTools.result) WritingTools.replace()
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 720)
        implicitHeight: col.implicitHeight + 36
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Icon { name: "tools-check-spelling"; size: 22; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Writing tools")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    text: WritingTools.from === "selection" ? Tr.t("the selected text") : Tr.t("what you copied")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                IconButton { icon: "window-close"; tip: Tr.t("Close") + " (Esc)"; onClicked: WritingTools.close() }
            }

            // the text, as it is now
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.min(140, srcText.implicitHeight + 20)
                radius: Theme.radiusSmall
                color: Theme.alpha(Theme.surface1, 0.6)
                clip: true
                Text {
                    id: srcText
                    x: 10
                    y: 10
                    width: parent.width - 20
                    text: WritingTools.source || Tr.t("Select some text first (or copy it), then open the writing tools.")
                    color: WritingTools.source ? Theme.dim : Theme.faint
                    wrapMode: Text.Wrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
            }

            // what to do: one click each
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: WritingTools.source !== ""
                Repeater {
                    model: WritingTools.presets
                    Choice {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        selected: WritingTools.doing === modelData.label
                        enabled: !WritingTools.busy
                        onClicked: WritingTools.choose(index)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: WritingTools.source !== ""
                spacing: 6
                Text {
                    text: Tr.t("Translate into")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: WritingTools.languages
                        Choice {
                            required property string modelData
                            text: modelData
                            enabled: !WritingTools.busy
                            selected: WritingTools.doing === Tr.t("Translate into %1", modelData)
                            onClicked: WritingTools.translate(modelData)
                        }
                    }
                }
            }
            TextField {
                id: custom
                Layout.fillWidth: true
                visible: WritingTools.source !== ""
                placeholder: Tr.t("Or say what to do — “make it sound excited”, “turn it into a tweet”…")
                onAccepted: if (text.trim()) WritingTools.run(text.trim(), text.trim())
            }

            // Chronoa's version
            Rectangle {
                Layout.fillWidth: true
                visible: WritingTools.busy || WritingTools.result !== "" || WritingTools.error !== ""
                implicitHeight: Math.max(64, Math.min(320, outText.implicitHeight + 24))
                radius: Theme.radiusSmall
                color: Theme.alpha(Theme.accent, 0.10)
                border.width: 1
                border.color: Theme.accentLine
                clip: true
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 12
                    contentHeight: outText.implicitHeight
                    clip: true
                    TextEdit {
                        id: outText
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        text: WritingTools.error ? WritingTools.error : WritingTools.busy ? Tr.t("Chronoa is writing — %1…", WritingTools.doing) : WritingTools.result
                        color: WritingTools.error ? Theme.danger : WritingTools.busy ? Theme.dim : Theme.text
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 14 * Theme.fontScale
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: WritingTools.result !== ""
                spacing: 8
                Button { flat: true; text: Tr.t("Try again"); onClicked: WritingTools.again() }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Copy"); onClicked: WritingTools.copy() }
                Button { kind: "primary"; text: Tr.t("Replace") + "  ↵"; onClicked: WritingTools.replace() }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Written by Chronoa · Esc closes")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
