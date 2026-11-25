// The control centre's notes — a folder of Markdown notes
// (QuickNotes: ~/Documents/Notes/, one .md per note, grouped into
// notebooks as subfolders). Make a note, search them, rename or delete
// one, and follow [[wiki links]] from one to another; everything
// autosaves. Export the current note as HTML and print it via lp.
// Sync is a TODO (marked in the UI, never faked).
// Readable by Chronoa too: each note is a plain .md file.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import Quickshell.Bluetooth
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Notifications

ColumnLayout {
    id: root
    spacing: Theme.px(10)
    property string query: ""
    property string newName: ""
    property string renameName: ""
    property bool renaming: false
    property bool nbNewVisible: false
    property bool nbRenaming: false
    readonly property var shown: {
        const ids = new Set(QuickNotes.search(query).map(n => n.id || n.name).concat(QuickNotes.contentHits));
        let all = QuickNotes.notes.filter(n => ids.has(n.id || n.name) || ids.has(n.name));
        if (Ui.notesNotebook !== "")
            all = all.filter(n => (n.notebook || "") === Ui.notesNotebook);
        return all;
    }
    readonly property var links: {
        const out = [];
        const re = /\[\[([^\[\]]+)\]\]/g;
        let m;
        while ((m = re.exec(QuickNotes.text || "")) !== null) {
            const n = m[1].trim();
            if (n !== "" && out.indexOf(n) < 0)
                out.push(n);
        }
        return out;
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(8)
        SectionTitle { Layout.fillWidth: true; text: Tr.t("Notes") }
        IconButton {
            icon: "document-new"
            size: Theme.px(28)
            tip: Tr.t("New note")
            onClicked: { root.query = ""; root.newName = ""; newRow.visible = true; newField.text = ""; Qt.callLater(function() { newField.forceActiveFocus(Qt.MouseFocusReason); }); }
        }
        IconButton {
            icon: "accessories-text-editor"
            size: Theme.px(28)
            tip: Tr.t("Open in Notes")
            onClicked: Ui.openNotes()
        }
    }

    // the new note's name, typed then made with Enter
    RowLayout {
        id: newRow
        Layout.fillWidth: true
        spacing: Theme.px(6)
        visible: false
        TextField {
            id: newField
            Layout.fillWidth: true
            placeholder: Tr.t("Note name — Enter makes it")
            label: Tr.t("New note name")
            onAccepted: { QuickNotes.create(text, Ui.notesNotebook || QuickNotes.currentNotebook); text = ""; newRow.visible = false; }
        }
        IconButton { icon: "window-close"; size: Theme.px(28); tip: Tr.t("Cancel"); onClicked: newRow.visible = false }
    }

    // ---- notebooks (subfolders of Documents/Notes) ------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Text { text: Tr.t("Notebook"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
        Choice { text: Tr.t("All"); selected: Ui.notesNotebook === ""; onClicked: Ui.notesNotebook = "" }
        Repeater {
            model: QuickNotes.notebooks
            Choice {
                required property string modelData
                text: modelData
                selected: Ui.notesNotebook === modelData
                onClicked: Ui.notesNotebook = modelData
            }
        }
        IconButton {
            icon: "folder-open"
            size: Theme.px(26)
            tip: Tr.t("New notebook")
            onClicked: { nbNewField.text = ""; root.nbNewVisible = !root.nbNewVisible; Qt.callLater(function() { nbNewField.forceActiveFocus(Qt.MouseFocusReason); }); }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        visible: root.nbNewVisible
        TextField {
            id: nbNewField
            Layout.fillWidth: true
            placeholder: Tr.t("Notebook name — Enter makes it")
            label: Tr.t("New notebook name")
            onAccepted: { QuickNotes.createNotebook(text); text = ""; root.nbNewVisible = false; }
        }
        IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Cancel"); onClicked: root.nbNewVisible = false }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        visible: (Ui.notesNotebook !== "" || QuickNotes.currentNotebook !== "") && !root.nbRenaming
        Button { text: Tr.t("Rename notebook"); kind: "plain"; onClicked: { nbRenameField.text = Ui.notesNotebook || QuickNotes.currentNotebook; root.nbRenaming = true; Qt.callLater(function() { nbRenameField.forceActiveFocus(Qt.MouseFocusReason); }); } }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        visible: root.nbRenaming
        TextField {
            id: nbRenameField
            Layout.fillWidth: true
            placeholder: Tr.t("Rename notebook to…")
            label: Tr.t("Rename notebook to")
            onAccepted: { QuickNotes.renameNotebook(Ui.notesNotebook || QuickNotes.currentNotebook, text); if (text.trim() !== "") Ui.notesNotebook = QuickNotes.validNotebook(text); root.nbRenaming = false; }
        }
        IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Cancel"); onClicked: root.nbRenaming = false }
    }

    TextField {
        Layout.fillWidth: true
        placeholder: Tr.t("Search notes…")
        label: Tr.t("Search notes")
        onTextChanged: { root.query = text; QuickNotes.searchBodies(text); }
    }

    // the notes, Click to open one
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: root.shown.length > 0
        Repeater {
            model: root.shown
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "accessories-text-editor"
                title: modelData.name
                subtitle: ((modelData.notebook || "") !== "" ? (modelData.notebook + " · ") : "") + QuickNotes.preview(modelData.name, modelData.notebook)
                selected: modelData.name === QuickNotes.current && (modelData.notebook || "") === QuickNotes.currentNotebook
                onClicked: QuickNotes.open(modelData.name, modelData.notebook)
            }
        }
    }
    EmptyState {
        visible: root.shown.length === 0 && QuickNotes.loaded
        icon: "accessories-text-editor"
        title: Tr.t("No notes yet")
        subtitle: Tr.t("Your notes are Markdown files in Documents/Notes")
        actionText: Tr.t("New note")
        onAction: QuickNotes.create("Untitled", "")
    }

    // the open note
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                text: (QuickNotes.currentNotebook !== "" ? (QuickNotes.currentNotebook + "/") : "") + (QuickNotes.current || Tr.t("Choose a note"))
                color: Theme.text
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            IconButton {
                icon: "document-properties"
                size: Theme.px(26)
                tip: Tr.t("Rename this note")
                onClicked: { root.renameName = QuickNotes.current; root.renaming = true; renameField.text = QuickNotes.current; Qt.callLater(function() { renameField.forceActiveFocus(Qt.MouseFocusReason); }); }
            }
            ConfirmButton {
                id: deleteNoteConfirm
                icon: "edit-delete"
                size: Theme.px(26)
                tip: Tr.t("Delete this note")
                armedText: Tr.t("Tap again to delete")
                interval: 4000
                enabled: QuickNotes.current !== ""
                onConfirmed: { if (QuickNotes.current !== "") QuickNotes.remove(QuickNotes.current, QuickNotes.currentNotebook); }
            }
            Connections {
                target: QuickNotes
                function onCurrentChanged() { deleteNoteConfirm.disarm(); }
                function onCurrentNotebookChanged() { deleteNoteConfirm.disarm(); }
            }
            IconButton {
                icon: "document-save"
                size: Theme.px(26)
                tip: Tr.t("Export this note as HTML")
                onClicked: QuickNotes.exportHtml()
            }
            IconButton {
                icon: "printer"
                size: Theme.px(26)
                tip: Tr.t("Print this note (lp)")
                onClicked: QuickNotes.printNote()
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            visible: QuickNotes.lastExported !== ""
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: QuickNotes.lastExported
                color: Theme.faint
                font.family: Theme.mono
                font.pixelSize: Theme.px(10) * Theme.fontScale
                elide: Text.ElideLeft
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            visible: QuickNotes.lastPrinted !== ""
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: Tr.t("Printed:") + " " + QuickNotes.lastPrinted
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                elide: Text.ElideLeft
            }
        }
        RowLayout {
            id: renameRow
            Layout.fillWidth: true
            spacing: Theme.px(6)
            visible: root.renaming
            TextField {
                id: renameField
                Layout.fillWidth: true
                placeholder: Tr.t("Rename to…")
                label: Tr.t("Rename note to")
                onAccepted: { QuickNotes.rename(QuickNotes.current, text, QuickNotes.currentNotebook); root.renaming = false; }
            }
            IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Cancel"); onClicked: { root.renaming = false; } }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(64, notes.contentHeight + 20)
            radius: Theme.radiusSmall
            color: Theme.surface1
            border.width: notes.activeFocus ? 1 : 0
            border.color: Theme.accentLine
            TextEdit {
                id: notes
                activeFocusOnTab: true          // the d-pad and Tab reach it (a pad's LB / RB leave it: Ui.navJump)
                Keys.onDownPressed: e => e.accepted = Ui.leaveAtEdge(notes, true)
                Keys.onUpPressed: e => e.accepted = Ui.leaveAtEdge(notes, false)
                Keys.onEscapePressed: Ui.closeAll()   // as the panel's own Escape: the edit would keep it
                Accessible.role: Accessible.EditableText
                Accessible.name: Tr.t("Note text")
                anchors.fill: parent
                anchors.margins: Theme.px(10)
                text: QuickNotes.text
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentInk
                wrapMode: TextEdit.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                onTextChanged: if (activeFocus) QuickNotes.set(text)
                Text {
                    visible: notes.text === ""
                    text: Tr.t("Write here — saved to Documents/Notes as Markdown. [[Like this]] links to another note.")
                    color: Theme.faint
                    font: notes.font
                }
            }
        }
        // [[links]] in this note, Click to jump to them
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            visible: root.links.length > 0
            Text {
                text: Tr.t("Links:")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Repeater {
                    model: root.links
                    Choice {
                        required property string modelData
                        text: "[[" + modelData + "]]"
                        selected: modelData === QuickNotes.current
                        onClicked: QuickNotes.jumpTo(modelData)
                    }
                }
            }
        }
    }

    // ---- notes sync: local-first, mirrored to a chosen cloud folder -------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Sync") }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Tr.t("Notes are kept in Documents/Notes. Choose a mounted cloud folder (Nextcloud, Dropbox, a network drive) to mirror them there. Nothing is deleted from either side.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    FolderPicker {
        Layout.fillWidth: true
        label: Tr.t("Sync folder")
        value: Settings.data.notesSyncPath || ""
        onPicked: path => { Settings.data.notesSyncPath = path; QuickNotes.syncNotes(); }
    }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: QuickNotes.syncState
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
        }
        Button {
            text: Tr.t("Sync now")
            flat: true
            enabled: Settings.data.notesSyncPath !== ""
            onClicked: QuickNotes.syncNotes()
        }
    }
}
