pragma Singleton
// Ambient light sensor brightness: read the IIO illuminance sensor the kernel
// exposes in sysfs and follow it. No sensor (most desktops, many laptops) or
// "adaptive" off: nothing runs — the person's brightness is theirs. A manual
// change while adaptive is on overrides for 30 s, then the sensor resumes.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool available: false
    property bool enabled: Settings.data.adaptiveBrightness
    property real lux: 0                // as read: noisy
    property real smoothLux: -1         // exponential average of readings
    property real targetBrightness: 0   // 0..1, from the smoothed lux
    property real manualOverride: -1    // >= 0: the person was last; a timer ends it
    property string sensorPath: ""

    // IIO illuminance only: an LED class file's "brightness" is what a light is
    // emitting, not what the room looks like — listing /sys/class/leds here
    // once drove a torch LED down as if it were a sensor reading.
    // SHANI_LUX_FILE gives the suite a sensor to drive.
    property string luxFile: Quickshell.env("SHANI_LUX_FILE")
    Process {
        id: probe
        running: true
        command: ["sh", "-c", luxFile ? "echo \"$0\"" : "for path in /sys/bus/iio/devices/iio:device*/in_illuminance_input /sys/bus/iio/devices/iio:device*/in_illuminance_raw /sys/class/ambient_light/*; do [ -f \"$path\" ] && [ -r \"$path\" ] && echo \"$path\"; done", luxFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = text.trim().split("\n").filter(p => p);
                root.sensorPath = paths[0] || "";
                root.available = root.sensorPath !== "";
                if (root.available && root.enabled)
                    root.readLux();
            }
        }
    }

    Process {
        id: luxReader
        command: ["cat", root.sensorPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseFloat(text.trim());
                if (isNaN(val))
                    return;
                root.lux = val;
                // Exponential smoothing (alpha 0.2): raw readings jitter by a
                // few percent between reads, and an unsmoothed stream hunting
                // around a threshold steps the backlight every read.
                root.smoothLux = root.smoothLux < 0 ? val : root.smoothLux * 0.8 + val * 0.2;
                root.apply();
            }
        }
    }
    Timer {
        interval: 5000
        running: root.available && root.enabled && root.manualOverride < 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readLux()
        // reading stops while the override is up: a stale sensor must not
        // fight the person's slider
    }
    function readLux() {
        if (!root.sensorPath || !root.available)
            return;
        luxReader.running = true;
    }

    // lux -> backlight. ~20 lx is a dim room, ~100 desk lamp, ~300 office,
    // 500+ near a window. Floor at 0.12: the panel must stay readable.
    function luxToLevel(v) {
        return Math.max(0.12, Math.min(1, (v - 15) / 385));
    }

    function apply() {
        if (root.manualOverride >= 0 || !root.enabled)
            return;
        const target = root.available ? luxToLevel(root.smoothLux) : timeLevel();
        if (Math.abs(Brightness.value - target) <= 0.05)
            return;     // already close: no step, no repost (same value does not re-emit)
        root.targetBrightness = target;
        if (Brightness.available)
            Brightness.applyAuto(target);
    }

    function timeLevel() {
        const h = new Date().getHours();
        if (h >= 9 && h < 17) return 0.8;      // working hours
        if (h >= 6 && h < 9) return 0.7;       // morning
        if (h >= 17 && h < 20) return 0.62;    // evening, dusk, indoors
        if (h >= 20 && h < 22) return 0.5;
        return 0.32;                           // night
    }

    // A person's change holds the sensor off for a while — one drag of the
    // quick settings' slider is consent to be left alone, not a master toggle.
    Timer {
        id: manualTimeout
        interval: 30000
        onTriggered: {
            if (root.manualOverride < 0)
                return;
            root.manualOverride = -1;
            if (root.available) root.readLux(); else root.apply();
        }
    }

    // Sync with Settings
    Connections {
        target: Settings.data
        function onAdaptiveBrightnessChanged() {
            root.enabled = Settings.data.adaptiveBrightness;
            if (root.enabled && !root.available) {
                root.smoothLux = -1;   // time path needs no history
                root.apply();
            } else if (root.enabled)
                root.readLux();
        }
    }
    Connections {
        target: Settings
        function onLoadedChanged() {
            root.enabled = Settings.data.adaptiveBrightness;
            if (root.enabled && !root.available) root.apply();
            else if (root.enabled) root.readLux();
        }
    }
    // a change the sensor did not make was the person: hold the sensor off
    Connections {
        target: Brightness
        function onValueChanged() {
            if (Brightness.automatic)
                return;
            root.manualOverride = Brightness.value;
            manualTimeout.restart();
        }
    }
}
