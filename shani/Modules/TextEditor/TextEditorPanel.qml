// Text Editor: plain text over files, in a window of its own. Tabs, open,
// save, save as, find and replace, syntax colours, line numbers, word wrap,
// text size. The documents are Services/TextDocs's, so closing the window
// loses nothing: what was typed is there when it opens again.
//
// Every action is a button with its shortcut in the tooltip - Ctrl+N new,
// Ctrl+O open, Ctrl+S save, Ctrl+Shift+S save as, Ctrl+W close the tab,
// Ctrl+Z undo, Ctrl+Shift+Z / Ctrl+Y redo, Ctrl+F find, Ctrl+H replace,
// Ctrl +/-/0 text size.
// The image's default for text files (dev.shani.TextEditor.desktop).
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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
        IconButton { size: Theme.px(30); icon: "document-new"; tip: Tr.t("New") + " (Ctrl+N)"; onClicked: TextDocs.newDoc() },
        IconButton { size: Theme.px(30); icon: "edit-undo"; tip: Tr.t("Undo") + " (Ctrl+Z)"; enabled: TextDocs.canUndo; onClicked: win.undo() },
        IconButton { size: Theme.px(30); icon: "edit-redo"; tip: Tr.t("Redo") + " (Ctrl+Shift+Z)"; enabled: TextDocs.canRedo; onClicked: win.redo() },
        IconButton { size: Theme.px(30); icon: "document-open"; tip: Tr.t("Open") + " (Ctrl+O)"; onClicked: win.pick() },
        Button { text: Tr.t("Save"); kind: TextDocs.current && TextDocs.current.modified ? "primary" : "plain"; enabled: TextDocs.current !== null && !TextDocs.saving; onClicked: win.save() },
        Button { text: Tr.t("Save as…"); flat: true; onClicked: win.saveAs() },
        IconButton { size: Theme.px(30); icon: "edit-find"; tip: Tr.t("Find") + " (Ctrl+F)"; on: win.finding; onClicked: { win.finding = !win.finding; if (win.finding) findField.input.forceActiveFocus(); } },
        IconButton { size: Theme.px(30); icon: "bookmark-new"; tip: "Toggle bookmark (Ctrl+B)"; onClicked: win.toggleBookmark() },
        IconButton { size: Theme.px(30); icon: "go-jump"; tip: "Go to line (Ctrl+G)"; onClicked: win.openGoto() },
        IconButton { size: Theme.px(30); icon: "applications-graphics"; tip: "TextMate theme"; onClicked: themeDialog.open() },
        IconButton { size: Theme.px(30); icon: "preferences-desktop-theme"; tip: "TextMate colours"; on: TextMate.enabled; onClicked: { TextMate.enabled = !TextMate.enabled; Settings.data.textmateEnabled = TextMate.enabled; Settings.save(); win.recolour(); } },
        IconButton { size: Theme.px(30); icon: "format-justify-left"; tip: Tr.t("Wrap long lines"); on: win.wordWrap; onClicked: win.wordWrap = !win.wordWrap },
        IconButton { size: Theme.px(30); icon: "view-list"; tip: Tr.t("Line numbers"); on: win.lineNumbers; onClicked: win.lineNumbers = !win.lineNumbers },
        IconButton { size: Theme.px(30); icon: "applications-graphics"; tip: Tr.t("Syntax colours"); on: win.colours; onClicked: { win.colours = !win.colours; Settings.data.textEditorColours = win.colours; } },
        IconButton { size: Theme.px(30); icon: "zoom-out"; tip: Tr.t("Smaller text") + " (Ctrl+-)"; onClicked: win.fontSize = Math.max(8, win.fontSize - 1) },
        IconButton { size: Theme.px(30); icon: "zoom-in"; tip: Tr.t("Larger text") + " (Ctrl++)"; onClicked: win.fontSize = Math.min(28, win.fontSize + 1) }
    ]
    implicitWidth: Theme.px(1000)
    implicitHeight: Theme.px(720)

    property bool wordWrap: true
    property bool lineNumbers: true
    property real fontSize: Settings.data.textEditorFontSize || 13
    property bool finding: false
    property bool replacing: false
    // find options
    property bool caseSensitive: false
    property bool wholeWord: false
    property bool useRegex: false
    property int matchIndex: -1
    // go-to-line and TextMate theme chooser
    property bool gotoOpen: false
    property string themeChoice: ""
    property int confirmClose: -1         // the tab asked to close with changes: a second click closes it
    property bool loading: false          // the editor is being filled, not typed in
    // ---- snippets: type a trigger, press Tab to expand ----
    readonly property var snippets: [
        { trigger: "if", body: "if () {\n    \n}" },
        { trigger: "for", body: "for () {\n    \n}" },
        { trigger: "fn", body: "function () {\n    \n}" },
        { trigger: "main", body: "function main() {\n    \n}" },
        { trigger: "class", body: "class {\n    \n}" },
        { trigger: "while", body: "while () {\n    \n}" },
        { trigger: "print", body: "console.log()" },
    ]
    function trySnippet() {
        const before = edit.text.substring(0, edit.cursorPosition);
        const m = before.match(/([\w()]+)$/);
        if (m) {
            const trigger = m[1];
            const snip = win.snippets.find(s => s.trigger === trigger);
            if (snip) {
                const at = edit.cursorPosition - trigger.length;  // cache before remove() moves the cursor
                edit.remove(at, edit.cursorPosition);
                edit.insert(at, snip.body);
                edit.cursorPosition = at + snip.body.length;
                edit.forceActiveFocus();
                return true;
            }
        }
        return false;
    }

    // ---- typing helpers: auto-close brackets/quotes and smart indent ----------
    function closeOf(ch) { return ch === "(" ? ")" : ch === "[" ? "]" : ch === "{" ? "}" : ch; }
    function handleAutoclose(e) {
        const t = edit.text, p = edit.cursorPosition, c = e.text;
        if (c.length === 1 && "([{\"'".indexOf(c) >= 0) {
            edit.insert(p, c + closeOf(c));
            edit.cursorPosition = p + 1;
            e.accepted = true;
            return true;
        }
        if (e.key === Qt.Key_Backspace && p > 0 && p < t.length) {
            const o = t.charAt(p - 1);
            if (closeOf(o) === t.charAt(p) && "([{\"'".indexOf(o) >= 0) {
                edit.remove(p - 1, 2);
                e.accepted = true;
                return true;
            }
        }
        if (e.key === Qt.Key_Return && !(e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.ShiftModifier)) {
            const lineStart = t.lastIndexOf("\n", p - 1) + 1;
            const line = t.slice(lineStart, p);
            const indent = (line.match(/^[ \t]*/) || [""])[0];
            const extra = /[\{\[\(]\s*$/.test(line) ? "    " : "";
            const next = t.charAt(p);
            if (extra && (next === "}" || next === "]" || next === ")")) {
                edit.insert(p, "\n" + indent + extra + "\n" + indent);
                edit.cursorPosition = p + 1 + indent.length + extra.length;
            } else {
                edit.insert(p, "\n" + indent + extra);
                edit.cursorPosition = p + 1 + indent.length + extra.length;
            }
            e.accepted = true;
            return true;
        }
        return false;
    }

    // ---- multiple cursors / column selection ----------------------------------
    // Qt's TextEdit has one cursor. We keep extra cursors as character offsets
    // and apply every edit at all positions, drawing the extras as overlays.
    // Alt+Shift+Down/Up adds a cursor on the line below/above at the same column
    // (column selection), mirroring VS Code's shortcut.
    property var extraCursors: []          // sorted ascending character offsets
    readonly property bool multiCursor: extraCursors.length > 0
    property bool computingRects: false    // guard: rectAt() moves the real cursor temporarily

    // the screen rect of any character offset (temporarily move the real cursor)
    function rectAt(pos) {
        if (pos < 0 || pos > edit.length) return Qt.rect(0, 0, 0, 0);
        const saved = edit.cursorPosition;
        const ss = edit.selectionStart, se = edit.selectionEnd;
        computingRects = true;
        edit.cursorPosition = pos;
        const r = Qt.rect(edit.cursorRectangle.x, edit.cursorRectangle.y,
                          Math.max(2, edit.cursorRectangle.width), edit.cursorRectangle.height);
        edit.cursorPosition = saved;
        if (se > ss) edit.select(ss, se);
        computingRects = false;
        return r;
    }

    // line and column of a character offset
    function lineCol(pos) {
        const before = edit.text.substring(0, Math.max(0, pos));
        const cut = before.lastIndexOf("\n");
        return { line: (before.match(/\n/g) || []).length, col: before.length - cut - 1 };
    }
    // offset of (line, col)
    function posAt(line, col) {
        const lines = edit.text.split("\n");
        if (line < 0 || line >= lines.length) return -1;
        let p = 0;
        for (let i = 0; i < line; i++) p += lines[i].length + 1;
        return p + Math.min(col, lines[line].length);
    }
    function addCursorVertical(delta) {
        const lc = lineCol(edit.cursorPosition);
        const p = posAt(lc.line + delta, lc.col);
        if (p < 0 || extraCursors.indexOf(p) >= 0 || p === edit.cursorPosition) return;
        extraCursors = extraCursors.concat([p]).sort((a, b) => a - b);
    }
    function clearExtraCursors() { if (extraCursors.length) extraCursors = []; }

    // insert `str` at the primary cursor and every extra cursor at once
    function insertAtCursors(str) {
        if (!multiCursor || str === "") return false;
        const all = Array.from(new Set([edit.cursorPosition].concat(extraCursors))).sort((a, b) => a - b);
        let t = edit.text;
        for (let i = all.length - 1; i >= 0; i--) {
            const p = all[i];
            t = t.substring(0, p) + str + t.substring(p);
        }
        const primaryNew = edit.cursorPosition + all.filter(p => p <= edit.cursorPosition).length * str.length;
        const newExtras = extraCursors.map(p => p + all.filter(up => up <= p).length * str.length);
        win.loading = true;
        edit.text = t;
        edit.cursorPosition = primaryNew;
        extraCursors = newExtras;
        win.loading = false;
        TextDocs.setText(t);
        repaint.restart();
        return true;
    }

    // backspace at the primary cursor and every extra cursor at once
    function backspaceAtCursors() {
        if (!multiCursor) return false;
        const all = Array.from(new Set([edit.cursorPosition].concat(extraCursors))).sort((a, b) => a - b);
        const del = all.map(p => p - 1).filter(p => p >= 0);
        if (del.length === 0) return false;
        const uniqDel = Array.from(new Set(del)).sort((a, b) => a - b);
        let t = edit.text;
        for (let i = uniqDel.length - 1; i >= 0; i--) {
            const p = uniqDel[i];
            t = t.substring(0, p) + t.substring(p + 1);
        }
        const primaryNew = Math.max(0, edit.cursorPosition - uniqDel.filter(p => p < edit.cursorPosition).length);
        const newExtras = extraCursors.map(p => Math.max(0, p - uniqDel.filter(d => d < p).length));
        win.loading = true;
        edit.text = t;
        edit.cursorPosition = primaryNew;
        extraCursors = newExtras;
        win.loading = false;
        TextDocs.setText(t);
        repaint.restart();
        return true;
    }

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
        if (!win.coloured) return;
        const ext = TextDocs.current ? (TextDocs.current.path || "").split(".").pop() : "";
        const tm = TextMate.highlight(edit.text, ext);
        if (tm !== "") {
            paint.text = '<pre style="margin:0; white-space:pre-wrap;">' + tm + "</pre>";
        } else {
            paint.text = '<pre style="margin:0; white-space:pre-wrap;">' + Highlight.html(edit.text, win.lang, win.tints) + "</pre>";
        }
    }
    onColouredChanged: recolour()
    onLangChanged: recolour()
    onTintsChanged: recolour()
    Timer { id: repaint; interval: 60; onTriggered: win.recolour() }

    // put text back without recording it as a fresh edit
    function showText(text) {
        if (text === null)
            return;
        win.loading = true;
        const pos = Math.min(edit.cursorPosition, text.length);
        edit.text = text;
        edit.cursorPosition = pos;
        win.loading = false;
        win.saveCaret();
        repaint.restart();
    }
    function undo() { win.showText(TextDocs.undo()); }
    function redo() { win.showText(TextDocs.redo()); }

    // where the caret and selection were in each document, by path (or by tab
    // for one not saved yet): switching tabs comes back to the same place
    property var caretByDoc: ({})
    function docKey() {
        const d = TextDocs.current;
        return d ? (d.path !== "" ? "file:" + d.path : "tab:" + TextDocs.active) : "";
    }
    function saveCaret() {
        const k = win.docKey();
        if (k === "") return;
        win.caretByDoc[k] = { pos: edit.cursorPosition, start: edit.selectionStart, end: edit.selectionEnd };
    }
    // false: nothing was remembered, the caret starts at the top
    function restoreCaret() {
        const c = win.caretByDoc[win.docKey()];
        if (!c) return false;
        const n = edit.length;
        edit.cursorPosition = Math.max(0, Math.min(c.pos, n));
        const a = Math.min(c.start, c.end), b = Math.max(c.start, c.end);
        if (b > a && b <= n)
            edit.select(a, b);   // after the caret: assigning it would clear the selection
        return true;
    }
    // the document in front, into the editor
    function load() {
        win.loading = true;
        edit.text = TextDocs.current ? TextDocs.current.text : "";
        if (TextDocs.goToLine > 0) {
            win.goToLine(TextDocs.goToLine);
            TextDocs.goToLine = 0;
        } else if (!win.restoreCaret()) {
            edit.cursorPosition = 0;
        }
        win.loading = false;
        win.saveCaret();
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
        if (Settings.data.textmateTheme) TextMate.themePath = Settings.data.textmateTheme;
        // the connection outlives the window: the editor can be closed while a
        // document is still being switched, and then `win` is gone
        if (TextDocs) TextDocs.onActiveChanged.connect(() => { if (win) win.clearExtraCursors(); });
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
        // a read-only file is never written over: Save becomes Save as
        if (TextDocs.current && TextDocs.current.readOnly) {
            win.saveAs();
            return;
        }
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
    // one matcher for search, live highlights and replace-all, so all three
    // agree on case, whole-word and regular-expression options
    function searchRegex(q) {
        if (!q) return null;
        try {
            if (win.useRegex)
                return new RegExp(q, (win.caseSensitive ? "" : "i") + "g");
            let esc = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            if (win.wholeWord) esc = "\\b" + esc + "\\b";
            return new RegExp(esc, (win.caseSensitive ? "" : "i") + "g");
        } catch (e) { return null; }
    }
    function findMatches(hay, q) {
        const re = win.searchRegex(q);
        if (!re) return [];
        const out = [];
        let m, guard = 0;
        while ((m = re.exec(hay)) !== null && guard++ < 500) {
            out.push(m.index);
            if (m[0].length === 0) re.lastIndex++;
        }
        return out;
    }
    readonly property var matchOffsets: win.finding && findField.text !== "" ? win.findMatches(edit.text, findField.text) : []
    function toggleBookmark() {
        const lc = win.lineCol(edit.cursorPosition);
        TextDocs.toggleBookmark(lc.line);
    }
    function openGoto() {
        win.gotoOpen = true;
        gotoField.text = String(win.lineCol(edit.cursorPosition).line + 1);
        gotoField.input.forceActiveFocus();
    }
    function submitGoto() {
        const n = parseInt(gotoField.text, 10);
        if (!isNaN(n)) win.goToLine(n);
        win.gotoOpen = false;
        edit.forceActiveFocus();
    }
    // matching bracket next to the cursor (or just after it), if there is one
    function matchBrace(pos) {
        const t = edit.text;
        const pairs = { ")": "(", "]": "[", "}": "{", "(": ")", "[": "]", "{": "}" };
        const ch = t.charAt(pos), prev = t.charAt(pos - 1);
        let at = -1;
        if (pairs[ch]) at = pos;
        else if (pairs[prev]) at = pos - 1;
        else return -1;
        const c = t.charAt(at);
        const opening = "([{".indexOf(c) >= 0;
        const want = pairs[c];
        const dir = opening ? 1 : -1;
        let depth = 0;
        for (let i = at + dir; i >= 0 && i < t.length; i += dir) {
            const x = t.charAt(i);
            if (x === c) depth++;
            else if (x === want) { depth--; if (depth === 0) return i; }
        }
        return -1;
    }
    function find(forward) {
        const offsets = win.matchOffsets;
        if (offsets.length === 0) { win.matchIndex = -1; return; }
        let i;
        if (forward)
            i = offsets.find(o => o >= edit.selectionEnd);
        else {
            i = -1;
            for (let k = offsets.length - 1; k >= 0; k--)
                if (offsets[k] < edit.selectionStart) { i = offsets[k]; break; }
        }
        if (i === undefined || i === -1)
            i = forward ? offsets[0] : offsets[offsets.length - 1];
        win.matchIndex = offsets.indexOf(i);
        const len = win.useRegex ? (win.searchRegex(findField.text).exec(edit.text.slice(i)) || [""])[0].length : findField.text.length;
        edit.select(i, i + Math.max(1, len));
    }
    readonly property int matches: win.matchOffsets.length
    // the selection is exactly one match of the find text, not merely text
    // that contains one: Replace must not eat the letters around it
    function selectionIsMatch() {
        const re = win.searchRegex(findField.text);
        if (!re || edit.selectedText === "") return false;
        const m = re.exec(edit.selectedText);
        return !!m && m.index === 0 && m[0].length === edit.selectedText.length;
    }
    function replaceOne() {
        if (win.selectionIsMatch()) {
            const at = edit.selectionStart;
            edit.remove(edit.selectionStart, edit.selectionEnd);
            edit.insert(at, replaceField.text);
            edit.cursorPosition = at + replaceField.text.length;
        }
        win.find(true);
    }
    function replaceAll() {
        const re = win.searchRegex(findField.text);
        if (!re) return;
        win.loading = true;
        // pass the string directly: JS String.replace expands $1/$2 captures (and
        // $$ to a literal $); a function replacement would insert them literally
        edit.text = edit.text.replace(re, replaceField.text);
        win.loading = false;
        TextDocs.setText(edit.text);
        repaint.restart();
    }

    function shortcut(e) {
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
        if (!ctrl)
            return false;
        if (e.key === Qt.Key_S) { if (shift) win.saveAs(); else win.save(); }
        else if (e.key === Qt.Key_Z) { if (shift) win.redo(); else win.undo(); }
        else if (e.key === Qt.Key_Y) win.redo();
        else if (e.key === Qt.Key_O) win.pick();
        else if (e.key === Qt.Key_N) TextDocs.newDoc();
        else if (e.key === Qt.Key_W) win.closeTab(TextDocs.active);
        else if (e.key === Qt.Key_F) { win.finding = true; win.replacing = false; findField.text = edit.selectedText; findField.input.forceActiveFocus(); }
        else if (e.key === Qt.Key_H) { win.finding = true; win.replacing = true; findField.input.forceActiveFocus(); }
        else if (e.key === Qt.Key_B) win.toggleBookmark();
        else if (e.key === Qt.Key_G) win.openGoto();
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
        } else if (TextDocs.docs.length <= 1) {
            Ui.textEditor = false;
        }
    }

    Item {
        id: card
        anchors.fill: parent
        Keys.onPressed: e => { if (win.shortcut(e)) e.accepted = true; }
        Keys.onEscapePressed: win.leave()

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(8)

            // ---- the open documents ----
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(32)
                contentWidth: tabRow.implicitWidth
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: tabRow
                    spacing: Theme.px(4)
                    Repeater {
                        model: TextDocs.docs
                        delegate: Rectangle {
                            id: tab
                            required property var modelData
                            required property int index
                            readonly property bool front: TextDocs.active === index
                            readonly property bool asking: win.confirmClose === index
                            width: tabText.implicitWidth + 50
                            height: Theme.px(32)
                            radius: Theme.radiusSmall
                            color: front ? Theme.accentSoft : tabArea.containsMouse ? Theme.hover : "transparent"
                            border.width: front ? 1 : 0
                            border.color: Theme.accentLine
                            Accessible.role: Accessible.PageTab
                            Accessible.name: modelData.name + (modelData.modified ? ", " + Tr.t("not saved") : "")
                            Accessible.onPressAction: TextDocs.show(index)
                            Text {
                                id: tabText
                                anchors { left: parent.left; leftMargin: Theme.px(12); verticalCenter: parent.verticalCenter }
                                text: tab.asking ? Tr.t("Close without saving?") : (tab.modelData.modified ? "● " : "") + tab.modelData.name
                                color: tab.asking ? Theme.danger : tab.front ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(12) * Theme.fontScale
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
                                anchors { right: parent.right; rightMargin: Theme.px(4); verticalCenter: parent.verticalCenter }
                                icon: "window-close"
                                size: Theme.px(22)
                                tip: Tr.t("Close") + " " + tab.modelData.name
                                onClicked: win.closeTab(tab.index)
                            }
                        }
                    }
                }
            }

            EmptyState {
                visible: TextDocs.docs.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon: "document-open"
                title: Tr.t("No document open")
                subtitle: Tr.t("Open a file, or start a new one")
                actionText: Tr.t("New document")
                onAction: TextDocs.newDoc()
            }

            // ---- find and replace ----
            RowLayout {
                Layout.fillWidth: true
                visible: win.finding && TextDocs.docs.length > 0
                spacing: Theme.px(6)
                TextField {
                    id: findField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Find")
                    onAccepted: win.find(true)
                    onTextChanged: win.matchIndex = -1
                    input.Keys.onEscapePressed: win.leave()
                    // Shift+Enter goes to the previous match, as in every editor
                    input.Keys.onPressed: e => {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            win.find(!(e.modifiers & Qt.ShiftModifier));
                            e.accepted = true;
                        }
                    }
                }
                CheckBox { text: "Aa"; checked: win.caseSensitive; onCheckedChanged: win.caseSensitive = checked; ToolTip.text: "Match case"; Accessible.name: "Match case" }
                CheckBox { text: "W"; checked: win.wholeWord; onCheckedChanged: win.wholeWord = checked; ToolTip.text: "Whole word"; Accessible.name: "Whole word" }
                CheckBox { text: ".*"; checked: win.useRegex; onCheckedChanged: win.useRegex = checked; ToolTip.text: "Regular expression"; Accessible.name: "Regular expression" }
                Text {
                    text: findField.text === "" ? "" : win.matches === 0 ? Tr.t("Not found") : (win.matchIndex >= 0 ? (win.matchIndex + 1) + "/" : "") + win.matches + " " + Tr.t("found")
                    color: win.matches === 0 && findField.text !== "" ? Theme.danger : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                IconButton { icon: "go-up"; tip: Tr.t("Previous match"); onClicked: win.find(false) }
                IconButton { icon: "go-down"; tip: Tr.t("Next match"); onClicked: win.find(true) }
                Button { text: Tr.t("Replace…"); flat: true; checked: win.replacing; onClicked: win.replacing = !win.replacing }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: win.finding && win.replacing
                spacing: Theme.px(6)
                TextField {
                    id: replaceField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Replace with")
                    onAccepted: win.replaceOne()
                    input.Keys.onEscapePressed: win.leave()
                }
                Button { text: Tr.t("Replace"); onClicked: win.replaceOne() }
                Button { text: Tr.t("Replace all"); onClicked: replaceAllConfirm.open() }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: win.gotoOpen
                spacing: Theme.px(6)
                TextField {
                    id: gotoField
                    Layout.fillWidth: true
                    placeholder: "Line number"
                    input.validator: IntValidator { bottom: 1; top: 1000000 }
                    onAccepted: win.submitGoto()
                    input.Keys.onEscapePressed: { win.gotoOpen = false; edit.forceActiveFocus(); }
                }
                Button { text: "Go"; onClicked: win.submitGoto() }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: { win.gotoOpen = false; edit.forceActiveFocus(); } }
            }

            // confirm dialog for replace all
            Dialog {
                id: replaceAllConfirm
                anchors.centerIn: parent
                width: Math.min(win.width * 0.8, Theme.px(400))
                title: Tr.t("Replace all?")
                modal: true
                standardButtons: Dialog.No | Dialog.Yes
                onAccepted: win.replaceAll()
                contentItem: ColumnLayout {
                    spacing: Theme.px(12)
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("This will replace all occurrences of the search text with the replacement text. This cannot be undone.")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                }
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
                    visible: win.lineNumbers
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
                    Repeater {
                        model: TextDocs.bookmarks()
                        Rectangle {
                            x: 2
                            y: 8 + modelData * (edit.font.pixelSize * 1.6) - flick.contentY
                            width: 4; height: 4; radius: 2
                            color: Theme.accent
                            visible: y > 0 && y < gutter.height
                        }
                    }
                }
                Flickable {
                    id: flick
                    visible: TextDocs.docs.length > 0
                    anchors { left: gutter.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: Theme.px(8); leftMargin: gutter.visible ? 0 : 8 }
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
                    // current line, matching bracket and every live search hit,
                    // drawn beneath the (see-through) editor text
                    Rectangle {
                        visible: TextDocs.docs.length > 0 && edit.activeFocus
                        x: 0; y: edit.cursorRectangle.y
                        width: edit.width; height: Math.max(edit.cursorRectangle.height, Theme.px(16))
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                        z: 0
                    }
                    Rectangle {
                        property int bracePos: win.matchBrace(edit.cursorPosition)
                        property rect r: bracePos >= 0 ? win.rectAt(bracePos) : Qt.rect(0, 0, 0, 0)
                        x: r.x; y: r.y; width: r.width; height: r.height
                        radius: 2
                        border.width: 1
                        border.color: Theme.accent
                        color: "transparent"
                        visible: bracePos >= 0 && r.width > 0
                        z: 1
                    }
                    Repeater {
                        model: win.matchOffsets.slice(0, 200)
                        Rectangle {
                            property rect r: win.rectAt(modelData)
                            x: r.x; y: r.y; width: r.width; height: r.height
                            radius: 2
                            color: Qt.rgba(1, 0.75, 0.15, 0.32)
                            visible: win.finding && r.width > 0
                            z: 1
                        }
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
                        activeFocusOnTab: true          // the d-pad and Tab reach it (a pad's LB / RB leave it: Ui.navJump)
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
                        onCursorRectangleChanged: { if (!win.computingRects) flick.follow(cursorRectangle); }
                        Keys.onPressed: e => {
                            // multiple cursors / column selection
                            if ((e.modifiers & Qt.ShiftModifier) && (e.modifiers & Qt.AltModifier)) {
                                if (e.key === Qt.Key_Down) { win.addCursorVertical(1); e.accepted = true; return; }
                                if (e.key === Qt.Key_Up)   { win.addCursorVertical(-1); e.accepted = true; return; }
                            }
                            if (win.multiCursor) {
                                if (e.key === Qt.Key_Escape) { win.clearExtraCursors(); e.accepted = true; return; }
                                if (e.key === Qt.Key_Backspace) { if (win.backspaceAtCursors()) { e.accepted = true; return; } }
                                if (e.text !== "" && !(e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.AltModifier)) {
                                    if (win.insertAtCursors(e.text)) { e.accepted = true; return; }
                                }
                            }
                            if (!win.multiCursor && !(e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.AltModifier)
                                    && win.handleAutoclose(e)) return;
                            if (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier) && !(e.modifiers & Qt.ControlModifier)) {
                                if (win.trySnippet()) { e.accepted = true; return; }
                            }
                            if (win.shortcut(e)) e.accepted = true;
                        }
                        Keys.onEscapePressed: win.leave()
                        onCursorPositionChanged: {
                            if (win.loading || win.computingRects) return;
                            win.saveCaret();
                            if (win.multiCursor) win.clearExtraCursors();
                        }
                        onSelectedTextChanged: { if (!win.loading && !win.computingRects) win.saveCaret(); }
                    }
                    // draw the extra cursors (column selection) as thin overlays
                    Repeater {
                        model: win.extraCursors
                        delegate: Rectangle {
                            property rect r: win.rectAt(modelData)
                            x: r.x; y: r.y; width: Math.max(2, r.width); height: r.height
                            color: Theme.accent
                            visible: edit.activeFocus
                            z: 5
                        }
                    }
                }
            }

            // ---- where the cursor is, what the file is, what went wrong ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(12)
                Text {
                    Layout.fillWidth: true
                    text: TextDocs.error !== "" ? TextDocs.error
                        : !TextDocs.current ? ""
                        : (TextDocs.current.path || Tr.t("Not saved yet")) + (TextDocs.current.readOnly ? "  ·  " + Tr.t("read-only") : "")
                    color: TextDocs.error !== "" ? Theme.danger : Theme.dim
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Text {
                    readonly property var at: {
                        const before = edit.text.substring(0, edit.cursorPosition);
                        const line = before.split("\n").length;
                        return [line, before.length - before.lastIndexOf("\n")];
                    }
                    text: Tr.t("Line") + " " + at[0] + ", " + Tr.t("column") + " " + at[1] + "  ·  " + edit.lineCount + " " + Tr.t("lines")
                          + "  ·  " + edit.text.split(/\s+/).filter(w => w.length > 0).length + " " + Tr.t("words")
                          + "  ·  " + edit.text.length + " " + Tr.t("characters")
                        + (win.lang !== "text" ? "  ·  " + win.lang : "")
                        + (win.multiCursor ? "  ·  " + (win.extraCursors.length + 1) + " " + Tr.t("cursors") : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    Dialog {
        id: themeDialog
        anchors.centerIn: parent
        width: Math.min(win.width * 0.7, Theme.px(420))
        title: "TextMate theme"
        modal: true
        standardButtons: Dialog.Close
        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(6)
            Choice {
                text: "Built-in highlighter"
                selected: !TextMate.enabled
                onClicked: { TextMate.enabled = false; Settings.data.textmateEnabled = false; Settings.save(); themeDialog.close(); win.recolour(); }
            }
            Repeater {
                model: TextMate.themes
                Choice {
                    required property var modelData
                    text: modelData.name || "Theme"
                    selected: TextMate.enabled && TextMate.themePath === modelData.path
                    onClicked: {
                        TextMate.enabled = true;
                        Settings.data.textmateEnabled = true;
                        Settings.data.textmateTheme = modelData.path;
                        Settings.save();
                        TextMate.themePath = modelData.path;
                        win.recolour();
                    }
                }
            }
            Text {
                visible: TextMate.themes.length === 0
                text: "Install .tmTheme bundles in Share/shani-textmate to see themes here."
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                wrapMode: Text.Wrap
            }
        }
    }
}
