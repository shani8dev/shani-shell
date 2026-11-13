// Notes (Notes): a folder of Markdown notes, one file per note, saved as
// you type. Notebooks are subfolders. Wiki links [[like this]] jump
// between notes. Export to HTML, print via CUPS. Sync is a TODO.
import Quickshell
import Quickshell.Io
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
    property string note: ""            // the last word about an image, in a line of its own
    tools: [
        IconButton {
            size: 30
            icon: "insert-image-symbolic"
            tip: Tr.t("Insert an image from the clipboard")
            onClicked: win.insertImage()
        }
    ]

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
                        // a task's box toggles where it is clicked, without a preview
                        TapHandler {
                            onTapped: event => {
                                if (win.toggleTask(event.position)) event.accepted = true;
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: win.note
                        visible: win.note !== ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        wrapMode: Text.Wrap
                    }

                    Process {
                        id: paste
                        property string name: ""
                        property string target: ""
                        stdout: StdioCollector {}
                        stderr: StdioCollector {}
                        onExited: code => win.pasted(code)
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

    /// Flip a task's [ ] to [x] (or back) when its box is clicked.
    function toggleTask(point) {
        const index = editor.positionAt(point.x, point.y);
        const text = editor.text;
        const start = text.lastIndexOf("\n", index - 1) + 1;
        let end = text.indexOf("\n", index);
        if (end < 0) end = text.length;
        const line = text.slice(start, end);
        const m = /^(\s*[-*]\s+\[)([ xX])(\].*)$/.exec(line);
        if (!m) return false;
        const box = start + m[1].length;                 // the char between [ and ]
        if (index < box - 1 || index > box + 1) return false;
        const mark = m[2] === " " ? "x" : " ";
        editor.text = text.slice(0, box) + mark + text.slice(box + 1);
        editor.cursorPosition = index;
        return true;
    }

    /// Take the clipboard's picture (wl-paste), keep it beside the notes, and
    /// point the note at it. Images in notes are files, so they survive.
    function insertImage() {
        const folder = Services.QuickNotes.dir + "/assets";
        const name = "pasted-" + Date.now() + ".png";
        paste.name = name;
        paste.target = folder + "/" + name;
        win.note = "";
        paste.command = ["sh", "-c", 'mkdir -p "$1" && (wl-paste --type image/png || wl-paste --type image/jpeg) > "$2"', "sh", folder, paste.target];
        paste.running = true;
    }

    function pasted(code) {
        if (code !== 0) {
            win.note = Tr.t("The clipboard has no image");
            return;
        }
        editor.insert(editor.cursorPosition, "![](" + paste.name + ")");
        win.note = Tr.t("Image added");
    }
}
