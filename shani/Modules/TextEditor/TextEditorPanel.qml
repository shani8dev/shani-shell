// Text Editor: plain text over files, in a window of its own. Tabs, open,
// save, save as, find and replace, syntax colours, line numbers, word wrap,
// text size. The documents are Services/TextDocs's, so closing the window
// loses nothing: what was typed is there when it opens again.
//
// Every action is a button with its shortcut in the tooltip - Ctrl+N new,
// Ctrl+O open, Ctrl+S save, Ctrl+Shift+S save as, Ctrl+Shift+W close the tab,
// Ctrl+Z undo, Ctrl+Shift+Z / Ctrl+Y redo, Ctrl+F find, Ctrl+H replace,
// Ctrl+Shift+R open recent, Ctrl +/-/0 text size, Ctrl+Tab / Ctrl+PgUp/PgDn switch tabs,
// Ctrl+Shift+T reopen the last closed tab, Ctrl+Shift+P present in the teleprompter.
// Ctrl+W closes the window and Ctrl+R refreshes: both belong to AppWindow.
// The image's default for text files (dev.shani.TextEditor.desktop).
import Quickshell
import Quickshell.Io
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
        IconButton { size: Theme.px(30); icon: "document-open-recent"; tip: "Open recent (Ctrl+Shift+R)"; onClicked: recentDialog.open() },
        IconButton { size: Theme.px(30); icon: "folder-open"; tip: "Project folder (Ctrl+K, O)"; on: win.sidebarOpen; onClicked: { if (TextDocs.folder === "") win.pickFolder(); else win.sidebarOpen = !win.sidebarOpen; } },
        IconButton { size: Theme.px(30); icon: "edit-find-in"; tip: "Find in files (Ctrl+Shift+F)"; on: win.findFilesOpen; onClicked: win.openFindFiles() },
        IconButton { size: Theme.px(30); icon: "view-split-left-right"; tip: "Split view (Ctrl+K, D)"; on: win.splitView; onClicked: win.splitView = !win.splitView },
        IconButton { size: Theme.px(30); icon: "applications-graphics"; tip: "Syntax language"; onClicked: syntaxDialog.open() },
        Button { text: Tr.t("Save"); kind: TextDocs.current && TextDocs.current.modified ? "primary" : "plain"; enabled: TextDocs.current !== null && !TextDocs.saving; onClicked: win.save() },
        Button { text: Tr.t("Save as…"); flat: true; onClicked: win.saveAs() },
        IconButton { size: Theme.px(30); icon: "view-fullscreen"; tip: "Present (Ctrl+Shift+P)"; onClicked: win.present() },
        IconButton { size: Theme.px(30); icon: "edit-find"; tip: Tr.t("Find") + " (Ctrl+F)"; on: win.finding; onClicked: { win.finding = !win.finding; if (win.finding) findField.input.forceActiveFocus(); } },
        IconButton { size: Theme.px(30); icon: "accessories-dictionary"; tip: Tr.t("Look up word"); enabled: win.canDefine; onClicked: win.lookUpWord() },
        IconButton { size: Theme.px(30); icon: "bookmark-new"; tip: "Toggle bookmark (Ctrl+B)"; onClicked: win.toggleBookmark() },
        IconButton { size: Theme.px(30); icon: "go-jump"; tip: "Go to line (Ctrl+G)"; onClicked: win.openGoto() },
        IconButton { size: Theme.px(30); icon: "entry-calendar"; tip: Tr.t("Insert date and time"); onClicked: win.insertDateTime() },
        IconButton { size: Theme.px(30); icon: "applications-graphics"; tip: "TextMate theme"; onClicked: themeDialog.open() },
        IconButton { size: Theme.px(30); icon: "preferences-desktop-theme"; tip: "TextMate colours"; on: TextMate.enabled; onClicked: { TextMate.enabled = !TextMate.enabled; Settings.data.textmateEnabled = TextMate.enabled; Settings.save(); win.recolour(); } },
        IconButton { size: Theme.px(30); icon: "format-justify-left"; tip: Tr.t("Wrap long lines"); on: win.wordWrap; onClicked: win.wordWrap = !win.wordWrap },
        IconButton { size: Theme.px(30); icon: "view-list"; tip: Tr.t("Line numbers"); on: win.lineNumbers; onClicked: win.lineNumbers = !win.lineNumbers },
        IconButton { size: Theme.px(30); icon: "applications-graphics"; tip: Tr.t("Syntax colours"); on: win.colours; onClicked: { win.colours = !win.colours; Settings.data.textEditorColours = win.colours; } },
        IconButton { size: Theme.px(30); icon: "zoom-out"; tip: Tr.t("Smaller text") + " (Ctrl+-)"; onClicked: win.fontSize = Math.max(8, win.fontSize - 1) },
        IconButton { size: Theme.px(30); icon: "zoom-in"; tip: Tr.t("Larger text") + " (Ctrl++)"; onClicked: win.fontSize = Math.min(28, win.fontSize + 1) },
        IconButton { size: Theme.px(30); icon: "text-x-generic"; tip: Tr.t("Markdown preview") + " (Ctrl+Shift+M)"; keys: "Ctrl+Shift+M"; accessibleName: Tr.t("Markdown preview"); on: win.markdownPreview; onClicked: win.toggleMarkdownPreview() },
        IconButton { size: Theme.px(30); icon: "preferences-desktop-font"; tip: Tr.t("Editor font"); onClicked: fontDialog.open() }
    ]
    implicitWidth: Theme.px(1000)
    implicitHeight: Theme.px(720)

    property bool wordWrap: true
    property bool lineNumbers: true
    property real fontSize: Settings.data.textEditorFontSize || 13
    // ---- font family ------------------------------------------------------------
    // Settings.data's JsonAdapter only accepts keys declared in Common/Settings.qml,
    // which the editor does not own, so the chosen family lives beside settings.json
    // (the same pattern as Services/Osk.qml).
    readonly property string fontPrefsDir: {
        const p = Settings.path;
        return p.substring(0, p.lastIndexOf("/"));
    }
    readonly property string fontPrefsPath: fontPrefsDir + "/text-editor-font.json"
    readonly property var fontFamilies: ["Monospace (default)"].concat(Array.from(Qt.fontFamilies()))
    property string fontFamily: fontPrefs.family || Theme.mono
    function setFontFamily(f) {
        fontPrefs.family = f === Theme.mono || f === "" ? "" : f;
        Quickshell.execDetached(["mkdir", "-p", win.fontPrefsDir]);
        fontPrefsFile.writeAdapter();
    }
    FileView {
        id: fontPrefsFile
        path: win.fontPrefsPath
        atomicWrites: true
        printErrors: false
        JsonAdapter {
            id: fontPrefs
            property string family: ""
        }
    }
    property bool finding: false
    property bool canDefine: false            // a selection is ready to look up in the Dictionary
    property bool replacing: false
    property bool markdownPreview: false   // rendered view of the current document (Ctrl+Shift+M)
    // find options
    property bool caseSensitive: false
    property bool wholeWord: false
    property bool useRegex: false
    property int matchIndex: -1
    // go-to-line and TextMate theme chooser
    property bool gotoOpen: false
    property string themeChoice: ""
    // shortcut: index-keyed tab close confirm is unsafe to migrate to ConfirmButton (tabs reorder/close shifts indices)
    property int confirmClose: -1         // the tab asked to close with changes: a second click closes it
    property var lastClosed: null         // { index, doc } of the last tab closed — Ctrl+Shift+T puts it back
    property bool loading: false          // the editor is being filled, not typed in
    // ---- IDE-style additions: project, MRU, groups, split, chords ---------------
    property bool sidebarOpen: false
    property bool splitView: false
    property bool findFilesOpen: false
    property string findFilesQuery: ""
    property var findFilesResults: []
    property bool findingFiles: false
    property string activeGroup: ""       // "" shows every tab; otherwise one folder
    property string chord: ""             // a pressed Ctrl+K, waiting for its second key
    readonly property var syntaxes: Object.keys(Highlight.langs).sort()
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
    // keep the file's own indent unit: a tab-indented file gets tabs back
    function indentUnit(indent) { return indent.indexOf("\t") >= 0 ? "\t" : "    "; }
    // what Enter inserts: the line's leading whitespace, one level deeper after
    // an opener; if a closer is already on the next line, leave an empty body
    function indentOnEnter(line, next) {
        const indent = (line.match(/^[ \t]*/) || [""])[0];
        const extra = /[\{\[\(]\s*$/.test(line) ? win.indentUnit(indent) : "";
        if (extra && (next === "}" || next === "]" || next === ")"))
            return "\n" + indent + extra + "\n" + indent;
        return "\n" + indent + extra;
    }
    function handleAutoclose(e) {
        const t = edit.text, p = edit.cursorPosition, c = e.text;
        const a = edit.selectionStart, b = edit.selectionEnd;
        if (c.length === 1 && ")]}".indexOf(c) >= 0 && b === a && t.charAt(p) === c) {
            // stepping over an auto-inserted closer must not stack another one
            edit.cursorPosition = p + 1;
            e.accepted = true;
            return true;
        }
        if (c.length === 1 && "([{\"'".indexOf(c) >= 0) {
            const close = closeOf(c);
            if (b > a) {
                // wrap the selection instead of throwing it behind the pair
                edit.insert(b, close);
                edit.insert(a, c);
                edit.select(a + 1, b + 1);
            } else {
                edit.insert(p, c + close);
                edit.cursorPosition = p + 1;
            }
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
            const ins = win.indentOnEnter(t.slice(lineStart, p), t.charAt(p));
            const bodyEnd = ins.indexOf("\n", 1);   // caret stops before a pre-existing closer
            edit.insert(p, ins);
            edit.cursorPosition = p + (bodyEnd >= 0 ? bodyEnd : ins.length);
            e.accepted = true;
            return true;
        }
        return false;
    }

    // ---- Markdown preview: a dependency-free subset, rendered as plain rows ---
    // Escaped first so a document can never inject its own tags. Links are last
    // so emphasis inside their label is handled, and their href stays escaped.
    function markdownInline(s) {
        let out = String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
        out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
        out = out.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
        out = out.replace(/(^|[^*])\*([^*]+)\*/g, "$1<i>$2</i>");
        out = out.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
        return out;
    }
    function mdRow(kind, html, extra) {
        const row = { kind: kind, html: html, level: 0, depth: 0, size: 1, mono: false };
        if (extra) for (const key in extra) row[key] = extra[key];
        return row;
    }
    // headings, paragraphs, -/* / 1. lists, quotes, fenced code, rules, blanks
    function markdownRows(text) {
        const rows = [];
        const lines = String(text).split("\n");
        let fenced = false;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (/^\s*```/.test(line)) {
                fenced = !fenced;
                rows.push(mdRow("blank", ""));
                continue;
            }
            if (fenced) { rows.push(mdRow("code", markdownInline(line), { mono: true, size: 0.92 })); continue; }
            if (line.trim() === "") { rows.push(mdRow("blank", "")); continue; }
            const heading = line.match(/^(#{1,6})\s+(.*)$/);
            if (heading) {
                const sizes = [1.7, 1.45, 1.25, 1.12, 1.04, 1];
                rows.push(mdRow("heading", markdownInline(heading[2]),
                                { level: heading[1].length, size: sizes[heading[1].length - 1], bold: true }));
                continue;
            }
            if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) { rows.push(mdRow("rule", "")); continue; }
            const bullet = line.match(/^(\s*)[-+*]\s+(.*)$/);
            if (bullet) {
                rows.push(mdRow("list", "• " + markdownInline(bullet[2]),
                                { depth: Math.min(4, Math.floor(bullet[1].length / 2)) }));
                continue;
            }
            const ordered = line.match(/^(\s*)(\d+)[.)]\s+(.*)$/);
            if (ordered) {
                rows.push(mdRow("list", ordered[2] + ". " + markdownInline(ordered[3]),
                                { depth: Math.min(4, Math.floor(ordered[1].length / 2)) }));
                continue;
            }
            const quote = line.match(/^\s*>\s?(.*)$/);
            if (quote) { rows.push(mdRow("quote", markdownInline(quote[1]))); continue; }
            rows.push(mdRow("para", markdownInline(line)));
        }
        return rows;
    }
    readonly property var previewRows: win.markdownPreview ? win.markdownRows(edit.text) : []
    // only local navigation targets: never hand a document's javascript: to the shell
    function openMarkdownLink(url) {
        if (/^(https?:\/\/|mailto:)/i.test(url)) Qt.openUrlExternally(url);
    }
    function toggleMarkdownPreview() {
        win.markdownPreview = !win.markdownPreview;
        if (!win.markdownPreview) edit.forceActiveFocus();
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
    // CorePad's one-click stamp: the current date and time at every cursor
    function insertDateTime() {
        win.insertAtCursors(Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm"));
        edit.forceActiveFocus();
    }
    function insertAtCursors(str) {
        // works with zero extra cursors too: insertDateTime() and callers must
        // not silently no-op when the person is editing with a single cursor
        if (str === "") return false;
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
    // an explicit choice on the document wins over extension / shebang detection
    readonly property string lang: TextDocs.current && TextDocs.current.syntax && TextDocs.current.syntax !== ""
        ? TextDocs.current.syntax
        : (TextDocs.current ? Highlight.langFor(TextDocs.current.path, TextDocs.current.text.substring(0, 120).split("\n")[0]) : "text")
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
    // Hand the whole document to the Teleprompter. The clipboard is the channel
    // (there is no shared service); the prompter reads and clears it on open.
    function present() {
        Quickshell.clipboardText = edit.text;
        Ui.teleprompter = true;
    }
    function closeTab(i) {
        if (TextDocs.docs[i].modified && win.confirmClose !== i) {
            win.confirmClose = i;
            confirmTimer.restart();
            return;
        }
        win.confirmClose = -1;
        // keep the doc object itself: its text, history and bookmarks survive,
        // so reopening is a true undo of the close (also for an unsaved tab)
        win.lastClosed = { index: i, doc: TextDocs.docs[i] };
        TextDocs.close(i);
    }
    function reopenTab() {
        const last = win.lastClosed;
        if (!last || !last.doc) return;
        win.lastClosed = null;
        const at = Math.min(last.index, TextDocs.docs.length);
        const list = TextDocs.docs.slice();
        list.splice(at, 0, last.doc);
        TextDocs.docs = list;
        TextDocs.show(at);
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
    // the clipboard hands the selection to the Dictionary; Ui.dictionary is the
    // same flag the shell's dictionaryOpen IPC sets (no the Ui singleton source file change needed)
    function lookUpWord() {
        const word = edit.selectedText.trim();
        if (word === "") return;
        Quickshell.clipboardText = word;
        Ui.dictionary = false;   // re-open so Dictionary re-reads the clipboard
        Qt.callLater(() => { Ui.dictionary = true; });
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
        // a chord's second key does not carry Ctrl (VS Code's Ctrl+K, X)
        if (win.chord !== "" && win.handleChord(e)) return true;
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
        if (!ctrl)
            return false;
        if (e.key === Qt.Key_K && !shift) { win.chord = "K"; chordTimer.restart(); return true; }
        if (e.key === Qt.Key_S) { if (shift) win.saveAs(); else win.save(); }
        else if (e.key === Qt.Key_Z) { if (shift) win.redo(); else win.undo(); }
        else if (e.key === Qt.Key_Y) win.redo();
        else if (e.key === Qt.Key_O) win.pick();
        else if (e.key === Qt.Key_R && shift) recentDialog.open();   // Ctrl+R is AppWindow's
        else if (e.key === Qt.Key_N) TextDocs.newDoc();
        else if (e.key === Qt.Key_W && shift) win.closeTab(TextDocs.active);   // Ctrl+W is AppWindow's
        else if (e.key === Qt.Key_T && shift) win.reopenTab();
        else if (e.key === Qt.Key_P && shift) win.present();
        else if (e.key === Qt.Key_Tab && TextDocs.docs.length > 1)
            TextDocs.show((TextDocs.active + (shift ? -1 : 1) + TextDocs.docs.length) % TextDocs.docs.length);
        else if ((e.key === Qt.Key_PageDown || e.key === Qt.Key_PageUp) && TextDocs.docs.length > 1)
            TextDocs.show((TextDocs.active + (e.key === Qt.Key_PageDown ? 1 : -1) + TextDocs.docs.length) % TextDocs.docs.length);
        else if (e.key === Qt.Key_F && !shift) { win.finding = true; win.replacing = false; findField.text = edit.selectedText; findField.input.forceActiveFocus(); }
        else if (e.key === Qt.Key_F && shift) win.openFindFiles();
        else if (e.key === Qt.Key_H) { win.finding = true; win.replacing = true; if (edit.selectedText !== "") findField.text = edit.selectedText; findField.input.forceActiveFocus(); }
        else if (e.key === Qt.Key_B) win.toggleBookmark();
        else if (e.key === Qt.Key_G) win.openGoto();
        else if (e.key === Qt.Key_M && shift) win.toggleMarkdownPreview();
        else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) win.fontSize = Math.min(28, win.fontSize + 1);
        else if (e.key === Qt.Key_Minus) win.fontSize = Math.max(8, win.fontSize - 1);
        else if (e.key === Qt.Key_0) win.fontSize = 13;
        else if (e.key === Qt.Key_BracketRight || e.key === Qt.Key_BracketLeft) win.jumpBrace();
        else return false;
        return true;
    }
    // Escape leaves the find bar; the window is closed like any other (Mod+Q, its button)
    function leave() {
        win.chord = "";
        if (win.finding) {
            win.finding = false;
            edit.forceActiveFocus();
        } else if (TextDocs.docs.length <= 1) {
            win.requestClose();   // the unsaved-work guard must not be bypassed
        }
    }

    // ---- project folder ---------------------------------------------------------
    // FileDirectory is the shell's own watched listing, already used by the file
    // chooser: the sidebar sees files made elsewhere without a manual refresh.
    FileDirectory { id: dirModel; path: TextDocs.folder }

    function pickFolder() {
        FilePicker.open({ mode: "folder", title: "Open a project folder",
                          startPath: TextDocs.folder || "",
                          onPicked: paths => { if (paths.length) win.openFolder(paths[0]); } });
    }
    function openFolder(path) { TextDocs.folder = path; win.sidebarOpen = true; }
    function openSidebarEntry(e) {
        if (!e) return;
        if (e.isDir) TextDocs.folder = e.path;
        else TextDocs.open(e.path);
    }

    // ---- find in files ----------------------------------------------------------
    // grep is given its arguments directly (no shell string), so a query with
    // spaces or quotes cannot become a command. -F keeps the query literal.
    Process {
        id: fileSearch
        stdout: SplitParser {
            onRead: line => {
                const m = String(line).match(/^([^:]+):(\d+):(.*)$/);
                if (!m || win.findFilesResults.length >= 200) return;
                win.findFilesResults = win.findFilesResults.concat([
                    { path: m[1], line: parseInt(m[2], 10), text: m[3] }
                ]);
            }
        }
        onExited: win.findingFiles = false
    }
    function findInFiles(q) {
        win.findFilesQuery = q;
        win.findFilesResults = [];
        win.findingFiles = false;
        if (q.trim() === "" || TextDocs.folder === "") return;
        win.findingFiles = true;
        fileSearch.command = ["grep", "-rnIF", "--exclude-dir=.git", "-e", q, TextDocs.folder];
        fileSearch.running = true;
    }
    // open() resets goToLine from its argument, so carry the line in "+N path"
    function openResult(r) { TextDocs.open("+" + r.line + " " + r.path); }
    function openFindFiles() {
        win.findFilesOpen = true;
        findFilesField.text = win.findFilesQuery;
        findFilesField.input.forceActiveFocus();
    }

    // ---- syntax selection, brace jump, block indent -----------------------------
    function setSyntax(name) {
        if (TextDocs.active < 0) return;
        TextDocs.setSyntax(TextDocs.active, name || "");
        repaint.restart();
    }
    // Ctrl+] toggles between a bracket and the one it encloses
    function jumpBrace() {
        const p = win.matchBrace(edit.cursorPosition);
        if (p < 0) return false;
        edit.cursorPosition = p;
        return true;
    }
    // Tab / Shift+Tab on selected lines indents or unindents the whole block
    function indentSelection(outward) {
        const t = edit.text, a = edit.selectionStart, b = edit.selectionEnd;
        if (b <= a) return false;
        const first = t.lastIndexOf("\n", a - 1) + 1;
        let last = t.indexOf("\n", b);
        if (last < 0) last = t.length;
        const block = t.substring(first, last);
        let delta = 0;
        const changed = block.split("\n").map(line => {
            if (outward) {
                const m = line.match(/^ {1,4}/);
                if (!m) return line;
                delta -= m[0].length;
                return line.substring(m[0].length);
            }
            delta += 4;
            return "    " + line;
        }).join("\n");
        if (changed === block) return false;
        win.loading = true;
        edit.text = t.substring(0, first) + changed + t.substring(last);
        edit.select(Math.max(first, a + delta), Math.min(edit.text.length, b + delta));
        win.loading = false;
        TextDocs.setText(edit.text);
        repaint.restart();
        return true;
    }

    // ---- two-key chords (Ctrl+K, then a letter) ---------------------------------
    function handleChord(e) {
        if (win.chord !== "K") return false;
        win.chord = "";
        chordTimer.stop();
        if (e.key === Qt.Key_O) win.pickFolder();
        else if (e.key === Qt.Key_F) win.openFindFiles();
        else if (e.key === Qt.Key_B) win.sidebarOpen = !win.sidebarOpen;
        else if (e.key === Qt.Key_D) win.splitView = !win.splitView;
        else if (e.key === Qt.Key_L) syntaxDialog.open();
        else return false;
        e.accepted = true;
        return true;
    }
    Timer { id: chordTimer; interval: 2500; onTriggered: win.chord = "" }

    function retryOpen() { if (TextDocs.lastPath !== "") TextDocs.open(TextDocs.lastPath); }
    function dismissError() { TextDocs.error = ""; }

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
                            visible: win.activeGroup === "" || TextDocs.groupOf(tab.modelData) === win.activeGroup
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

            // ---- tab groups: one chip per folder, filtering the tab strip ----
            RowLayout {
                Layout.fillWidth: true
                visible: TextDocs.groups().length > 1
                spacing: Theme.px(6)
                Repeater {
                    model: TextDocs.groups()
                    Choice {
                        required property var modelData
                        text: modelData === "Scratch" ? "Unsaved" : modelData.split("/").pop()
                        selected: win.activeGroup === modelData
                                  || (win.activeGroup === "" && modelData === TextDocs.groupOf(TextDocs.current))
                        onClicked: { win.activeGroup = modelData; TextDocs.showGroup(modelData); }
                    }
                }
                Button { text: "All tabs"; flat: true; checked: win.activeGroup === ""; onClicked: win.activeGroup = "" }
            }

            // ---- a failed open is a state with its own way out ------------------
            RowLayout {
                Layout.fillWidth: true
                visible: TextDocs.error !== ""
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    text: TextDocs.error
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Button { text: "Retry"; onClicked: win.retryOpen() }
                Button { text: "Dismiss"; flat: true; onClicked: win.dismissError() }
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

                // ---- project sidebar: the folder's files, watched live ----------
                Rectangle {
                    id: sidebar
                    visible: win.sidebarOpen
                    width: visible ? Theme.px(220) : 0
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    z: 3
                    color: Theme.surface1
                    border.width: 1
                    border.color: Theme.border
                    clip: true
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(6)
                        spacing: Theme.px(6)
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: TextDocs.folder.split("/").pop()
                                color: Theme.text
                                elide: Text.ElideMiddle
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                            IconButton { size: Theme.px(24); icon: "folder-open"; tip: "Open another folder"; onClicked: win.pickFolder() }
                            IconButton { size: Theme.px(24); icon: "window-close"; tip: "Hide sidebar"; onClicked: win.sidebarOpen = false }
                        }
                        TextField {
                            id: sidebarFilter
                            Layout.fillWidth: true
                            placeholder: "Filter files"
                            label: "Filter files"
                            onTextChanged: dirModel.query = text
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: dirModel.error !== ""
                            text: dirModel.error
                            color: Theme.danger
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: dirModel.error === "" && TextDocs.folder !== ""
                            model: dirModel.entries
                            clip: true
                            delegate: Item {
                                required property var modelData
                                width: ListView.view.width
                                height: Theme.px(26)
                                Accessible.role: Accessible.ListItem
                                Accessible.name: modelData.name + (modelData.isDir ? ", folder" : ", file")
                                Accessible.onPressAction: win.openSidebarEntry(modelData)
                                Rectangle { anchors.fill: parent; color: fileArea.containsMouse ? Theme.hover : "transparent" }
                                Text {
                                    anchors { left: parent.left; leftMargin: Theme.px(8); verticalCenter: parent.verticalCenter }
                                    width: parent.width - Theme.px(16)
                                    text: (modelData.isDir ? "▸ " : "  ") + modelData.name
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
                                MouseArea {
                                    id: fileArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: win.openSidebarEntry(modelData)
                                }
                            }
                        }
                        EmptyState {
                            visible: TextDocs.folder === "" && dirModel.error === ""
                            Layout.fillWidth: true
                            icon: "folder-open"
                            title: "No folder open"
                            subtitle: "Open a project folder to browse its files"
                            actionText: "Open folder"
                            onAction: win.pickFolder()
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: TextDocs.folder !== "" && dirModel.entries.count === 0 && !dirModel.loading && dirModel.error === ""
                            text: "No files here"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                }

                // line numbers: beside unwrapped text, where a line is a row
                Item {
                    id: gutter
                    visible: win.lineNumbers && !win.markdownPreview
                    width: visible ? numbers.implicitWidth + 16 : 0
                    anchors { left: sidebar.right; top: parent.top; bottom: parent.bottom }
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
                    visible: TextDocs.docs.length > 0 && !win.markdownPreview
                    anchors {
                        left: gutter.right; right: parent.right; top: parent.top; bottom: parent.bottom
                        margins: Theme.px(8); leftMargin: gutter.visible ? 0 : 8
                        rightMargin: rightAnchor.width + Theme.px(8)
                    }
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
                        font.family: win.fontFamily
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
                            if (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ControlModifier) && edit.selectionEnd > edit.selectionStart) {
                                if (win.indentSelection(!!(e.modifiers & Qt.ShiftModifier))) { e.accepted = true; return; }
                            }
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
                        onSelectedTextChanged: { if (!win.loading && !win.computingRects) win.saveCaret(); win.canDefine = edit.selectedText.trim() !== ""; }
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

                    // ---- right dock: split reading pane + line overview ---------
                    Item {
                        id: rightAnchor
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                        width: (splitPane.visible ? splitPane.width : 0) + (minimap.visible ? minimap.width : 0)
                        z: 3

                        // a mirrored reading pane of the same document; a click
                        // moves the primary caret, so one file can be read ahead
                        Rectangle {
                            id: splitPane
                            visible: win.splitView && TextDocs.docs.length > 0
                            width: visible ? Math.min(Theme.px(420), win.width * 0.4) : 0
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            color: Theme.surface1
                            border.width: 1
                            border.color: Theme.border
                            clip: true
                            Accessible.role: Accessible.EditableText
                            Accessible.name: "Split view"
                            Accessible.description: "A mirrored reading pane of this document"
                            Flickable {
                                id: mirrorFlick
                                anchors.fill: parent
                                anchors.margins: Theme.px(8)
                                contentWidth: mirror.width
                                contentHeight: mirror.height
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                contentY: flick.contentY
                                Text {
                                    id: mirror
                                    width: mirrorFlick.width
                                    text: win.coloured ? paint.text : edit.text
                                    textFormat: win.coloured ? Text.RichText : Text.PlainText
                                    color: Theme.text
                                    font: edit.font
                                    wrapMode: win.wordWrap ? Text.Wrap : Text.NoWrap
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const y = mouseY + mirrorFlick.contentY - Theme.px(8);
                                        const line = Math.max(1, Math.min(edit.lineCount,
                                            Math.floor(y / Math.max(1, edit.font.pixelSize * 1.6)) + 1));
                                        win.goToLine(line);
                                        edit.forceActiveFocus();
                                    }
                                }
                            }
                        }

                        // line overview: one tick per line (sampled on long files)
                        Item {
                            id: minimap
                            visible: win.lineNumbers && TextDocs.docs.length > 0
                            width: visible ? Theme.px(48) : 0
                            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                            Accessible.role: Accessible.List
                            Accessible.name: "Line overview"
                            Accessible.description: "Click a line to jump there"
                            Rectangle { anchors.fill: parent; color: Theme.surface1; border.width: 1; border.color: Theme.border }
                            Repeater {
                                model: Math.min(edit.lineCount, 120)
                                Rectangle {
                                    readonly property real frac: index / Math.max(1, edit.lineCount)
                                    readonly property int sample: Math.min(edit.lineCount - 1, Math.round(frac * edit.lineCount))
                                    x: 2
                                    y: frac * minimap.height
                                    width: Math.max(2, Math.min(minimap.width - 6, String(edit.text.split("\n")[sample] || "").length * 0.55))
                                    height: Math.max(1, minimap.height / Math.max(1, edit.lineCount) - 1)
                                    color: Theme.alpha(Theme.accent, 0.5)
                                }
                            }
                            Rectangle {
                                y: flick.contentHeight > 0 ? flick.contentY / flick.contentHeight * minimap.height : 0
                                width: minimap.width
                                height: flick.contentHeight > 0 ? Math.max(6, flick.height / flick.contentHeight * minimap.height) : minimap.height
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                                border.width: 1
                                border.color: Theme.accentLine
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    const line = Math.max(1, Math.min(edit.lineCount,
                                        Math.round(mouseY / Math.max(1, minimap.height) * edit.lineCount)));
                                    win.goToLine(line);
                                }
                            }
                        }
                    }
                }
                // ---- rendered Markdown: a mode switch over the same area -----
                Flickable {
                    id: mdFlick
                    visible: win.markdownPreview && TextDocs.docs.length > 0
                    focus: win.markdownPreview
                    activeFocusOnTab: true
                    anchors {
                        left: gutter.right; right: parent.right; top: parent.top; bottom: parent.bottom
                        margins: Theme.px(8); leftMargin: gutter.visible ? 0 : 8
                        rightMargin: rightAnchor.width + Theme.px(8)
                    }
                    contentWidth: mdColumn.width
                    contentHeight: mdColumn.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Accessible.role: Accessible.Document
                    Accessible.name: Tr.t("Markdown preview")
                    Accessible.description: Tr.t("Rendered view of the current document; Page Up and Page Down scroll")
                    Keys.onPressed: e => {
                        let dy = 0;
                        if (e.key === Qt.Key_PageDown) dy = height * 0.8;
                        else if (e.key === Qt.Key_PageUp) dy = -height * 0.8;
                        else if (e.key === Qt.Key_Down) dy = Theme.px(40);
                        else if (e.key === Qt.Key_Up) dy = -Theme.px(40);
                        else return;
                        contentY = Math.max(0, Math.min(contentHeight - height, contentY + dy));
                        e.accepted = true;
                    }
                    Column {
                        id: mdColumn
                        width: mdFlick.width
                        spacing: Theme.px(4)
                        Repeater {
                            model: win.previewRows
                            Item {
                                required property var modelData
                                width: mdColumn.width
                                readonly property int indent: modelData.depth * Theme.px(16)
                                height: modelData.kind === "blank" ? Theme.px(8)
                                      : modelData.kind === "rule" ? Theme.px(12)
                                      : rowText.implicitHeight + (modelData.kind === "code" || modelData.kind === "quote" ? Theme.px(12) : 0)
                                Rectangle {
                                    anchors.fill: parent
                                    visible: modelData.kind === "code" || modelData.kind === "quote"
                                    color: Theme.hover
                                    radius: Theme.radiusSmall
                                }
                                Rectangle {
                                    visible: modelData.kind === "quote"
                                    x: indent; y: Theme.px(4); width: 2; height: parent.height - Theme.px(8)
                                    color: Theme.accent
                                }
                                Rectangle {
                                    visible: modelData.kind === "rule"
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    height: 1
                                    color: Theme.border
                                }
                                Text {
                                    id: rowText
                                    anchors {
                                        left: parent.left; leftMargin: Theme.px(4) + indent
                                        right: parent.right; rightMargin: Theme.px(4)
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: modelData.html
                                    textFormat: Text.RichText
                                    wrapMode: Text.Wrap
                                    color: modelData.kind === "quote" ? Theme.dim : Theme.text
                                    font.family: modelData.mono ? Theme.mono : Theme.font
                                    font.pixelSize: win.fontSize * Theme.fontScale * modelData.size
                                    font.bold: !!modelData.bold
                                    Accessible.role: modelData.kind === "heading" ? Accessible.Heading : Accessible.StaticText
                                    Accessible.name: modelData.html.replace(/<[^>]*>/g, "")
                                    onLinkActivated: url => win.openMarkdownLink(url)
                                }
                            }
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

    // ---- open recent / quick switcher --------------------------------------------
    Dialog {
        id: recentDialog
        anchors.centerIn: parent
        width: Math.min(win.width * 0.7, Theme.px(460))
        height: Math.min(win.height * 0.7, Theme.px(420))
        title: "Open recent"
        modal: false
        standardButtons: Dialog.Close
        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(8)
            TextField {
                id: recentFilter
                Layout.fillWidth: true
                placeholder: "Filter recent files"
                label: "Filter recent files"
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: TextDocs.recentFiles.filter(p => recentFilter.text === "" || p.toLowerCase().indexOf(recentFilter.text.toLowerCase()) >= 0)
                delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: Theme.px(30)
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData
                    Accessible.onPressAction: win.openRecent(modelData)
                    Text {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        anchors.leftMargin: Theme.px(8)
                        text: modelData
                        color: Theme.text
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { win.openRecent(modelData); recentDialog.close(); }
                    }
                }
            }
            EmptyState {
                visible: TextDocs.recentFiles.length === 0
                Layout.fillWidth: true
                icon: "document-open-recent"
                title: "No recent files"
                subtitle: "Files you open show up here"
            }
        }
    }

    // ---- find in files -----------------------------------------------------------
    Dialog {
        id: findFilesDialog
        anchors.centerIn: parent
        width: Math.min(win.width * 0.8, Theme.px(560))
        height: Math.min(win.height * 0.75, Theme.px(460))
        title: "Find in files"
        modal: false
        standardButtons: Dialog.Close
        onOpened: findFilesField.input.forceActiveFocus()
        onClosed: win.findFilesOpen = false
        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: findFilesField
                    Layout.fillWidth: true
                    placeholder: "Search the project folder"
                    label: "Find in files"
                    onAccepted: win.findInFiles(text)
                }
                Button { text: "Search"; onClicked: win.findInFiles(findFilesField.text) }
            }
            Text {
                Layout.fillWidth: true
                visible: TextDocs.folder === ""
                text: "Open a project folder first (Ctrl+K, O)"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                visible: win.findingFiles
                text: "Searching…"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: TextDocs.folder !== "" && win.findFilesResults.length > 0
                clip: true
                model: win.findFilesResults
                delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: Theme.px(40)
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.text + ", " + modelData.path + ", line " + modelData.line
                    Accessible.onPressAction: win.openResult(modelData)
                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.px(8) }
                        Text {
                            text: modelData.text
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        Text {
                            text: modelData.path + ":" + modelData.line
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { win.openResult(modelData); findFilesDialog.close(); }
                    }
                }
            }
            EmptyState {
                visible: TextDocs.folder !== "" && !win.findingFiles && win.findFilesQuery !== "" && win.findFilesResults.length === 0
                Layout.fillWidth: true
                icon: "edit-find"
                title: "Not found"
                subtitle: "No matches in this folder"
            }
        }
    }

    // ---- syntax language override -------------------------------------------------
    Dialog {
        id: syntaxDialog
        anchors.centerIn: parent
        width: Math.min(win.width * 0.5, Theme.px(340))
        title: "Syntax language"
        modal: true
        standardButtons: Dialog.Close
        onOpened: syntaxCombo.currentIndex = Math.max(0, win.syntaxes.indexOf(win.lang))
        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)
            Text {
                Layout.fillWidth: true
                text: "Highlight as"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            ComboBox {
                id: syntaxCombo
                Layout.fillWidth: true
                model: win.syntaxes
                Accessible.name: "Syntax language"
                onActivated: i => win.setSyntax(win.syntaxes[i])
            }
            Button {
                text: "Automatic (from file type)"
                flat: true
                onClicked: { win.setSyntax(""); syntaxDialog.close(); }
            }
        }
    }

    // ---- editor font picker ------------------------------------------------------
    Dialog {
        id: fontDialog
        anchors.centerIn: parent
        width: Math.min(win.width * 0.6, Theme.px(380))
        title: Tr.t("Editor font")
        modal: true
        standardButtons: Dialog.Close
        onOpened: fontCombo.currentIndex = win.fontFamily === Theme.mono ? 0 : Math.max(0, win.fontFamilies.indexOf(win.fontFamily))
        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)
            Text {
                Layout.fillWidth: true
                text: Tr.t("Font family")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            ComboBox {
                id: fontCombo
                Layout.fillWidth: true
                model: win.fontFamilies
                Accessible.name: Tr.t("Font family")
                onActivated: i => win.setFontFamily(i === 0 ? "" : win.fontFamilies[i])
            }
            Text {
                Layout.fillWidth: true
                text: "Aa Bb Cc 0123  { }  =>  var x = 1;" + (win.fontFamily === Theme.mono ? "" : "  ·  " + win.fontFamily)
                color: Theme.text
                font.family: win.fontFamily
                font.pixelSize: win.fontSize * Theme.fontScale
                wrapMode: Text.Wrap
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
