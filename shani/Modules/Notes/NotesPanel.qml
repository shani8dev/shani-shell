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
    implicitWidth: Theme.px(900)
    implicitHeight: Theme.px(600)
    property string note: ""            // the last word about an image, in a line of its own
    tools: [
        IconButton {
            size: Theme.px(30)
            icon: "insert-image-symbolic"
            tip: Tr.t("Insert an image from the clipboard")
            onClicked: win.insertImage()
        }
    ]

    property string filterText: ""
    property string selectedNotebook: ""
    // delete asks first: a note is a file on disk, and there is no undo
    property bool confirmDelete: false
    property bool confirmNotebook: false
    Timer { id: deleteTimer; interval: 4000; onTriggered: win.confirmDelete = false }
    Timer { id: notebookTimer; interval: 4000; onTriggered: win.confirmNotebook = false }


    Item {
        id: card
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Sidebar: notebooks + notes list
            Rectangle {
                Layout.preferredWidth: Theme.px(260)
                Layout.fillHeight: true
                color: Theme.surface1
                radius: Theme.radiusLarge

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    spacing: Theme.px(6)

                    // Search
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: Tr.t("Filter note names…")
                        text: win.filterText
                        onTextChanged: win.filterText = text
                    }

                    // the notebooks, as picks (all of them, or one); + makes one, − removes the chosen
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
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
                        IconButton { size: Theme.px(28); icon: "list-add"; tip: Tr.t("New notebook"); onClicked: Services.QuickNotes.createNotebook(Tr.t("New notebook")) }
                        IconButton {
                            size: Theme.px(28)
                            visible: win.selectedNotebook !== ""
                            icon: "list-remove"
                            tip: win.confirmNotebook
                                ? Tr.t("Tap again to delete the notebook and its notes")
                                : Tr.t("Remove the notebook %1").arg(win.selectedNotebook)
                            onClicked: {
                                if (win.confirmNotebook) { Services.QuickNotes.deleteNotebook(win.selectedNotebook); win.selectedNotebook = ""; win.confirmNotebook = false; }
                                else { win.confirmNotebook = true; notebookTimer.restart(); }
                            }
                        }
                    }

                    // Search across note bodies
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: Tr.t("Search note text (Enter)…")
                        onAccepted: {
                            const results = Services.QuickNotes.searchBodies(text);
                            if (results.length > 0) Services.QuickNotes.open(results[0].name, results[0].notebook);
                        }
                    }

                    // Notes list
                    ListView {
                        id: noteList
                        reuseItems: true
                        cacheBuffer: 400
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: Services.QuickNotes.notes.filter(n => (win.selectedNotebook === "" || n.notebook === win.selectedNotebook) && (win.filterText === "" || n.name.toLowerCase().indexOf(win.filterText.toLowerCase()) >= 0))
                        delegate: ItemDelegate {
                            width: ListView.view.width
                            text: modelData.name
                            highlighted: modelData.id === Services.QuickNotes.current
                            onClicked: {
                                const slash = modelData.id.indexOf("/");
                                if (slash >= 0) Services.QuickNotes.open(modelData.id.slice(slash + 1), modelData.id.slice(0, slash));
                                else Services.QuickNotes.open(modelData.name, "");
                            }
                        }
                    }
                    // nothing here: say why, and offer the thing that fills it
                    EmptyState {
                        visible: noteList.count === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        icon: win.filterText !== "" ? "edit-find" : "text-x-generic"
                        title: win.filterText !== "" ? Tr.t("No note matches") : Tr.t("No notes yet")
                        subtitle: win.filterText !== ""
                            ? Tr.t("Try another word, or clear the filter")
                            : Tr.t("Notes save as you type — start one below")
                        actionText: win.filterText !== "" ? Tr.t("Clear the filter") : ""
                        onAction: win.filterText = ""
                    }

                    // New note button
                    Button {
                        Layout.fillWidth: true
                        text: Tr.t("New note")
                        kind: "primary"
                        onClicked: Services.QuickNotes.create(Tr.t("Untitled"), win.selectedNotebook)
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
                    Layout.preferredHeight: Theme.px(40)
                    spacing: Theme.px(4)
                    Layout.margins: Theme.px(8)

                    Label { text: Services.QuickNotes.current || Tr.t("No note selected"); font.bold: true; Layout.fillWidth: true }
                    Button { text: Tr.t("Export HTML"); enabled: Services.QuickNotes.current !== ""; onClicked: Services.QuickNotes.exportHtml() }
                    Button { text: Tr.t("Print"); enabled: Services.QuickNotes.current !== ""; onClicked: Services.QuickNotes.printNote() }
                    // the note is a file on disk: ask before it goes
                    Button {
                        text: win.confirmDelete ? Tr.t("Tap again to delete") : Tr.t("Delete")
                        kind: "danger"
                        enabled: Services.QuickNotes.current !== ""
                        onClicked: {
                            if (Services.QuickNotes.current === "") return;
                            if (win.confirmDelete) {
                                Services.QuickNotes.remove(Services.QuickNotes.current, Services.QuickNotes.currentNotebook);
                                win.confirmDelete = false;
                            } else {
                                win.confirmDelete = true;
                                deleteTimer.restart();
                            }
                        }
                    }
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
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(14)
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
                        font.pixelSize: Theme.px(12) * Theme.fontScale
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
                    spacing: Theme.px(4)
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
