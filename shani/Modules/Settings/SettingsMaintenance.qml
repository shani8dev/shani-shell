// Settings > Maintenance: system space, a report to save, and factory reset.
// Cleaning and reset need administrator access; the tool asks for it, and this
// page says why before asking. No file's contents are ever shown here.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/ToolPath.js" as ToolPath

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property bool busy: false
    property bool cleaned: false
    property string reportPath: ""
    property bool resetDone: false
    property bool showReset: false
    property bool clearFiles: false
    property bool keepDownloads: true
    property string error: ""
    property string note: ""
    property bool noteOk: true
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_MAINTENANCE_TOOL"), "system_maintenance.py")

    onActiveChanged: if (active) { showReset = false; if (resetConfirm) resetConfirm.disarm(); publish(); }
    Component.onCompleted: if (active) publish()
    onBusyChanged: publish()

    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.maintenance = { cleaned: page.cleaned, report: page.reportPath, reset: page.resetDone, error: page.error };
        Ui.systemState = o;
    }
    function run(proc) { page.busy = true; page.note = ""; proc.running = true; publish(); }
    function saveReport(path) { copyProc.command = ["cp", "--", page.reportPath, path]; run(copyProc); }
    function reset() {
        page.busy = true; page.note = "";
        resetProc.payload = JSON.stringify({ home: page.clearFiles, keepDownloads: page.keepDownloads });
        resetProc.running = true; publish();
    }
    function openReportPicker() {
        FilePicker.open({ mode: "save", title: Tr.t("Save the report"),
            defaultName: page.reportPath.split("/").pop(), startPath: Quickshell.env("HOME") || "",
            onPicked: paths => { if (paths && paths.length) page.saveReport(paths[0]); } });
    }

    Process {
        id: cleanProc; command: ["python3", page.tool, "clean"]
        stdout: StdioCollector { onStreamFinished: {
            let r = {}; try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("Could not read the reply") }; }
            page.cleaned = !!r.ok; page.error = r.ok ? "" : String(r.error || Tr.t("Could not clean system space"));
            page.note = r.ok ? Tr.t("Old system files were removed") : page.error; page.noteOk = !!r.ok; publish();
        } }
        onExited: code => { if (code !== 0 && !page.cleaned) { page.error = Tr.t("Could not clean system space"); page.note = page.error; page.noteOk = false; } publish(); }
    }
    Process {
        id: reportProc; command: ["python3", page.tool, "report"]
        stdout: StdioCollector { onStreamFinished: {
            let r = {}; try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("Could not read the reply") }; }
            if (r.ok && r.path) { page.reportPath = String(r.path); page.error = ""; page.note = Tr.t("Report ready"); page.noteOk = true; }
            else { page.error = String(r.error || Tr.t("Could not make a report")); page.note = page.error; page.noteOk = false; }
            publish();
        } }
        onExited: code => { if (code !== 0 && page.reportPath === "") { page.error = Tr.t("Could not make a report"); page.note = page.error; page.noteOk = false; } publish(); }
    }
    Process {
        id: copyProc
        stderr: StdioCollector { id: copyErr }
        onExited: code => {
            page.note = code === 0 ? Tr.t("Report saved") : Tr.t("Could not save the report"); page.noteOk = code === 0;
            if (code !== 0) page.error = String(copyErr.text.trim().split("\n").pop() || Tr.t("Could not save the report"));
            publish();
        }
    }
    Process {
        id: resetProc; stdinEnabled: true; property string payload: ""
        stdout: StdioCollector { onStreamFinished: {
            let r = {}; try { r = JSON.parse(text) || {}; } catch (e) { r = { ok: false, error: Tr.t("Could not read the reply") }; }
            page.resetDone = !!r.ok; page.error = r.ok ? "" : String(r.error || Tr.t("Could not reset this computer"));
            page.note = r.ok ? Tr.t("Reset started. This computer will restart.") : page.error; page.noteOk = !!r.ok;
            if (r.ok) { page.showReset = false; resetPhrase.text = ""; } publish();
        } }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            if (code !== 0 && !page.resetDone) { page.error = Tr.t("Could not reset this computer"); page.note = page.error; page.noteOk = false; }
            publish();
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("System space")
        hint: Tr.t("Old update images and backups use system space. Cleaning them needs administrator access; your files are not touched.")
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            ConfirmButton {
                id: cleanConfirm
                implicitWidth: Theme.px(200); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                enabled: !page.busy; text: Tr.t("Clean system space"); armedText: Tr.t("Tap again to clean system space")
                kind: "danger"
                onConfirmed: run(cleanProc)
            }
            Item { Layout.fillWidth: true }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Report")
        hint: Tr.t("A bundle of the system's own reports. Save a copy where you want it; nothing private is shown here.")
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Working…"); iconSize: Theme.px(16) }
        ListRow {
            Layout.fillWidth: true; visible: page.reportPath !== ""
            icon: "text-x-generic"; title: Tr.t("Report ready"); subtitle: page.reportPath; interactive: false
        }
        EmptyState {
            Layout.fillWidth: true; visible: page.reportPath === "" && !page.busy
            icon: "text-x-generic"; title: Tr.t("No report yet")
            subtitle: Tr.t("Make one to keep a record of this computer's state.")
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            Button { text: Tr.t("Make a report"); enabled: !page.busy; busy: page.busy; onClicked: run(reportProc) }
            Button { visible: page.reportPath !== ""; text: Tr.t("Save a copy…"); enabled: !page.busy; onClicked: page.openReportPicker() }
            Item { Layout.fillWidth: true }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Reset this computer")
        hint: Tr.t("Returns the system to how it was when it was first set up. This cannot be undone.")
        Button { text: Tr.t("Reset…"); enabled: !page.busy && !page.showReset; onClicked: { page.showReset = true; publish(); } }
        ColumnLayout {
            Layout.fillWidth: true; visible: page.showReset; spacing: Theme.px(8)
            InfoBanner {
                Layout.fillWidth: true; tone: "warn"; title: Tr.t("Read this first")
                text: Tr.t("This removes the system's settings and apps. %1 %2").arg(
                    page.clearFiles ? Tr.t("Your files will be removed too.") : Tr.t("Your files stay."))
                    .arg(page.keepDownloads ? Tr.t("Downloads stay.") : Tr.t("Downloads will be removed."))
            }
            Picks {
                label: Tr.t("Your files"); current: page.clearFiles
                options: [{ label: Tr.t("Keep my files"), value: false }, { label: Tr.t("Clear my files too"), value: true }]
                onPicked: v => { page.clearFiles = v; publish(); }
            }
            Picks {
                label: Tr.t("Downloads"); current: page.keepDownloads
                options: [{ label: Tr.t("Keep downloads"), value: true }, { label: Tr.t("Clear downloads too"), value: false }]
                onPicked: v => { page.keepDownloads = v; publish(); }
            }
            TextField {
                id: resetPhrase; Layout.fillWidth: true
                placeholder: Tr.t("Type \"reset this computer\""); label: Tr.t("Confirmation phrase")
                onAccepted: if (resetConfirm.enabled) resetConfirm.trigger()
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Button { flat: true; text: Tr.t("Cancel"); onClicked: { page.showReset = false; resetConfirm.disarm(); resetPhrase.text = ""; publish(); } }
                ConfirmButton {
                    id: resetConfirm
                    implicitWidth: Theme.px(200); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    enabled: !page.busy && resetPhrase.text === "reset this computer"
                    text: Tr.t("Reset this computer"); armedText: Tr.t("Tap again to reset"); kind: "danger"
                    onConfirmed: page.reset()
                }
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Type the phrase exactly, then tap twice. Nothing happens until the second tap.")
                color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }
        }
    }

    InfoBanner { Layout.fillWidth: true; visible: page.note !== ""; tone: page.noteOk ? "ok" : "error"; text: page.note }
}
