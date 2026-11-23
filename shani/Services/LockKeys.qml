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
        id: discover
        running: true
        command: ["sh", "-c", 'for k in capslock numlock; do set -- "$0"/*::$k/brightness; [ -f "$1" ] && echo "$k $1"; done', root.dir]
        stdout: SplitParser {
            onRead: l => {
                const [k, p] = l.split(" ");
                if (k === "capslock") root.capsPath = p; else if (k === "numlock") root.numPath = p;
            }
        }
    }
    // a docked/unplugged keyboard changes the sysfs paths; re-glob slowly
    // Quickshell Process has no restart() - stop/start is the supported way
    Timer { interval: 5000; repeat: true; running: true; onTriggered: { discover.running = false; discover.running = true; } }
    FileView { id: capsFile; path: root.capsPath; printErrors: false; blockLoading: true }
    FileView { id: numFile; path: root.numPath; printErrors: false; blockLoading: true }
    // an unreadable LED is not "off" - that would fire a false OSD toggle
    function readLed(file, ledPath, key) {
        if (!ledPath) return false;
        file.reload();
        const v = parseInt(file.text(), 10);
        if (isNaN(v) || (v !== 0 && v !== 1)) return false;
        root[key] = v > 0;
        return true;
    }
    Timer {
        interval: 500
        repeat: true
        running: root.capsPath !== "" || root.numPath !== ""
        onTriggered: {
            const capsOk = root.readLed(capsFile, root.capsPath, "caps");
            const numOk = root.readLed(numFile, root.numPath, "num");
            if (capsOk || numOk) root.known = true;
        }
    }
}
