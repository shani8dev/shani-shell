pragma Singleton
// After every screenshot (niri announces each on its event stream), a
// notification that can do something with it: annotate it (satty), ask
// Chronoa about it (it looks at the picture with look_at_image), or copy the
// path. notify-send -A waits for the button pressed and prints its name.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property string last: ""
    property bool canAnnotate: false

    function offer(path) {
        last = path;
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
                    Quickshell.execDetached(["satty", "--filename", root.last, "--output-filename", root.last]);
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
        command: ["sh", "-c", "command -v satty"]
        onExited: code => root.canAnnotate = code === 0
    }
    Connections {
        target: Niri
        function onScreenshotSaved(path) { root.offer(path); }
    }
}
