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
            section: page.section
        };
        Ui.systemState = o;
    }
    function errorFor(v) { const r = page.results[v] || {}; return r.error || ""; }
    function have(v) { const r = page.results[v] || {}; return r.have === true; }
    function list(v, key) { const r = page.results[v] || {}; return r[key] || []; }
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
        id: reader
        property string verb: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("This section could not be read") }; }
                const o = Object.assign({}, page.results); o[reader.verb] = r; page.results = o;
                page.publish();
            }
        }
        // start the next read only after this one has exited: restarting a
        // Process from onStreamFinished raced its collector and lost rows.
        onExited: code => page.next()
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
    }
}
