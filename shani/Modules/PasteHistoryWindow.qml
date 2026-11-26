// Paste history: cliphist's last entries as numbered slots, so a number key
// pastes one without lifting a hand from the keyboard. Search is fuzzy (the
// same ranking as the launcher), favourites live in the clipboard pins, and
// the history itself stays in Services/Clipboard. An image entry is only
// offered when wl-paste can actually provide one; otherwise the window says so.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: Tr.t("Paste history")
    visible: Ui.pasteHistory
    onGone: Ui.pasteHistory = false
    implicitWidth: Theme.px(560)
    implicitHeight: Theme.px(680)

    property string search: ""
    property bool favouritesOnly: false
    property string note: ""
    property string imageTypes: ""
    property bool imageSupported: false

    readonly property var entries: Clipboard.entries || []
    readonly property bool hasEntries: win.entries.length > 0
    readonly property var shown: win.visibleEntries()

    Timer { id: noteTimer; interval: 5000; onTriggered: win.note = "" }
    function flash(msg) { win.note = msg; noteTimer.restart(); }

    // ---- slots, search, favourites ---------------------------------------------
    function slotLabel(n) { return Clipboard.slotLabel(n); }
    function pasteNumber(n) {
        if (!Clipboard.pasteSlot(n - 1)) { win.flash(Tr.t("There is no slot %1").arg(n)); return false; }
        win.flash(Tr.t("Pasted slot %1").arg(n));
        return true;
    }
    function pasteEntry(e) {
        if (!e) return false;
        Clipboard.copyAndPaste(e);
        win.flash(Tr.t("Pasted"));
        return true;
    }
    function deleteEntry(e) {
        if (!e) return false;
        Clipboard.remove(e);
        win.flash(Tr.t("Deleted from history"));
        return true;
    }
    function toggleFavourite(e) {
        if (!e) return false;
        const added = Clipboard.toggleFavourite(e.text);
        win.flash(added ? Tr.t("Added to favourites") : Tr.t("Removed from favourites"));
        return added;
    }
    // ---- handing a snippet on ---------------------------------------------------
    // Share and the Editor take a path, so a text entry is written to a small
    // file in the runtime dir; the text also goes on the clipboard as the handoff.
    function snippetPath(e) {
        return (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-snippet-" + e.id + ".txt";
    }
    function saveSnippet(e) {
        if (!e || e.image) return "";
        snippetFile.path = win.snippetPath(e);
        snippetFile.setText(e.text);
        return win.snippetPath(e);
    }
    function sendSnippet(e) {
        if (!e) return false;
        const p = e.image ? e.preview : win.saveSnippet(e);
        if (!p) return false;
        if (!e.image) Quickshell.clipboardText = e.text;
        Ui.pasteHistory = false;
        Ui.closeAll();
        Share.open(p);
        win.flash(Tr.t("Snippet sent to Share"));
        return true;
    }
    function openInEditor(e) {
        if (!e || e.image) return false;
        const p = win.saveSnippet(e);
        if (!p) return false;
        Quickshell.clipboardText = e.text;
        Ui.pasteHistory = false;
        Ui.closeAll();
        Ui.textEditorOpenPath = p;     // TextEditorPanel.take() opens it
        Ui.textEditor = true;
        win.flash(Tr.t("Opened in Editor"));
        return true;
    }
    FileView { id: snippetFile; printErrors: false }
    function visibleEntries() {
        let list = win.entries.slice();
        if (win.favouritesOnly)
            list = list.filter(e => Clipboard.isFavourite(e.text));
        const q = String(win.search || "").trim().toLowerCase();
        if (q)
            list = list.filter(e => Clipboard.fuzzyScore(e.text, q) > 0);
        return list;
    }

    // ---- can wl-paste offer an image here? ------------------------------------
    // A headless session (or one without an image-capable clipboard) has no
    // image/* target: the Insert image control then explains why, rather than
    // pasting nothing and looking broken.
    function checkImages() { imageProbe.running = false; imageProbe.running = true; }
    function insertImage() {
        if (!win.imageSupported) {
            win.flash(Tr.t("Pasting images is not supported here - only text is available"));
            return false;
        }
        win.flash(Tr.t("Use your normal image paste shortcut; images do not have a number"));
        return true;
    }
    Process {
        id: imageProbe
        command: Clipboard.imageTypesCommand()
        stdout: StdioCollector {
            onStreamFinished: {
                win.imageTypes = text;
                win.imageSupported = /image\//i.test(text);
            }
        }
        stderr: StdioCollector { }
        onExited: code => { if (code !== 0) win.imageSupported = false; }
    }
    Component.onCompleted: win.checkImages()

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { win.visible = false; Ui.pasteHistory = false; }
        // paste-by-number: 1..9, but never while typing a search
        Keys.onPressed: e => {
            if (searchField.activeFocus) return;
            if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                win.pasteNumber(e.key - Qt.Key_0);
                e.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(8)

            SectionTitle { Layout.fillWidth: true; text: Tr.t("Clipboard history") }
            TextField {
                id: searchField
                objectName: "paste-search"
                Layout.fillWidth: true
                label: Tr.t("Fuzzy search the clipboard")
                placeholder: Tr.t("Type a few letters to find an entry")
                text: win.search
                onTextChanged: win.search = text
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Choice {
                    objectName: "paste-favourites"
                    text: Tr.t("Favourites only")
                    selected: win.favouritesOnly
                    onClicked: win.favouritesOnly = !win.favouritesOnly
                    KeyFocus { name: parent.Accessible.name; onActivated: win.favouritesOnly = !win.favouritesOnly }
                }
                Button {
                    text: Tr.t("Insert image")
                    onClicked: win.insertImage()
                    Accessible.name: Tr.t("Insert image")
                    KeyFocus { name: parent.Accessible.name; onActivated: win.insertImage() }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: win.note !== ""
                text: win.note
                color: Theme.accent; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.type("small")
                Accessible.role: Accessible.StaticText; Accessible.name: win.note
            }
            Text {
                Layout.fillWidth: true
                visible: !Clipboard.available
                text: Tr.t("Clipboard history is not available")
                color: Theme.danger; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.type("small")
                Accessible.role: Accessible.StaticText; Accessible.name: text
            }

            ListView {
                id: slotList
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                spacing: Theme.px(4)
                model: win.shown
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    objectName: "paste-slot-" + (slotList.index + 1)
                    width: slotList.width; height: Theme.px(60); radius: Theme.radiusSmall
                    color: Theme.surface1
                    Accessible.role: Accessible.ListItem
                    Accessible.name: Tr.t("Slot %1").arg(slotList.index + 1) + ", "
                        + (row.modelData.image ? Tr.t("Image") : row.modelData.text)
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(6) }
                        spacing: Theme.px(8)
                        Rectangle {
                            Layout.preferredWidth: Theme.px(26); Layout.preferredHeight: Theme.px(26)
                            radius: Theme.px(6); color: Theme.accentSoft
                            Text { anchors.centerIn: parent; text: win.slotLabel(slotList.index); color: Theme.accentInk
                                   font.family: Theme.mono; font.pixelSize: Theme.type("body") }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text {
                                Layout.fillWidth: true; text: row.modelData.image ? Tr.t("Image") : row.modelData.text
                                color: Theme.text; elide: Text.ElideRight; maximumLineCount: 1
                                font.family: row.modelData.image ? Theme.font : Theme.mono
                                font.pixelSize: Theme.type("body")
                            }
                            Text {
                                Layout.fillWidth: true; visible: row.modelData.image
                                text: row.modelData.preview || Tr.t("No preview")
                                color: Theme.faint; elide: Text.ElideMiddle
                                font.family: Theme.font; font.pixelSize: Theme.type("caption")
                            }
                        }
                        IconButton {
                            icon: "folder-publicshare"
                            size: Theme.px(24)
                            tip: Tr.t("Send this snippet")
                            accessibleName: tip
                            onClicked: win.sendSnippet(row.modelData)
                            KeyFocus { name: parent.Accessible.name; onActivated: win.sendSnippet(row.modelData) }
                        }
                        IconButton {
                            visible: !row.modelData.image
                            icon: "accessories-text-editor"
                            size: Theme.px(24)
                            tip: Tr.t("Open in Editor")
                            accessibleName: tip
                            onClicked: win.openInEditor(row.modelData)
                            KeyFocus { name: parent.Accessible.name; onActivated: win.openInEditor(row.modelData) }
                        }
                        IconButton {
                            id: fav
                            icon: Clipboard.isFavourite(row.modelData.text) ? "star" : "star-outline"
                            size: Theme.px(24)
                            tip: Clipboard.isFavourite(row.modelData.text) ? Tr.t("Remove favourite") : Tr.t("Add favourite")
                            accessibleName: tip
                            onClicked: win.toggleFavourite(row.modelData)
                            KeyFocus { name: parent.Accessible.name; onActivated: win.toggleFavourite(row.modelData) }
                        }
                        IconButton {
                            icon: "edit-delete"
                            size: Theme.px(24)
                            tip: Tr.t("Delete")
                            accessibleName: Tr.t("Delete slot %1").arg(slotList.index + 1)
                            onClicked: win.deleteEntry(row.modelData)
                            KeyFocus { name: parent.Accessible.name; onActivated: win.deleteEntry(row.modelData) }
                        }
                    }
                    // click a row to paste it; its name includes the slot number
                    KeyFocus { name: row.Accessible.name; onActivated: win.pasteEntry(row.modelData) }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: !win.hasEntries && Clipboard.available
                    icon: "edit-paste"
                    title: Tr.t("Clipboard is empty")
                    subtitle: Tr.t("Copied text and images appear here")
                }
                Text {
                    anchors.centerIn: parent
                    visible: win.hasEntries && win.shown.length === 0
                    text: win.favouritesOnly ? Tr.t("No favourite entries") : Tr.t("No matching entries")
                    color: Theme.dim
                    font.family: Theme.font; font.pixelSize: Theme.type("body")
                }
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Press 1-9 to paste a slot, Enter to paste the selected one")
                color: Theme.faint; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.type("caption")
            }
        }
    }
}
