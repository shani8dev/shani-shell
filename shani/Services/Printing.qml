pragma Singleton
// What the printer is doing (CUPS): the jobs still queued, for the Island.
// Only asked while CUPS is there (its socket).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property int jobs: 0
    property string lastPrint: ""          // last file sent via printFile, for the tests
    property string lastError: ""          // why printFile refused a file, for the UI
    function openQueue() { Quickshell.execDetached(["sh", "-c", "command -v system-config-printer >/dev/null && exec system-config-printer; exec xdg-open http://localhost:631/jobs/"]); }
    // `lp` can only spool things it can render: PDFs, pictures and plain text.
    // FileActions calls printFile for its catch-all "other" kind too, which
    // would hand a .zip/.deb/.iso to lp. No synchronous MIME probe exists here
    // (gio info is a Process), so allowlist the printable extensions by name.
    function printable(path) {
        const ext = (path.split("/").pop().split(".").pop() || "").toLowerCase();
        return ["pdf", "png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif", "avif",
                "txt", "text", "md", "log", "csv", "rtf", "html", "htm", "xml", "json"].indexOf(ext) >= 0;
    }
    // print one file (the PDF reader's print button): CUPS `lp` is the whole
    // backend — no print_file daemon to build — and lpstat above reports it.
    function printFile(path) {
        lastError = "";
        if (!path)
            return false;
        if (!printable(path)) {
            lastError = Tr.t("This file type cannot be printed");
            return false;
        }
        lastPrint = path;
        Quickshell.execDetached(["lp", "--", path]);
        return true;
    }
    // lpstat alone, its lines counted here (was sh + lpstat + grep: three programs a poll)
    Process {
        id: q
        command: ["lpstat", "-o"]
        stdout: StdioCollector { onStreamFinished: root.jobs = text.split("\n").filter(l => l.trim()).length }
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
