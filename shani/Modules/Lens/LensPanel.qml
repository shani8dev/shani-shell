// What Lens found in the region you selected: the snippet, its text (select
// any of it), decoded QR/barcodes as links, and what to do next — copy,
// search, define, translate, save, or ask Chronoa (with your own question, or not).
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
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: visible && Settings.blurWanted ? lensRegion : null
    Region { id: lensRegion; item: card; radius: Theme.radiusLarge }

    // deferred so the focus sink below cannot take focus after the field does
    onVisibleChanged: if (visible) Qt.callLater(() => question.input.forceActiveFocus())

    // the clipboard is the word channel to the Dictionary (which seeds its
    // search box from it on open); Ui.dictionary is the same flag the shell's
    // dictionaryOpen IPC uses. No the Ui singleton source file change needed.
    function defineSelection() {
        const word = String(Lens.text || "").trim();
        if (word === "") return;
        Quickshell.clipboardText = word;
        Ui.dictionary = false;   // re-open so Dictionary re-reads the clipboard
        Qt.callLater(() => { Ui.dictionary = true; });
        Lens.close();
    }

    MouseArea { objectName: "nav:pointer"; anchors.fill: parent; onClicked: Lens.close() }
    // Escape closes from anywhere in the card, not only while the question has focus.
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Lens.close() }

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
            anchors.margins: Theme.px(18)
            spacing: Theme.px(12)

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "system-search"; size: Theme.px(20); color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Lens.phase === "reading" ? Tr.t("Lens · reading…") : Tr.t("Lens")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(15) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Read the selection again"); onClicked: Lens.capture() }
                IconButton { icon: "window-close"; size: Theme.px(28); tip: Tr.t("Close"); onClicked: Lens.close() }
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
                    anchors.margins: Theme.px(8)
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
                    subtitle: /^https?:\/\//.test(modelData) ? Tr.t("QR code · open link") : Tr.t("Code · copy")
                    onClicked: /^https?:\/\//.test(modelData) ? Qt.openUrlExternally(modelData) : (Quickshell.clipboardText = modelData)
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(180, found.implicitHeight)
                Layout.minimumHeight: Theme.px(24)
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
                    text: Lens.phase === "reading" ? "" : (Lens.error || Lens.text || Tr.t("No text found in the selection."))
                    color: Lens.text ? Theme.text : Theme.dim
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentInk
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button { text: Tr.t("Copy text"); enabled: Lens.text !== ""; onClicked: { Lens.copyText(); Lens.close(); } }
                Button { text: Tr.t("Search"); enabled: Lens.text !== ""; onClicked: { Lens.search(); Lens.close(); } }
                Button { text: Tr.t("Define"); enabled: Lens.text.trim() !== ""; onClicked: win.defineSelection() }
                Button { text: Tr.t("Translate"); enabled: Lens.text !== ""; onClicked: { Lens.translate(); Lens.close(); } }
                Button { text: Tr.t("Save image"); enabled: Lens.image !== ""; onClicked: { Lens.save(); Lens.close(); } }
                Button { text: Tr.t("Open image"); enabled: Lens.image !== ""; onClicked: { Lens.openImage(); Lens.close(); } }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: question
                    Layout.fillWidth: true
                    Accessible.name: Tr.t("Ask Chronoa about this…")
                    placeholder: Tr.t("Ask Chronoa about this…")
                    onAccepted: if (Lens.phase === "ready") Lens.ask(text)
                    input.Keys.onEscapePressed: Lens.close()
                }
                Button { text: Tr.t("Ask Chronoa"); kind: "primary"; enabled: Lens.phase === "ready"; onClicked: Lens.ask(question.text) }
            }
        }
    }
}
