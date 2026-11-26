// Settings > System > Persistence: what this machine keeps when it switches
// systems. A service can be installed, disabled and blocked while its state
// still lives on — because the state is not in the system slot. Read-only:
// nothing here writes a file or changes a service.
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
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_MACHINE_TOOL"), "system_machine.py")
    property var report: ({})
    property bool busy: false
    property string note: ""
    property bool noteOk: true

    readonly property var mounts: Array.isArray(page.report.mounts) ? page.report.mounts : []
    readonly property var dataDirs: Array.isArray(page.report.data) ? page.report.data : []

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.persistence = {
            mounts: page.mounts.map(m => String(m && m.path || "")),
            data: page.dataDirs.map(d => String(d && d.path || ""))
        };
        Ui.systemState = o;
    }
    function load() {
        page.busy = true;
        page.note = "";
        proc.command = ["python3", page.tool, "persistence"];
        proc.running = false;
        proc.running = true;
    }
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = {}; }
                page.report = r && typeof r === "object" ? r : {};
                page.note = String(page.report.error || "");
                page.noteOk = page.note === "";
                page.publish();
            }
        }
        stderr: StdioCollector { id: errOut }
        onExited: code => {
            page.busy = false;
            if (code !== 0) {
                page.note = errOut.text.trim().split("\n").pop() || Tr.t("Could not read what is kept");
                page.noteOk = false;
                page.publish();
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Persistence")
        hint: Tr.t("A service can be installed, disabled and blocked while its state still lives on — because the state is not in the system slot.")

        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Reading what is kept…"); iconSize: Theme.px(16) }
        EmptyState {
            Layout.fillWidth: true
            visible: !page.busy && page.mounts.length === 0 && page.note === ""
            icon: "drive-harddisk"
            title: Tr.t("Nothing reported")
            subtitle: Tr.t("No kept locations were found for this machine.")
        }
        Repeater {
            model: page.mounts
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "drive-harddisk"
                title: String(modelData.path || Tr.t("Kept location"))
                subtitle: [String(modelData.source || ""), String(modelData.note || "")].filter(function (x) { return x !== ""; }).join("  ·  ")
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Kept across a slot switch")
        hint: Tr.t("These folders stay as they are when the other system starts.")
        Repeater {
            model: page.dataDirs
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "folder"
                title: String(modelData.path || Tr.t("Folder"))
                subtitle: String(modelData.size || "")
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Button { text: Tr.t("Check again"); enabled: !page.busy; busy: page.busy; onClicked: page.load() }
    }
    InfoBanner {
        Layout.fillWidth: true
        visible: page.note !== ""
        tone: page.noteOk ? "ok" : "error"
        text: page.note
    }
}
