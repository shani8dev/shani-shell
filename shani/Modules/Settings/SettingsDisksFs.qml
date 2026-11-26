// Settings > Disks and storage: a read of the storage stack — RAID, LVM,
// Btrfs and drive health. Nothing here writes: a scrub or a mount changes bytes,
// so those actions stay in the Disks app and in the person's own tools.
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

    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_DISKS_TOOL"), "system_disks.py")
    property string section: "raid"
    property var sections: [
        { v: "raid", label: Tr.t("RAID") },
        { v: "lvm", label: Tr.t("LVM") },
        { v: "btrfs", label: Tr.t("Btrfs") },
        { v: "smart", label: Tr.t("Disk health") }
    ]
    property var verbs: ["raid", "lvm", "btrfs", "compression", "smart"]
    property var results: ({})
    property int done: 0
    property bool busy: false

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function load() {
        page.results = ({});
        page.done = 0;
        page.busy = true;
        publish();
        raidProc.running = false; raidProc.running = true;
        lvmProc.running = false; lvmProc.running = true;
        btrfsProc.running = false; btrfsProc.running = true;
        compressionProc.running = false; compressionProc.running = true;
        smartProc.running = false; smartProc.running = true;
    }
    function store(verb, text) {
        let r = {};
        try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("This section could not be read") }; }
        const o = Object.assign({}, page.results); o[verb] = r; page.results = o;
        page.done = page.done + 1;
        if (page.done >= page.verbs.length) page.busy = false;
        publish();
    }
    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        const raid = page.results.raid || {};
        const lvm = page.results.lvm || {};
        const btrfs = page.results.btrfs || {};
        const comp = page.results.compression || {};
        const smart = page.results.smart || {};
        o.disksfs = {
            raid: raid.arrays || [],
            lvm: { pvs: lvm.pvs || [], vgs: lvm.vgs || [], lvs: lvm.lvs || [] },
            btrfs: { subvolumes: btrfs.subvolumes || [], scrub: btrfs.scrub || "", compression: comp.lines || [] },
            smart: smart.disks || [],
            show: btrfs.show || {},
            df: btrfs.df || [],
            scrubState: btrfs.scrub_state || "",
            smartd: smart.schedule || {},
            section: page.section
        };
        Ui.systemState = o;
    }
    function errorFor(v) { const r = page.results[v] || {}; return r.error || ""; }
    function have(v) { const r = page.results[v] || {}; return r.have === true; }
    function list(v, key) { const r = page.results[v] || {}; return r[key] || []; }
    function countOf(v) { return Array.isArray(v) ? v.length : (typeof v === "number" ? v : 0); }
    function btrfsShow() { return (page.results.btrfs || {}).show || {}; }
    function scrubState() { return (page.results.btrfs || {}).scrub_state || ""; }
    function scrubNote(st) {
        if (st === "never") return Tr.t("Never scrubbed — there are no check results for this filesystem");
        if (st === "finished") return Tr.t("Last check finished");
        if (st === "running") return Tr.t("A check is running");
        if (st === "unknown") return Tr.t("The check state is not known");
        return "";
    }
    function dfTitle(row) {
        const k = row.kind || "";
        const p = row.profile || "";
        return (k && p) ? (k + " · " + p) : (k || p || Tr.t("Allocation"));
    }
    function smartd() { return (page.results.smart || {}).schedule || {}; }
    function serviceNote(v) { return v === true ? Tr.t("running") : (v === false ? Tr.t("not running") : Tr.t("not known")); }
    function scanNote(s) {
        if (s.scan_never) return Tr.t("Every disk is skipped");
        return s.scan ? Tr.t("Disks are scanned") : Tr.t("No automatic disk scan");
    }
    function lvmFacts() {
        const out = [];
        const r = page.results.lvm || {};
        const groups = [
            { k: Tr.t("Physical volumes"), a: r.pvs || [] },
            { k: Tr.t("Volume groups"), a: r.vgs || [] },
            { k: Tr.t("Logical volumes"), a: r.lvs || [] }
        ];
        for (const g of groups)
            for (const v of g.a)
                out.push({ label: g.k, value: typeof v === "object" ? (v.name || JSON.stringify(v)) : String(v) });
        return out;
    }

    Process {
        id: raidProc
        command: ["python3", page.tool, "raid"]
        stdout: StdioCollector { id: raidOut }
        onExited: code => page.store("raid", raidOut.text)
    }

    Process {
        id: lvmProc
        command: ["python3", page.tool, "lvm"]
        stdout: StdioCollector { id: lvmOut }
        onExited: code => page.store("lvm", lvmOut.text)
    }

    Process {
        id: btrfsProc
        command: ["python3", page.tool, "btrfs"]
        stdout: StdioCollector { id: btrfsOut }
        onExited: code => page.store("btrfs", btrfsOut.text)
    }

    Process {
        id: compressionProc
        command: ["python3", page.tool, "compression"]
        stdout: StdioCollector { id: compressionOut }
        onExited: code => page.store("compression", compressionOut.text)
    }

    Process {
        id: smartProc
        command: ["python3", page.tool, "smart"]
        stdout: StdioCollector { id: smartOut }
        onExited: code => page.store("smart", smartOut.text)
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Disks and storage")
        hint: Tr.t("A read of the storage this computer has. Nothing here changes data.")
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: page.sections
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.section === modelData.v
                    onClicked: { page.section = modelData.v; page.publish(); }
                }
            }
        }
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Reading…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.errorFor(page.section) !== ""
            tone: "error"
            text: page.errorFor(page.section)
            accessibleRole: Accessible.AlertMessage
        }
    }

    SettingsSection {
        Layout.fillWidth: true; visible: page.section === "raid"
        title: Tr.t("RAID arrays")
        EmptyState {
            visible: !page.busy && (!page.have("raid") || page.list("raid", "arrays").length === 0)
            icon: "drive-harddisk"
            title: page.have("raid") ? Tr.t("No RAID arrays") : Tr.t("No RAID tool is installed")
            subtitle: page.have("raid") ? Tr.t("This computer has no RAID arrays set up.") : Tr.t("This computer has no RAID information to show.")
        }
        Repeater {
            model: page.have("raid") ? page.list("raid", "arrays") : []
            ColumnLayout {
                id: arr
                required property var modelData
                Layout.fillWidth: true
                ListRow {
                    Layout.fillWidth: true; interactive: false
                    icon: "drive-harddisk"
                    title: arr.modelData.name || Tr.t("Array")
                    subtitle: arr.modelData.state || ""
                    trailing: arr.modelData.devices || ""
                }
                Text {
                    Layout.fillWidth: true
                    visible: (arr.modelData.detail || "") !== ""
                    text: arr.modelData.detail || ""
                    color: Theme.dim; wrapMode: Text.Wrap
                    font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true; visible: page.section === "lvm"
        title: Tr.t("Logical volumes")
        hint: Tr.t("The physical volumes, volume groups and logical volumes this computer reports.")
        EmptyState {
            visible: !page.busy && (!page.have("lvm") || page.lvmFacts().length === 0)
            icon: "drive-harddisk"
            title: page.have("lvm") ? Tr.t("No logical volumes") : Tr.t("No volume tool is installed")
            subtitle: page.have("lvm") ? Tr.t("This computer does not use logical volumes.") : Tr.t("This computer has no volume information to show.")
        }
        Repeater {
            model: page.have("lvm") ? page.lvmFacts() : []
            ListRow {
                required property var modelData
                Layout.fillWidth: true; interactive: false
                title: modelData.label
                subtitle: modelData.value
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true; visible: page.section === "btrfs"
        title: Tr.t("Btrfs")
        hint: Tr.t("Subvolumes, the last check and compression sizes, read only.")
        EmptyState {
            visible: !page.busy && (!page.have("btrfs") || page.list("btrfs", "subvolumes").length === 0)
            icon: "folder"
            title: page.have("btrfs") ? Tr.t("No subvolumes") : Tr.t("Btrfs is not available")
            subtitle: page.have("btrfs") ? Tr.t("This computer has no Btrfs subvolumes to show.") : Tr.t("This computer has no Btrfs information to show.")
        }
        ListRow {
            Layout.fillWidth: true; interactive: false
            visible: !page.busy && page.have("btrfs") &&
                     (page.btrfsShow().label !== "" || page.btrfsShow().uuid !== "" || page.countOf(page.btrfsShow().devices) > 0)
            icon: "folder"
            title: page.btrfsShow().label || Tr.t("Filesystem")
            subtitle: page.btrfsShow().uuid ? Tr.t("UUID %1", page.btrfsShow().uuid) : ""
            trailing: Tr.t("Devices: %1", page.countOf(page.btrfsShow().devices))
        }
        Repeater {
            model: page.have("btrfs") ? page.list("btrfs", "df") : []
            ListRow {
                required property var modelData
                Layout.fillWidth: true; interactive: false
                icon: "folder"
                title: page.dfTitle(modelData)
                subtitle: Tr.t("Total %1, used %2", modelData.total || "", modelData.used || "")
            }
        }
        ListRow {
            Layout.fillWidth: true; interactive: false
            visible: !page.busy && page.have("btrfs") && page.scrubNote(page.scrubState()) !== ""
            icon: "dialog-information"
            title: page.scrubNote(page.scrubState())
        }
        Repeater {
            model: page.have("btrfs") ? page.list("btrfs", "subvolumes") : []
            ListRow {
                required property var modelData
                Layout.fillWidth: true; interactive: false
                icon: "folder"
                title: modelData.path || Tr.t("Subvolume")
                subtitle: modelData.parent ? Tr.t("from %1").arg(modelData.parent) : (modelData.id || "")
            }
        }
        Text {
            Layout.fillWidth: true
            visible: ((page.results.btrfs || {}).scrub || "") !== ""
            text: Tr.t("Last check") + ": " + (page.results.btrfs || {}).scrub
            color: Theme.dim; wrapMode: Text.Wrap
            font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale
        }
        Repeater {
            model: page.list("compression", "lines")
            Text {
                required property var modelData
                Layout.fillWidth: true
                text: modelData
                color: Theme.dim; wrapMode: Text.Wrap
                font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true; visible: page.section === "smart"
        title: Tr.t("Disk health")
        hint: Tr.t("What the drives say about their own health. Nothing is tested or changed.")
        EmptyState {
            visible: !page.busy && (!page.have("smart") || page.list("smart", "disks").length === 0)
            icon: "drive-harddisk"
            title: page.have("smart") ? Tr.t("No drives to show") : Tr.t("No drive health tool is installed")
            subtitle: page.have("smart") ? Tr.t("No drive reported its health.") : Tr.t("This computer has no drive health information to show.")
        }
        Repeater {
            model: page.have("smart") ? page.list("smart", "disks") : []
            ColumnLayout {
                id: disk
                required property var modelData
                Layout.fillWidth: true
                ListRow {
                    Layout.fillWidth: true; interactive: false
                    icon: "drive-harddisk"
                    title: disk.modelData.name || Tr.t("Drive")
                    subtitle: disk.modelData.model || ""
                    trailing: disk.modelData.temp ? Tr.t("%1°C").arg(disk.modelData.temp) : ""
                }
                Text {
                    Layout.fillWidth: true
                    visible: (disk.modelData.health || "") !== ""
                    text: Tr.t("Health") + ": " + disk.modelData.health
                    color: Theme.dim; wrapMode: Text.Wrap
                    font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }
        }
        // An on-demand reading is not a scheduled test. Show what smartd is set
        // up to do; nothing here starts a test.
        ColumnLayout {
            Layout.fillWidth: true
            visible: !page.busy && (page.have("smart") || page.smartd().config_present === true)
            spacing: Theme.px(8)
            SectionTitle { Layout.fillWidth: true; text: Tr.t("Test schedule") }
            ListRow {
                Layout.fillWidth: true; interactive: false
                icon: "dialog-information"
                title: Tr.t("Schedule file")
                subtitle: page.smartd().config_present ? Tr.t("A schedule file is present") : Tr.t("No schedule file")
            }
            ListRow {
                Layout.fillWidth: true; interactive: false
                icon: "dialog-information"
                title: Tr.t("Disk scans")
                subtitle: page.scanNote(page.smartd())
            }
            ListRow {
                Layout.fillWidth: true; interactive: false
                icon: "drive-harddisk"
                title: Tr.t("Disks listed one by one")
                trailing: String(page.countOf(page.smartd().per_disk))
            }
            ListRow {
                Layout.fillWidth: true; interactive: false
                icon: "drive-harddisk"
                title: Tr.t("Deferred tests")
                trailing: String(page.countOf(page.smartd().deferred))
            }
            ListRow {
                Layout.fillWidth: true; interactive: false
                icon: "drive-harddisk"
                title: Tr.t("Disks skipped with never")
                trailing: String(page.countOf(page.smartd().never))
            }
            ListRow {
                Layout.fillWidth: true; interactive: false
                icon: "dialog-information"
                title: Tr.t("Test service")
                subtitle: page.serviceNote(page.smartd().service)
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("A health reading taken here is not a scheduled test.")
                color: Theme.dim; wrapMode: Text.Wrap
                font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
