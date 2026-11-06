pragma Singleton
// "What's new" after an update: /etc/shani-version (what the update wrote)
// against the last version this shell has told the person about, kept in
// Quickshell state. A new version is told once — a notification whose
// "See everything" opens the shipped data/whats-new.md (a summary of
// FEATURES.md) — then recorded, so a restart never tells twice. A first
// install records silently. Event-driven: one read at startup (and when
// asked via `qs -c shani ipc call shani whatsNewCheck`), never a poll.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "WhatsNew.js" as WhatsNewLogic

Singleton {
    id: root
    property string currentVersion: ""       // from /etc/shani-version
    property string lastSeen: ""             // from state, loaded below
    property string shownVersion: ""         // the version last told about (for tests)
    property bool stateLoaded: false

    FileView {
        id: stateFile
        path: Quickshell.statePath("whats-new-last.txt")
        printErrors: false
        atomicWrites: true
        onLoaded: {
            root.lastSeen = WhatsNewLogic.parseVersion(text());
            root.stateLoaded = true;
            root.check();
        }
        onLoadFailed: { root.lastSeen = ""; root.stateLoaded = true; root.check(); }
    }

    function check() {
        if (!stateLoaded || !versionProc.running)
            versionProc.running = true;
    }

    Process {
        id: versionProc
        running: true
        command: ["sh", "-c", "cat /etc/shani-version 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = WhatsNewLogic.parseVersion(text);
                root.currentVersion = cur;
                const decision = WhatsNewLogic.shouldShow(cur, root.lastSeen);
                if (decision === "show") {
                    root.shownVersion = cur;
                    tell.running = true;
                }
                if (decision !== "none") {
                    root.lastSeen = cur;
                    stateFile.setText(cur);
                }
            }
        }
    }

    // the card: "See everything" opens the shipped summary (FEATURES.md,
    // shortened) in the default reader
    readonly property string notesPath: "/usr/share/shani/whats-new.md"
    function openNotes() {
        Quickshell.execDetached(["sh", "-c", 'for f in "$1" "$HOME/.config/quickshell/shani/../data/whats-new.md" "$HOME/Documents/shani/shani-shell/data/whats-new.md"; do [ -f "$f" ] && exec xdg-open "$f"; done', "sh", root.notesPath]);
    }
    Process {
        id: tell
        command: ["notify-send", "-a", "Updates", "-i", "software-update-available", "-A", "see=See everything",
                  "What's new in " + root.currentVersion, "A short tour of what this update brings. See everything for the full list."]
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "see") root.openNotes() }
    }
}
