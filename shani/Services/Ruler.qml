pragma Singleton
// Ruler: freeze the screen and measure anything in pixels.
//
// Ported from Screen Ruler (src/ruler.rs): take a full-screen
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
    property real dpi: 0            // calibration from the panel; 0 = unknown -> px only

    // grim captures real pixels while the frozen image is shown in logical
    // coordinates: derive the ratio from the output we are drawing on instead
    // of leaving it at 1.0 (which made "real pixels" false on scaled screens).
    readonly property real outputScale: {
        const o = Displays.outputs.find(o => o.name === Niri.focusedOutput) || Displays.outputs[0];
        return o && o.scale > 0 ? o.scale : 1.0;
    }
    Component.onCompleted: { root.ratio = root.outputScale; }

    // calibration survives a restart; no file (or a bad one) keeps px-only
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/shani-shell/ruler.json"
    FileView {
        id: calib
        path: root.configPath
        printErrors: false
        onLoaded: {
            try {
                const n = Number((JSON.parse(text() || "{}") || {}).dpi);
                root.dpi = isFinite(n) && n > 0 ? n : 0;
            } catch (e) { root.dpi = 0; }
        }
    }
    function setDpi(v) {
        const n = Number(v);
        root.dpi = isFinite(n) && n > 0 ? n : 0;
        calib.setText(JSON.stringify({ dpi: root.dpi }));
    }
    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "${1%/*}"', "sh", root.configPath]
    }

    // the measured size, in screenshot pixels
    readonly property int measuredW: hasStart && endX !== startX ? Math.round(Math.abs(endX - startX) * ratio) : 0
    readonly property int measuredH: hasStart && endY !== startY ? Math.round(Math.abs(endY - startY) * ratio) : 0

    // physical units are opt-in: px stays the default until a DPI is calibrated
    function physLabel(w, h) {
        if (root.dpi <= 0) return "";
        const cm = v => (v / root.dpi * 2.54).toFixed(1);
        const inch = v => (v / root.dpi).toFixed(2);
        return h > 0 ? cm(w) + " × " + cm(h) + " cm / " + inch(w) + " × " + inch(h) + " in"
                     : cm(w) + " cm / " + inch(w) + " in";
    }
    function withUnits(px, w, h) {
        const phys = physLabel(w, h);
        return phys ? px + "  (" + phys + ")" : px;
    }
    function sizeLabel() {
        if (measuredW === 0 && measuredH === 0) return "";
        if (measuredH === 0) return withUnits(measuredW + " px", measuredW, 0);
        if (measuredW === 0) return withUnits(measuredH + " px", measuredH, 0);
        return withUnits(measuredW + " × " + measuredH + " px", measuredW, measuredH);
    }

    // with a second point there is a line: its real length and angle, whether
    // the drag was a rectangle diagonal or a free-angle Shift line
    readonly property bool hasSecond: hasStart && (endX !== startX || endY !== startY)
    readonly property int diagonalPx: hasSecond
        ? Math.round(Math.sqrt(Math.pow(endX - startX, 2) + Math.pow(endY - startY, 2)) * ratio) : 0
    readonly property real lineAngle: {
        if (!hasSecond) return 0;
        const a = Math.atan2(endY - startY, endX - startX) * 180 / Math.PI;
        return a < 0 ? a + 180 : a;               // 0..180, an undirected line
    }
    function lineLabel() {
        return hasSecond ? Tr.t("%1 px diagonal · %2°", diagonalPx, lineAngle.toFixed(1)) : "";
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
