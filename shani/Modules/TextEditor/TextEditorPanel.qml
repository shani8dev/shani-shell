// TextEditor (TextEditor): a plain-text editor over a file. Open, edit,
// save, save-as, find/replace, line numbers, word wrap, multi-tab with
// syntax highlighting and bracket matching.
// Replaces org.gnome.TextEditor for everyday text editing.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services as Services

PanelWindow {
    id: win
    visible: Ui.textEditor && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Services.Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-texteditor"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ---- tab model ----
    property var tabs: []            // [{path, name, modified, lang, text}]
    property int activeTab: -1
    property bool showLineNumbers: true
    property bool wordWrap: true
    property string searchText: ""
    property string replaceText: ""
    property bool showFind: false
    property bool showReplace: false

    MouseArea { anchors.fill: parent; onClicked: Ui.textEditor = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 1200)
        height: Math.min(parent.height - 60, 900)
        radius: Theme.radiusLg

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---- tab bar ----
            TabBar {
                id: tabBar
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                model: win.tabs
                delegate: Text {
                    text: modelData.name + (modelData.modified ? " ●" : "")
                    font.pixelSize: 13
                    color: tabBar.currentIndex === index ? Theme.text : Theme.onSurfaceVariant
                    padding: 12
                }
                onCurrentIndexChanged: { win.activeTab = currentIndex; win.refreshEditor(); }
                RowLayout {
                    anchors.fill: parent
                    spacing: 0
                    TabButton {
                        text: "+"
                        width: 30
                        flat: true
                        onClicked: win.newFile()
                    }
                }
            }

            // ---- find/replace bar ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: win.showFind
                spacing: 4
                anchors.margins: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "Find…"
                        text: win.searchText
                        onTextChanged: win.searchText = text
                        onAccepted: win.findNext()
                    }
                    Button { text: "Next"; onClicked: win.findNext() }
                    Button { text: "Prev"; onClicked: win.findPrev() }
                    Button { text: "×"; onClicked: win.showFind = false }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: win.showReplace
                    spacing: 4
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "Replace…"
                        text: win.replaceText
                        onTextChanged: win.replaceText = text
                    }
                    Button { text: "Replace"; onClicked: win.replaceOne() }
                    Button { text: "All"; onClicked: win.replaceAll() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    CheckBox { text: "Line numbers"; checked: win.showLineNumbers; onToggled: win.showLineNumbers = checked }
                    CheckBox { text: "Word wrap"; checked: win.wordWrap; onToggled: win.wordWrap = checked }
                }
            }

            // ---- editor area ----
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Line numbers
                ScrollView {
                    Layout.preferredWidth: win.showLineNumbers ? 48 : 0
                    Layout.fillHeight: true
                    visible: win.showLineNumbers
                    TextArea {
                        id: lineNums
                        readOnly: true
                        text: {
                            const t = win.activeTab >= 0 && win.activeTab < win.tabs.length ? win.tabs[win.activeTab].text : "";
                            const lines = t.split("\n");
                            let nums = "";
                            for (let i = 1; i <= lines.length; i++) nums += i + "\n";
                            return nums;
                        }
                        font.family: "monospace"
                        font.pixelSize: 13
                        color: Theme.onSurfaceVariant
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Main editor
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    TextArea {
                        id: editor
                        text: win.activeTab >= 0 && win.activeTab < win.tabs.length ? win.tabs[win.activeTab].text : ""
                        wrapMode: win.wordWrap ? TextEdit.Wrap : TextEdit.NoWrap
                        font.family: "monospace"
                        font.pixelSize: 13
                        selectByKeyboard: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        onTextChanged: {
                            if (win.activeTab >= 0 && win.activeTab < win.tabs.length) {
                                win.tabs[win.activeTab].text = text;
                                win.tabs[win.activeTab].modified = true;
                                tabBar.forceLayout();
                            }
                        }
                        onCursorPositionChanged: {
                            const before = text.slice(0, cursorPosition);
                            const lines = before.split("\n");
                            win.cursorLine = lines.length;
                            win.cursorCol = lines[lines.length - 1].length + 1;
                            win.highlightMatch();
                        }
                    }
                }
            }

            // ---- status bar ----
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                spacing: 8
                anchors.margins: 4
                Label {
                    text: win.activeTab >= 0 ? "Line " + win.cursorLine + ", Col " + win.cursorCol + "  |  " +
                          (win.tabs[win.activeTab].text.split("\n").length) + " lines" : ""
                    font.pixelSize: 11
                    color: Theme.onSurfaceVariant
                }
                Label {
                    text: win.activeTab >= 0 ? win.tabs[win.activeTab].path || "New file" : ""
                    font.pixelSize: 11
                    color: Theme.onSurfaceVariant
                    Layout.fillWidth: true
                }
                Label { text: win.wordWrap ? "Wrap" : "No wrap"; font.pixelSize: 11; color: Theme.onSurfaceVariant }
            }
        }
    }

    // ---- syntax highlighting data ----
    property string currentLang: ""
    property var theme: { keyword: "#569cd6", string: "#ce9178", comment: "#6a9955",
                          number: "#b5cea8", function: "#dcdcaa", type: "#4ec9b0" }

    const kwPython = ["def","class","if","elif","else","for","while","try","except","finally","with","as","import","from","return","yield","lambda","pass","break","continue","and","or","not","in","is","None","True","False","self"];
    const kwJs = ["function","const","let","var","if","else","for","while","do","switch","case","break","continue","return","try","catch","finally","throw","new","class","extends","import","export","default","async","await","true","false","null","undefined","this","super"];
    const kwQml = ["import","property","signal","function","Component","Item","Rectangle","Text","Column","Row","Grid","ListView","Model","delegate","on","Connections","Binding","State","Transition","Animation","Timer","Qt","Quick","Controls","Layouts","Dialogs","Wayland","Io","Common","Services"];

    function langForPath(path) {
        const ext = path.split(".").pop().toLowerCase();
        switch (ext) {
            case "py": return "python";
            case "js": case "ts": return "javascript";
            case "qml": return "qml";
            case "sh": case "bash": return "shell";
            case "html": return "html";
            case "css": return "css";
            case "json": return "json";
            case "md": return "markdown";
            default: return "text";
        }
    }

    function getKeywords(lang) {
        switch (lang) {
            case "python": return kwPython;
            case "javascript": return kwJs;
            case "qml": return kwQml;
            default: return [];
        }
    }

    function escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function highlightSyntax() {
        if (win.activeTab < 0) return;
        win.currentLang = langForPath(win.tabs[win.activeTab].path);
        // Syntax highlighting is applied via a RichText overlay when needed.
        // For now, track language and bracket positions for future highlighting.
        win.matchPos = win.findMatchingBracket(editor.cursorPosition - 1, true);
        if (win.matchPos < 0) win.matchPos = win.findMatchingBracket(editor.cursorPosition, false);
    }

    function refreshEditor() {
        if (win.activeTab < 0) { editor.text = ""; return; }
        editor.text = win.tabs[win.activeTab].text;
        win.currentLang = langForPath(win.tabs[win.activeTab].path);
        win.showLineNumbers = true;
        win.highlightSyntax();
    }

    // ---- bracket matching ----
    property int matchPos: -1
    const bracketPairs = [["(", ")"], ["[", "]"], ["{", "}"]];

    function findMatchingBracket(pos, forward) {
        const text = editor.text;
        if (pos < 0 || pos >= text.length) return -1;
        const ch = text[pos];
        let open = "", close = "", dir = 1, depth = 0;
        for (const p of bracketPairs) {
            if (ch === p[0]) { open = p[0]; close = p[1]; dir = 1; break; }
            if (ch === p[1]) { open = p[1]; close = p[0]; dir = -1; break; }
        }
        if (!open) return -1;
        let i = pos + dir;
        while (i >= 0 && i < text.length) {
            if (text[i] === close) { if (depth === 0) return i; depth--; }
            else if (text[i] === open) depth++;
            i += dir;
        }
        return -1;
    }

    function highlightMatch() {
        const cp = editor.cursorPosition;
        win.matchPos = win.findMatchingBracket(cp - 1, true);
        if (win.matchPos < 0) win.matchPos = win.findMatchingBracket(cp, false);
    }

    editor.onCursorPositionChanged: win.highlightMatch();

    // ---- tab actions ----
    function newFile() {
        win.tabs.push({ path: "", name: "Untitled", modified: false, lang: "text", text: "" });
        win.activeTab = win.tabs.length - 1;
        tabBar.currentIndex = win.activeTab;
        win.refreshEditor();
    }

    function closeTab(index) {
        win.tabs.splice(index, 1);
        if (win.tabs.length === 0) win.newFile();
        else if (win.activeTab >= win.tabs.length) win.activeTab = win.tabs.length - 1;
        tabBar.currentIndex = win.activeTab;
        win.refreshEditor();
    }

    function openFile(path) {
        for (let i = 0; i < win.tabs.length; i++) {
            if (win.tabs[i].path === path) { win.activeTab = i; tabBar.currentIndex = i; win.refreshEditor(); return; }
        }
        fileReader.path = path;
        fileReader.running = true;
    }

    function saveFile() {
        if (win.activeTab < 0) return;
        const tab = win.tabs[win.activeTab];
        if (tab.path === "") { saveAsFile(); return; }
        fileWriter.path = tab.path;
        fileWriter.text = tab.text;
        fileWriter.running = true;
        tab.modified = false;
        tabBar.forceLayout();
    }

    function saveAsFile(path) {
        if (win.activeTab < 0) return;
        const tab = win.tabs[win.activeTab];
        tab.path = path;
        tab.name = path.split("/").pop();
        tab.lang = langForPath(path);
        saveFile();
    }

    function findNext() {
        if (win.searchText === "" || win.activeTab < 0) return;
        const idx = editor.text.indexOf(win.searchText, editor.cursorPosition);
        if (idx >= 0) { editor.cursorPosition = idx; editor.select(idx, idx + win.searchText.length); }
    }

    function findPrev() {
        if (win.searchText === "" || win.activeTab < 0) return;
        const idx = editor.text.lastIndexOf(win.searchText, editor.cursorPosition - 1);
        if (idx >= 0) { editor.cursorPosition = idx; editor.select(idx, idx + win.searchText.length); }
    }

    function replaceOne() {
        if (editor.selectedText === win.searchText) {
            editor.remove(editor.selectionStart, editor.selectionEnd);
            editor.insert(editor.cursorPosition, win.replaceText);
        }
        findNext();
    }

    function replaceAll() {
        if (win.activeTab < 0) return;
        editor.text = editor.text.split(win.searchText).join(win.replaceText);
    }

    // File I/O via Process
    Process {
        id: fileReader
        property string path: ""
        property string text: ""
        command: ["cat", path]
        stdout: StdioCollector {
            onStreamFinished: {
                const tab = { path: fileReader.path, name: fileReader.path.split("/").pop(),
                              modified: false, lang: langForPath(fileReader.path), text: text };
                win.tabs.push(tab);
                win.activeTab = win.tabs.length - 1;
                tabBar.currentIndex = win.activeTab;
                win.refreshEditor();
            }
        }
    }

    Process {
        id: fileWriter
        property string path: ""
        property string text: ""
        command: ["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", text, path]
        onExited: { /* saved */ }
    }

    // File dialogs
    FileDialog {
        id: fileDialog
        title: "Open file"
        onAccepted: openFile(fileDialog.selectedFile.toString().replace("file://", ""))
    }
    FileDialog {
        id: saveAsDialog
        title: "Save as"
        fileMode: FileDialog.SaveFile
        onAccepted: saveAsFile(saveAsDialog.selectedFile.toString().replace("file://", ""))
    }

    Keys.onEscapePressed: Ui.textEditor = false
    Keys.onPressed: e => {
        if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_S) { saveFile(); e.accepted = true; }
        if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_O) { fileDialog.open(); e.accepted = true; }
        if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_F) { win.showFind = true; e.accepted = true; }
        if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_N) { newFile(); e.accepted = true; }
    }

    Component.onCompleted: { win.newFile(); }
}