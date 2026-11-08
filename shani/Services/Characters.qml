pragma Singleton
// Searchable Unicode characters for the Characters panel (and the
// launcher's ":" prefix, which used to know only emoji).
//
// The table is built by bridge/characters.py: its emoji names come from
// /usr/share/unicode/emoji/emoji-test.txt when the unicode package is
// installed, and everything else comes from Python's unicodedata over a
// curated set of blocks (symbols, math, arrows, the Indic scripts,
// Greek, Cyrillic, …). The ucd tool was checked for and is not on this
// machine, so unicodedata — the same public Unicode data — is what
// serves the names here (see the script's header).
//
// Search runs in the script (the table is ~9k entries); a debounce
// keeps typing from spawning one process per key.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_CHARACTERS_TOOL") || "/usr/lib/shani-shell/characters.py"
    property var results: []        // [{ ch, name, cat, cp }], best first
    property bool loaded: false     // one answer has come back
    property string query: ""       // the last query asked for
    property string last: ""        // the char last copied (for the tests)

    function search(q) {
        query = String(q || "").trim();
        debounce.restart();
    }
    function browse() { search(""); }
    function copy(entry) {
        if (!entry || !entry.ch) return;
        Quickshell.clipboardText = entry.ch;
        last = entry.ch;
        Quickshell.execDetached(["notify-send", "-a", "Characters", entry.ch, entry.name || ""]);
    }
    Timer {
        id: debounce
        interval: 200
        onTriggered: {
            toolProc.query = root.query;
            toolProc.running = true;
        }
    }
    Process {
        id: toolProc
        property string query: ""
        command: ["python3", root.tool, "search", query, "--limit", "240"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.results = JSON.parse(text || "[]");
                } catch (e) {
                    root.results = [];
                }
                root.loaded = true;
            }
        }
    }
    Component.onCompleted: browse()
}
