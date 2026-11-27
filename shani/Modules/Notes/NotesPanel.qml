// Notes (Notes): a folder of Markdown notes, one file per note, saved as
// you type. Notebooks are subfolders. Wiki links [[like this]] jump
// between notes. Export to HTML, print via CUPS. QuickNotes mirrors the folder
// to a locally chosen sync folder; no account, no network.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services as Services
import qs.Modules.Notes

AppWindow {
    id: win
    appName: "Notes"
    sidePane: notebooksPane
    visible: Ui.notes
    onGone: Ui.notes = false
    margins: 0
    implicitWidth: Theme.px(900)
    implicitHeight: Theme.px(600)
    shortcutSearch: filterField   // Ctrl+F focuses the note-name filter
    // Ctrl+R is AppWindow's; notes autosave, so there is nothing to refresh
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
    onSelectedNotebookChanged: deleteNotebookConfirm.disarm()
    property string lockMode: ""            // "" | "set" | "check" — the passphrase box
    property string lockPass: ""
    // delete asks first: a note is a file on disk; it goes to Trash, not rm
    property string bodyQuery: ""
    property string tagFilter: ""
    property bool showTrash: false
    property bool showHistory: false
    // knowledge-base surfaces: a reading view, link neighbours and a move tray
    property bool previewMode: false
    property bool showBacklinks: false
    property bool showMove: false
    property string selectedTemplate: ""
    property string targetNotebook: ""
    property string statusText: ""
    property int historyIndex: -1
    readonly property string currentId: Services.QuickNotes.noteId(Services.QuickNotes.current, Services.QuickNotes.currentNotebook)
    // any narrowing at all: an empty list is "no match", not "no notes"
    readonly property bool hasFilter: filterText !== "" || tagFilter !== "" || selectedNotebook !== ""
    // a pending "tap again" belongs to the item it was armed on: switching
    // notes or notebooks must not delete the new selection on one tap
    Connections {
        target: Services.QuickNotes
        function onCurrentChanged() {
            // picking a note in the drawer leaves it, on a phone
            notebooksPane.open = false;
            // switching notes cancels the pending two-tap delete (the button
            // exists by the time a real note switch happens)
            if (deleteNoteConfirm) deleteNoteConfirm.disarm();
            win.note = "";
            win.historyIndex = -1;
            win.targetNotebook = "";
            win.statusText = "";
            win.showBacklinks = false;
            win.showMove = false;
            // history belongs to the note it was opened for: restoring an old
            // version after a switch would write it into the new note
            win.showHistory = false;
        }
    }


    Item {
        id: card
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Sidebar: notebooks + notes list — a column, a drawer on a phone
            SidePane {
                id: notebooksPane
                compact: win.compact
                paneWidth: Theme.px(260)
                label: Tr.t("Notebooks")
                Rectangle { anchors.fill: parent; color: Theme.surface1; radius: Theme.radiusLarge }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    spacing: Theme.px(6)

                    // Search
                    TextField {
                        id: filterField
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
                            onClicked: { win.selectedNotebook = ""; notebooksPane.open = false; }
                        }
                        Repeater {
                            model: Services.QuickNotes.notebooks
                            Choice {
                                required property string modelData
                                text: modelData
                                selected: win.selectedNotebook === modelData
                                onClicked: { win.selectedNotebook = modelData; notebooksPane.open = false; }
                            }
                        }
                        IconButton { size: Theme.touchTarget; icon: "list-add"; tip: Tr.t("New notebook"); onClicked: Services.QuickNotes.createNotebook(Tr.t("New notebook")) }
                        ConfirmButton {
                            id: deleteNotebookConfirm
                            size: Theme.touchTarget
                            visible: win.selectedNotebook !== ""
                            icon: "list-remove"
                            tip: Tr.t("Remove the notebook %1").arg(win.selectedNotebook)
                            armedText: Tr.t("Tap again to delete the notebook and its notes")
                            value: win.selectedNotebook
                            interval: 4000
                            onConfirmed: { Services.QuickNotes.deleteNotebook(win.selectedNotebook); win.selectedNotebook = ""; }
                        }
                    }

                    // Search across note bodies
                    TextField {
                        id: bodyField
                        Layout.fillWidth: true
                        placeholderText: Tr.t("Search note text (tag: notebook: name: \"phrase\")…")
                        onAccepted: {
                            win.bodyQuery = String(text).trim();
                            Services.QuickNotes.searchBodies(win.bodyQuery);
                        }
                    }

                    // every body-search hit, not only the first one
                    ListView {
                        visible: win.bodyQuery !== ""
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(Theme.px(120), contentHeight)
                        clip: true
                        model: Services.QuickNotes.bodyResults
                        delegate: ItemDelegate {
                            required property var modelData
                            width: ListView.view.width
                            implicitHeight: Theme.touchTarget
                            text: modelData.name + (modelData.notebook ? "  ·  " + modelData.notebook : "")
                            onClicked: Services.QuickNotes.open(modelData.name, modelData.notebook)
                        }
                    }

                    // A body search that found nothing is different from "no notes":
                    // say so, instead of leaving the person with an empty sidebar.
                    EmptyState {
                        visible: win.bodyQuery !== "" && Services.QuickNotes.bodyResults.length === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(90)
                        icon: "edit-find"
                        title: Tr.t("No note contains that text")
                        subtitle: Tr.t("Try tag:, notebook:, name: or a quoted phrase")
                    }

                    // Notes list
                    ListView {
                        id: noteList
                        reuseItems: true
                        cacheBuffer: 400
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: Services.QuickNotes.sortedNotes(Services.QuickNotes.filterNotes(win.filterText, win.selectedNotebook, win.tagFilter))
                        delegate: Rectangle {
                            required property var modelData
                            width: noteList.width
                            implicitHeight: Math.max(Theme.touchTarget, noteText.implicitHeight + prevText.implicitHeight + Theme.px(10))
                            radius: Theme.radiusSmall
                            color: modelData.id === Services.QuickNotes.current ? Theme.accentSoft
                                : rowMouse.containsMouse ? Theme.hover : "transparent"
                            ColumnLayout {
                                anchors { fill: parent; margins: Theme.px(4) }
                                spacing: 0
                                Text {
                                    id: noteText
                                    Layout.fillWidth: true
                                    text: (Services.QuickNotes.isPinned(modelData.id) ? "★ " : "")
                                          + modelData.name + (modelData.notebook ? "  ·  " + modelData.notebook : "")
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: Theme.type("body")
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: prevText
                                    Layout.fillWidth: true
                                    text: Services.QuickNotes.preview(modelData.name, modelData.notebook)
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.type("caption")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const slash = modelData.id.indexOf("/");
                                    if (slash >= 0) Services.QuickNotes.open(modelData.id.slice(slash + 1), modelData.id.slice(0, slash));
                                    else Services.QuickNotes.open(modelData.name, "");
                                }
                            }
                            // keys and a controller: Enter / Space opens this note, as the click
                            KeyFocus {
                                name: modelData.name + (modelData.notebook ? "  ·  " + modelData.notebook : "")
                                onActivated: {
                                    const slash = modelData.id.indexOf("/");
                                    if (slash >= 0) Services.QuickNotes.open(modelData.id.slice(slash + 1), modelData.id.slice(0, slash));
                                    else Services.QuickNotes.open(modelData.name, "");
                                }
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.name + (Services.QuickNotes.isPinned(modelData.id) ? ", " + Tr.t("pinned") : "")
                                             + (modelData.notebook ? ", " + modelData.notebook : "")
                            Accessible.onPressAction: {
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
                        icon: win.hasFilter ? "edit-find" : "text-x-generic"
                        title: win.hasFilter ? Tr.t("No note matches") : Tr.t("No notes yet")
                        subtitle: win.hasFilter
                            ? Tr.t("Try another word, or clear the filter")
                            : Tr.t("Notes save as you type — start one below")
                        actionText: win.hasFilter ? Tr.t("Clear the filter") : ""
                        onAction: { win.filterText = ""; win.tagFilter = ""; win.selectedNotebook = ""; }
                    }

                    // sort order and #tags
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        Repeater {
                            model: [["updated", "Updated"], ["created", "Created"], ["title", "Title"]]
                            Choice {
                                required property var modelData
                                text: modelData[1]
                                selected: Services.QuickNotes.sortBy === modelData[0]
                                onClicked: { Services.QuickNotes.sortBy = modelData[0]; Settings.data.notesSortBy = modelData[0]; Settings.save(); }
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        Choice { text: Tr.t("All tags"); selected: win.tagFilter === ""; onClicked: win.tagFilter = "" }
                        Repeater {
                            model: Services.QuickNotes.tags()
                            Choice {
                                required property string modelData
                                text: modelData
                                selected: win.tagFilter === modelData
                                onClicked: { win.tagFilter = modelData; Services.QuickNotes.searchBodies("#" + modelData.replace(/^#/, "")); }
                            }
                        }
                    }

                    // Templates (Obsidian's core Templates plugin): pick one,
                    // then make a note whose body is already filled in.
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        Repeater {
                            model: Services.QuickNotes.templates()
                            Choice {
                                required property string modelData
                                text: modelData
                                selected: win.selectedTemplate === modelData
                                onClicked: win.selectedTemplate = modelData
                                Accessible.name: Tr.t("Template %1").arg(modelData)
                            }
                        }
                    }
                    Button {
                        Layout.fillWidth: true
                        text: win.selectedTemplate === "" ? Tr.t("Pick a template…")
                                                          : Tr.t("New from %1 template").arg(win.selectedTemplate)
                        enabled: win.selectedTemplate !== ""
                        onClicked: win.newFromTemplate()
                    }

                    // Tag management: add one to the open note, or remove the
                    // tag selected in the chips above.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        TextField {
                            id: tagField
                            Layout.fillWidth: true
                            placeholder: Tr.t("Add a #tag")
                            onAccepted: win.addTagFromField()
                        }
                        Button { text: Tr.t("Add tag"); enabled: tagField.text !== ""; onClicked: win.addTagFromField() }
                        IconButton {
                            size: Theme.touchTarget
                            icon: "list-remove"
                            tip: win.tagFilter === "" ? Tr.t("Select a tag above to remove it")
                                                      : Tr.t("Remove tag %1").arg(win.tagFilter)
                            enabled: win.tagFilter !== ""
                            onClicked: win.removeSelectedTag()
                        }
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

                // The title stays visible while formatting actions scroll.
                TextField {
                    id: titleField
                    Layout.fillWidth: true
                    Layout.margins: Theme.px(8)
                    placeholderText: Tr.t("No note selected")
                    label: Tr.t("Note title")
                    text: Services.QuickNotes.current
                    enabled: Services.QuickNotes.current !== ""
                    onAccepted: win.renameCurrent(text)
                    Connections {
                        target: Services.QuickNotes
                        function onCurrentChanged() { titleField.text = Services.QuickNotes.current; }
                    }
                }
                ActionStrip {
                    id: formatBar
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.space(2)
                    Layout.rightMargin: Theme.space(2)
                    spacing: Theme.space(1)
                    Button { text: "B"; enabled: editor.enabled; onClicked: win.wrapSelection("**", "**") }
                    Button { text: "I"; enabled: editor.enabled; onClicked: win.wrapSelection("*", "*") }
                    Button { text: "H"; enabled: editor.enabled; onClicked: win.prefixLine("# ") }
                    Button { text: Tr.t("Link"); enabled: editor.enabled; onClicked: win.wrapSelection("[", "](https://)") }
                    Button { text: Tr.t("Code"); enabled: editor.enabled; onClicked: win.wrapSelection("`", "`") }
                    Button { text: Tr.t("Checklist"); enabled: Services.QuickNotes.current !== "" && editor.enabled; onClicked: win.insertChecklist() }
                    Button { text: Tr.t("Earlier versions"); enabled: Services.QuickNotes.current !== ""; onClicked: win.openHistory() }
                    Button { text: Tr.t("Trash…"); enabled: true; onClicked: { win.showTrash = !win.showTrash; Services.QuickNotes.trashList.running = true; } }
                    Button { text: Tr.t("Attach…"); enabled: Services.QuickNotes.current !== "" && editor.enabled; onClicked: Services.QuickNotes.attachFile() }
                    Button {
                        text: Services.QuickNotes.locked
                              ? (Services.QuickNotes.unlocked ? Tr.t("Locked") : Tr.t("Unlock…"))
                              : Tr.t("Lock…")
                        enabled: Services.QuickNotes.current !== ""
                        onClicked: {
                            if (Services.QuickNotes.locked && Services.QuickNotes.unlocked)
                                return;
                            win.lockPass = "";
                            win.lockMode = Services.QuickNotes.locked ? "check" : "set";
                            lockField.forceActiveFocus();
                        }
                    }
                    Button { text: Tr.t("Export HTML"); enabled: Services.QuickNotes.current !== "" && (!Services.QuickNotes.locked || Services.QuickNotes.unlocked); onClicked: Services.QuickNotes.exportHtml() }
                    Button { text: Tr.t("Print"); enabled: Services.QuickNotes.current !== "" && (!Services.QuickNotes.locked || Services.QuickNotes.unlocked); onClicked: Services.QuickNotes.printNote() }
                    // the note is a file on disk: ask before it goes
                    ConfirmButton {
                        id: deleteNoteConfirm
                        implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                        implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                        text: Tr.t("Delete")
                        armedText: Tr.t("Tap again to delete")
                        kind: "danger"
                        interval: 4000
                        enabled: Services.QuickNotes.current !== ""
                        onConfirmed: Services.QuickNotes.remove(Services.QuickNotes.current, Services.QuickNotes.currentNotebook)
                    }
                }

                // Knowledge-base actions get their own row: reading view,
                // pin, links, versions, moving and both export formats.
                ActionStrip {
                    id: actionBar
                    Layout.fillWidth: true
                    spacing: Theme.space(1)
                    Layout.leftMargin: Theme.space(2)
                    Layout.rightMargin: Theme.space(2)
                    Button {
                        text: win.previewMode ? Tr.t("Edit") : Tr.t("Preview")
                        enabled: Services.QuickNotes.current !== ""
                        Accessible.name: win.previewMode ? Tr.t("Switch to raw Markdown") : Tr.t("Switch to rendered preview")
                        onClicked: win.previewMode = !win.previewMode
                    }
                    Button {
                        text: Services.QuickNotes.isPinned(win.currentId) ? Tr.t("Unpin") : Tr.t("Pin")
                        enabled: Services.QuickNotes.current !== ""
                        Accessible.name: Services.QuickNotes.isPinned(win.currentId) ? Tr.t("Unpin this note") : Tr.t("Pin this note")
                        onClicked: {
                            Services.QuickNotes.togglePin(win.currentId);
                            win.statusText = Services.QuickNotes.isPinned(win.currentId) ? Tr.t("Note pinned") : Tr.t("Note unpinned");
                        }
                    }
                    Button {
                        text: Tr.t("Backlinks")
                        enabled: Services.QuickNotes.current !== ""
                        onClicked: { win.showBacklinks = !win.showBacklinks; if (win.showBacklinks) Services.QuickNotes.updateBacklinks(); }
                    }
                    Button {
                        text: Tr.t("Move…")
                        enabled: Services.QuickNotes.current !== ""
                        onClicked: win.showMove = !win.showMove
                    }
                    Button { text: Tr.t("Export MD"); enabled: Services.QuickNotes.current !== ""; onClicked: Services.QuickNotes.exportMarkdownDialog() }
                    Button { text: Tr.t("Present note"); enabled: Services.QuickNotes.current !== ""; onClicked: win.presentNote() }
                }

                // One line of feedback for pin/tag/export actions and gpg
                // errors: the rest of the window never has to guess why.
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(8)
                    visible: win.statusText !== "" || Services.QuickNotes.lockError !== ""
                    text: Services.QuickNotes.lockError !== "" ? Services.QuickNotes.lockError : win.statusText
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StatusBar
                }

                // With no note open the editor would swallow typing and the
                // save timer would drop it: say so, and offer the way out.
                EmptyState {
                    visible: Services.QuickNotes.current === ""
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    icon: "text-x-generic"
                    title: Tr.t("No note selected")
                    subtitle: Tr.t("Pick a note on the left, or start a new one")
                    actionText: Tr.t("New note")
                    onAction: Services.QuickNotes.create(Tr.t("Untitled"), win.selectedNotebook)
                }

                // An outside editor changed the file: autosave is stopped until
                // the person picks a side, so their edits are never overwritten.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(8)
                    Layout.rightMargin: Theme.px(8)
                    visible: Services.QuickNotes.diskChanged
                    implicitHeight: conflictRow.implicitHeight + Theme.px(12)
                    color: Theme.surface1
                    radius: Theme.radiusSmall
                    RowLayout {
                        id: conflictRow
                        anchors { fill: parent; margins: Theme.px(6) }
                        spacing: Theme.px(6)
                        Text {
                            Layout.fillWidth: true
                            text: Tr.t("This note changed on disk while you were editing. Reload to use the disk version, or Discard to keep your edits.")
                            color: Theme.text
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: Theme.type("small")
                        }
                        Button { text: Tr.t("Reload"); onClicked: Services.QuickNotes.reloadFromDisk() }
                        Button { text: Tr.t("Discard"); onClicked: Services.QuickNotes.discardExternalChange() }
                    }
                }

                // A locked note asks for its passphrase before the body appears.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(8)
                    Layout.rightMargin: Theme.px(8)
                    visible: (Services.QuickNotes.locked && !Services.QuickNotes.unlocked) || win.lockMode === "set"
                    implicitHeight: lockRow.implicitHeight + Theme.px(12)
                    color: Theme.surface1
                    radius: Theme.radiusSmall
                    RowLayout {
                        id: lockRow
                        anchors { fill: parent; margins: Theme.px(6) }
                        spacing: Theme.px(6)
                        TextField {
                            id: lockField
                            Layout.fillWidth: true
                            secret: true
                            placeholderText: win.lockMode === "set" ? Tr.t("Choose a passphrase") : Tr.t("Passphrase for this note")
                            text: win.lockPass
                            onTextChanged: win.lockPass = text
                            onAccepted: win.submitLock()
                            error: Services.QuickNotes.lockError
                        }
                        Button {
                            text: win.lockMode === "set" ? Tr.t("Lock it") : Tr.t("Unlock")
                            kind: "primary"
                            enabled: win.lockPass !== ""
                            onClicked: win.submitLock()
                        }
                        Button {
                            text: Tr.t("Cancel")
                            visible: win.lockMode === "set"
                            onClicked: { win.lockMode = ""; win.lockPass = ""; }
                        }
                    }
                }

                // Text editor
                ScrollView {
                    visible: Services.QuickNotes.current !== "" && !win.previewMode
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextArea {
                        id: editor
                        enabled: Services.QuickNotes.current !== "" && (!Services.QuickNotes.locked || Services.QuickNotes.unlocked)
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
                        font.pixelSize: Theme.type("body")
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

                // Reading view: Obsidian's Ctrl+E reading/raw toggle. The
                // parser only produces wiki:/http(s): link targets, and the
                // view draws everything as PlainText, so markup in a note
                // cannot become markup in the shell.
                ScrollView {
                    visible: win.previewMode && Services.QuickNotes.current !== ""
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    NotesMarkdown {
                        width: parent ? parent.width : 0
                        markdown: Services.QuickNotes.text
                        Accessible.role: Accessible.Document
                        Accessible.name: Tr.t("Preview of %1").arg(Services.QuickNotes.current)
                        onWikiLink: name => Services.QuickNotes.jumpTo(name)
                        onWebLink: url => Quickshell.execDetached(["xdg-open", url])
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
                            Accessible.name: Tr.t("Follow the link %1").arg(modelData)
                            // a date goes to Calendar, a contact name to the
                            // address book, everything else is a note link
                            onClicked: win.followWikiLink(modelData)
                        }
                    }
                }

                // due dates on open tasks, and a field to add one to this line
                RowLayout {
                    Layout.fillWidth: true
                    visible: Services.QuickNotes.dueDates().length > 0
                    spacing: Theme.px(4)
                    Repeater {
                        model: Services.QuickNotes.dueDates()
                        Choice {
                            required property var modelData
                            text: modelData.due + "  " + modelData.text
                            selected: false
                            onClicked: { editor.cursorPosition = Services.QuickNotes.posForLine ? Services.QuickNotes.posForLine(modelData.line) : editor.cursorPosition; }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    TextField {
                        id: dueField
                        Layout.fillWidth: true
                        placeholder: "Due date YYYY-MM-DD on this task"
                        onAccepted: win.addDue(text)
                    }
                    Button { text: Tr.t("Set due"); enabled: dueField.text !== ""; onClicked: win.addDue(dueField.text) }
                }

                // version history and trash are small collapsible drawers
                Rectangle {
                    visible: win.showHistory
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(180)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    ColumnLayout {
                        anchors { fill: parent; margins: Theme.px(4) }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: Tr.t("Earlier versions"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                            Button { text: Tr.t("Previous"); enabled: win.historyIndex > 0; onClicked: win.stepVersion(-1) }
                            Button { text: Tr.t("Next"); enabled: win.historyIndex >= 0 && win.historyIndex < Services.QuickNotes.historyList.length - 1; onClicked: win.stepVersion(1) }
                            Button {
                                text: Tr.t("Restore this version")
                                enabled: win.historyIndex >= 0
                                onClicked: {
                                    Services.QuickNotes.restoreVersion(Services.QuickNotes.historyList[win.historyIndex]);
                                    win.showHistory = false;
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Services.QuickNotes.versionPreview
                            color: Theme.dim
                            font.family: Theme.mono
                            font.pixelSize: Theme.px(10)
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            Accessible.name: Tr.t("Version preview")
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: Services.QuickNotes.historyList
                            delegate: ItemDelegate {
                                required property string modelData
                                width: ListView.view.width
                                implicitHeight: Theme.touchTarget
                                text: modelData.split("/").pop()
                                Accessible.name: Tr.t("Version %1").arg(modelData.split("/").pop())
                                onClicked: { win.historyIndex = index; Services.QuickNotes.previewVersion(modelData); }
                            }
                        }
                        EmptyState {
                            visible: Services.QuickNotes.historyList.length === 0
                            Layout.fillWidth: true
                            icon: "document-open-recent"
                            title: Tr.t("No earlier versions yet")
                            subtitle: Tr.t("A copy is kept each time the note is saved")
                        }
                    }
                }

                // Obsidian's backlinks pane: notes that point here via [[...]].
                Rectangle {
                    visible: win.showBacklinks
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(120)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    ColumnLayout {
                        anchors { fill: parent; margins: Theme.px(4) }
                        Text { text: Tr.t("Notes linking here"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: Services.QuickNotes.backlinkResults
                            delegate: ItemDelegate {
                                required property string modelData
                                width: ListView.view.width
                                implicitHeight: Theme.touchTarget
                                text: modelData
                                Accessible.name: Tr.t("Backlink from %1").arg(modelData)
                                onClicked: Services.QuickNotes.open(modelData)
                            }
                        }
                        EmptyState {
                            visible: Services.QuickNotes.backlinkResults.length === 0
                            Layout.fillWidth: true
                            icon: "edit-find"
                            title: Tr.t("No notes link here yet")
                            subtitle: Tr.t("Write [[%1]] in another note").arg(Services.QuickNotes.current)
                        }
                    }
                }

                // Move/copy between notebooks (folders), without a file manager.
                Rectangle {
                    visible: win.showMove
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(90)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    ColumnLayout {
                        anchors { fill: parent; margins: Theme.px(4) }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.px(4)
                            Choice {
                                text: Tr.t("Top level")
                                selected: win.targetNotebook === ""
                                onClicked: win.targetNotebook = ""
                            }
                            Repeater {
                                model: Services.QuickNotes.notebooks
                                Choice {
                                    required property string modelData
                                    text: modelData
                                    selected: win.targetNotebook === modelData
                                    onClicked: win.targetNotebook = modelData
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                text: Tr.t("Move here")
                                enabled: win.targetNotebook !== Services.QuickNotes.currentNotebook
                                onClicked: {
                                    if (Services.QuickNotes.moveToNotebook(Services.QuickNotes.current, Services.QuickNotes.currentNotebook, win.targetNotebook))
                                        win.statusText = Tr.t("Note moved");
                                    else
                                        win.statusText = Tr.t("Move refused — a note with that name is already there");
                                    win.showMove = false;
                                }
                            }
                            Button {
                                text: Tr.t("Copy here")
                                onClicked: {
                                    if (Services.QuickNotes.copyToNotebook(Services.QuickNotes.current, Services.QuickNotes.currentNotebook, win.targetNotebook))
                                        win.statusText = Tr.t("Note copied");
                                    else
                                        win.statusText = Tr.t("Copy refused — a note with that name is already there");
                                    win.showMove = false;
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    visible: win.showTrash
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(120)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    ColumnLayout {
                        anchors { fill: parent; margins: Theme.px(4) }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: Tr.t("Trash"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                            Button {
                                text: Tr.t("Empty the trash")
                                flat: true
                                enabled: Services.QuickNotes.trashed.length > 0
                                Accessible.name: Tr.t("Permanently delete every trashed note")
                                onClicked: Services.QuickNotes.emptyTrash()
                            }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: Services.QuickNotes.trashed
                            delegate: ItemDelegate {
                                required property string modelData
                                width: ListView.view.width
                                implicitHeight: Theme.touchTarget
                                text: modelData
                                Accessible.name: Tr.t("Restore note %1").arg(modelData)
                                onClicked: { Services.QuickNotes.restore(modelData); win.showTrash = false; }
                            }
                        }
                    }
                }
            }
        }
    }

    // Escape / Ctrl+W come from AppWindow and go through requestClose()

    /// Wrap the selection in a Markdown marker, keeping the selection after it.
    function wrapSelection(prefix, suffix) {
        const t = editor.text;
        const a = editor.selectionStart, b = editor.selectionEnd;
        const mid = t.slice(a, b);
        Services.QuickNotes.set(t.slice(0, a) + prefix + mid + suffix + t.slice(b));
        editor.select(a + prefix.length, a + prefix.length + mid.length);
        editor.forceActiveFocus();
    }
    /// Turn the current line into a heading.
    function prefixLine(prefix) {
        const t = editor.text;
        const a = t.lastIndexOf("\n", editor.cursorPosition - 1) + 1;
        Services.QuickNotes.set(t.slice(0, a) + prefix + t.slice(a));
        editor.cursorPosition = editor.cursorPosition + prefix.length;
        editor.forceActiveFocus();
    }
    function openHistory() {
        win.showHistory = !win.showHistory;
        if (win.showHistory) Services.QuickNotes.history(Services.QuickNotes.noteId(Services.QuickNotes.current, Services.QuickNotes.currentNotebook));
    }
    /// Send the open note to the Teleprompter through the clipboard.
    function presentNote() {
        if (Services.QuickNotes.current === "") return;
        Quickshell.clipboardText = Services.QuickNotes.text;
        Ui.teleprompter = true;
    }
    /// Adds (or clears) @due(YYYY-MM-DD) on the task line the cursor is on.
    function addDue(date) {
        const before = editor.text.slice(0, editor.cursorPosition);
        const line = before.split("\n").length - 1;
        if (!Services.QuickNotes.setDueDate(line, String(date || "").trim())) return false;
        dueField.text = "";
        editor.forceActiveFocus();
        return true;
    }

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
        const lineIndex = text.slice(0, start).split("\n").length - 1;
        if (!Services.QuickNotes.toggleChecklistItem(lineIndex)) return false;
        editor.cursorPosition = index;
        return true;
    }

    /// Put a fresh checklist box at the cursor (the service keeps the text).
    function insertChecklist() {
        editor.cursorPosition = Services.QuickNotes.insertChecklistItem(editor.cursorPosition);
        editor.forceActiveFocus();
    }

    /// Lock the open note with the typed passphrase, or open a locked one.
    function submitLock() {
        if (win.lockPass === "")
            return;
        if (win.lockMode === "set")
            Services.QuickNotes.lockNote(win.lockPass);
        else
            Services.QuickNotes.unlockNote(win.lockPass);
        win.lockPass = "";
        win.lockMode = "";
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

    /// Rename the open note; the title field shows the real name again even
    /// when the service refuses a duplicate or an empty one.
    function renameCurrent(name) {
        const old = Services.QuickNotes.current;
        const n = String(name || "").trim();
        if (old !== "" && n !== "" && n !== old)
            Services.QuickNotes.rename(old, n, Services.QuickNotes.currentNotebook);
        titleField.text = Services.QuickNotes.current;
    }

    /// Step through the visible note list without leaving the keyboard.
    function stepNote(delta) {
        const m = noteList.model;
        if (!m || m.length === 0) return false;
        let i = 0;
        while (i < m.length && m[i].id !== win.currentId) i++;
        const at = Math.max(0, Math.min(m.length - 1, (i >= m.length ? 0 : i) + delta));
        const n = m[at];
        if (!n) return false;
        const slash = n.id.indexOf("/");
        if (slash >= 0) Services.QuickNotes.open(n.id.slice(slash + 1), n.id.slice(0, slash));
        else Services.QuickNotes.open(n.name, "");
        return true;
    }
    /// Walk the dated versions after reading one; restore is a separate act.
    function stepVersion(delta) {
        const h = Services.QuickNotes.historyList;
        if (!h.length) return false;
        win.historyIndex = Math.max(0, Math.min(h.length - 1, win.historyIndex + delta));
        Services.QuickNotes.previewVersion(h[win.historyIndex]);
        return true;
    }
    function newFromTemplate() {
        if (win.selectedTemplate === "") return false;
        const ok = Services.QuickNotes.createFromTemplate(win.selectedTemplate, Tr.t("Untitled"), win.selectedNotebook);
        win.statusText = ok ? Tr.t("Created from %1 template").arg(win.selectedTemplate)
                            : Tr.t("A note with that name already exists");
        return ok;
    }
    function addTagFromField() {
        if (!Services.QuickNotes.addTag(tagField.text)) {
            win.statusText = Tr.t("Use a tag of letters, numbers, - or _");
            return false;
        }
        tagField.text = "";
        win.statusText = "";
        return true;
    }
    function removeSelectedTag() {
        if (win.tagFilter === "") return false;
        const ok = Services.QuickNotes.removeTag(win.tagFilter);
        win.statusText = ok ? Tr.t("Removed tag %1").arg(win.tagFilter)
                            : Tr.t("That tag is not in this note");
        return ok;
    }

    /// Resolve [[2026-11-25]] to a Calendar day and [[Ada Lovelace]] to a
    /// contact; anything else stays an ordinary wiki link to a note.
    function wikiLinkTarget(name) {
        const raw = String(name || "").trim();
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
        if (m) {
            const y = Number(m[1]), mo = Number(m[2]) - 1, d = Number(m[3]);
            const day = new Date(y, mo, d);
            if (day.getFullYear() === y && day.getMonth() === mo && day.getDate() === d)
                return { kind: "date", label: raw, when: day.getTime() };
        }
        const needle = raw.toLowerCase();
        const c = Services.Contacts.contacts.find(x => String(x.name || "").trim().toLowerCase() === needle);
        if (c) return { kind: "contact", label: c.name, uid: c.uid };
        return { kind: "note", label: raw };
    }
    function followWikiLink(name) {
        const target = win.wikiLinkTarget(name);
        if (target.kind === "date") {
            Services.Agenda.openCalendar();
            Services.Agenda.showDay(target.when);
            return;
        }
        if (target.kind === "contact") {
            const c = Services.Contacts.contacts.find(x => x.uid === target.uid);
            if (c) {
                Services.Contacts.selected = null;
                Ui.openContacts();
                Services.Contacts.selected = c;
                return;
            }
        }
        Services.QuickNotes.jumpTo(name);
    }

    Shortcut { sequence: "Ctrl+N"; onActivated: Services.QuickNotes.create(Tr.t("Untitled"), win.selectedNotebook) }
    Shortcut { sequence: "Ctrl+F"; onActivated: filterField.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+E"; onActivated: win.previewMode = !win.previewMode }
    Shortcut { sequence: "Ctrl+B"; onActivated: win.wrapSelection("**", "**") }
    Shortcut { sequence: "Ctrl+I"; onActivated: win.wrapSelection("*", "*") }
    Shortcut { sequence: "Ctrl+K"; onActivated: win.wrapSelection("[[", "]]") }
    Shortcut { sequence: "Ctrl+Shift+P"; onActivated: Services.QuickNotes.togglePin(win.currentId) }
    Shortcut { sequence: "Ctrl+Shift+F"; onActivated: bodyField.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: tagField.forceActiveFocus() }
    Shortcut { sequence: "Alt+Down"; onActivated: win.stepNote(1) }
    Shortcut { sequence: "Alt+Up"; onActivated: win.stepNote(-1) }
}
