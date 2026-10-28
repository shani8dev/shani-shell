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
    onActiveChanged: if (active) read.running = true

    Process {
        id: read
        command: ["sh", "-c", 'for p in HandleLidSwitch HandleLidSwitchExternalPower HandlePowerKey; do
                busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager $p 2>/dev/null | sed "s/^s \\"\\(.*\\)\\"/\\1/"; done
            ls /proc/acpi/button/lid 2>/dev/null | head -1; [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ] && echo battery']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                page.lid = l[0] || "suspend";
                page.lidOnPower = l[1] || "suspend";
                page.powerKey = l[2] || "poweroff";
                page.hasLid = text.indexOf("LID") >= 0 || text.indexOf("battery") >= 0;
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

    SectionTitle { Layout.fillWidth: true; text: "Lid and power button" }
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
        visible: page.note !== ""
        text: page.note
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
