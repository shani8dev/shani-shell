pragma Singleton
// After every screenshot (niri announces each on its event stream), a
// notification that can do something with it: annotate it (the configured tool),
// ask Chronoa about it (it looks at the picture with look_at_image), or copy the
// path. notify-send -A waits for the button pressed and prints its name.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string last: ""
    // the whole screen after a countdown (the OSD counts; it is gone before the shot)
    property int countdown: 0
    function later(seconds) {
        countdown = seconds;
        tick.restart();
    }
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) {
                stop();
                shoot.restart();
            }
        }
    }
    Timer { id: shoot; interval: 300; onTriggered: Quickshell.execDetached(["niri", "msg", "action", "screenshot-screen"]) }
    property string annTool: (Settings.loaded && Settings.data.screenshotAnnotationTool) || "satty"
    property bool canAnnotate: false
    property bool canSatty: false

    function offer(path) {
        last = path;
        if (Settings.data.screenshotCopyImage)
            Quickshell.execDetached(["sh", "-c", 'p="$1"; case "$p" in *.png) t=image/png;; *.jpg|*.jpeg) t=image/jpeg;; *.webp) t=image/webp;; *) t=image/png;; esac; wl-copy --type "$t" < "$p"', "sh", path]);
        // "default": a click on the notification itself opens the picture (Pantheon, GNOME)
        const args = ["notify-send", "-a", "Screenshot", "-i", path, "-A", "default=Open", "-A", "ask=Ask Chronoa", "-A", "share=Share…", "-A", "ocr=Copy text"];
        if (canAnnotate)
            args.push("-A", "annotate=Annotate");
        prompt.command = args.concat(["Screenshot saved", path.replace(Quickshell.env("HOME"), "~")]);
        prompt.running = true;
    }

    Process {
        id: prompt
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim();
                if (a === "default")
                    Quickshell.execDetached(["xdg-open", root.last]);
                else if (a === "annotate")
                    root.annotate();
                else if (a === "ask")
                    Chronoa.ask("I just took a screenshot. Look at it with look_at_image: " + root.last + "\nWhat is on it, and is there anything I should do?");
                else if (a === "share")
                    Share.open(root.last);
                else if (a === "ocr") {
                    ocr.command = ["sh", "-c", 'tesseract "$1" stdout 2>/dev/null | wl-copy', "sh", root.last];
                    ocr.running = true;
                }
            }
        }
    }
    Process { id: ocr }
    Process {
        running: true
        command: ["sh", "-c", "command -v " + root.annTool + " >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector { onStreamFinished: root.canAnnotate = text.trim() === "yes" }
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v satty >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector { onStreamFinished: root.canSatty = text.trim() === "yes" }
    }
    Timer {
        id: check
        interval: 100
        running: true
        repeat: false
        onTriggered: check.running = false
    }
    Connections {
        target: Niri
        function onScreenshotSaved(path) { root.offer(path); }
    }
    onAnnToolChanged: check.restart()
    function annotate() {
        // swappy edits PNG pictures only; a JPEG picture falls back to satty if available
        if (root.annTool === "swappy" && !root.last.endsWith(".png") && root.canSatty) {
            Quickshell.execDetached(["sh", "-c", 'command -v satty >/dev/null 2>&1 && exec satty --filename "$1" --output-filename "$1"; exec swappy -f "$1"', "sh", root.last]);
            return;
        }
        if (root.annTool === "swappy")
            Quickshell.execDetached(["swappy", "-f", root.last]);
        else
            Quickshell.execDetached(["satty", "--filename", root.last, "--output-filename", root.last]);
    }
}
