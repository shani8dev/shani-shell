pragma Singleton
// Screen backlight and the flashlight LED, both through brightnessctl (the
// systemd-logind backlight path, so no root). Hidden when there is no device.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool available: false
    property real value: 0          // 0..1
    property string device: ""
    property string torch: ""       // LED class device named *flash* / *torch*
    property bool torchOn: false
    signal changedByUser()

    function set(v) {
        v = Math.max(0.01, Math.min(1, v));
        value = v;
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", Math.round(v * 100) + "%"]);
        changedByUser();
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
