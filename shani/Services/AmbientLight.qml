pragma Singleton
// Ambient light sensor brightness: read from the Linux ALS sysfs interface and
// adjust screen brightness automatically. Falls back to time-based adaptive
// brightness if no sensor is found. Manual overrides are respected.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool available: false
    property bool enabled: Settings.data.adaptiveBrightness
    property real lux: 0          // measured in lux
    property real targetBrightness: 0  // 0..1
    property real manualOverride: -1   // -1 = no override
    property string sensorPath: ""
    signal changedByUser()

    // Read lux from ALS sysfs (common paths)
    Process {
        id: probe
        running: true
        // IIO illuminance sensors (an LED's brightness is not a light reading)
        command: ["sh", "-c", "for path in /sys/bus/iio/devices/iio:device*/in_illuminance_input /sys/bus/iio/devices/iio:device*/in_illuminance_raw /sys/class/ambient_light/*; do [ -f \"$path\" ] && [ -r \"$path\" ] && echo \"$path\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = text.trim().split("\n").filter(p => p);
                if (paths.length > 0) {
                    root.sensorPath = paths[0];
                    root.available = true;
                    root.readLux();
                    // Start continuous reading
                    readInterval.restart();
                } else {
                    root.available = false;
                    // Fall back to time-based if no sensor
                    root.readTimeBased();
                }
            }
        }
    }

    Timer {
        id: readInterval
        interval: 5000
        running: root.available
        repeat: true
        onTriggered: root.readLux()
    }

    Timer {
        id: timeInterval
        interval: 60000
        running: !root.available
        repeat: true
        onTriggered: root.readTimeBased()
    }

    // Read current lux from sensor
    Process {
        id: luxReader
        command: ["cat", root.sensorPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseFloat(text.trim());
                if (!isNaN(val)) {
                    root.lux = val;
                    root.calculateBrightness();
                }
            }
        }
    }
    function readLux() {
        if (!root.sensorPath || !root.available)
            return;
        luxReader.running = true;
    }

    // Calculate target brightness from lux (typical curve: 50-500 lux = 0.5-1.0, 0-50 lux = 0.2-0.5)
    function calculateBrightness() {
        if (!root.available || root.manualOverride >= 0)
            return;

        // Clamp lux to reasonable range (0-1000 lux for calculation)
        const clampedLux = Math.max(0, Math.min(1000, root.lux));
        
        // Simple linear mapping with clamping
        let target = (clampedLux - 20) / 400;  // 20 lux = 0, 420 lux = 1
        target = Math.max(0.2, Math.min(1.0, target));
        
        root.targetBrightness = target;
        
        // Apply if enabled and not locked
        if (root.enabled && Brightness.available && Math.abs(Brightness.value - target) > 0.02) {
            Brightness.applyAuto(target);
        }
    }

    // Time-based adaptive brightness (fallback when no sensor)
    function readTimeBased() {
        if (root.available || !root.enabled || root.manualOverride >= 0)
            return;
        
        const h = new Date().getHours();
        // Daytime (6am-8pm): brighter, Nighttime (8pm-6am): dimmer
        let target = 0.5;
        if (h >= 6 && h < 9) target = 0.6;
        else if (h >= 9 && h < 17) target = 0.8;
        else if (h >= 17 && h < 20) target = 0.65;
        else if (h >= 20 && h < 22) target = 0.5;
        else target = 0.35;
        
        root.targetBrightness = target;
        
        if (root.enabled && Brightness.available && Math.abs(Brightness.value - target) > 0.02) {
            Brightness.applyAuto(target);
        }
    }

    // Manually set brightness override
    function setManualOverride(v) {
        root.manualOverride = v;
        if (v < 0) {
            root.manualOverride = -1;
            // Re-enable automatic after a delay if user hasn't manually adjusted
            manualTimeout.restart();
        }
    }

    Timer {
        id: manualTimeout
        interval: 30000  // 30 seconds after manual change, re-enable auto
        onTriggered: {
            if (root.manualOverride >= 0) {
                root.manualOverride = -1;
                // Re-read sensor or time-based
                if (root.available) {
                    root.readLux();
                } else {
                    root.readTimeBased();
                }
            }
        }
    }

    // Sync with Settings
    Connections {
        target: Settings.data
        function onAdaptiveBrightnessChanged() {
            root.enabled = Settings.data.adaptiveBrightness;
            if (root.enabled)
                root.available ? root.readLux() : root.readTimeBased();
        }
    }

    // Sync with Brightness changes
    Connections {
        target: Brightness
        function onValueChanged() {
            if (Brightness.automatic)
                return;          // our own adjustment, not the person's
            root.manualOverride = Brightness.value;
            manualTimeout.restart();
            root.changedByUser();
        }
    }

    // Initialize
    Component.onCompleted: {
        root.enabled = Settings.data.adaptiveBrightness;
    }
}
