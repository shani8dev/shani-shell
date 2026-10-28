pragma Singleton
// Quick notes in the sidebar (after Dux's notepad): one Markdown file,
// ~/Documents/Notes/quick.md, saved as you type — readable by any editor and
// by Chronoa.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string path: (Quickshell.env("XDG_DOCUMENTS_DIR") || Quickshell.env("HOME") + "/Documents") + "/Notes/quick.md"
    property string text: ""
    property bool loaded: false

    function set(t) {
        text = t;
        save.restart();
    }
    Timer {
        id: save
        interval: 600
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", root.path.substring(0, root.path.lastIndexOf("/"))]);
            file.setText(root.text);
        }
    }
    FileView {
        id: file
        path: root.path
        printErrors: false
        onLoaded: { root.text = text(); root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
}
