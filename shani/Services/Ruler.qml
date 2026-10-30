pragma Singleton
// Ruler: freeze the screen and measure anything in pixels.
//
// Ported from voltkit's Screen Ruler (src/ruler.rs): take a full-screen
// screenshot, show it frozen full screen, drag to measure (width × height),
// Shift for a straight line, right-click to clear, Esc to close,
// Ctrl+C to copy the size. Measurements are in the screenshot's real pixels.
//
// Uses grim for the capture (niri offers wlr-screencopy) and wl-copy for
// the clipboard, matching the shell's other screen-capture paths.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property string phase: "idle"   // idle | capturing | ready | failed
    property string image: ""
    property string error: ""
    property real startX: 0
    property real startY: 0
    property real endX: 0
    property real endY: 0
    property real cursorX: 0
    property real cursorY: 0
    property bool hasStart: false
    property bool straight: false
    property real ratio: 1.0        // screenshot pixels per logical pixel
    property int screenW: 0
    property int screenH: 0

    // the measured size, in screenshot pixels
    readonly property int measuredW: hasStart && endX !== startX ? Math.round(Math.abs(endX - startX) * ratio) : 0
    readonly property int measuredH: hasStart && endY !== startY ? Math.round(Math.abs(endY - startY) * ratio) : 0

    function sizeLabel() {
        if (measuredW === 0 && measuredH === 0) return "";
        if (measuredH === 0) return measuredW + " px";
        if (measuredW === 0) return measuredH + " px";
        return measuredW + " × " + measuredH + " px";
    }

    function capture() {
        if (phase === "capturing" || phase === "ready")
            return;
        error = "";
        image = "";
        hasStart = false;
        startX = 0; startY = 0; endX = 0; endY = 0;
        phase = "capturing";
        root.image = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-ruler-" + Date.now() + ".png";
        grab.command = ["sh", "-c", 'grim "$1"', "sh", root.image];
        grab.running = true;
    }
    function close() {
        phase = "idle";
        image = "";
        hasStart = false;
        startX = 0; startY = 0; endX = 0; endY = 0;
    }
    function clear() {
        hasStart = false;
        startX = 0; startY = 0; endX = 0; endY = 0;
    }
    function copySize() {
        const t = sizeLabel();
        if (t === "")
            return;
        Quickshell.clipboardText = t;
        Quickshell.execDetached(["notify-send", "-a", "Screen Ruler", "Copied " + t]);
    }

    Process {
        id: grab
        onExited: function(code) {
            if (code !== 0) {
                root.phase = "failed";
                root.error = "Could not capture the screen";
                return;
            }
            root.phase = "ready";
        }
    }
}
