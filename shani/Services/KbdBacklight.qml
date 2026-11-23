pragma Singleton
// Keyboard backlight (the LED class device that brightnessctl exposes, e.g.
// tpacpi::kbd_backlight). Three positions, chosen in Settings > Keyboard &
// input: follow the room (auto), always on, always off. The tile in the
// sidebar is the quick way to flip it on or off by hand.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool available: false
    property string device: ""
    property int max: 0
    property int value: 0
    readonly property bool on: value > 0
    // no reason to burn while the screen is dimmed or the session is locked;
    // waking re-runs the mode, so auto re-reads the room and "on" uses the saved level
    readonly property bool resting: Lock.locked || Idle.dimmed
    Connections { target: Lock; function onLockedChanged() { root.applyRest(); } }
    Connections { target: Idle; function onDimmedChanged() { root.applyRest(); } }
    function applyRest() {
        if (!root.available) return;
        if (root.resting) root.setLevel(0);
        else root.apply();
    }

    // probe the device and its range
    Process {
        running: true
        command: ["sh", "-c", "brightnessctl -l 2>/dev/null | sed -n \"s/Device '\\''\\([^'\\'']*\\)'\\'' of class 'leds'.*/\\1/p\" | grep -iE 'kbd|keyboard' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = text.trim();
                if (!d) return;
                root.device = d;
                root.available = true;
                maxProc.command = ["brightnessctl", "-d", d, "-m"];
                maxProc.running = true;
            }
        }
    }
    Process {
        id: maxProc
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");
                if (f.length >= 4) {
                    root.value = parseInt(f[2]) || 0;
                    root.max = parseInt(f[3]) || 0;
                    root.apply();
                }
            }
        }
    }
    Process { id: setProc }

    function setLevel(v) {
        if (!root.available || !root.device) return;
        const level = Math.max(0, Math.min(root.max, v));
        // a light key or a late timer must not re-light a locked/dimmed session
        if (level > 0 && root.resting) return;
        setProc.command = ["brightnessctl", "-d", root.device, "set", String(level)];
        setProc.running = true;
        root.value = level;
    }
    // the keyboard's own light keys: a step up or down, kept as the level (and out
    // of "follow the room", which would undo it at the next look at the room)
    signal stepped()
    function step(dir) {
        if (!root.available || root.max <= 0)
            return;
        const next = Math.max(0, Math.min(root.max, root.value + dir));
        Settings.data.kbdBacklight = next > 0 ? "on" : "off";
        if (next > 0)
            Settings.data.kbdBacklightLevel = next;
        root.setLevel(next);
        root.stepped();
    }
    function toggle() {
        if (root.on) {
            Settings.data.kbdBacklight = "off";
            root.setLevel(0);
        } else {
            Settings.data.kbdBacklight = "on";
            const lvl = Settings.data.kbdBacklightLevel > 0 ? Settings.data.kbdBacklightLevel : (root.max > 0 ? root.max : 1);
            root.setLevel(lvl);
        }
        root.stepped();
    }

    // what "auto" means: dark room or night time → on; bright room or day → off
    function autoLevel() {
        const lux = AmbientLight.available ? AmbientLight.smoothLux : -1;
        const h = new Date().getHours();
        const night = h >= 19 || h < 7;
        if (lux >= 0) return lux < 40 ? root.max : 0;
        return night ? (root.max > 0 ? root.max : 1) : 0;
    }

    function apply() {
        if (!root.available) return;
        const mode = Settings.data.kbdBacklight || "auto";
        if (mode === "on") {
            const lvl = Settings.data.kbdBacklightLevel > 0 ? Settings.data.kbdBacklightLevel : (root.max > 0 ? root.max : 1);
            root.setLevel(lvl);
        }
        else if (mode === "off") root.setLevel(0);
        else root.setLevel(root.autoLevel());
    }

    // follow the room and the clock while in auto
    Timer {
        interval: 30000
        running: root.available
        repeat: true
        onTriggered: if ((Settings.data.kbdBacklight || "auto") === "auto") root.apply()
    }
    Connections {
        target: Settings.data
        function onKbdBacklightChanged() { root.apply(); }
        // Settings > Keyboard & input picks Dim/Medium/Bright/Full; without this
        // the choice was stored but the light did not change until a manual step
        function onKbdBacklightLevelChanged() { root.apply(); }
    }
    Connections { target: AmbientLight; function onSmoothLuxChanged() { if ((Settings.data.kbdBacklight || "auto") === "auto") root.apply(); } }
}
