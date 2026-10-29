pragma Singleton
// What the printer is doing (CUPS): the jobs still queued, for the Island.
// Only asked while CUPS is there (its socket), every few seconds.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property int jobs: 0
    function openQueue() { Quickshell.execDetached(["sh", "-c", "command -v system-config-printer >/dev/null && exec system-config-printer; exec xdg-open http://localhost:631/jobs/"]); }
    Process {
        id: q
        command: ["sh", "-c", '[ -S /run/cups/cups.sock ] || exit 0; lpstat -o 2>/dev/null | grep -c .']
        stdout: StdioCollector { onStreamFinished: root.jobs = parseInt(text.trim()) || 0 }
    }
    Timer { interval: 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: q.running = true }
}
