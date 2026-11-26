// Settings > Firmware: devices already present and updates offered for them.
// Devices are read when the page opens; checking for updates uses the network,
// so it runs only when asked. Installing asks for authorisation itself.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import "../../Common/ToolPath.js" as ToolPath

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property bool busy: false
    property var devices: []
    property var updates: []
    property string applied: ""
    property string error: ""
    property string note: ""
    property bool noteOk: false
    property bool confirming: false
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_FIRMWARE_TOOL"), "system_firmware.py")

    onActiveChanged: if (active) { confirming = false; load(); }
    Component.onCompleted: if (active) load()
    onBusyChanged: publish()

    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.firmware = {
            devices: page.devices.map(d => d.name || d.id || ""),
            updates: page.updates.map(u => u.name || u.version || ""),
            applied: page.applied,
            error: page.error
        };
        Ui.systemState = o;
    }
    function load() { if (deviceProc) deviceProc.running = true; publish(); }
    function check() { page.busy = true; page.note = ""; updateProc.running = true; publish(); }
    function apply() { page.busy = true; page.note = ""; page.confirming = false; applyProc.running = true; publish(); }

    Process {
        id: deviceProc
        command: ["python3", page.tool, "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("Could not read devices") }; }
                page.devices = Array.isArray(r.devices) ? r.devices : [];
                page.error = r.error ? String(r.error) : "";
                if (page.error) { page.note = page.error; page.noteOk = false; }
                publish();
            }
        }
        onExited: code => { publish(); }
    }
    Process {
        id: updateProc
        command: ["python3", page.tool, "updates"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("Could not check for updates") }; }
                page.updates = Array.isArray(r.updates) ? r.updates : [];
                page.error = r.error ? String(r.error) : "";
                if (page.error) { page.note = page.error; page.noteOk = false; }
                else if (page.updates.length === 0) { page.note = Tr.t("No updates are offered"); page.noteOk = true; }
                publish();
            }
        }
        onExited: code => { if (code !== 0 && page.error === "") { page.error = Tr.t("Could not check for updates"); page.note = page.error; page.noteOk = false; } publish(); }
    }
    Process {
        id: applyProc
        command: ["python3", page.tool, "apply"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text) || {}; } catch (e) { r = { ok: false, error: Tr.t("Could not read the reply") }; }
                page.applied = r.ok ? "ok" : "error";
                page.error = r.ok ? "" : String(r.error || Tr.t("Could not install updates"));
                page.note = r.ok ? Tr.t("Updates installed") : page.error;
                page.noteOk = !!r.ok;
                publish();
            }
        }
        stderr: StdioCollector { id: applyErr }
        onExited: code => { if (code !== 0 && page.applied !== "ok") { page.applied = "error"; page.error = String(applyErr.text.trim().split("\n").pop() || Tr.t("Could not install updates")); page.note = page.error; page.noteOk = false; } publish(); }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Devices")
        hint: Tr.t("Devices are read as soon as this page opens. Checking for updates uses the network, so it runs only when you ask.")
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Working…"); iconSize: Theme.px(16) }
        Repeater {
            model: page.devices
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "computer"
                title: modelData.name || modelData.id || Tr.t("Device")
                subtitle: [modelData.vendor, modelData.version].filter(x => x).join("  ·  ")
                interactive: false
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: page.devices.length === 0 && !page.busy
            icon: "computer"
            title: Tr.t("No devices found")
            subtitle: Tr.t("The firmware tool did not report a device on this computer.")
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Updates offered")
        hint: Tr.t("These are the updates offered for the devices above.")
        Repeater {
            model: page.updates
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "software-update-available"
                title: modelData.name || modelData.version || Tr.t("Update")
                subtitle: [modelData.version, modelData.description].filter(x => x).join("  ·  ")
                interactive: false
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: page.updates.length === 0 && !page.busy
            icon: "software-update-available"
            title: Tr.t("Nothing to check yet")
            subtitle: Tr.t("Choose Check for updates to ask the network what is offered.")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Check for updates")
                enabled: !page.busy
                busy: page.busy
                onClicked: page.check()
            }
            ConfirmButton {
                id: installConfirm
                implicitWidth: Theme.px(160)
                implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                visible: page.updates.length > 0
                enabled: !page.busy
                text: Tr.t("Install updates")
                armedText: Tr.t("Tap again to install")
                kind: "danger"
                onConfirmed: { page.confirming = true; publish(); }
            }
            Item { Layout.fillWidth: true }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.confirming
            spacing: Theme.px(6)
            Text {
                Layout.fillWidth: true
                text: Tr.t("Keep the computer plugged in. If your disk unlocks by itself it will ask for its passphrase once after this — have it ready.")
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button { flat: true; text: Tr.t("Cancel"); onClicked: { page.confirming = false; installConfirm.disarm(); publish(); } }
                ConfirmButton {
                    implicitWidth: Theme.px(180)
                    implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    enabled: !page.busy
                    text: Tr.t("Install updates")
                    armedText: Tr.t("Tap again to install updates")
                    kind: "danger"
                    onConfirmed: page.apply()
                }
            }
        }
    }

    InfoBanner {
        Layout.fillWidth: true
        visible: page.note !== ""
        tone: page.noteOk ? "ok" : "error"
        text: page.note
    }
}
