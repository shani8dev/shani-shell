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
    // the battery's health: Settings > Power > Battery (SettingsBattery)
    onActiveChanged: if (active) read.running = true
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) read.running = true

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
                if (page.limit > 0) Settings.data.batteryLimit = page.limit;
            }
        }
    }
    Process {
        id: write
        stdinEnabled: true
        property string payload: ""
        property int requestedLimit: -1
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: text.trim() || "cancelled" }; }
                page.note = r.ok ? "" : r.error;
                if (r.ok && write.requestedLimit > 0) Settings.data.batteryLimit = write.requestedLimit;
                write.requestedLimit = -1;
                read.running = true;
            }
        }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
    }
    function saveLimit(pct) {
        if (write.running) return;
        write.requestedLimit = pct;
        write.payload = JSON.stringify({ percent: pct });
        write.command = adminCmd.concat(["battery-limit"]);
        write.stdinEnabled = true;
        write.running = true;
    }
    function save(patch) {
        if (write.running) return;
        write.requestedLimit = -1;
        const req = Object.assign({ lid: lid, lidOnPower: lidOnPower, powerKey: powerKey }, patch);
        write.payload = JSON.stringify(req);
        write.command = adminCmd.concat(["power-keys"]);
        write.stdinEnabled = true;
        write.running = true;
    }

    // "Sleep" sleeps the way chosen below (it may be sleep-then-hibernate); hibernate where it works
    readonly property bool sleepish: ["suspend", "suspend-then-hibernate", "hybrid-sleep"].indexOf(lid) >= 0
    readonly property var lidOptions: [{ label: Tr.t("Sleep"), value: Power.sleepVerb }]
        .concat(Power.canHibernate ? [{ label: Tr.t("Hibernate"), value: "hibernate" }] : [])
        .concat([{ label: Tr.t("Lock"), value: "lock" }, { label: Tr.t("Nothing"), value: "ignore" }, { label: Tr.t("Power off"), value: "poweroff" }])
    function shown(v) { return ["suspend", "suspend-then-hibernate", "hybrid-sleep"].indexOf(v) >= 0 ? Power.sleepVerb : v; }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Lid, power button and battery") }
    // how it sleeps: offered only where this machine can hibernate
    Picks {
        visible: Power.canSuspendThenHibernate || Power.canHybridSleep
        label: Tr.t("When it sleeps")
        options: [{ label: Tr.t("Just sleep"), value: "suspend" }]
            .concat(Power.canSuspendThenHibernate ? [{ label: Tr.t("Sleep, then hibernate after a while - saves the battery"), value: "suspend-then-hibernate" }] : [])
            .concat(Power.canHybridSleep ? [{ label: Tr.t("Sleep, with a copy on disk - safe from a power cut"), value: "hybrid-sleep" }] : [])
        current: Power.sleepVerb
        onPicked: v => {
            Settings.data.sleepStyle = v;
            // the lid's "Sleep" follows the choice (logind runs it, not the shell)
            const p = {};
            if (["suspend", "suspend-then-hibernate", "hybrid-sleep"].indexOf(page.lid) >= 0) p.lid = v;
            if (["suspend", "suspend-then-hibernate", "hybrid-sleep"].indexOf(page.lidOnPower) >= 0) p.lidOnPower = v;
            if (Object.keys(p).length) page.save(p);
        }
    }
    Picks { visible: page.hasLid; label: Tr.t("Closing the lid"); options: page.lidOptions; current: page.shown(page.lid); onPicked: v => page.save({ lid: v }) }
    Picks { visible: page.hasLid; label: Tr.t("Closing the lid while plugged in"); options: page.lidOptions; current: page.shown(page.lidOnPower); onPicked: v => page.save({ lidOnPower: v }) }
    Picks {
        label: Tr.t("Pressing the power button")
        options: [{ label: Tr.t("Power off"), value: "poweroff" }, { label: Tr.t("Sleep"), value: "suspend" }]
            .concat(Power.canHibernate ? [{ label: Tr.t("Hibernate"), value: "hibernate" }] : [])
            .concat([{ label: Tr.t("Lock"), value: "lock" }, { label: Tr.t("Nothing"), value: "ignore" }])
        current: page.powerKey
        onPicked: v => page.save({ powerKey: v })
    }
    Picks {
        visible: page.limit > 0
        label: Tr.t("Stop charging at (keeps the battery healthy when mostly plugged in)")
        options: [{ label: "60 %", value: "60" }, { label: "80 %", value: "80" }, { label: "90 %", value: "90" }, { label: Tr.t("Full"), value: "100" }]
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
