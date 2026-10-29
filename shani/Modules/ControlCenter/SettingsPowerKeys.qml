// Settings > Power > Lid and power button: logind's own answer, read from it
// (no password), changed through bridge/shani-admin.py power-keys — a logind
// drop-in, your own password asked.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 10
    property bool active: false
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property string lid: ""
    property string lidOnPower: ""
    property string powerKey: ""
    property bool hasLid: false
    property string note: ""
    property int limit: -1                // the battery's charge limit; -1: it has none
    property string health: ""            // "87 % of new · 312 charge cycles"
    Process {
        running: page.active
        command: ["sh", "-c", 'b=$(upower -e 2>/dev/null | grep -m1 BAT) || exit 0; upower -i "$b" | sed -n "s/^ *capacity: *//p; s/^ *charge-cycles: *//p"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n").filter(x => x);
                const cap = l[0] ? Math.round(parseFloat(l[0])) + " % of its capacity when new" : "";
                const cyc = l[1] && l[1] !== "N/A" && parseInt(l[1]) > 0 ? parseInt(l[1]) + " charge cycles" : "";
                page.health = [cap, cyc].filter(x => x).join(" · ");
            }
        }
    }
    onActiveChanged: if (active) read.running = true

    Process {
        id: read
        command: ["sh", "-c", 'for p in HandleLidSwitch HandleLidSwitchExternalPower HandlePowerKey; do
                busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager $p 2>/dev/null | sed "s/^s \\"\\(.*\\)\\"/\\1/"; done
            ls /proc/acpi/button/lid 2>/dev/null | head -1; [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ] && echo battery
            f=$(ls /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -1); [ -n "$f" ] && echo "limit=$(cat "$f")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                page.lid = l[0] || "suspend";
                page.lidOnPower = l[1] || "suspend";
                page.powerKey = l[2] || "poweroff";
                page.hasLid = text.indexOf("LID") >= 0 || text.indexOf("battery") >= 0;
                const lim = /limit=(\d+)/.exec(text);
                page.limit = lim ? parseInt(lim[1]) : -1;
            }
        }
    }
    Process {
        id: write
        stdinEnabled: true
        property string payload: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: text.trim() || "cancelled" }; }
                page.note = r.ok ? "" : r.error;
                read.running = true;
            }
        }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
    }
    function saveLimit(pct) {
        write.payload = JSON.stringify({ percent: pct });
        write.command = adminCmd.concat(["battery-limit"]);
        write.stdinEnabled = true;
        write.running = true;
    }
    function save(patch) {
        const req = Object.assign({ lid: lid, lidOnPower: lidOnPower, powerKey: powerKey }, patch);
        write.payload = JSON.stringify(req);
        write.command = adminCmd.concat(["power-keys"]);
        write.stdinEnabled = true;
        write.running = true;
    }

    component Picks: ColumnLayout {
        id: picks
        property string label
        property var options: []
        property string current
        signal picked(string value)
        Layout.fillWidth: true
        spacing: 6
        Text { text: picks.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: picks.options
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: picks.current === modelData.value
                    onClicked: picks.picked(modelData.value)
                }
            }
        }
    }
    readonly property var lidOptions: [{ label: "Sleep", value: "suspend" }, { label: "Lock", value: "lock" }, { label: "Nothing", value: "ignore" }, { label: "Power off", value: "poweroff" }]

    SectionTitle { Layout.fillWidth: true; text: "Lid, power button and battery" }
    Picks { visible: page.hasLid; label: "Closing the lid"; options: page.lidOptions; current: page.lid; onPicked: v => page.save({ lid: v }) }
    Picks { visible: page.hasLid; label: "Closing the lid while plugged in"; options: page.lidOptions; current: page.lidOnPower; onPicked: v => page.save({ lidOnPower: v }) }
    Picks {
        label: "Pressing the power button"
        options: [{ label: "Power off", value: "poweroff" }, { label: "Sleep", value: "suspend" }, { label: "Lock", value: "lock" }, { label: "Nothing", value: "ignore" }]
        current: page.powerKey
        onPicked: v => page.save({ powerKey: v })
    }
    Text {
        Layout.fillWidth: true
        visible: page.health !== ""
        text: "Battery health: " + page.health
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Picks {
        visible: page.limit > 0
        label: "Stop charging at (keeps the battery healthy when mostly plugged in)"
        options: [{ label: "60 %", value: "60" }, { label: "80 %", value: "80" }, { label: "90 %", value: "90" }, { label: "Full", value: "100" }]
        current: String(page.limit)
        onPicked: v => page.saveLimit(parseInt(v))
    }
    Text {
        Layout.fillWidth: true
        visible: page.note !== ""
        text: page.note
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
