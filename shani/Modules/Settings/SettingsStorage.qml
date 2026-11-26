// Settings > Storage: what takes room in your own space, and making it free -
// the Trash, the thumbnails, each app's cache, downloads untouched for months,
// Flatpak runtimes nothing uses (bridge/cleanup.py). Old downloads go to the
// Trash, not away. The system's part (update images, old snapshots) is
// Storage cleanup and what fills the disk.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/Format.js" as Format
import "../../Common/ToolPath.js" as ToolPath

ColumnLayout {
    id: page
    spacing: Theme.px(8)
    property bool active: false
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property bool fstrimEnabled: false
    property bool fstrimLoaded: false

    // System storage is a read of this system, not of a person's files. It runs
    // when the page opens or the person asks again, never on a timer.
    readonly property string healthTool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_HEALTH_TOOL"), "system_health.py")
    property var storageInfo: ({})
    property bool storageBusy: false
    property bool storageReadDone: false
    readonly property var capacityKeys: ["Free", "Total", "Used", "Snapshots", "Quotas"]
    readonly property var maintenanceKeys: ["Scrub", "Scrub tmr", "Maint tmrs", "bees", "Dedup", "Dev errors"]
    readonly property var capacityTitles: ({
        "Free": Tr.t("Free space"), "Total": Tr.t("Total space"), "Used": Tr.t("Used space"),
        "Snapshots": Tr.t("Snapshots"), "Quotas": Tr.t("Quotas")
    })
    readonly property var maintenanceTitles: ({
        "Scrub": Tr.t("Data check"), "Scrub tmr": Tr.t("Data check schedule"),
        "Maint tmrs": Tr.t("Maintenance schedule"), "bees": Tr.t("Background compression"),
        "Dedup": Tr.t("Deduplication"), "Dev errors": Tr.t("Device errors")
    })

    onActiveChanged: if (active) { scan(); fstrimGet.running = false; fstrimGet.running = true; storageReload(); }

    readonly property string tool: Quickshell.env("SHANI_CLEANUP_TOOL") || "/usr/lib/shani-shell/cleanup.py"
    property var found: null
    property bool scanning: false
    property string busy: ""                 // what is being cleaned
    property string asking: ""               // the one that needs a second click (it cannot be undone)
    property string done: ""
    readonly property real freeable: !found ? 0 : found.trash.size + found.thumbnails.size + found.downloads.size
        + found.caches.filter(c => c.keep === "").reduce((a, c) => a + c.size, 0)

    function scan() { scanning = true; scanner.running = true; }

    // Only stable read state goes to the harness. A failed read publishes an
    // empty report with its error, never an invented "all clear".
    function publishStorage() {
        const o = Object.assign({}, Ui.systemState || {});
        const info = page.storageInfo || {};
        o.storageInfo = {
            summary: info.summary || {}, warnings: info.warnings || [],
            subvolumes: info.subvolumes || [], error: info.error || "", have: !!info.have
        };
        Ui.systemState = o;
    }
    function storageReload() {
        if (page.storageBusy) return;
        page.storageBusy = true;
        page.storageReadDone = false;
        storageReader.running = false;
        storageReader.running = true;
        publishStorage();
    }
    function applyStorage(r) {
        const raw = r && typeof r === "object" ? r : {};
        page.storageInfo = {
            have: !!raw.have,
            error: raw.error ? String(raw.error) : "",
            summary: raw.summary && typeof raw.summary === "object" ? raw.summary : {},
            subvolumes: Array.isArray(raw.subvolumes) ? raw.subvolumes : [],
            warnings: Array.isArray(raw.warnings) ? raw.warnings : []
        };
        page.storageReadDone = true;
        publishStorage();
    }
    function sizeText(v) { return typeof v === "number" ? page.human(v) : String(v || ""); }
    function statusIcon(s) {
        const v = String(s || "").toLowerCase();
        if (v === "ok" || v === "pass" || v === "passed" || v === "good") return "dialog-ok";
        if (["warn", "warning", "critical", "fail", "failed", "error"].indexOf(v) >= 0) return "dialog-warning";
        return "dialog-information";
    }
    function storageDetail(row) {
        if (!row || typeof row !== "object") return "";
        let out = String(row.message || "");
        const used = page.sizeText(row.used);
        const uncompressed = page.sizeText(row.uncompressed);
        if (uncompressed !== "") {
            const extra = used !== ""
                ? Tr.t("uses %1, uncompressed %2").arg(used).arg(uncompressed)
                : Tr.t("uncompressed %1").arg(uncompressed);
            out = out ? out + "  ·  " + extra : extra;
        } else if (out === "" && used !== "") {
            out = Tr.t("uses %1").arg(used);
        }
        return out;
    }

    function clean(what, arg, label) {
        busy = what + (arg ? ":" + arg : "");
        asking = "";
        cleaner.label = label;
        cleaner.command = ["python3", page.tool, "clean", what].concat(arg ? [arg] : []);
        cleaner.running = true;
    }
    // emptying the Trash and deleting a cache cannot be undone: a second click
    function confirmThen(key, what, arg, label) {
        if (page.asking !== key) { page.asking = key; askTimer.restart(); return; }
        page.clean(what, arg, label);
    }
    Timer { id: askTimer; interval: 4000; onTriggered: page.asking = "" }
    Component.onCompleted: { scan(); fstrimGet.running = false; fstrimGet.running = true; if (active) storageReload(); else publishStorage(); }
    onStorageInfoChanged: publishStorage()
    // read-only status: no pkexec, so the toggle is never hidden behind an auth prompt
    Process { id: fstrimGet; command: ["sh", "-c", "systemctl is-enabled fstrim.timer 2>/dev/null || true"]; stdout: StdioCollector { onStreamFinished: { page.fstrimEnabled = text.trim() === "enabled" || text.trim() === "static"; page.fstrimLoaded = true; } } }
    Process { id: fstrimSet; stdinEnabled: true; property string payload: ""; onStarted: { write(payload + "\n"); stdinEnabled = false; } onExited: code => { stdinEnabled = true; fstrimGet.running = false; fstrimGet.running = true; if (code !== 0) page.done = Tr.t("Could not change SSD trim"); } }
    Process {
        id: scanner
        command: ["python3", page.tool, "scan"]
        stdout: StdioCollector { onStreamFinished: { try { page.found = JSON.parse(text); } catch (e) {} page.scanning = false; } }
        onExited: page.scanning = false
    }
    Process {
        id: storageReader
        command: ["python3", page.healthTool, "storage"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text) || {}; }
                catch (e) { r = { have: false, error: Tr.t("Could not read the storage check") }; }
                page.applyStorage(r);
            }
        }
        onExited: code => {
            if (code !== 0 && (!page.storageInfo.have || !page.storageReadDone))
                page.applyStorage({ have: false, error: Tr.t("The storage check could not finish") });
            page.storageBusy = false;
            publishStorage();
        }
    }
    Process {
        id: cleaner
        property string label: ""
        stderr: StdioCollector { id: cleanErr }
        onExited: code => {
            page.done = code === 0 ? Tr.t("Done: %1").arg(cleaner.label) : (cleanErr.text.trim().split("\n").pop() || Tr.t("Could not clean that"));
            page.busy = "";
            page.scan();
        }
    }
    function human(b) { return Format.humanSize(b, "si"); }

    component Row_: RowLayout {
        id: r
        property string icon
        property string title
        property string detail
        property real size: 0
        property string action: Tr.t("Clean")
        property bool danger: false
        property bool asking: false
        property bool working: false
        property bool can: size > 0
        signal go()
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.px(52)
        spacing: Theme.px(12)
        Icon { name: r.icon; size: Theme.px(22); color: Theme.dim }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text { Layout.fillWidth: true; text: r.title; color: Theme.text; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: Theme.type("body") }
            Text { Layout.fillWidth: true; visible: r.detail !== ""; text: r.detail; color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: Theme.type("small") }
        }
        Text { text: page.human(r.size); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("body"); font.features: { "tnum": 1 } }
        Button {
            Layout.preferredWidth: Theme.px(140)
            enabled: r.can && !r.working && page.busy === ""
            kind: r.asking ? "danger" : "plain"
            text: r.working ? Tr.t("Cleaning…") : r.asking ? Tr.t("Click again") : r.action
            onClicked: r.go()
        }
    }


    RowLayout {
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: page.scanning && !page.found ? Tr.t("Measuring…") : Tr.t("Up to %1 can be freed").arg(page.human(page.freeable))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.type("subtitle")
                font.weight: Font.DemiBold
            }
            Text {
                text: page.done !== "" ? page.done : Tr.t("Only your own files. Nothing here is needed to use the computer.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
            }
        }
        IconButton { size: Theme.px(30); icon: "view-refresh"; tip: Tr.t("Measure again"); onClicked: page.scan() }
    }

    Row_ {
        visible: !!page.found
        icon: "user-trash"
        title: Tr.t("Trash")
        detail: page.found ? page.found.trash.count + " " + Tr.t("items") + "  ·  " + Tr.t("emptying it cannot be undone") : ""
        size: page.found ? page.found.trash.size : 0
        action: Tr.t("Empty")
        asking: page.asking === "trash"
        working: page.busy === "trash"
        onGo: page.confirmThen("trash", "trash", "", Tr.t("the Trash is empty"))
    }
    Row_ {
        visible: !!page.found
        icon: "image-x-generic"
        title: Tr.t("Thumbnails")
        detail: Tr.t("small copies of pictures and videos; made again when needed")
        size: page.found ? page.found.thumbnails.size : 0
        working: page.busy === "thumbnails"
        onGo: page.clean("thumbnails", "", Tr.t("thumbnails cleared"))
    }
    Row_ {
        visible: !!page.found
        icon: "folder-download"
        title: Tr.t("Old downloads")
        detail: page.found ? (page.found.downloads.count > 0
            ? Tr.t("%1 untouched for %2 days, into the Trash").arg(page.found.downloads.count).arg(page.found.downloads.days)
            : Tr.t("nothing older than %1 days").arg(page.found.downloads.days)) : ""
        size: page.found ? page.found.downloads.size : 0
        action: Tr.t("Move to Trash")
        working: page.busy === "downloads"
        onGo: page.clean("downloads", "", Tr.t("old downloads are in the Trash"))
    }
    Row_ {
        visible: !!page.found && page.found.flatpak
        icon: "package-x-generic"
        title: Tr.t("Unused Flatpak runtimes")
        detail: Tr.t("left behind by apps that were removed")
        size: 0
        can: true
        action: Tr.t("Remove")
        working: page.busy === "flatpak"
        onGo: page.clean("flatpak", "", Tr.t("unused runtimes removed"))
    }
    // what removed apps left in your home folder is Software's Leftovers list
    ListRow {
        Layout.fillWidth: true
        icon: "edit-clear"
        title: Tr.t("Data left by removed apps")
        subtitle: Tr.t("settings and files apps leave in your home folder — in Software")
        trailing: "›"
        onClicked: Ui.openSoftware("leftovers")
    }

    SettingsSection {
        spacing: Theme.px(8)
        visible: page.fstrimLoaded
        title: Tr.t("SSD maintenance")
        SwitchRow {
        Layout.fillWidth: true
        visible: page.fstrimLoaded
        text: Tr.t("Trim SSD weekly (fstrim.timer)")
        hint: Tr.t("Keeps SSD performance steady; safe to leave on")
        checked: page.fstrimEnabled
        onToggled: on => { fstrimSet.payload = JSON.stringify({ enabled: on }); fstrimSet.command = page.adminCmd.concat(["fstrim-set"]); fstrimSet.running = true; }
    }
    }

    SettingsSection {
        spacing: Theme.px(8)
        visible: !!page.found && page.found.caches.length > 0
        title: Tr.t("App caches")
        Repeater {
        model: page.found ? page.found.caches.filter(c => c.size > 0) : []
        delegate: Row_ {
            required property var modelData
            Layout.fillWidth: true
            icon: modelData.keep !== "" ? "emblem-readonly" : "folder"
            title: modelData.name
            detail: modelData.keep !== "" ? Tr.t("kept: %1").arg(modelData.keep) : Tr.t("the app makes it again as it needs it")
            size: modelData.size
            can: modelData.keep === "" && modelData.size > 0
            asking: page.asking === "cache:" + modelData.name
            working: page.busy === "cache:" + modelData.name
            onGo: page.confirmThen("cache:" + modelData.name, "cache", modelData.name, modelData.name + " " + Tr.t("cleared"))
        }
    }
    }

    SettingsSection {
        Layout.fillWidth: true
        spacing: Theme.px(8)
        title: Tr.t("System storage")
        hint: Tr.t("Space and upkeep on this system. Reading it may ask for administrator access; nothing here is changed.")

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Read storage")
                enabled: !page.storageBusy
                busy: page.storageBusy
                onClicked: page.storageReload()
            }
            Item { Layout.fillWidth: true }
        }
        BusyNote { Layout.fillWidth: true; visible: page.storageBusy; note: Tr.t("Reading storage…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.storageReadDone && !page.storageInfo.have
            tone: "error"
            title: Tr.t("Storage check could not finish")
            text: page.storageInfo.error || Tr.t("No storage details could be read; nothing was changed.")
        }

        Repeater {
            model: page.capacityKeys
            ListRow {
                required property string modelData
                Layout.fillWidth: true
                visible: !!page.storageInfo.summary && !!page.storageInfo.summary[modelData]
                icon: "drive-harddisk"
                title: page.capacityTitles[modelData] || modelData
                subtitle: page.storageDetail((page.storageInfo.summary || {})[modelData] || {})
                interactive: false
            }
        }
        Repeater {
            model: page.maintenanceKeys
            ListRow {
                required property string modelData
                Layout.fillWidth: true
                visible: !!page.storageInfo.summary && !!page.storageInfo.summary[modelData]
                icon: page.statusIcon(((page.storageInfo.summary || {})[modelData] || {}).status)
                title: page.maintenanceTitles[modelData] || modelData
                subtitle: page.storageDetail((page.storageInfo.summary || {})[modelData] || {})
                interactive: false
            }
        }
        Repeater {
            model: page.storageInfo.subvolumes || []
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: page.statusIcon(modelData.status)
                title: modelData.name || Tr.t("Subvolume")
                subtitle: page.storageDetail(modelData)
                interactive: false
            }
        }
        Repeater {
            model: page.storageInfo.warnings || []
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: page.statusIcon(modelData.status)
                title: modelData.message || modelData.key || Tr.t("Warning")
                interactive: false
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: page.storageReadDone && page.storageInfo.have && !page.storageBusy
                && Object.keys(page.storageInfo.summary || {}).length === 0
                && (page.storageInfo.subvolumes || []).length === 0
                && (page.storageInfo.warnings || []).length === 0
            icon: "drive-harddisk"
            title: Tr.t("No storage details")
            subtitle: Tr.t("The check finished without any storage details to show.")
        }
    }

    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Tr.t("Update images, old snapshots and the system's logs can take space; clean them up when you need room.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
        }

    }

    RowLayout {
        Layout.fillWidth: true
        Button { text: Tr.t("What fills the disk…"); flat: true; onClicked: { Ui.closeAll(); Ui.diskUsage = true; } }
    }
}
