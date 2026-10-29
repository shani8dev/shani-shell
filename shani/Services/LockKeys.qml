pragma Singleton
// Caps Lock and Num Lock, for the OSD and the lock screen's "Caps Lock is on"
// (many laptops have no light for them). niri does not report them, so they are
// read where the kernel keeps the keyboards' LEDs: /sys/class/leds/*::capslock,
// a file read (no process) twice a second - only when such an LED exists.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string dir: Quickshell.env("SHANI_LEDS_DIR") || "/sys/class/leds"
    property string capsPath: ""
    property string numPath: ""
    property bool caps: false
    property bool num: false
    property bool known: false            // the first read is a value, not a change

    Process {
        running: true
        command: ["sh", "-c", 'for k in capslock numlock; do set -- "$0"/*::$k/brightness; [ -f "$1" ] && echo "$k $1"; done', root.dir]
        stdout: SplitParser {
            onRead: l => {
                const [k, p] = l.split(" ");
                if (k === "capslock") root.capsPath = p; else root.numPath = p;
            }
        }
    }
    FileView { id: capsFile; path: root.capsPath; printErrors: false; blockLoading: true }
    FileView { id: numFile; path: root.numPath; printErrors: false; blockLoading: true }
    Timer {
        interval: 500
        repeat: true
        running: root.capsPath !== "" || root.numPath !== ""
        onTriggered: {
            if (root.capsPath) { capsFile.reload(); root.caps = parseInt(capsFile.text()) > 0; }
            if (root.numPath) { numFile.reload(); root.num = parseInt(numFile.text()) > 0; }
            root.known = true;
        }
    }
}
