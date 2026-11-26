// Settings > System > Graphics: the cards, the driver bound to each, the render
// nodes a card offers and the OpenGL answer. About keeps the short summary;
// driver updates stay in Software. One read of system_machine.py answers both
// the graphics and the drivers questions.
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

    readonly property var devices: Array.isArray(page.report.devices) ? page.report.devices : []
    readonly property var render: Array.isArray(page.report.render) ? page.report.render : []

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.graphics = {
            devices: page.devices.map(d => String(d && d.name || "")),
            render: page.render.map(p => String(p || "")),
            gl: String(page.report.gl || "")
        };
        Ui.systemState = o;
    }
    function load() {
        page.busy = true;
        page.note = "";
        proc.command = ["python3", page.tool, "graphics"];
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
                page.publish();
            }
        }
        stderr: StdioCollector { id: errOut }
        onExited: code => {
            page.busy = false;
            page.noteOk = code === 0;
            if (code !== 0)
                page.note = errOut.text.trim().split("\n").pop() || Tr.t("Could not read the graphics cards");
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Graphics")
        hint: Tr.t("The cards this machine found, and the driver each one uses. About keeps the short summary; Software owns driver updates.")

        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Looking at the graphics cards…"); iconSize: Theme.px(16) }
        EmptyState {
            Layout.fillWidth: true
            visible: !page.busy && page.devices.length === 0 && page.note === ""
            icon: "video-display"
            title: Tr.t("No graphics card reported")
            subtitle: page.report.have && page.report.have.lspci === false
                ? Tr.t("The tool that lists cards is not installed")
                : Tr.t("No card was found in this machine")
        }
        Repeater {
            model: page.devices
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "video-display"
                title: String(modelData.name || Tr.t("Graphics card"))
                subtitle: [String(modelData.vendor || ""), modelData.driver
                    ? Tr.t("driver %1", String(modelData.driver)) : Tr.t("no driver bound")]
                    .filter(x => x !== "").join("  ·  ")
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Render nodes")
        hint: Tr.t("A card with no render node is present but unusable for drawing.")

        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "video-display"
            title: page.render.length ? page.render.join(", ") : Tr.t("No render node found")
            subtitle: page.render.length > 0 ? Tr.t("%1 nodes").arg(page.render.length) : ""
        }
        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "application-x-executable"
            title: Tr.t("OpenGL")
            subtitle: String(page.report.gl || Tr.t("Not reported"))
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
