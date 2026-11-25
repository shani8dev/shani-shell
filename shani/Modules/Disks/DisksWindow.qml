// Disks: all block devices on the system — disks, partitions, filesystems,
// mount points, and SMART health. Destructive operations (erase, format,
// encrypt, install stick) need two-click confirmation and polkit authorisation.
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Disks"
    visible: Ui.disks
    onGone: Ui.disks = false
    implicitWidth: Theme.px(760)
    implicitHeight: Theme.px(560)

    // selected device
    property var selectedDisk: null
    // operation mode: "list" (default), "erase", "format", "encrypt", "install"
    property string opMode: ""
    // form fields
    property string formFsType: "ext4"
    property string formLabel: ""
    property string formNewLabel: ""
    property string formPassphrase: ""
    property string formPassphrase2: ""
    property string formConfirm: ""
    property string formIso: ""
    property bool showLoops: false
    property string mountOptions: ""
    property string smartTestKind: "short"
    // ---- units: auto or one of bytes/KB/MB/GB/TB ----
    property string unitScale: "auto"
    function human(n) {
        n = Number(n) || 0;
        const s = win.unitScale;
        if (s === "bytes") return Math.round(n) + " B";
        if (s === "KB") return (n / 1e3).toFixed(1) + " KB";
        if (s === "MB") return (n / 1e6).toFixed(1) + " MB";
        if (s === "GB") return (n / 1e9).toFixed(1) + " GB";
        if (s === "TB") return (n / 1e12).toFixed(1) + " TB";
        if (n >= 1e12) return (n / 1e12).toFixed(1) + " TB";
        if (n >= 1e9) return (n / 1e9).toFixed(1) + " GB";
        if (n >= 1e6) return (n / 1e6).toFixed(1) + " MB";
        if (n >= 1e3) return (n / 1e3).toFixed(1) + " KB";
        return n + " B";
    }

    // type/protocol subtitle: NVMe/SATA/USB/SD plus SSD/HDD for whole disks
    function diskKind(d) {
        if (!d) return "";
        const transport = String(d.transport || "").toUpperCase();
        const kind = d.type !== "disk" ? String(d.type || "").toUpperCase()
            : d.rotational ? Tr.t("HDD") : Tr.t("SSD");
        return transport ? transport + " · " + kind : kind;
    }

    // lsblk -p puts the full path in `name`; partition nodes are raw lsblk data
    function partPath(p) {
        const n = String((p && (p.name || p.path)) || "");
        return n && n.charAt(0) !== "/" ? "/dev/" + n : n;
    }

    // A mounted filesystem cannot be checked reliably, even read-only.
    function isMounted(d) {
        if (!d) return false;
        if ((d.mountpoints || []).length > 0) return true;
        return (d.children || []).some(c => (c.mountpoints || []).length > 0);
    }
    function canScan(d) {
        return !!d && !Disks.busy && !Disks.deviceIsSystem(d.path) && !win.isMounted(d);
    }

    function smartEta() {
        if (Disks.smartTestPercent <= 0) return "—";
        const elapsed = Date.now() - Number(Disks.smartTestStarted);
        const left = elapsed * (100 - Disks.smartTestPercent) / Disks.smartTestPercent;
        return Math.max(1, Math.round(left / 60000)) + " min";
    }

    // Destructive ops: removable media are allowed with the two-click confirm;
    // anything internal needs its full device path typed as well — and the
    // running system disk is never allowed, typed or not.
    function canDestroy() {
        const d = win.selectedDisk;
        if (!d || Disks.deviceIsSystem(d.path)) return false;
        if (d.removable) return true;
        return String(d.path || "") !== "" && win.formConfirm.trim() === d.path;
    }
    function clearOp() {
        win.opMode = "";
        win.confirmAction = "";
        win.formConfirm = "";
        win.formPassphrase = "";
        win.formPassphrase2 = "";
    }

    // ---- selectivity: search + by-fs filter over the disk list ----
    property string filterText: ""
    property string fsFilter: ""
    property var fsChoices: [["", Tr.t("By fs: All")], ["ext4", "ext4"], ["vfat", "vfat"], ["ntfs", "ntfs"], ["exfat", "exfat"], ["xfs", "xfs"], ["btrfs", "btrfs"], ["zfs", "zfs"]]
    function diskMatch(d) {
        if (!d) return false;
        if (d.type !== "disk" && !(win.showLoops && d.type === "loop")) return false;
        const t = win.filterText.toLowerCase();
        const s = (d.name + " " + (d.path || "") + " " + (d.label || "") + " " + (d.model || "")).toLowerCase();
        if (t && s.indexOf(t) < 0) return false;
        if (win.fsFilter) {
            const kids = (d.children || []).map(c => String(c.fstype || "")).join(" ");
            if (String(d.fstype || "") !== win.fsFilter && kids.indexOf(win.fsFilter) < 0) return false;
        }
        return true;
    }
    function filteredDisks() { return Disks.disks.filter(win.diskMatch); }
    function clearFilter() { win.filterText = ""; win.fsFilter = ""; }

    // ---- partitions of the selected disk (dedicated list) ----
    function partList(d) { return (d && d.children) || []; }

    // ---- ATA SMART attributes sometimes arrive without a name; fall back to the id ----
    function attrName(a) {
        return String((a && (a.name || a.id)) || "").toUpperCase().replace(/^ATA_SMART_/, "").replace(/^ATA_/, "");
    }

    // ---- performance view: benchmark history ----
    property var benchHistory: []
    property var _lastBench: null
    function runBench() {
        if (win.selectedDisk && !Disks.busy) Disks.benchmark(win.selectedDisk.path);
    }
    function noteBench() {
        const r = Disks.benchmarkResult;
        if (!r || r === win._lastBench || r.mbps === undefined) return;
        win._lastBench = r;
        win.benchHistory = win.benchHistory.slice(-9).concat([{
            at: new Date().toISOString().slice(11, 16),
            mbps: r.mbps, bytes: r.bytes,
        }]);
    }

    // ---- large-file finder: read-only find, sorted by size, shown in a preview dialog ----
    property var bigFiles: []
    function scanBigFiles() {
        const d = win.selectedDisk;
        if (!d) return;
        bigFinder.command = ["find", d.path, "-xdev", "-type", "f", "-size", "+1M", "-printf", "%s\t%TY-%Tm-%Td %TH:%TM\t%p\\n"];
        if (!bigFinder.running) bigFinder.running = true;
    }

    // two-click confirm for destructive ops
    property string confirmAction: ""
    Timer { id: confirmTimer; interval: 4000; onTriggered: win.confirmAction = "" }

    // A pending confirm is armed for one device + one op only. Switching either
    // must re-arm it, otherwise one click on the new target fires the old op.
    onSelectedDiskChanged: { win.confirmAction = ""; confirmTimer.stop(); }
    onOpModeChanged: { win.confirmAction = ""; confirmTimer.stop(); }

    onVisibleChanged: if (visible) Disks.refresh()

    // refresh() rebuilds the model: keep the same drive selected by path
    Connections {
        target: Disks
        function onDisksChanged() {
            win.noteBench();
            const p = win.selectedDisk ? win.selectedDisk.path : "";
            if (p) {
                const fresh = Disks.disks.find(d => d.path === p);
                win.selectedDisk = fresh || null;
            }
        }
    }

    // Esc: leave op mode first, then close
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: {
            if (win.opMode !== "") win.clearOp();
            else Ui.disks = false;
        }
    }

    // Large files finder: read-only, sorts by size; "-printf" is GNU findutils (Linux)
    Process {
        id: bigFinder
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                String(text).split("\n").forEach(line => {
                    const p = String(line).split("\t");
                    if (p.length >= 3) out.push({ size: Number(p[0]) || 0, when: p[1].trim(), path: p[2] });
                });
                out.sort((a, b) => b.size - a.size);
                win.bigFiles = out.slice(0, 20);
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(16)
        spacing: Theme.px(8)

        // ---- header: title, search + by-fs filter, unit scale, loop devices, actions ----
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: Tr.t("Disks")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(16) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            TextField {
                Layout.preferredWidth: Theme.px(180)
                placeholder: Tr.t("Search disks…")
                text: win.filterText
                onTextChanged: win.filterText = text
            }
            Repeater {
                model: win.fsChoices
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.fsFilter === modelData[0]
                    onClicked: win.fsFilter = modelData[0]
                }
            }
            Repeater {
                model: [["auto", Tr.t("Auto")], ["bytes", "B"], ["KB", "KB"], ["MB", "MB"], ["GB", "GB"], ["TB", "TB"]]
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.unitScale === modelData[0]
                    onClicked: win.unitScale = modelData[0]
                }
            }
            Choice { text: Tr.t("Loop devices"); selected: win.showLoops; onClicked: win.showLoops = !win.showLoops }
            Button {
                text: Tr.t("Refresh")
                flat: true
                enabled: !Disks.busy
                onClicked: Disks.refresh()
            }
            Button {
                visible: Disks.busy
                text: Tr.t("Cancel job")
                kind: "danger"
                flat: true
                onClicked: Disks.cancelJob()
            }
            Button {
                visible: win.opMode === ""
                text: Tr.t("Done")
                flat: true
                onClicked: Ui.disks = false
            }
            Button {
                visible: win.opMode !== ""
                text: Tr.t("Cancel")
                flat: true
                onClicked: win.clearOp()
            }
        }

        // ---- job progress (write operations stream their progress) -------------
        ColumnLayout {
            visible: Disks.busy
            Layout.fillWidth: true
            spacing: Theme.px(2)
            Text {
                Layout.fillWidth: true
                text: Disks.jobLabel || Tr.t("Working…")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(5)
                radius: Theme.px(2)
                color: Theme.alpha(Theme.text, 0.15)
                Accessible.role: Accessible.ProgressBar
                Accessible.name: Tr.t("Operation progress")
                Rectangle { width: parent.width * Math.max(0, Disks.jobProgress) / 100; height: parent.height; radius: parent.radius; color: Theme.accent }
            }
        }

        // ---- error banner: visible with no form open too (e.g. "Operation cancelled") ----
        Text {
            visible: Disks.error !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Disks.error
            color: Theme.red
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        // ---- operation form (shown when an op is selected) ----
        ColumnLayout {
            visible: win.opMode !== ""
            Layout.fillWidth: true
            spacing: Theme.px(6)

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: win.opMode === "erase" ? Tr.t("Erase %1 — this permanently deletes all data on the device.", win.selectedDisk ? win.selectedDisk.path : "")
                    : win.opMode === "format" ? Tr.t("Format %1 — this creates a new filesystem, replacing whatever is there.", win.selectedDisk ? win.selectedDisk.path : "")
                    : win.opMode === "encrypt" ? Tr.t("Encrypt %1 — this erases the device and creates an encrypted volume. You will need the passphrase to unlock it.", win.selectedDisk ? win.selectedDisk.path : "")
                    : Tr.t("Write %1 to %2 — this replaces everything on the USB drive with the install image.", win.formIso, win.selectedDisk ? win.selectedDisk.path : "")
                color: win.opMode === "install" ? Theme.text : Theme.red
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }

            // The running system disk can never be wiped; for any other internal
            // device the exact path has to be typed before the buttons wake up.
            Text {
                visible: win.opMode !== "" && win.selectedDisk && Disks.deviceIsSystem(win.selectedDisk.path)
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("This is the running system disk — it cannot be erased, formatted or encrypted.")
                color: Theme.red
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            TextField {
                visible: win.opMode !== "" && win.selectedDisk && !win.selectedDisk.removable && !Disks.deviceIsSystem(win.selectedDisk.path)
                Layout.fillWidth: true
                placeholder: win.selectedDisk ? Tr.t("Type %1 to confirm", win.selectedDisk.path) : ""
                label: Tr.t("Type the device name to confirm")
                text: win.formConfirm
                onTextChanged: win.formConfirm = text
            }

            // erase options
            RowLayout {
                visible: win.opMode === "erase"
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    text: Tr.t("Quick erase")
                    kind: "danger"
                    enabled: win.canDestroy()
                    onClicked: {
                        if (win.confirmAction === "erase-quick") { Disks.eraseQuick(win.selectedDisk.path); win.clearOp(); }
                        else { win.confirmAction = "erase-quick"; confirmTimer.restart(); }
                    }
                }
                Text {
                    text: win.confirmAction === "erase-quick" ? Tr.t("Click again to confirm") : Tr.t("Wipes filesystem signatures (fast, not secure)")
                    color: win.confirmAction === "erase-quick" ? Theme.red : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
            RowLayout {
                visible: win.opMode === "erase"
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    text: Tr.t("Secure erase")
                    kind: "danger"
                    enabled: win.canDestroy()
                    onClicked: {
                        if (win.confirmAction === "erase-secure") { Disks.eraseSecure(win.selectedDisk.path); win.clearOp(); }
                        else { win.confirmAction = "erase-secure"; confirmTimer.restart(); }
                    }
                }
                Text {
                    text: win.confirmAction === "erase-secure" ? Tr.t("Click again to confirm") : Tr.t("Zeros the first 100 MB (slower, safer)")
                    color: win.confirmAction === "erase-secure" ? Theme.red : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }

            // format options
            RowLayout {
                visible: win.opMode === "format"
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("Filesystem:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: Disks.fstypes
                    Choice {
                        required property var modelData
                        text: modelData.name
                        selected: win.formFsType === modelData.id
                        onClicked: win.formFsType = modelData.id
                    }
                }
            }
            TextField {
                visible: win.opMode === "format"
                Layout.fillWidth: true
                placeholder: Tr.t("Label (optional)")
                label: Tr.t("Label")
                text: win.formLabel
                onTextChanged: win.formLabel = text
            }
            RowLayout {
                visible: win.opMode === "format"
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    text: Tr.t("Format")
                    kind: "danger"
                    enabled: win.canDestroy()
                    onClicked: {
                        if (win.confirmAction === "format") { Disks.format(win.selectedDisk.path, win.formFsType, win.formLabel); win.clearOp(); }
                        else { win.confirmAction = "format"; confirmTimer.restart(); }
                    }
                }
                Text {
                    text: win.confirmAction === "format" ? Tr.t("Click again to confirm") : Tr.t("This replaces all data on the device")
                    color: win.confirmAction === "format" ? Theme.red : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }

            // encrypt options
            RowLayout {
                visible: win.opMode === "encrypt"
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("Filesystem:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: Disks.fstypes
                    Choice {
                        required property var modelData
                        text: modelData.name
                        selected: win.formFsType === modelData.id
                        onClicked: win.formFsType = modelData.id
                    }
                }
            }
            TextField {
                visible: win.opMode === "encrypt"
                Layout.fillWidth: true
                placeholder: Tr.t("Passphrase")
                label: Tr.t("Passphrase")
                secret: true
                text: win.formPassphrase
                onTextChanged: win.formPassphrase = text
            }
            TextField {
                visible: win.opMode === "encrypt"
                Layout.fillWidth: true
                placeholder: Tr.t("Passphrase again")
                label: Tr.t("Passphrase again")
                secret: true
                text: win.formPassphrase2
                onTextChanged: win.formPassphrase2 = text
            }
            Text {
                visible: win.opMode === "encrypt"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("There is no way to recover this passphrase — if you forget it, the data on the device is lost forever.")
                color: Theme.red
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                visible: win.opMode === "encrypt"
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    text: Tr.t("Encrypt")
                    kind: "danger"
                    enabled: win.canDestroy() && win.formPassphrase.length >= 8 && win.formPassphrase === win.formPassphrase2
                    onClicked: {
                        if (win.confirmAction === "encrypt") { Disks.encrypt(win.selectedDisk.path, win.formFsType, win.formPassphrase); win.clearOp(); }
                        else { win.confirmAction = "encrypt"; confirmTimer.restart(); }
                    }
                }
                Text {
                    text: win.formPassphrase2 !== "" && win.formPassphrase !== win.formPassphrase2 ? Tr.t("The passphrases do not match")
                        : win.confirmAction === "encrypt" ? Tr.t("Click again to confirm") : Tr.t("Erases the device and creates an encrypted volume")
                    color: win.confirmAction === "encrypt" ? Theme.red : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }

            // install stick
            TextField {
                visible: win.opMode === "install"
                Layout.fillWidth: true
                placeholder: Tr.t("Path to ISO file")
                label: Tr.t("ISO file")
                text: win.formIso
                onTextChanged: win.formIso = text
            }
            RowLayout {
                visible: win.opMode === "install"
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    text: Tr.t("Write")
                    kind: "danger"
                    enabled: win.formIso !== "" && win.selectedDisk && win.selectedDisk.removable
                    onClicked: {
                        if (win.confirmAction === "install") { Disks.installStick(win.selectedDisk.path, win.formIso); win.clearOp(); }
                        else { win.confirmAction = "install"; confirmTimer.restart(); }
                    }
                }
                Text {
                    text: win.confirmAction === "install" ? Tr.t("Click again to confirm") : Tr.t("Replaces everything on the USB drive")
                    color: win.confirmAction === "install" ? Theme.red : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }

        }

        // ---- disk list ----
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            reuseItems: true
            cacheBuffer: 400
            model: win.filteredDisks()
            // shortcut: a disk row owns a partition bar, mount toggles and action buttons — ListRow has no slot for that layout, upgrade if it gains one
            delegate: Rectangle {
                id: diskRow
                required property var modelData
                width: list.width
                height: Theme.px(72)
                radius: Theme.radiusSmall
                Accessible.role: Accessible.ListItem
                Accessible.name: (modelData.model || modelData.name || "") + " · " + win.diskKind(modelData) + " · " + (modelData.size || "")
                color: win.selectedDisk === modelData ? Theme.alpha(Theme.accent, 0.12)
                    : rowArea.containsMouse ? Theme.hover : "transparent"
                border.width: win.selectedDisk === modelData ? 2 : 0
                border.color: Theme.accent

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(10)
                    spacing: Theme.px(2)

                    RowLayout {
                        Layout.fillWidth: true
                        Icon {
                            name: modelData.removable ? "drive-removable-media" : "drive-harddisk"
                            size: Theme.px(22)
                            color: Theme.dim
                        }
                        Text {
                            text: modelData.model || modelData.name
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: win.diskKind(modelData)
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.size
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                    }

                    // partitions / mount points
                    RowLayout {
                        Layout.fillWidth: true
                        visible: modelData.children && modelData.children.length > 0
                        spacing: Theme.px(4)
                        Repeater {
                            model: modelData.children || []
                            // per-volume mount toggle: mount the partition, not the whole disk
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: Math.max(60, labelText.implicitWidth + toggleText.implicitWidth + 20)
                                implicitHeight: Theme.px(20)
                                radius: Theme.px(4)
                                color: Theme.alpha(Theme.accent, 0.1)
                                RowLayout {
                                    anchors { fill: parent; margins: Theme.px(4) }
                                    spacing: Theme.px(4)
                                    Text {
                                        id: labelText
                                        text: (modelData.label || modelData.fstype || modelData.name) +
                                            (modelData.mountpoints && modelData.mountpoints.length > 0 ? " → " + modelData.mountpoints[0] : "")
                                        color: Theme.text
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(10) * Theme.fontScale
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        id: toggleText
                                        visible: win.selectedDisk === diskRow.modelData &&
                                            !!(modelData.fstype || (modelData.mountpoints || []).length)
                                        text: (modelData.mountpoints || []).length > 0 ? Tr.t("Unmount") : Tr.t("Mount")
                                        color: Theme.accent
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(9) * Theme.fontScale
                                        Accessible.role: Accessible.Button
                                        Accessible.name: toggleText.text
                                        Accessible.onPressAction: toggleText.toggle()
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: toggleText.toggle()
                                        }
                                        function toggle() {
                                            const p = win.partPath(modelData);
                                            if (!p || Disks.busy) return;
                                            if ((modelData.mountpoints || []).length > 0) Disks.unmount(p);
                                            else Disks.mount(p);
                                        }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    // proportional space-allocation bar: each partition's width
                    // is its share of the disk, with unallocated space left dark
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: (modelData.children || []).length > 0 && modelData.bytes > 0
                        spacing: Theme.px(2)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(10)
                            radius: Theme.px(5)
                            color: Theme.pressed
                            clip: true
                            Row {
                                anchors.fill: parent
                                Repeater {
                                    model: modelData.children || []
                                    Rectangle {
                                        required property var modelData
                                        height: parent.height
                                        width: parent.width * Math.min(1, (Number(modelData.size) || 0) / Math.max(1, diskRow.modelData.bytes || 1))
                                        color: Theme.alpha(Theme.accent, 0.75)
                                        border.width: 1
                                        border.color: Theme.surface1
                                    }
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (modelData.children || []).map(c => (c.label || c.fstype || c.name) + " " + win.human(c.bytes || 0)).join("  ·  ")
                            color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(9) * Theme.fontScale; elide: Text.ElideRight
                        }
                    }

                    // actions (shown when selected)
                    RowLayout {
                        visible: win.selectedDisk === modelData
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Button { text: Tr.t("Health"); flat: true; onClicked: Disks.checkHealth(modelData.path) }
                        Button { text: Tr.t("Mount"); flat: true; visible: !modelData.mountpoints || modelData.mountpoints.length === 0; onClicked: Disks.mount(modelData.path) }
                        Button {
                            text: Tr.t("Unmount"); flat: true
                            visible: !modelData.removable && modelData.mountpoints && modelData.mountpoints.length > 0
                            onClicked: Disks.unmount(modelData.path)
                        }
                        Button { text: Tr.t("Eject"); flat: true; visible: modelData.removable; onClicked: Disks.powerOff(modelData.path) }
                        Item { Layout.fillWidth: true }
                        Button { text: Tr.t("Partitions…"); flat: true; visible: modelData.type === "disk"; onClicked: partDialog.open() }
                        Button { text: Tr.t("Tools…"); flat: true; visible: modelData.type === "disk"; onClicked: toolsDialog.open() }
                        Button { text: Tr.t("Performance…"); flat: true; visible: modelData.type === "disk"; onClicked: perfDialog.open() }
                        Button { text: Tr.t("Large files…"); flat: true; visible: modelData.type === "disk"; onClicked: { win.scanBigFiles(); win.bigFiles = []; bigDialog.open() } }
                        Button { text: Tr.t("Erase…"); kind: "danger"; flat: true; onClicked: { win.opMode = "erase"; win.formFsType = "ext4"; win.formLabel = ""; win.formConfirm = ""; } }
                        Button { text: Tr.t("Format…"); kind: "outline"; flat: true; onClicked: { win.opMode = "format"; win.formFsType = "ext4"; win.formLabel = ""; win.formConfirm = ""; } }
                        Button { text: Tr.t("Encrypt…"); kind: "outline"; flat: true; onClicked: { win.opMode = "encrypt"; win.formFsType = "ext4"; win.formPassphrase = ""; win.formPassphrase2 = ""; win.formConfirm = ""; } }
                        Button { text: Tr.t("Install stick…"); kind: "outline"; flat: true; visible: modelData.removable; onClicked: { win.opMode = "install"; win.formIso = ""; } }
                    }
                    RowLayout {
                        visible: win.selectedDisk === modelData
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Button { text: Tr.t("SMART details…"); flat: true; onClicked: { Disks.smartDetails(modelData.path); smartDialog.open(); } }
                        Button {
                            text: Tr.t("Relabel…"); flat: true
                            enabled: !Disks.busy && !Disks.deviceIsSystem(modelData.path)
                            onClicked: { win.formNewLabel = modelData.label || ""; win.confirmAction = ""; relabelDialog.open(); }
                        }
                        Button {
                            text: win.confirmAction === "fsck-" + modelData.path ? Tr.t("Tap again to confirm") : Tr.t("Check filesystem")
                            flat: true
                            enabled: win.canScan(modelData)
                            onClicked: {
                                if (win.confirmAction === "fsck-" + modelData.path) {
                                    win.confirmAction = ""; Disks.fsck(modelData.path); scanDialog.open();
                                } else { win.confirmAction = "fsck-" + modelData.path; confirmTimer.restart(); }
                            }
                        }
                        Button {
                            text: win.confirmAction === "badblocks-" + modelData.path ? Tr.t("Tap again to confirm") : Tr.t("Bad blocks")
                            flat: true
                            enabled: win.canScan(modelData)
                            onClicked: {
                                if (win.confirmAction === "badblocks-" + modelData.path) {
                                    win.confirmAction = ""; Disks.badblocks(modelData.path); scanDialog.open();
                                } else { win.confirmAction = "badblocks-" + modelData.path; confirmTimer.restart(); }
                            }
                        }
                        // filesystem checks need an unmounted volume
                        Text {
                            visible: win.selectedDisk === modelData && win.isMounted(modelData)
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Tr.t("Unmount this filesystem before checking it")
                            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Button {
                            text: Tr.t("Mount options…"); flat: true
                            visible: !(modelData.mountpoints && modelData.mountpoints.length > 0)
                            onClicked: { win.mountOptions = ""; mountDialog.open(); }
                        }
                        Button { text: Tr.t("Benchmark"); flat: true; enabled: !Disks.busy; onClicked: Disks.benchmark(modelData.path) }
                        Button {
                            text: win.confirmAction === "own-" + modelData.path ? Tr.t("Tap again to confirm") : Tr.t("Take ownership")
                            kind: "danger"; flat: true
                            visible: modelData.removable
                            onClicked: {
                                if (win.confirmAction === "own-" + modelData.path) { Disks.takeOwnership(modelData.path); win.confirmAction = ""; }
                                else { win.confirmAction = "own-" + modelData.path; confirmTimer.restart(); }
                            }
                        }
                        Button { text: Tr.t("Detach loop"); flat: true; visible: modelData.type === "loop"; onClicked: Disks.detachLoop(modelData.path) }
                    }
                }
                MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                MouseArea {
                    anchors.fill: parent
                    z: 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.selectedDisk = win.selectedDisk === modelData ? null : modelData
                }
                KeyFocus { onActivated: win.selectedDisk = win.selectedDisk === modelData ? null : modelData }
            }
            // ---- empty / error states: no disks, no match, or read failure ----
            EmptyState {
                anchors.centerIn: parent
                visible: list.count === 0 && !Disks.busy
                icon: "drive-harddisk"
                title: Disks.error !== "" ? Tr.t("Could not read the disks")
                    : (list.count === 0 && Disks.disks.length === 0 ? Tr.t("No disks found") : Tr.t("No matching disks"))
                subtitle: Disks.error !== "" ? Tr.t("Is lsblk installed?")
                    : (list.count === 0 && Disks.disks.length === 0 ? Tr.t("lsblk could not find any block devices") : Tr.t("Try a different search term"))
                actionText: list.count === 0 && Disks.disks.length > 0 && Disks.error === "" ? Tr.t("Clear filter") : ""
                onAction: win.clearFilter()
            }
        }

        // ---- SMART health display ----
        ColumnLayout {
            visible: win.selectedDisk && Disks.health[win.selectedDisk.path]
            Layout.fillWidth: true
            spacing: Theme.px(4)
            readonly property var health: (win.selectedDisk && Disks.health[win.selectedDisk.path]) || ({})
            Text {
                text: Tr.t("SMART health: %1", win.selectedDisk && Disks.health[win.selectedDisk.path] ? Disks.health[win.selectedDisk.path].overall || "—" : "—")
                color: win.selectedDisk && Disks.health[win.selectedDisk.path] && Disks.health[win.selectedDisk.path].overall === "passed" ? Theme.accent : Theme.red
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                visible: win.selectedDisk && Disks.health[win.selectedDisk.path] && Disks.health[win.selectedDisk.path].temp !== undefined
                text: win.selectedDisk && Disks.health[win.selectedDisk.path] ? Tr.t("%1°C · %2 hours", Disks.health[win.selectedDisk.path].temp || 0, Disks.health[win.selectedDisk.path].hours || 0) : ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                visible: Disks.benchmarkResult !== null && Disks.benchmarkResult.mbps !== undefined
                text: Tr.t("Read %1 in %2 s · %3 MB/s", win.human(Disks.benchmarkResult ? Disks.benchmarkResult.bytes : 0), Disks.benchmarkResult ? Disks.benchmarkResult.seconds : 0, Disks.benchmarkResult ? Disks.benchmarkResult.mbps : 0)
                color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }

        // ---- footer ----
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Tr.t("Click a disk to see its partitions and actions · Esc closes")
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
        }

        // ---- detailed SMART dialog + self-tests ----------------------------------
        Dialog {
            id: smartDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.9, Theme.px(520))
            height: Math.min(win.height * 0.85, Theme.px(560))
            title: Tr.t("SMART details · %1", win.selectedDisk ? win.selectedDisk.model || win.selectedDisk.path : "")
            modal: true
            standardButtons: Dialog.Close
            contentItem: Flickable {
                clip: true
                contentHeight: smartCol.implicitHeight
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: smartCol
                    width: parent.width
                    spacing: Theme.px(4)
                    readonly property var info: Disks.smart || ({})
                    Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: Tr.t("%1 · %2 · %3°C · %4 hours powered on").arg(smartCol.info.model || "").arg(smartCol.info.serial || "").arg(smartCol.info.temp || 0).arg(smartCol.info.hours || 0); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { Layout.fillWidth: true; text: Tr.t("Overall: %1", smartCol.info.overall === true || smartCol.info.overall === "passed" ? Tr.t("PASSED") : Tr.t("FAILED")); color: smartCol.info.overall === true || smartCol.info.overall === "passed" ? Theme.accent : Theme.red; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { Layout.fillWidth: true; text: Tr.t("Attributes (ID · name · value · worst · threshold · raw)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Repeater {
                        model: smartCol.info.attributes || []
                        Text { required property var modelData; Layout.fillWidth: true; text: [modelData.id, win.attrName(modelData), modelData.value, modelData.worst, modelData.thresh, modelData.raw].join(" · "); color: Theme.faint; font.family: Theme.mono; font.pixelSize: Theme.px(9) * Theme.fontScale }
                    }
                    // capacity + health refresh (expansion)
                    Text { Layout.fillWidth: true; text: Tr.t("Capacity: %1", smartCol.info.capacity ? win.human(smartCol.info.capacity) : "—"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        readonly property var curHealth: win.selectedDisk ? Disks.health[win.selectedDisk.path] : null
                        Button { text: Tr.t("Refresh health"); flat: true; enabled: !!win.selectedDisk; onClicked: Disks.checkHealth(win.selectedDisk ? win.selectedDisk.path : "") }
                        Text { Layout.fillWidth: true; visible: !!curHealth; text: Tr.t("Health: %1", curHealth.overall || "—"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    }
                    Text { Layout.fillWidth: true; text: Tr.t("Self-test log"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Repeater {
                        model: smartCol.info.tests || []
                        Text { required property var modelData; Layout.fillWidth: true; text: modelData.type + " · " + modelData.status + " · " + modelData.hours + " h"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(9) * Theme.fontScale }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: Disks.smartTestDevice !== ""
                        wrapMode: Text.Wrap
                        text: Disks.smartTestRemaining >= 0
                            ? Tr.t("Self-test %1 — %2% done · about %3 left", Disks.smartTestKind, Math.round(Disks.smartTestPercent), win.smartEta())
                            : Tr.t("Self-test %1 — starting…", Disks.smartTestKind)
                        color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(5)
                        visible: Disks.smartTestDevice !== ""
                        radius: Theme.px(2)
                        color: Theme.alpha(Theme.text, 0.15)
                        Rectangle { width: parent.width * Disks.smartTestPercent / 100; height: parent.height; radius: parent.radius; color: Theme.accent }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Repeater {
                            model: [["short", Tr.t("Short")], ["long", Tr.t("Extended")], ["conveyance", Tr.t("Conveyance")]]
                            Choice { required property var modelData; text: modelData[1]; selected: win.smartTestKind === modelData[0]; onClicked: win.smartTestKind = modelData[0] }
                        }
                        Button {
                            text: Tr.t("Start self-test"); kind: "outline"
                            enabled: win.selectedDisk && !Disks.busy
                            onClicked: Disks.smartTest(win.selectedDisk.path, win.smartTestKind)
                        }
                    }
                }
            }
        }

        // ---- mount options (noauto / ro / uid / gid) ------------------------------
        Dialog {
            id: mountDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.8, Theme.px(420))
            title: Tr.t("Mount options")
            modal: true
            standardButtons: Dialog.Ok | Dialog.Cancel
            visible: false
            onAccepted: {
                if (win.selectedDisk) Disks.mountWithOptions(win.selectedDisk.path, win.mountOptions);
            }
            contentItem: ColumnLayout {
                spacing: Theme.px(6)
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: Tr.t("Comma-separated udisks options, e.g. ro,noauto,uid=1000,gid=1000."); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                TextField {
                    Layout.fillWidth: true
                    placeholder: "ro,noauto,uid=1000,gid=1000"
                    text: win.mountOptions
                    onTextChanged: win.mountOptions = text
                }
            }
        }

        // ---- relabel: metadata only, no reformat -----------------------------------
        Dialog {
            id: relabelDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.85, Theme.px(440))
            title: Tr.t("Change label · %1", win.selectedDisk ? win.selectedDisk.path : "")
            modal: true
            standardButtons: Dialog.Close
            contentItem: ColumnLayout {
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Tr.t("Changing the label updates filesystem metadata only — your data is kept.")
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("New label")
                    label: Tr.t("New label")
                    text: win.formNewLabel
                    onTextChanged: win.formNewLabel = text
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Button {
                        text: win.confirmAction.indexOf("relabel-") === 0 ? Tr.t("Tap again to confirm") : Tr.t("Change label")
                        kind: "outline"
                        enabled: win.formNewLabel.trim() !== ""
                        onClicked: {
                            const key = "relabel-" + (win.selectedDisk ? win.selectedDisk.path : "");
                            if (win.confirmAction === key) {
                                Disks.relabel(win.selectedDisk.path, win.formNewLabel.trim());
                                win.confirmAction = "";
                                relabelDialog.close();
                            } else { win.confirmAction = key; confirmTimer.restart(); }
                        }
                    }
                    Text {
                        text: win.confirmAction.indexOf("relabel-") === 0 ? Tr.t("Click again to confirm") : Tr.t("Label is changed in place, without reformatting")
                        color: win.confirmAction.indexOf("relabel-") === 0 ? Theme.red : Theme.dim
                        font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
            }
        }

        // ---- read-only scan output (fsck -n / badblocks -n) ------------------------
        Dialog {
            id: scanDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.9, Theme.px(560))
            height: Math.min(win.height * 0.8, Theme.px(480))
            title: Tr.t("Scan results · %1", win.selectedDisk ? win.selectedDisk.path : "")
            modal: true
            standardButtons: Dialog.Close
            contentItem: ColumnLayout {
                spacing: Theme.px(6)
                Text {
                    Layout.fillWidth: true
                    text: Disks.scanResult ? (Disks.scanResult.command === "fsck" ? Tr.t("Filesystem check") : Tr.t("Bad-block scan")) : Tr.t("Running…")
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: scanText.implicitHeight
                    ScrollBar.vertical: ScrollBar {}
                    Text {
                        id: scanText
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: Disks.scanResult ? (Disks.scanResult.output || Tr.t("Done")) : Tr.t("Working…")
                        color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                }
            }
        }

        // ---- partition list (per selected disk) ------------------------------------
        Dialog {
            id: partDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.9, Theme.px(520))
            height: Math.min(win.height * 0.8, Theme.px(480))
            title: Tr.t("Partitions · %1", win.selectedDisk ? win.selectedDisk.path : "")
            modal: true
            standardButtons: Dialog.Close
            contentItem: ColumnLayout {
                spacing: Theme.px(4)
                Repeater {
                    model: win.partList(win.selectedDisk)
                    Text {
                        required property var modelData
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: [modelData.name, (modelData.label || modelData.fstype || "").trim(),
                               win.human(modelData.size || 0),
                               (modelData.mountpoints || []).length ? "→ " + modelData.mountpoints[0] : Tr.t("(unmounted)"),
                               modelData.ro ? Tr.t("read-only") : ""] .filter(t => t !== "").join(" · ")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: win.partList(win.selectedDisk).length === 0
                    icon: "drive-harddisk"
                    title: Tr.t("No partitions")
                    subtitle: Tr.t("The disk has no partition table entries yet.")
                }
            }
        }

        // ---- tools: wipe tools on the selected disk ---------------------------------
        Dialog {
            id: toolsDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.8, Theme.px(440))
            title: Tr.t("Tools · %1", win.selectedDisk ? win.selectedDisk.path : "")
            modal: true
            standardButtons: Dialog.Close
            contentItem: ColumnLayout {
                spacing: Theme.px(6)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Button {
                        text: win.confirmAction === "wipe-quick" ? Tr.t("Tap again to confirm") : Tr.t("Quick erase")
                        kind: "danger"
                        enabled: !!win.selectedDisk
                        onClicked: {
                            if (win.confirmAction === "wipe-quick") { win.confirmAction = ""; Disks.eraseQuick(win.selectedDisk.path); }
                            else { win.confirmAction = "wipe-quick"; confirmTimer.restart(); }
                        }
                    }
                    Button {
                        text: win.confirmAction === "wipe-secure" ? Tr.t("Tap again to confirm") : Tr.t("Secure erase")
                        kind: "danger"
                        enabled: !!win.selectedDisk
                        onClicked: {
                            if (win.confirmAction === "wipe-secure") { win.confirmAction = ""; Disks.eraseSecure(win.selectedDisk.path); }
                            else { win.confirmAction = "wipe-secure"; confirmTimer.restart(); }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: Disks.jobLabel !== "" || Disks.error !== ""
                    text: Disks.jobLabel || Disks.error
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: win.selectedDisk === null
                    icon: "drive-harddisk"
                    title: Tr.t("No disk selected")
                    subtitle: Tr.t("Open a disk to run wipe tools on it.")
                }
            }
        }

        // ---- performance view: benchmark history -------------------------------------
        Dialog {
            id: perfDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.8, Theme.px(480))
            title: Tr.t("Performance")
            modal: true
            standardButtons: Dialog.Close
            contentItem: ColumnLayout {
                spacing: Theme.px(4)
                Repeater {
                    model: win.benchHistory
                    Text {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.at + "  " + modelData.mbps.toFixed(1) + Tr.t(" MB/s")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                Button { text: Tr.t("Benchmark now"); flat: true; enabled: !!win.selectedDisk && !Disks.busy; onClicked: win.runBench() }
                EmptyState {
                    anchors.centerIn: parent
                    visible: win.benchHistory.length === 0
                    icon: "drive-harddisk"
                    title: Tr.t("No benchmark results yet")
                    subtitle: Tr.t("Run the benchmark to see read speed.")
                }
            }
        }

        // ---- large files: read-only find with size + modification time preview -------
        Dialog {
            id: bigDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.85, Theme.px(520))
            height: Math.min(win.height * 0.8, Theme.px(480))
            title: Tr.t("Large files")
            modal: true
            standardButtons: Dialog.Close
            contentItem: ColumnLayout {
                spacing: Theme.px(2)
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: bigCol.implicitHeight
                    ScrollBar.vertical: ScrollBar {}
                    ColumnLayout {
                        id: bigCol
                        width: parent.width
                        Repeater {
                            model: win.bigFiles
                            Text {
                                required property var modelData
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: modelData.when + "  " + win.human(modelData.size || 0) + "\n" + modelData.path
                                color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale
                            }
                        }
                        EmptyState {
                            Layout.fillWidth: true
                            visible: win.bigFiles.length === 0
                            icon: "document-open"
                            title: bigFinder.running ? Tr.t("Scanning…") : Tr.t("No large files found")
                            subtitle: bigFinder.running ? Tr.t("Reading files from the disk") : Tr.t("Nothing above the 1 MB size threshold")
                        }
                    }
                }
            }
        }
    }
}
