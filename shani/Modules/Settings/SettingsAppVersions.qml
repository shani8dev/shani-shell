// Settings > System > App versions: what is installed, from the three places
// that keep their own lists. Software still installs and updates; this page
// only reports. There is no total across the three kinds — they do not share a
// version or a unit of counting.
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
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_APPS_TOOL"), "system_apps.py")
    property var report: ({})
    property bool busy: false
    property string note: ""
    property bool noteOk: true

    property var flatpak: []
    property var snap: []
    property var os: []

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function normalise(list) {
        return (Array.isArray(list) ? list : []).map(function (a) {
            return typeof a === "string" ? { name: a, version: "" } : (a || {});
        });
    }
    function publish() {
        const row = a => ({ name: String(a.name || a.id || ""), version: String(a.version || "") });
        const o = Object.assign({}, Ui.systemState || {});
        o.appversions = {
            flatpak: page.flatpak.map(row),
            snap: page.snap.map(row),
            os: page.os.map(row)
        };
        Ui.systemState = o;
    }
    function load() {
        page.busy = true;
        page.note = "";
        proc.command = ["python3", page.tool, "list"];
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
                page.flatpak = page.normalise(page.report.flatpak);
                page.snap = page.normalise(page.report.snap);
                page.os = page.normalise(page.report.os);
                page.publish();
            }
        }
        stderr: StdioCollector { id: errOut }
        onExited: code => {
            page.busy = false;
            page.noteOk = code === 0;
            if (code !== 0)
                page.note = errOut.text.trim().split("\n").pop() || Tr.t("Could not list the apps");
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Apps from the app store")
        hint: Tr.t("Installed from the app store, with the version each one has.")
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Listing apps…"); iconSize: Theme.px(16) }
        EmptyState {
            Layout.fillWidth: true
            visible: !page.busy && page.flatpak.length === 0 && page.note === ""
            icon: "package"
            title: Tr.t("No apps from the store")
            subtitle: Tr.t("Nothing is installed from this source.")
        }
        Repeater {
            model: page.flatpak
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "package"
                title: String(modelData.name || modelData.id || Tr.t("App"))
                subtitle: String(modelData.version || "")
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Packaged apps")
        hint: Tr.t("Installed as self-contained packages, each with its own version.")
        EmptyState {
            Layout.fillWidth: true
            visible: !page.busy && page.snap.length === 0 && page.note === ""
            icon: "package"
            title: Tr.t("No packaged apps")
            subtitle: Tr.t("Nothing is installed from this source.")
        }
        Repeater {
            model: page.snap
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "package"
                title: String(modelData.name || modelData.id || Tr.t("App"))
                subtitle: String(modelData.version || "")
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("System apps")
        hint: Tr.t("Apps that came with the system, listed by the system's own package records.")
        EmptyState {
            Layout.fillWidth: true
            visible: !page.busy && page.os.length === 0 && page.note === ""
            icon: "package"
            title: Tr.t("No system apps reported")
            subtitle: Tr.t("Nothing was found in the package records.")
        }
        Repeater {
            model: page.os
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "package"
                title: String(modelData.name || modelData.id || Tr.t("App"))
                subtitle: String(modelData.version || "")
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Updates and games")
        ListRow {
            Layout.fillWidth: true
            icon: "system-software-install"
            title: Tr.t("App and game updates")
            subtitle: Tr.t("Software installs updates and keeps games up to date")
            trailing: "›"
            onClicked: Ui.openSoftware("installed")
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("The three lists above are counted on their own. There is no total across them.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
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
