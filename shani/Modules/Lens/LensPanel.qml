// What Lens found in the region you selected: the snippet, its text (select
// any of it), decoded QR/barcodes as links, and what to do next — copy,
// search, translate, save, or ask Chronoa (with your own question, or not).
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Lens.phase === "reading" || Lens.phase === "ready" || Lens.phase === "failed"
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-lens"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: visible && Settings.data.blur ? lensRegion : null
    Region { id: lensRegion; item: card; radius: Theme.radiusLarge }

    onVisibleChanged: if (visible) question.input.forceActiveFocus()

    MouseArea { anchors.fill: parent; onClicked: Lens.close() }

    Glass {
        id: card
        strong: true
        width: Math.min(620, parent.width - 80)
        height: Math.min(parent.height - 120, col.implicitHeight + 36)
        anchors.centerIn: parent
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "system-search"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Lens.phase === "reading" ? "Lens · reading…" : "Lens"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "view-refresh"; size: 28; onClicked: Lens.capture() }
                IconButton { icon: "window-close"; size: 28; onClicked: Lens.close() }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(220, snippet.implicitHeight > 0 ? snippet.paintedHeight + 16 : 120)
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true
                Image {
                    id: snippet
                    anchors.fill: parent
                    anchors.margins: 8
                    // only once grim has written it: a load attempted at capture
                    // start fails on the missing file and is never retried
                    source: Lens.phase === "ready" && Lens.image !== "" ? "file://" + Lens.image : ""
                    fillMode: Image.PreserveAspectFit
                    cache: false
                }
            }

            Repeater {
                model: Lens.codes === "" ? [] : Lens.codes.split("\n")
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: /^https?:\/\//.test(modelData) ? "web-browser" : "edit-paste"
                    title: modelData
                    subtitle: /^https?:\/\//.test(modelData) ? "QR code · open link" : "Code · copy"
                    onClicked: /^https?:\/\//.test(modelData) ? Qt.openUrlExternally(modelData) : (Quickshell.clipboardText = modelData)
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(180, found.implicitHeight)
                Layout.minimumHeight: 24
                contentHeight: found.implicitHeight
                clip: true
                TextEdit {
                    id: found
                    Accessible.role: Accessible.EditableText
                    Accessible.name: Tr.t("Text found on the screen")
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: Lens.phase === "reading" ? "" : (Lens.error || Lens.text || "No text found in the selection.")
                    color: Lens.text ? Theme.text : Theme.dim
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentInk
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8
                Button { text: Tr.t("Copy text"); enabled: Lens.text !== ""; onClicked: { Lens.copyText(); Lens.close(); } }
                Button { text: Tr.t("Search"); enabled: Lens.text !== ""; onClicked: { Lens.search(); Lens.close(); } }
                Button { text: Tr.t("Translate"); enabled: Lens.text !== ""; onClicked: { Lens.translate(); Lens.close(); } }
                Button { text: Tr.t("Save image"); onClicked: { Lens.save(); Lens.close(); } }
                Button { text: Tr.t("Open image"); onClicked: { Lens.openImage(); Lens.close(); } }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: question
                    Layout.fillWidth: true
                    placeholder: Tr.t("Ask Chronoa about this…")
                    onAccepted: Lens.ask(text)
                    input.Keys.onEscapePressed: Lens.close()
                }
                Button { text: Tr.t("Ask Chronoa"); kind: "primary"; enabled: Lens.phase === "ready"; onClicked: Lens.ask(question.text) }
            }
        }
    }
}
