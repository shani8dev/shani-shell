// Archives: look inside a zip, tar, 7z or ISO, and take it out - into a new
// folder beside it (nothing is written over), or into a folder you choose.
// Services/Archive reads and extracts with libarchive's bsdtar.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Archive Manager"
    doc: Archive.name
    visible: Archive.shown
    onGone: Archive.close()
    implicitWidth: 720
    implicitHeight: 620

    function pick() {
        FilePicker.open({ mode: "open", title: Tr.t("Open an archive"), filters: Archive.types,
                          startPath: Archive.file !== "" ? Archive.file.substring(0, Archive.file.lastIndexOf("/")) : (Quickshell.env("HOME") + "/Downloads"),
                          onPicked: paths => { if (paths.length) Archive.open(paths[0]); } });
    }
    function extractTo() {
        FilePicker.open({ mode: "folder", title: Tr.t("Extract into"),
                          startPath: Archive.file.substring(0, Archive.file.lastIndexOf("/")),
                          onPicked: paths => { if (paths.length) Archive.extract(paths[0]); } });
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_O) { win.pick(); e.accepted = true; }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_E) { Archive.extract(""); e.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Icon { name: "package-x-generic"; size: 22; color: Theme.accent }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: Archive.file !== "" ? Archive.name : Tr.t("Archive Manager")
                        color: Theme.text
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: 15 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: Archive.file !== ""
                        text: Archive.reading ? Tr.t("Reading…")
                            : Archive.entries.length + " " + Tr.t("items") + "  ·  " + Archive.human(Archive.totalSize) + " " + Tr.t("when extracted")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                }
                Button { text: Tr.t("Open…"); flat: true; onClicked: win.pick() }
            }

            // ---- what is inside ----
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                clip: true
                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 1
                    boundsBehavior: Flickable.StopAtBounds
                    model: Archive.entries
                    delegate: RowLayout {
                        id: row
                        required property var modelData
                        readonly property int depth: modelData.path.split("/").length - 1
                        width: list.width
                        height: 26
                        spacing: 8
                        Item { implicitWidth: row.depth * 14; implicitHeight: 1 }
                        Icon { name: row.modelData.dir ? "folder" : "text-x-generic"; size: 16; color: row.modelData.dir ? Theme.accent : Theme.dim }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.path.split("/").pop()
                            color: Theme.text
                            elide: Text.ElideMiddle
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                        }
                        Text {
                            text: row.modelData.dir ? "" : Archive.human(row.modelData.size)
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                            font.features: { "tnum": 1 }
                        }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: Archive.entries.length === 0 && !Archive.reading
                    icon: "package-x-generic"
                    title: Archive.error !== "" ? Archive.error : !Archive.available ? Tr.t("bsdtar (libarchive) is not installed") : Tr.t("No archive open")
                    subtitle: Archive.error !== "" || !Archive.available ? "" : Tr.t("Open a zip, tar, 7z or ISO to see what is inside")
                }
            }

            // ---- what happened ----
            RowLayout {
                Layout.fillWidth: true
                visible: Archive.extractedTo !== "" || (Archive.error !== "" && Archive.entries.length > 0)
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: Archive.error !== "" ? Archive.error : Tr.t("Extracted to") + " " + Archive.extractedTo
                    color: Archive.error !== "" ? Theme.danger : Theme.dim
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Button {
                    visible: Archive.extractedTo !== ""
                    text: Tr.t("Show the folder")
                    onClicked: Files.show(Archive.extractedTo)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true
                    kind: "primary"
                    enabled: Archive.entries.length > 0 && !Archive.extracting
                    text: Archive.extracting ? Tr.t("Extracting…") : Tr.t("Extract here")
                    onClicked: Archive.extract("")
                }
                Button {
                    Layout.fillWidth: true
                    enabled: Archive.entries.length > 0 && !Archive.extracting
                    text: Tr.t("Extract to…")
                    onClicked: win.extractTo()
                }
            }
        }
    }
}
