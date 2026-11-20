pragma Singleton
// Calibrating a touchscreen or a pen (Settings > Keyboard & input): the
// calibration in force is set aside (niri reads the device raw), four targets
// are shown on its screen (Modules/Calibrate), and where each touch landed gives
// the matrix (Common/Calibrate.js) - written as Settings' touchMatrix /
// tabletMatrix, which Services/InputConfig puts in niri's input config. Escape,
// or a target missed by more than a quarter of the screen, gives the old one back.
import Quickshell
import QtQuick
import qs.Common
import "../Common/Calibrate.js" as Cal

Singleton {
    id: root
    property string kind: ""              // "touch" | "tablet" while calibrating
    property var previous: []
    property var seen: []                 // where the targets were touched, so far
    readonly property var targets: Cal.targets
    readonly property int step: seen.length
    property string result: ""            // for the tests: "ok" | "cancelled" | "failed"
    readonly property string key: kind === "tablet" ? "tabletMatrix" : "touchMatrix"
    // the screen the device draws on (Settings' mapping), else the one in use
    readonly property string output: {
        const m = kind === "tablet" ? Settings.data.tabletOutput : Settings.data.touchOutput;
        return m && m[0] !== "@" ? m : (Niri.focusedOutput || "");
    }

    function start(k) {
        if (kind !== "") return;
        previous = Array.from(Settings.data[k === "tablet" ? "tabletMatrix" : "touchMatrix"] || []);
        Settings.data[k === "tablet" ? "tabletMatrix" : "touchMatrix"] = [];      // raw, while the targets are touched
        seen = [];
        result = "";
        kind = k;
    }
    // a touch on the overlay: x, y in fractions of its screen
    function touched(x, y) {
        if (kind === "") return;
        const t = targets[seen.length];
        if (Math.abs(x - t[0]) > 0.25 || Math.abs(y - t[1]) > 0.25) {
            cancel("failed");
            return;
        }
        seen = seen.concat([[x, y]]);
        if (seen.length < targets.length) return;
        const m = Cal.solve(seen.map((s, i) => ({ seen: s, target: targets[i] })));
        if (!m) { cancel("failed"); return; }
        Settings.data[key] = m;
        result = "ok";
        kind = "";
    }
    function cancel(why) {
        if (kind === "") return;
        Settings.data[key] = previous;
        result = why || "cancelled";
        kind = "";
    }
}
