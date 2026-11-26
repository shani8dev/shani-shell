// Settings > Background work: jobs set to run later and process priority, both
// read only. Interrupt spread lives under System health, the audit log under
// Security. The phone switches live in the Background app.
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

    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_BG_TOOL"), "system_background.py")
    property string topic: "schedules"
    property var topics: [
        { v: "schedules", label: Tr.t("Scheduled work") },
        { v: "priority", label: Tr.t("Process priority") }
    ]
    property var verbs: ["schedules", "priority"]
    property var results: ({})
    property int i: -1
    property bool busy: false

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function load() { page.i = -1; page.results = ({}); page.next(); }
    function next() {
        page.i++;
        if (page.i >= page.verbs.length) { page.busy = false; page.publish(); return; }
        page.busy = true;
        reader.verb = page.verbs[page.i];
        reader.command = ["python3", page.tool, reader.verb];
        reader.running = false;
        reader.running = true;
    }
    function obj(v) { return page.results[v] || {}; }
    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        const sch = page.obj("schedules");
        const pri = page.obj("priority");
        o.background = {
            schedules: sch.files || [],
            priority: { installed: pri.installed || "", active: pri.active || "" },
            topic: page.topic
        };
        Ui.systemState = o;
    }

    Process {
        id: reader
        property string verb: ""
        stdout: StdioCollector { id: readOut }
        // The shell's own reader pattern: read the collector after exit, then
        // start the next verb. Parsing in onStreamFinished raced the collector
        // and lost rows for fast commands.
        onExited: code => {
            let r = {};
            try { r = JSON.parse(readOut.text) || {}; } catch (e) { r = { error: Tr.t("This section could not be read") }; }
            const o = Object.assign({}, page.results); o[reader.verb] = r; page.results = o;
            page.publish();
            page.next();
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Background work")
        hint: Tr.t("Work this computer does on its own. Read only.")
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: page.topics
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.topic === modelData.v
                    onClicked: { page.topic = modelData.v; page.publish(); }
                }
            }
        }
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Reading…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: (page.obj(page.topic).error || "") !== ""
            tone: "error"
            text: page.obj(page.topic).error || ""
            accessibleRole: Accessible.AlertMessage
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: page.topic === "schedules"
        title: Tr.t("Scheduled work")
        hint: Tr.t("Jobs set to run at a time, with the account each one runs as. Your own jobs live in Services and timers.")
        EmptyState {
            visible: !page.busy && (page.obj("schedules").files || []).length === 0
            icon: "alarm-symbolic"; title: Tr.t("No scheduled jobs")
            subtitle: Tr.t("This computer has no system jobs set to run.")
        }
        Repeater {
            model: (page.obj("schedules").files || [])
            ColumnLayout {
                id: job
                required property var modelData
                Layout.fillWidth: true
                ListRow {
                    Layout.fillWidth: true
                    interactive: false
                    icon: "alarm-symbolic"
                    title: job.modelData.file || Tr.t("Job file")
                }
                Repeater {
                    model: job.modelData.lines || []
                    Text {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData
                        color: Theme.dim
                        wrapMode: Text.Wrap
                        font.family: Theme.mono
                        font.pixelSize: Theme.type("caption")
                    }
                }
            }
        }
        Button {
            Layout.fillWidth: true
            text: Tr.t("Open services and timers")
            onClicked: { Ui.closeAll(); Ui.servicesApp = true; }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: page.topic === "priority"
        title: Tr.t("Process priority")
        hint: Tr.t("Priority is set by each job when it starts, so it cannot be changed from this page.")
        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "preferences-system"
            title: Tr.t("Priority tool installed")
            subtitle: page.obj("priority").installed || Tr.t("not reported")
        }
        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "preferences-system"
            title: Tr.t("Priority tool running")
            subtitle: page.obj("priority").active || Tr.t("not running")
        }
        Text {
            Layout.fillWidth: true
            visible: (page.obj("priority").detail || "") !== ""
            text: page.obj("priority").detail || ""
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.mono
            font.pixelSize: Theme.type("caption")
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Phone and watch, with no window open")
        hint: Tr.t("Each one runs only while its switch is on. The grouped switches live in the Background app.")
        Button {
            text: Tr.t("Open the Background app")
            flat: true
            Accessible.name: Tr.t("Open the Background app with the grouped switches")
            onClicked: { Ui.closeAll(); Ui.backgroundServices = true; }
        }
    }
}
