// "What should happen to it?" - the card for files dropped on the Island (or a
// Shelf item's "Convert…"): only what fits these files, one click each
// (Services/FileActions). Esc or Cancel closes it.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: FileActions.files.length > 0
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors.top: true
    margins.top: 56
    implicitWidth: Theme.px(520)
    implicitHeight: card.implicitHeight + 12
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-file-actions"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.data.blur && visible ? cardRegion : null
    Region { id: cardRegion; item: card; radius: card.radius }
    // a new offer must not inherit typed limits from the previous file's form
    Connections {
        target: FileActions
        function onFilesChanged() {
            if (!FileActions.files.length) return;
            fMin.text = ""; fMax.text = ""; fW.text = ""; fH.text = "";
        }
    }

    Glass {
        id: card
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.px(500)
        implicitHeight: col.implicitHeight + 32
        radius: Theme.radiusLarge
        strong: true
        focus: true
        Keys.onEscapePressed: FileActions.close()
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(12)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)
                AppIcon {
                    implicitSize: 32
                    icon: ({ image: "image-x-generic", video: "video-x-generic", audio: "audio-x-generic", pdf: "x-office-document" })[FileActions.kinds] || "text-x-generic"
                    name: "F"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: FileActions.fitting ? Tr.t("What size does the form allow?") : Tr.t("What should happen to it?")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(15) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: FileActions.files.length === 1 ? FileActions.files[0].split("/").pop()
                            : Tr.t("%1 files", FileActions.files.length) + " · " + FileActions.files.map(f => f.split("/").pop()).join(", ")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                }
            }
            // ---- the size step: the usual kinds, or the form's own numbers
            GridLayout {
                Layout.fillWidth: true
                visible: FileActions.fitting
                columns: 2
                rowSpacing: Theme.px(6)
                columnSpacing: Theme.px(6)
                Repeater {
                    model: FileActions.presetsHere
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: "document-save"
                        title: modelData.label
                        subtitle: (modelData.min ? FileActions.kb(modelData.min) + " - " : Tr.t("up to ")) + FileActions.kb(modelData.max)
                                  + (modelData.w ? " · " + modelData.w + "×" + modelData.h + " px" : "")
                        onClicked: FileActions.fit(modelData)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: FileActions.fitting
                spacing: Theme.px(6)
                Text { text: Tr.t("Or the form's own:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField { id: fMin; Layout.preferredWidth: Theme.px(70); placeholder: Tr.t("min KB") }
                TextField { id: fMax; Layout.preferredWidth: Theme.px(70); placeholder: Tr.t("max KB") }
                TextField { id: fW; Layout.preferredWidth: Theme.px(60); visible: FileActions.kinds === "image"; placeholder: Tr.t("width") }
                TextField { id: fH; Layout.preferredWidth: Theme.px(60); visible: FileActions.kinds === "image"; placeholder: Tr.t("height") }
                Button {
                    text: Tr.t("Fit")
                    kind: "primary"
                    enabled: parseInt(fMax.text) > 0
                    onClicked: FileActions.fit({ max: parseInt(fMax.text) || 0, min: parseInt(fMin.text) || 0, w: parseInt(fW.text) || 0, h: parseInt(fH.text) || 0 })
                }
            }
            GridLayout {
                Layout.fillWidth: true
                visible: !FileActions.fitting
                columns: 2
                rowSpacing: Theme.px(6)
                columnSpacing: Theme.px(6)
                Repeater {
                    model: FileActions.actions
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: modelData.icon
                        title: modelData.label
                        onClicked: FileActions.run(modelData.id)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: FileActions.fitting ? Tr.t("Forms differ - check the form's own limits. The result is a new file next to this one.")
                                          : Tr.t("The result is saved next to the file - nothing is overwritten.")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Button { Layout.alignment: Qt.AlignRight; text: Tr.t("Cancel"); onClicked: FileActions.close() }
        }
    }
}
