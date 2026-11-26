// Settings > System health: checks run on request, with every result shown in
// plain words. This page only reads; it does not change anything it reports.
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
    property var checks: []
    property string error: ""
    property string note: ""
    property bool noteOk: true
    property bool ranFromButton: false
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_HEALTH_TOOL"), "system_health.py")

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()
    onBusyChanged: publish()

    // the mark follows the result: passed, needs attention, failed, or just information
    function statusIcon(s) {
        const l = statusLabel(s);
        return l === Tr.t("Passed") ? "dialog-ok" : l === Tr.t("Needs attention") ? "dialog-warning"
             : l === Tr.t("Failed") ? "dialog-error" : "dialog-information";
    }
    function statusLabel(s) {
        const v = String(s || "").toLowerCase();
        if (["ok", "pass", "passed", "good", "healthy"].indexOf(v) >= 0) return Tr.t("Passed");
        if (["warn", "warning", "needs attention", "degraded"].indexOf(v) >= 0) return Tr.t("Needs attention");
        if (["fail", "failed", "error", "bad"].indexOf(v) >= 0) return Tr.t("Failed");
        return Tr.t("Information");
    }
    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.health = {
            checks: page.checks.map(c => (c.title || c.key || "") + ": " + page.statusLabel(c.status)),
            error: page.error
        };
        Ui.systemState = o;
    }
    function load() { page.busy = true; page.ranFromButton = false; if (listProc) listProc.running = true; publish(); }
    function run() { page.busy = true; page.note = ""; page.ranFromButton = true; if (listProc) listProc.running = true; publish(); }

    Process {
        id: listProc
        command: ["python3", page.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("Could not read the checks") }; }
                page.checks = Array.isArray(r.checks) ? r.checks : [];
                page.error = r.error ? String(r.error) : "";
                if (page.error) {
                    page.note = page.error;
                    page.noteOk = false;
                } else if (page.ranFromButton) {
                    page.note = Tr.t("Checks finished");
                    page.noteOk = true;
                }
                page.ranFromButton = false;
                publish();
            }
        }
        onExited: code => {
            if (code !== 0 && page.error === "") {
                page.error = Tr.t("Could not read the checks");
                page.note = page.error;
                page.noteOk = false;
            }
            publish();
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("System health")
        hint: Tr.t("Checks run when you ask for them. Nothing is changed while they run.")
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Run checks")
                kind: "primary"
                enabled: !page.busy
                busy: page.busy
                onClicked: page.run()
            }
            Item { Layout.fillWidth: true }
        }
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Running checks…"); iconSize: Theme.px(16) }
        Repeater {
            model: page.checks
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: page.statusIcon(modelData.status)
                title: modelData.title || modelData.key || Tr.t("Check")
                subtitle: [page.statusLabel(modelData.status), modelData.detail].filter(x => x).join("  ·  ")
                interactive: false
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: page.checks.length === 0 && !page.busy && page.error === ""
            icon: "dialog-ok"
            title: Tr.t("Nothing to report")
            subtitle: Tr.t("No checks were reported. Run them to see how this computer is doing.")
        }
    }

    InfoBanner {
        Layout.fillWidth: true
        visible: page.note !== ""
        tone: page.noteOk ? "ok" : "error"
        text: page.note
    }
}
