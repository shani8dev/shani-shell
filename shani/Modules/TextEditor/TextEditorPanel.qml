// Text Editor: plain text over files, in a window of its own. Tabs, open,
// save, save as, find and replace, syntax colours, line numbers, word wrap,
// text size. The documents are Services/TextDocs's, so closing the window
// loses nothing: what was typed is there when it opens again.
//
// Every action is a button with its shortcut in the tooltip - Ctrl+N new,
// Ctrl+O open, Ctrl+S save, Ctrl+Shift+S save as, Ctrl+W close the tab,
// Ctrl+F find, Ctrl+H replace, Ctrl +/-/0 text size.
// The image's default for text files (dev.shani.TextEditor.desktop).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/Highlight.js" as Highlight

AppWindow {
    id: win
    appName: "Text Editor"
    doc: TextDocs.current ? (TextDocs.current.modified ? "● " : "") + TextDocs.current.name : ""
    visible: Ui.textEditor
    onGone: Ui.textEditor = false
    tools: [
        IconButton { size: 30; icon: "document-new"; tip: Tr.t("New") + " (Ctrl+N)"; onClicked: TextDocs.newDoc() },
        IconButton { size: 30; icon: "document-open"; tip: Tr.t("Open") + " (Ctrl+O)"; onClicked: win.pick() },
        Button { text: Tr.t("Save"); kind: TextDocs.current && TextDocs.current.modified ? "primary" : "plain"; enabled: TextDocs.current !== null && !TextDocs.saving; onClicked: win.save() },
        Button { text: Tr.t("Save as…"); flat: true; onClicked: win.saveAs() },
        IconButton { size: 30; icon: "edit-find"; tip: Tr.t("Find") + " (Ctrl+F)"; on: win.finding; onClicked: { win.finding = !win.finding; if (win.finding) findField.input.forceActiveFocus(); } },
        IconButton { size: 30; icon: "format-justify-left"; tip: Tr.t("Wrap long lines"); on: win.wordWrap; onClicked: win.wordWrap = !win.wordWrap },
        IconButton { size: 30; icon: "view-list"; tip: Tr.t("Line numbers"); on: win.lineNumbers; onClicked: win.lineNumbers = !win.lineNumbers },
        IconButton { size: 30; icon: "applications-graphics"; tip: Tr.t("Syntax colours"); on: win.colours; onClicked: { win.colours = !win.colours; Settings.data.textEditorColours = win.colours; } },
        IconButton { size: 30; icon: "zoom-out"; tip: Tr.t("Smaller text") + " (Ctrl+-)"; onClicked: win.fontSize = Math.max(8, win.fontSize - 1) },
        IconButton { size: 30; icon: "zoom-in"; tip: Tr.t("Larger text") + " (Ctrl++)"; onClicked: win.fontSize = Math.min(28, win.fontSize + 1) }
    ]
    implicitWidth: 1000
    implicitHeight: 720

    property bool wordWrap: true
    property bool lineNumbers: true
    property real fontSize: Settings.data.textEditorFontSize || 13
    property bool finding: false
    property bool replacing: false
    property int confirmClose: -1         // the tab asked to close with changes: a second click closes it
    property bool loading: false          // the editor is being filled, not typed in

    onFontSizeChanged: Settings.data.textEditorFontSize = fontSize

    // ---- syntax colours ----------------------------------------------------------
    property bool colours: Settings.data.textEditorColours !== false
    readonly property string lang: TextDocs.current ? Highlight.langFor(TextDocs.current.path, TextDocs.current.text.substring(0, 120).split("\n")[0]) : "text"
    // not for plain text (nothing to colour), nor for a very long file (each
    // change colours the whole text again)
    readonly property bool coloured: colours && lang !== "text" && edit.length <= 200000
    readonly property var tints: Settings.data.darkMode
        ? ({ comment: "#8a93a0", string: "#8fd18a", number: "#f2a65a", keyword: "#6cb6ff", heading: "#ffd166", added: "#8fd18a", removed: "#ff8f8f" })
        : ({ comment: "#6a737d", string: "#1b7f3b", number: "#b35900", keyword: "#0550ae", heading: "#8a4b00", added: "#1b7f3b", removed: "#b3261e" })
    function recolour() {
        if (win.coloured)
            paint.text = '<pre style="margin:0; white-space:pre-wrap;">' + Highlight.html(edit.text, win.lang, win.tints) + "</pre>";
    }
    onColouredChanged: recolour()
    onLangChanged: recolour()
    onTintsChanged: recolour()
    Timer { id: repaint; interval: 60; onTriggered: win.recolour() }

    // the document in front, into the editor
    function load() {
        win.loading = true;
        edit.text = TextDocs.current ? TextDocs.current.text : "";
        win.loading = false;
        edit.cursorPosition = 0;
        if (TextDocs.goToLine > 0) {
            win.goToLine(TextDocs.goToLine);
            TextDocs.goToLine = 0;
        }
        edit.forceActiveFocus();
    }
    function goToLine(n) {
        const lines = edit.text.split("\n");
        const line = Math.max(1, Math.min(n, lines.length));
        let pos = 0;
        for (let i = 0; i < line - 1; i++)
            pos += lines[i].length + 1;
        edit.cursorPosition = pos;
    }
    Connections {
        target: TextDocs
        function onRevisionChanged() { win.load(); }
    }
    // a file handed over while the editor was closed, or while it is open
    function take() {
        const p = Ui.textEditorOpenPath;
        if (p === "")
            return;
        Ui.textEditorOpenPath = "";
        TextDocs.open(p);
    }
    Connections {
        target: Ui
        function onTextEditorOpenPathChanged() { win.take(); }
    }
    Component.onCompleted: {
        if (TextDocs.docs.length === 0)
            TextDocs.newDoc();
        else
            win.load();
        win.take();
    }

    function pick() {
        FilePicker.open({ mode: "open", title: Tr.t("Open a text file"),
                          startPath: TextDocs.current && TextDocs.current.path ? TextDocs.current.path.substring(0, TextDocs.current.path.lastIndexOf("/")) : "",
                          onPicked: paths => { if (paths.length) TextDocs.open(paths[0]); } });
    }
    function saveAs() {
        const d = TextDocs.current;
        FilePicker.open({ mode: "save", title: Tr.t("Save as"), defaultName: d && d.path ? d.name : "untitled.txt",
                          startPath: d && d.path ? d.path.substring(0, d.path.lastIndexOf("/")) : (Quickshell.env("HOME") + "/Documents"),
                          onPicked: paths => { if (paths.length) TextDocs.saveAs(paths[0]); } });
    }
    function save() {
        if (!TextDocs.save())
            win.saveAs();
    }
    function closeTab(i) {
        if (TextDocs.docs[i].modified && win.confirmClose !== i) {
            win.confirmClose = i;
            confirmTimer.restart();
            return;
        }
        win.confirmClose = -1;
        TextDocs.close(i);
    }
    Timer { id: confirmTimer; interval: 4000; onTriggered: win.confirmClose = -1 }

    // ---- find and replace -------------------------------------------------------
    function find(forward) {
        const q = findField.text;
        if (q === "")
            return;
        const hay = edit.text.toLowerCase(), needle = q.toLowerCase();
        let at = forward ? hay.indexOf(needle, edit.selectionEnd) : hay.lastIndexOf(needle, edit.selectionStart - 1);
        if (at < 0)       // wrap around
            at = forward ? hay.indexOf(needle) : hay.lastIndexOf(needle);
        if (at >= 0)
            edit.select(at, at + q.length);
    }
    readonly property int matches: {
        const q = findField.text.toLowerCase();
        if (!win.finding || q === "")
            return 0;
        return edit.text.toLowerCase().split(q).length - 1;
    }
    function replaceOne() {
        if (edit.selectedText.toLowerCase() === findField.text.toLowerCase() && edit.selectedText !== "") {
            const at = edit.selectionStart;
            edit.remove(edit.selectionStart, edit.selectionEnd);
            edit.insert(at, replaceField.text);
            edit.cursorPosition = at + replaceField.text.length;
        }
        win.find(true);
    }
    function replaceAll() {
        const q = findField.text;
        if (q === "")
            return;
        const re = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");
        edit.text = edit.text.replace(re, () => replaceField.text);
    }

    function shortcut(e) {
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
        if (!ctrl)
            return false;
        if (e.key === Qt.Key_S) { if (shift) win.saveAs(); else win.save(); }
        else if (e.key === Qt.Key_O) win.pick();
        else if (e.key === Qt.Key_N) TextDocs.newDoc();
        else if (e.key === Qt.Key_W) win.closeTab(TextDocs.active);
        else if (e.key === Qt.Key_F) { win.finding = true; win.replacing = false; findField.input.forceActiveFocus(); }
        else if (e.key === Qt.Key_H) { win.finding = true; win.replacing = true; findField.input.forceActiveFocus(); }
        else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) win.fontSize = Math.min(28, win.fontSize + 1);
        else if (e.key === Qt.Key_Minus) win.fontSize = Math.max(8, win.fontSize - 1);
        else if (e.key === Qt.Key_0) win.fontSize = 13;
        else return false;
        return true;
    }
    // Escape leaves the find bar; the window is closed like any other (Mod+Q, its button)
    function leave() {
        if (win.finding) {
            win.finding = false;
            edit.forceActiveFocus();
        }
    }

    Item {
        id: card
        anchors.fill: parent
        Keys.onPressed: e => { if (win.shortcut(e)) e.accepted = true; }
        Keys.onEscapePressed: win.leave()

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            // ---- the open documents ----
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                contentWidth: tabRow.implicitWidth
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: tabRow
                    spacing: 4
                    Repeater {
                        model: TextDocs.docs
                        delegate: Rectangle {
                            id: tab
                            required property var modelData
                            required property int index
                            readonly property bool front: TextDocs.active === index
                            readonly property bool asking: win.confirmClose === index
                            width: tabText.implicitWidth + 50
                            height: 32
                            radius: Theme.radiusSmall
                            color: front ? Theme.accentSoft : tabArea.containsMouse ? Theme.hover : "transparent"
                            border.width: front ? 1 : 0
                            border.color: Theme.accentLine
                            Accessible.role: Accessible.PageTab
                            Accessible.name: modelData.name + (modelData.modified ? ", " + Tr.t("not saved") : "")
                            Accessible.onPressAction: TextDocs.show(index)
                            Text {
                                id: tabText
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: tab.asking ? Tr.t("Close without saving?") : (tab.modelData.modified ? "● " : "") + tab.modelData.name
                                color: tab.asking ? Theme.danger : tab.front ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: e => { if (e.button === Qt.MiddleButton) win.closeTab(tab.index); else TextDocs.show(tab.index); }
                            }
                            IconButton {
                                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                icon: "window-close"
                                size: 22
                                tip: Tr.t("Close") + " " + tab.modelData.name
                                onClicked: win.closeTab(tab.index)
                            }
                        }
                    }
                }
            }

            // ---- find and replace ----
            RowLayout {
                Layout.fillWidth: true
                visible: win.finding
                spacing: 6
                TextField {
                    id: findField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Find")
                    onAccepted: win.find(true)
                    input.Keys.onEscapePressed: win.leave()
                }
                Text {
                    text: findField.text === "" ? "" : win.matches === 0 ? Tr.t("Not found") : win.matches + " " + Tr.t("found")
                    color: win.matches === 0 && findField.text !== "" ? Theme.danger : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                IconButton { icon: "go-up"; tip: Tr.t("Previous match"); onClicked: win.find(false) }
                IconButton { icon: "go-down"; tip: Tr.t("Next match"); onClicked: win.find(true) }
                Button { text: Tr.t("Replace…"); flat: true; checked: win.replacing; onClicked: win.replacing = !win.replacing }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: win.finding && win.replacing
                spacing: 6
                TextField {
                    id: replaceField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Replace with")
                    onAccepted: win.replaceOne()
                    input.Keys.onEscapePressed: win.leave()
                }
                Button { text: Tr.t("Replace"); onClicked: win.replaceOne() }
                Button { text: Tr.t("Replace all"); onClicked: win.replaceAll() }
            }

            // ---- the text ----
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                clip: true

                // line numbers: beside unwrapped text, where a line is a row
                Item {
                    id: gutter
                    visible: win.lineNumbers && !win.wordWrap
                    width: visible ? numbers.implicitWidth + 16 : 0
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    clip: true
                    Text {
                        id: numbers
                        x: 8
                        y: 8 - flick.contentY
                        text: Array.from({ length: edit.lineCount }, (_, i) => i + 1).join("\n")
                        color: Theme.faint
                        horizontalAlignment: Text.AlignRight
                        font: edit.font
                    }
                }
                Flickable {
                    id: flick
                    anchors { left: gutter.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 8; leftMargin: gutter.visible ? 0 : 8 }
                    contentWidth: edit.width
                    contentHeight: edit.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    function follow(r) {
                        if (contentY > r.y) contentY = r.y;
                        else if (contentY + height < r.y + r.height) contentY = r.y + r.height - height;
                        if (contentX > r.x) contentX = r.x;
                        else if (contentX + width < r.x + r.width + 8) contentX = r.x + r.width + 8 - width;
                    }
                    // the colours: the same text, drawn underneath with its comments,
                    // strings, numbers and keywords tinted (Common/Highlight.js), while
                    // the editor above it draws its own letters see-through. Same font,
                    // width and wrapping, so the two lie exactly on each other.
                    TextEdit {
                        id: paint
                        visible: win.coloured
                        width: edit.width
                        height: edit.height
                        readOnly: true
                        activeFocusOnPress: false
                        selectByMouse: false
                        enabled: false
                        wrapMode: edit.wrapMode
                        textFormat: TextEdit.RichText
                        color: Theme.text
                        font: edit.font
                        tabStopDistance: edit.tabStopDistance
                    }
                    TextEdit {
                        id: edit
                        width: win.wordWrap ? flick.width : Math.max(flick.width, implicitWidth + 8)
                        height: Math.max(flick.height, implicitHeight)
                        wrapMode: win.wordWrap ? TextEdit.Wrap : TextEdit.NoWrap
                        textFormat: TextEdit.PlainText
                        readOnly: TextDocs.current !== null && TextDocs.current.readOnly
                        color: win.coloured ? "transparent" : Theme.text
                        // the cursor takes the text's colour, which may be see-through
                        cursorDelegate: Rectangle {
                            width: 2
                            color: Theme.text
                            visible: edit.cursorVisible
                        }
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentInk
                        selectByMouse: true
                        persistentSelection: true
                        font.family: Theme.mono
                        font.pixelSize: win.fontSize * Theme.fontScale
                        tabStopDistance: 4 * font.pixelSize * 0.6
                        Accessible.role: Accessible.EditableText
                        Accessible.name: Tr.t("Text") + ": " + (TextDocs.current ? TextDocs.current.name : "")
                        onTextChanged: { if (!win.loading) TextDocs.setText(text); repaint.restart(); }
                        onCursorRectangleChanged: flick.follow(cursorRectangle)
                        Keys.onPressed: e => { if (win.shortcut(e)) e.accepted = true; }
                        Keys.onEscapePressed: win.leave()
                    }
                }
            }

            // ---- where the cursor is, what the file is, what went wrong ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: TextDocs.error !== "" ? TextDocs.error
                        : !TextDocs.current ? ""
                        : (TextDocs.current.path || Tr.t("Not saved yet")) + (TextDocs.current.readOnly ? "  ·  " + Tr.t("read-only") : "")
                    color: TextDocs.error !== "" ? Theme.danger : Theme.dim
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Text {
                    readonly property var at: {
                        const before = edit.text.substring(0, edit.cursorPosition);
                        const line = before.split("\n").length;
                        return [line, before.length - before.lastIndexOf("\n")];
                    }
                    text: Tr.t("Line") + " " + at[0] + ", " + Tr.t("column") + " " + at[1] + "  ·  " + edit.lineCount + " " + Tr.t("lines")
                        + (TextDocs.current && TextDocs.current.eol === "\r\n" ? "  ·  CRLF" : "")
                        + (win.lang !== "text" ? "  ·  " + win.lang : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
