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
    spacing: Theme.px(10)
    property bool active: false
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property string lid: ""
    property string lidOnPower: ""
    property string powerKey: ""
    property bool hasLid: false
    property string note: ""
    property int limit: -1                // the battery's charge limit; -1: it has none
    // the battery's health: Settings > Power > Battery (SettingsBattery)
    onActiveChanged: if (active) { read.running = true; wakeRead.running = true; plRead.running = true; }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) { read.running = true; wakeRead.running = true; plRead.running = true; }

    // A handheld's chip power limit (Ananta OS's Gaming > Handheld): where the
    // kernel offers one (bridge/powerlimit.py), as steps across the firmware's
    // own range; set through shani-admin.py power-limit.
    property var powerLimit: null         // { method, min, max, current } or null
    readonly property string powerLimitTool: Quickshell.env("SHANI_POWERLIMIT_TOOL") || "/usr/lib/shani-shell/powerlimit.py"
    Process {
        id: plRead
        command: ["python3", page.powerLimitTool, "show"]
        stdout: StdioCollector { onStreamFinished: { try { page.powerLimit = JSON.parse(text); } catch (e) { page.powerLimit = null; } } }
    }
    readonly property var powerLimitSteps: {
        if (!powerLimit || powerLimit.max <= powerLimit.min) return [];
        const s = [];
        for (let i = 0; i < 5; i++) s.push(Math.round(powerLimit.min + (powerLimit.max - powerLimit.min) * i / 4));
        if (s.indexOf(powerLimit.current) < 0 && powerLimit.current >= powerLimit.min && powerLimit.current <= powerLimit.max) s.push(powerLimit.current);
        return s.filter((v, i) => s.indexOf(v) === i).sort((a, b) => a - b);
    }
    function savePowerLimit(watts) {
        if (writer.running) return;
        writer.requestedLimit = -1;
        writer.payload = JSON.stringify({ watts: watts });
        writer.command = adminCmd.concat(["power-limit"]);
        writer.stdinEnabled = true;
        writer.running = true;
    }

    // What can wake this computer from sleep (Ananta OS's "wake sources"): each
    // device's own kernel switch, listed by bridge/wakeup.py (no password) and
    // changed through shani-admin.py wakeup - now and at every boot.
    property var wakers: []               // [{ path, name, kind, enabled }]
    readonly property string wakeupTool: Quickshell.env("SHANI_WAKEUP_TOOL") || "/usr/lib/shani-shell/wakeup.py"
    Process {
        id: wakeRead
        command: ["python3", page.wakeupTool, "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.wakers = JSON.parse(text); } catch (e) { page.wakers = []; } }
        }
    }
    function saveWake(path, on) {
        if (writer.running) return;
        writer.requestedLimit = -1;
        writer.payload = JSON.stringify({ path: path, enabled: on });
        writer.command = adminCmd.concat(["wakeup"]);
        writer.stdinEnabled = true;
        writer.running = true;
    }

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
        id: writer
        stdinEnabled: true
        property string payload: ""
        property int requestedLimit: -1
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: text.trim() || "cancelled" }; }
                page.note = r.ok ? "" : r.error;
                if (r.ok && writer.requestedLimit > 0) Settings.data.batteryLimit = writer.requestedLimit;
                writer.requestedLimit = -1;
                read.running = true;
                wakeRead.running = true;
                plRead.running = true;
            }
        }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
    }
    function saveLimit(pct) {
        if (writer.running) return;
        writer.requestedLimit = pct;
        writer.payload = JSON.stringify({ percent: pct });
        writer.command = adminCmd.concat(["battery-limit"]);
        writer.stdinEnabled = true;
        writer.running = true;
    }
    function save(patch) {
        if (writer.running) return;
        writer.requestedLimit = -1;
        const req = Object.assign({ lid: lid, lidOnPower: lidOnPower, powerKey: powerKey }, patch);
        writer.payload = JSON.stringify(req);
        writer.command = adminCmd.concat(["power-keys"]);
        writer.stdinEnabled = true;
        writer.running = true;
    }

    // "Sleep" sleeps the way chosen below (it may be sleep-then-hibernate); hibernate where it works
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
        // until a choice is made here niri has the button and sleeps (its default,
        // logind's would power off); once made, niri lets logind have it (InputConfig)
        current: Settings.data.powerKeyByLogind ? page.powerKey : "suspend"
        onPicked: v => { Settings.data.powerKeyByLogind = true; Settings.touch("powerKeyByLogind"); page.save({ powerKey: v }); }
    }
    // the firmware accepts every integer 50-100, not just four named steps
    RowLayout {
        visible: page.limit > 0
        Layout.fillWidth: true
        spacing: Theme.px(8)
        Text {
            text: Tr.t("Stop charging at (keeps the battery healthy when mostly plugged in)")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(13) * Theme.fontScale
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        TextField {
            id: limitField
            Layout.preferredWidth: Theme.px(80)
            label: Tr.t("Charge limit in percent")
            placeholder: Tr.t("50 to 100")
            text: String(page.limit)
            input.validator: IntValidator { bottom: 50; top: 100 }
            input.onEditingFinished: {
                const v = parseInt(text, 10);
                if (v >= 50 && v <= 100 && v !== page.limit) page.saveLimit(v);
            }
        }
        Text { text: "%"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
    }
    Picks {
        visible: page.powerLimitSteps.length > 1
        label: Tr.t("Chip power limit - more watts, more speed in games; fewer, a cooler, quieter handheld that lasts longer")
        options: page.powerLimitSteps.map(w => ({ label: w + " W", value: String(w) }))
        current: page.powerLimit ? String(page.powerLimit.current) : ""
        onPicked: v => page.savePowerLimit(parseInt(v))
    }
    SectionTitle { Layout.fillWidth: true; visible: page.wakers.length > 0; text: Tr.t("What can wake this computer") }
    Repeater {
        model: page.wakers
        SwitchRow {
            required property var modelData
            Layout.fillWidth: true
            text: modelData.name
            hint: modelData.kind === "usb" ? Tr.t("A key or a click on it wakes the computer from sleep")
                : modelData.kind === "lid" ? Tr.t("Opening the lid wakes the computer from sleep")
                : Tr.t("A wake-up signal from another computer on the network wakes it")
            checked: modelData.enabled
            onToggled: on => page.saveWake(modelData.path, on)
        }
    }
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Lid & idle (logind)") }
    Text { Layout.fillWidth: true; text: Tr.t("Managed in /etc/systemd/logind.conf.d/50-shani-shell.conf. Values: suspend, lock, ignore, poweroff, hibernate, hybrid-sleep, suspend-then-hibernate."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    Repeater {
        model: ["HandleLidSwitch","HandleLidSwitchExternalPower","HandleLidSwitchDocked","IdleAction"]
        RowLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: Theme.px(6)
            Text { Layout.preferredWidth: Theme.px(220); text: modelData; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: lidVal; Layout.fillWidth: true; text: page.logind[modelData] || ""; placeholder: "suspend" }
            Button { text: Tr.t("Save"); onClicked: page.saveLogind(modelData, lidVal.text.trim()) }
        }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Text { Layout.preferredWidth: Theme.px(220); text: "IdleActionSec"; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: idleSec; Layout.fillWidth: true; text: page.logind["IdleActionSec"] || ""; placeholder: "300" }
        Button { text: Tr.t("Save"); onClicked: page.saveLogind("IdleActionSec", idleSec.text.trim()) }
    }

    Text {
        Layout.fillWidth: true
        visible: page.note !== ""
        text: page.note
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
}
