// The control centre's notes — a folder of Markdown notes
// (QuickNotes: ~/Documents/Notes/, one .md per note), after the single
// quick.md. Make a note, search them, rename or delete one, and follow
// [[wiki links]] from one to another; everything autosaves.
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
    spacing: 10
    property string query: ""
    property string newName: ""
    property string renameName: ""
    property bool renaming: false
    readonly property var shown: {
        const names = new Set(QuickNotes.search(query).map(n => n.name).concat(QuickNotes.contentHits));
        return QuickNotes.notes.filter(n => names.has(n.name));
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
        spacing: 8
        SectionTitle { Layout.fillWidth: true; text: Tr.t("Notes") }
        IconButton {
            icon: "document-new"
            size: 28
            tip: Tr.t("New note")
            onClicked: { root.query = ""; root.newName = ""; newRow.visible = true; newField.text = ""; Qt.callLater(function() { newField.forceActiveFocus(Qt.MouseFocusReason); }); }
        }
        IconButton {
            icon: "accessories-text-editor"
            size: 28
            tip: Tr.t("Open this note in the editor")
            onClicked: { Ui.closeAll(); Chronoa.openEditor(QuickNotes.path); }
        }
    }

    // the new note's name, typed then made with Enter
    RowLayout {
        id: newRow
        Layout.fillWidth: true
        spacing: 6
        visible: false
        TextField {
            id: newField
            Layout.fillWidth: true
            placeholder: Tr.t("Note name — Enter makes it")
            label: Tr.t("New note name")
            onAccepted: { QuickNotes.create(text); text = ""; newRow.visible = false; }
        }
        IconButton { icon: "window-close"; size: 28; tip: Tr.t("Cancel"); onClicked: newRow.visible = false }
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
                subtitle: QuickNotes.preview(modelData.name)
                selected: modelData.name === QuickNotes.current
                onClicked: QuickNotes.open(modelData.name)
            }
        }
    }
    EmptyState {
        visible: root.shown.length === 0 && QuickNotes.loaded
        icon: "accessories-text-editor"
        title: Tr.t("No notes yet")
        subtitle: Tr.t("Make one with the + above — each is a Markdown file in Documents/Notes")
    }

    // the open note
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: QuickNotes.current || Tr.t("Choose a note")
                color: Theme.text
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            IconButton {
                icon: "document-properties"
                size: 26
                tip: Tr.t("Rename this note")
                onClicked: { root.renameName = QuickNotes.current; root.renaming = true; renameField.text = QuickNotes.current; Qt.callLater(function() { renameField.forceActiveFocus(Qt.MouseFocusReason); }); }
            }
            IconButton {
                icon: "edit-delete"
                size: 26
                tip: Tr.t("Delete this note")
                onClicked: QuickNotes.remove(QuickNotes.current)
            }
        }
        RowLayout {
            id: renameRow
            Layout.fillWidth: true
            spacing: 6
            visible: root.renaming
            TextField {
                id: renameField
                Layout.fillWidth: true
                placeholder: Tr.t("Rename to…")
                label: Tr.t("Rename note to")
                onAccepted: { QuickNotes.rename(QuickNotes.current, text); root.renaming = false; }
            }
            IconButton { icon: "window-close"; size: 26; tip: Tr.t("Cancel"); onClicked: { root.renaming = false; } }
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
                Accessible.role: Accessible.EditableText
                Accessible.name: Tr.t("Note text")
                anchors.fill: parent
                anchors.margins: 10
                text: QuickNotes.text
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentInk
                wrapMode: TextEdit.Wrap
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
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
            spacing: 6
            visible: root.links.length > 0
            Text {
                text: Tr.t("Links:")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: 4
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
}
