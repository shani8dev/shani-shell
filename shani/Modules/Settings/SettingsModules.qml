// Settings > Kernel modules: loaded modules (read-only) + managed drop-ins (CRUD).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property string query: ""
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property var blacklist: []
    property var loadOnBoot: []
    property var sysctl: ({})
    property var sysctlLive: ({})
    property string note: ""
    property bool busy: false

    onActiveChanged: if (active) { KernelModules.refresh(); loadManaged(); }
    Component.onCompleted: if (active) { KernelModules.refresh(); loadManaged(); }

    function loadManaged() { blRead.running = false; blRead.running = true; mlRead.running = false; mlRead.running = true; sysRead.running = false; sysRead.running = true; }
    Process { id: blRead; command: page.adminCmd.concat(["modprobe-blacklist-get"]); stdout: StdioCollector { onStreamFinished: { try { page.blacklist = (JSON.parse(text).modules) || []; } catch(e) {} } } }
    Process { id: mlRead; command: page.adminCmd.concat(["modules-load-get"]); stdout: StdioCollector { onStreamFinished: { try { page.loadOnBoot = (JSON.parse(text).modules) || []; } catch(e) {} } } }
    Process { id: sysRead; command: page.adminCmd.concat(["sysctl-get"]); stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); page.sysctl = d.settings || {}; page.sysctlLive = d.live || {}; } catch(e) {} } } }

    function saveManaged(cmd, modules) {
        page.busy = true; page.note = "";
        saveProc.payload = JSON.stringify({ modules: modules });
        saveProc.command = page.adminCmd.concat([cmd]);
        saveProc.running = true;
    }
    function saveSysctl(settings) {
        page.busy = true; page.note = "";
        saveProc.payload = JSON.stringify({ settings: settings });
        saveProc.command = page.adminCmd.concat(["sysctl-set"]);
        saveProc.running = true;
    }
    Process {
        id: saveProc; stdinEnabled: true; property string payload: ""
        stderr: StdioCollector { id: saveErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.busy = false; page.note = code === 0 ? Tr.t("Saved") : (saveErr.text.trim().split("\n").pop() || Tr.t("Could not save")); page.loadManaged(); KernelModules.refresh(); }
    }

    readonly property var shown: {
        const q = page.query.trim().toLowerCase();
        const all = KernelModules.modules || [];
        if (q === "") return all;
        return all.filter(m => String(m.name).toLowerCase().indexOf(q) >= 0
            || (m.usedBy || []).some(d => String(d).toLowerCase().indexOf(q) >= 0));
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Blacklisted modules") }
    Text { Layout.fillWidth: true; text: Tr.t("Managed in /etc/modprobe.d/50-shani-shell.conf. Blacklisted modules are prevented from loading."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        TextField { id: blAdd; Layout.fillWidth: true; placeholder: Tr.t("Module name to blacklist") }
        Button { text: Tr.t("Add"); kind: "primary"; enabled: !page.busy && /^[A-Za-z0-9_-]+$/.test(blAdd.text.trim()); onClicked: { const n = blAdd.text.trim(); if (page.blacklist.indexOf(n) < 0) page.saveManaged("modprobe-blacklist-set", page.blacklist.concat([n])); blAdd.text = ""; } }
    }
    Repeater {
        model: page.blacklist
        ListRow {
            required property var modelData; required property int index
            Layout.fillWidth: true; interactive: false; icon: "dialog-cancel"; title: modelData
            subtitle: Tr.t("blacklisted")
            Button { text: Tr.t("Remove"); enabled: !page.busy; onClicked: { const a = page.blacklist.slice(); a.splice(index, 1); page.saveManaged("modprobe-blacklist-set", a); } }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Load at boot") }
    Text { Layout.fillWidth: true; text: Tr.t("Managed in /etc/modules-load.d/50-shani-shell.conf."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        TextField { id: mlAdd; Layout.fillWidth: true; placeholder: Tr.t("Module name to load at boot") }
        Button { text: Tr.t("Add"); kind: "primary"; enabled: !page.busy && /^[A-Za-z0-9_-]+$/.test(mlAdd.text.trim()); onClicked: { const n = mlAdd.text.trim(); if (page.loadOnBoot.indexOf(n) < 0) page.saveManaged("modules-load-set", page.loadOnBoot.concat([n])); mlAdd.text = ""; } }
    }
    Repeater {
        model: page.loadOnBoot
        ListRow {
            required property var modelData; required property int index
            Layout.fillWidth: true; interactive: false; icon: "application-x-addon"; title: modelData
            subtitle: Tr.t("loads at boot")
            Button { text: Tr.t("Remove"); enabled: !page.busy; onClicked: { const a = page.loadOnBoot.slice(); a.splice(index, 1); page.saveManaged("modules-load-set", a); } }
        }
    }
    Text { Layout.fillWidth: true; visible: page.note !== ""; text: page.note; color: page.note === Tr.t("Saved") ? Theme.accent : Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Kernel tuning (sysctl)") }
    Text { Layout.fillWidth: true; text: Tr.t("Managed in /etc/sysctl.d/50-shani-shell.conf. Only allowlisted keys."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    Repeater {
        model: ["vm.swappiness", "fs.inotify.max_user_watches", "fs.inotify.max_user_instances", "kernel.sysrq"]
        RowLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: Theme.px(6)
            Text { Layout.preferredWidth: Theme.px(220); text: modelData; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: sysField; Layout.fillWidth: true; placeholder: page.sysctlLive[modelData] || ""; text: page.sysctl[modelData] || "" }
            Button { text: Tr.t("Save"); enabled: !page.busy && /^\d+$/.test(sysField.text.trim()); onClicked: { const o = Object.assign({}, page.sysctl); o[modelData] = sysField.text.trim(); page.saveSysctl(o); } }
        }
    }
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Loaded modules") }
    Text { Layout.fillWidth: true; text: Tr.t("%1 modules loaded. Read from /proc/modules; nothing here loads or unloads a running module.").arg(KernelModules.count); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    TextField { Layout.fillWidth: true; placeholder: Tr.t("Filter modules…"); onTextChanged: page.query = text }
    ColumnLayout {
        Layout.fillWidth: true; spacing: Theme.px(2)
        Repeater {
            model: page.shown
            ListRow {
                required property var modelData
                Layout.fillWidth: true; interactive: false; icon: "application-x-addon"; title: modelData.name
                subtitle: { const deps = (modelData.usedBy || []).length ? Tr.t("used by %1", modelData.usedBy.join(", ")) : Tr.t("no dependents"); return Tr.t("%1 KiB", Math.round((modelData.size || 0) / 1024)) + "  ·  " + deps; }
            }
        }
    }
    Text { Layout.fillWidth: true; visible: page.shown.length === 0 && KernelModules.loaded; text: Tr.t("No module matches."); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
}
