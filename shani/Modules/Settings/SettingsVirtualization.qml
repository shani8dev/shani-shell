// Settings > Virtualization: whether this computer can run virtual machines,
// and what is already there. Read-only from bridge/system_virt.py; managing
// what exists happens in the Containers window.
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
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_VIRT_TOOL"), "system_virt.py")

    property bool kvmUsable: false
    property string kvmDevice: ""
    property var kvmModules: []
    property string kvmDetail: ""
    property var have: ({})
    property var libvirt: []
    property var lxc: []
    property var lxd: []
    property var nspawn: []
    property var groups: []
    property string error: ""
    property int pending: 0

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.virtualization = {
            kvm: page.kvmUsable, libvirt: page.nameList(page.libvirt), lxc: page.nameList(page.lxc),
            lxd: page.nameList(page.lxd), nspawn: page.nameList(page.nspawn)
        };
        Ui.systemState = o;
    }
    function nameOf(x) {
        if (x === null || x === undefined) return "";
        if (typeof x === "object") return String(x.name || x.title || x.id || x.value || "");
        return String(x);
    }
    function detailOf(x) {
        if (x === null || typeof x !== "object") return "";
        return String(x.state || x.detail || x.status || "");
    }
    function nameList(a) { return (Array.isArray(a) ? a : []).map(x => page.nameOf(x)); }
    function load() {
        page.pending = 2;
        kvmProc.running = false; kvmProc.running = true;
        invProc.running = false; invProc.running = true;
    }
    function done() { if (page.pending > 0) page.pending--; }
    function parseKvm(text) {
        let r = {};
        try { r = JSON.parse(text) || {}; } catch (e) { r = {}; }
        page.kvmUsable = !!r.usable;
        page.kvmDevice = r.device || "";
        page.kvmModules = Array.isArray(r.modules) ? r.modules : [];
        page.kvmDetail = r.detail || "";
        page.publish();
    }
    function parseInventory(text) {
        let r = {};
        try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("Could not read what is installed") }; }
        page.have = (r.have && typeof r.have === "object" && !Array.isArray(r.have)) ? r.have : {};
        page.libvirt = Array.isArray(r.libvirt) ? r.libvirt : [];
        page.lxc = Array.isArray(r.lxc) ? r.lxc : [];
        page.lxd = Array.isArray(r.lxd) ? r.lxd : [];
        page.nspawn = Array.isArray(r.nspawn) ? r.nspawn : [];
        page.error = r.error || "";
        page.rebuild();
    }
    function rebuild() {
        const g = [];
        const add = (id, title, icon, hint, empty, list) => {
            const l = Array.isArray(list) ? list : [];
            g.push({
                title: title, icon: icon, hint: hint, empty: empty,
                installed: !!page.have[id] || l.length > 0,
                rows: l.map(x => ({ title: page.nameOf(x), subtitle: page.detailOf(x) }))
            });
        };
        add("virsh", Tr.t("Virtual machines"), "computer", Tr.t("Whole computers running inside this one"), Tr.t("Virtual machine tools are not installed"), page.libvirt);
        add("lxc", Tr.t("Light containers"), "package-system", Tr.t("Small containers sharing this computer's kernel"), Tr.t("These containers are not installed"), page.lxc);
        add("lxd", Tr.t("System containers"), "package-system", Tr.t("Containers managed as a system service"), Tr.t("These containers are not installed"), page.lxd);
        add("machinectl", Tr.t("Machine containers"), "computer", Tr.t("Containers started from a machine image"), Tr.t("These containers are not installed"), page.nspawn);
        page.groups = g;
        page.publish();
    }

    Process {
        id: kvmProc; command: ["python3", page.tool, "kvm"]
        stdout: StdioCollector { onStreamFinished: page.parseKvm(text) }
        onExited: page.done()
    }
    Process {
        id: invProc; command: ["python3", page.tool, "inventory"]
        stdout: StdioCollector { onStreamFinished: page.parseInventory(text) }
        onExited: page.done()
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Can this computer run virtual machines")
        hint: Tr.t("A check of the hardware and the parts needed to run them.")
        BusyNote { Layout.fillWidth: true; visible: page.pending > 0; note: Tr.t("Loading…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.pending === 0
            tone: page.kvmUsable ? "ok" : "warn"
            title: page.kvmUsable ? Tr.t("This computer can run virtual machines") : Tr.t("Something is missing for virtual machines")
            text: page.kvmDetail || (page.kvmUsable ? "" : Tr.t("The hardware or the parts it needs are not ready yet."))
        }
        ListRow {
            Layout.fillWidth: true; interactive: false; icon: "computer"
            title: Tr.t("Virtual machine device")
            subtitle: Tr.t("The part of the processor that makes this possible")
            trailing: page.kvmDevice ? Tr.t("Present") : Tr.t("Not found")
        }
        ListRow {
            Layout.fillWidth: true; interactive: false; icon: "application-x-executable"
            title: Tr.t("Parts already loaded")
            trailing: page.kvmModules.join(" ") || Tr.t("None")
        }
        InfoBanner { Layout.fillWidth: true; visible: page.error !== ""; tone: "error"; text: page.error; accessibleRole: Accessible.AlertMessage }
    }

    Repeater {
        model: page.groups
        SettingsSection {
            required property var modelData
            Layout.fillWidth: true
            title: modelData.title
            hint: modelData.hint
            Repeater {
                model: modelData.rows
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    icon: "computer"
                    title: modelData.title
                    subtitle: modelData.subtitle
                }
            }
            EmptyState {
                visible: !modelData.installed && modelData.rows.length === 0
                icon: "computer"
                title: Tr.t("Not installed")
                subtitle: modelData.empty
            }
        }
    }

    ListRow {
        Layout.fillWidth: true
        icon: "system-software-install"
        title: Tr.t("Manage containers and toolboxes")
        subtitle: Tr.t("Open the Containers window")
        trailing: Tr.t("Open")
        onClicked: { Ui.closeAll(); Ui.containers = true; }
    }
}
