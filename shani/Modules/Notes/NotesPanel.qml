// Notes (Notes): a folder of Markdown notes, one file per note, saved as
// you type. Notebooks are subfolders. Wiki links [[like this]] jump
// between notes. Export to HTML, print via CUPS. Sync is a TODO.
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services as Services

AppWindow {
    id: win
    appName: "Notes"
    visible: Ui.notes
    onGone: Ui.notes = false
    margins: 0
    implicitWidth: 900
    implicitHeight: 600

    property string filterText: ""
    property string selectedNotebook: ""


    Item {
        id: card
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Sidebar: notebooks + notes list
            Rectangle {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                color: Theme.surface1
                radius: Theme.radiusLarge

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    // Search
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "Filter notes…"
                        text: win.filterText
                        onTextChanged: win.filterText = text
                    }

                    // the notebooks, as picks (all of them, or one); + makes one, − removes the chosen
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Choice {
                            text: Tr.t("All")
                            selected: win.selectedNotebook === ""
                            onClicked: win.selectedNotebook = ""
                        }
                        Repeater {
                            model: Services.QuickNotes.notebooks
                            Choice {
                                required property string modelData
                                text: modelData
                                selected: win.selectedNotebook === modelData
                                onClicked: win.selectedNotebook = modelData
                            }
                        }
                        IconButton { size: 28; icon: "list-add"; tip: Tr.t("New notebook"); onClicked: Services.QuickNotes.createNotebook(Tr.t("New notebook")) }
                        IconButton {
                            size: 28
                            visible: win.selectedNotebook !== ""
                            icon: "list-remove"
                            tip: Tr.t("Remove the notebook %1").arg(win.selectedNotebook)
                            onClicked: { Services.QuickNotes.deleteNotebook(win.selectedNotebook); win.selectedNotebook = ""; }
                        }
                    }

                    // Search across note bodies
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "Search in notes…"
                        onAccepted: {
                            const results = Services.QuickNotes.searchBodies(text);
                            if (results.length > 0) Services.QuickNotes.open(results[0].name, results[0].notebook);
                        }
                    }

                    // Notes list
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: Services.QuickNotes.notes.filter(n => (win.selectedNotebook === "" || n.notebook === win.selectedNotebook) && (win.filterText === "" || n.name.toLowerCase().indexOf(win.filterText.toLowerCase()) >= 0))
                        delegate: ItemDelegate {
                            width: parent.width
                            text: modelData.name
                            highlighted: modelData.id === Services.QuickNotes.current
                            onClicked: {
                                const slash = modelData.id.indexOf("/");
                                if (slash >= 0) Services.QuickNotes.open(modelData.id.slice(slash + 1), modelData.id.slice(0, slash));
                                else Services.QuickNotes.open(modelData.name, "");
                            }
                        }
                    }

                    // New note button
                    Button {
                        Layout.fillWidth: true
                        text: "+ New note"
                        onClicked: Services.QuickNotes.create("Untitled", win.selectedNotebook)
                    }
                }
            }

            // Editor
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Toolbar
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    spacing: 4
                    anchors.margins: 8

                    Label { text: Services.QuickNotes.current || "No note selected"; font.bold: true; Layout.fillWidth: true }
                    Button { text: "Export HTML"; onClicked: Services.QuickNotes.exportHtml() }
                    Button { text: "Print"; onClicked: Services.QuickNotes.printNote() }
                    Button { text: "Delete"; onClicked: { if (Services.QuickNotes.current !== "") Services.QuickNotes.remove(Services.QuickNotes.current, Services.QuickNotes.currentNotebook); } }
                }

                // Text editor
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextArea {
                        id: editor
                        text: Services.QuickNotes.text
                        onTextChanged: {
                            if (text !== Services.QuickNotes.text) Services.QuickNotes.text = text;
                        }
                        wrapMode: TextEdit.Wrap
                        font.family: "monospace"
                        font.pixelSize: 14
                    }
                }

                // Wiki links
                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 4
                    Repeater {
                        model: Services.QuickNotes.links()
                        delegate: Button {
                            text: "[[" + modelData + "]]"
                            onClicked: Services.QuickNotes.open(modelData, "")
                        }
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: Ui.notes = false
}
