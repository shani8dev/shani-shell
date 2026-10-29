pragma Singleton
// Screen backlight and the flashlight LED, both through brightnessctl (the
// systemd-logind backlight path, so no root). Hidden when there is no device.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property bool available: false
    property real value: 0          // 0..1
    property string device: ""
    property string torch: ""       // LED class device named *flash* / *torch*
    property bool torchOn: false
    property bool adaptive: AmbientLight.available && AmbientLight.enabled
    signal changedByUser()

    // Use ambient light sensor if available, otherwise use time-based
    Connections {
        target: AmbientLight
        function onAvailableChanged() {
            root.adaptive = AmbientLight.available && AmbientLight.enabled;
        }
        function onEnabledChanged() {
            root.adaptive = AmbientLight.available && AmbientLight.enabled;
        }
    }

    // When AmbientLight is disabled, restore manual brightness
    Connections {
        target: AmbientLight
        function onEnabledChanged() {
            if (!AmbientLight.enabled && AmbientLight.available) {
                // Restore manual brightness value
                root.value = Math.max(0.2, Math.min(1.0, root.value));
            }
        }
    }

    // a change made by adaptive brightness, not by a person: no OSD, no override
    property bool automatic: false
    function applyAuto(v) {
        automatic = true;
        value = Math.max(0.01, Math.min(1, v));
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", Math.round(value * 100) + "%"]);
        automatic = false;
    }

    function set(v) {
        v = Math.max(0.01, Math.min(1, v));
        value = v;
        if (device !== "")
            Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", Math.round(v * 100) + "%"]);
        else if (ddc.length)                 // a desktop: the monitor itself, over DDC/CI
            setDdc(ddc[0].display, v);
        changedByUser();
    }

    // ---- monitors over DDC/CI (ddcutil; its udev rule lets the person reach
    // /dev/i2c-*). Slow — about a tenth of a second a command — so each
    // monitor's change waits for the slider to settle. ---------------------
    property var ddc: []                  // [{ display, model, value }]
    property var pending: ({})
    function setDdc(display, v) {
        pending[display] = Math.round(Math.max(0, Math.min(1, v)) * 100);
        ddc = ddc.map(m => m.display === display ? Object.assign({}, m, { value: v }) : m);
        ddcSettle.restart();
    }
    Timer {
        id: ddcSettle
        interval: 350
        onTriggered: {
            const args = Object.keys(root.pending).map(n => "ddcutil --noverify --display " + n + " setvcp 10 " + root.pending[n]).join("; ");
            root.pending = {};
            Quickshell.execDetached(["sh", "-c", args]);
        }
    }
    // "Display 1 … Monitor: DEL:DELL U2720Q:…" then each one's brightness (VCP 10)
    Process {
        id: ddcProbe
        running: true
        command: ["sh", "-c", 'command -v ddcutil >/dev/null || exit 0; ddcutil detect --terse 2>/dev/null | awk "/^Display/{n=\$2} /Monitor:/{split(\$0,a,\":\"); print n\"\t\"a[3]}" |
            while IFS="	" read -r n m; do v=$(ddcutil --display "$n" getvcp 10 --terse 2>/dev/null | awk "{print \$4\"/\"\$5}"); printf "%s\t%s\t%s\n" "$n" "$m" "$v"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                root.ddc = text.trim().split("\n").filter(l => l.split("\t").length === 3).map(l => {
                    const f = l.split("\t"), v = f[2].split("/");
                    return { display: f[0], model: f[1].trim() || "Monitor " + f[0], value: v.length === 2 && parseInt(v[1]) > 0 ? parseInt(v[0]) / parseInt(v[1]) : 0.5 };
                });
                if (root.device === "" && root.ddc.length) {
                    root.value = root.ddc[0].value;
                    root.available = true;
                }
            }
        }
    }
    function step(delta) {
        if (available)
            set(value + delta);
    }
    function toggleTorch() {
        if (torch === "")
            return;
        torchOn = !torchOn;
        Quickshell.execDetached(["brightnessctl", "-q", "-d", torch, "set", torchOn ? "100%" : "0"]);
    }

    // `brightnessctl -m -l`: one device per line, "name,class,cur,pct%,max".
    Process {
        id: probe
        running: true
        command: ["brightnessctl", "-m", "-l"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.trim().split("\n")) {
                    const f = line.split(",");
                    if (f.length < 5)
                        continue;
                    if (f[1] === "backlight" && root.device === "") {
                        root.device = f[0];
                        root.value = parseInt(f[2]) / Math.max(1, parseInt(f[4]));
                        root.available = true;
                    } else if (f[1] === "leds" && /flash|torch/i.test(f[0]) && root.torch === "") {
                        root.torch = f[0];
                        root.torchOn = parseInt(f[2]) > 0;
                    }
                }
            }
        }
    }
}
