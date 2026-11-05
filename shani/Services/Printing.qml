pragma Singleton
// What the printer is doing (CUPS): the jobs still queued, for the Island.
// Only asked while CUPS is there (its socket).
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
    // every 3 s while a job is queued (the Island follows it), every 30 s
    // otherwise. This poll is the one that stays by design (measured: one
    // lpstat fork per 30 s, nothing while idle on a printer-less machine):
    // CUPS does offer IPP job notifications, but only to a subscription a
    // notifier daemon (cups-filters) holds — the shell would need that extra
    // daemon, and watching the spool directory instead would still miss
    // printer state changes (offline, out of paper). Not at all on a
    // computer with no printer - most of them - which is asked again every 10 min.
    property bool hasPrinters: false
    Process {
        id: printers
        command: ["sh", "-c", '[ -S /run/cups/cups.sock ] && lpstat -p 2>/dev/null | grep -q .']
        onExited: code => root.hasPrinters = code === 0
    }
    Timer { interval: 600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: printers.running = true }
    Timer { interval: root.jobs > 0 ? 3000 : 30000; running: root.hasPrinters; repeat: true; triggeredOnStart: true; onTriggered: q.running = true }
}
