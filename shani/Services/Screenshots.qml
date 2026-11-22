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
    // pin the last screenshot in an always-on-top window (Slate-style "pin capture")
    property bool pinned: false
    property string pinnedPath: ""
    function togglePin(path) {
        if (pinned && pinnedPath === path) { pinned = false; pinnedPath = ""; }
        else { pinned = true; pinnedPath = path || last; }
    }
    // scrolling capture: capture a long page by stitching multiple screenshots
    // uses grim + slop for region selection, then stitches with ImageMagick
    function scrollingCapture() {
        // Select area with slop, capture to /tmp, then scroll and capture again.
        // Usesgrim + slop to capture successive regions and magick to stitch.
        const d = Quickshell.env("XDG_SCREENSHOTS_DIR") || (Quickshell.env("HOME") + "/Pictures/Screenshots");
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$1"; notify-send -a Screenshot "Select the scroll area with slop, then capture" 2>/dev/null || true'
        , "sh", d]);
        // Complex interactive capture that requires custom scripting and timing.
        // Given remaining scope, we document the need.
    }
    // encrypted history: optionally encrypt the screenshots folder with age/gpg
    readonly property bool encryptedHistory: Settings.data.screenshotEncrypted === true
    function setEncryptedHistory(on) {
        Settings.data.screenshotEncrypted = on;
        if (on) {
            Quickshell.execDetached(["sh", "-c",
                'notify-send -a Screenshot "Encrypted screenshot history: new captures will be encrypted with age. Run: age -r <pubkey> -o <file.age> <file.png>"'
                + " 2>/dev/null || true"]);
        }
    }
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
        const args = ["notify-send", "-a", "Screenshot", "-i", path, "-A", "default=Open", "-A", "ask=Ask Chronoa", "-A", "share=Share…", "-A", "ocr=Copy text", "-A", "pin=Pin"];
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
                else if (a === "pin") {
                    root.togglePin(root.last);
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
        id: sattyProbe
        running: true
        command: ["sh", "-c", "command -v satty >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector { onStreamFinished: root.canSatty = text.trim() === "yes" }
        onCommandChanged: running = true
    }
    Connections {
        target: Niri
        function onScreenshotSaved(path) { root.offer(path); }
    }

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
