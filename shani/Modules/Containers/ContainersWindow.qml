// Containers (Pods' and BoxBuddy's jobs, the way Ananta Dev does them): Distrobox
// toolboxes - a whole Ubuntu, Fedora, Arch or Debian sharing your home folder -
// made from a chip, opened in your terminal, their apps put in your menu, upgraded,
// removed; and your rootless Podman containers (start, stop, restart, logs, remove)
// and images (remove, prune). Everything through bridge/containers.py, as you - no
// administrator password. The Containers app owns the live inventory.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Containers"
    visible: Ui.containers
    onGone: Ui.containers = false
    implicitWidth: Theme.px(680)
    implicitHeight: Theme.px(620)

    readonly property string tool: Quickshell.env("SHANI_CONTAINERS_TOOL") || "/usr/lib/shani-shell/containers.py"
    // the toolboxes Ananta Dev offers, and the images they come from
    readonly property var distros: [
        ["ubuntu", "Ubuntu 24.04", "docker.io/library/ubuntu:24.04"],
        ["fedora", "Fedora", "registry.fedoraproject.org/fedora-toolbox:latest"],
        ["arch", "Arch Linux", "docker.io/library/archlinux:latest"],
        ["debian", "Debian 13", "docker.io/library/debian:13"]
    ]
    property string tab: "boxes"
    property var containers: []
    property var images: []
    property bool hasPodman: true
    property bool hasDistrobox: true
    property string error: ""
    property string note: ""
    property string removing: ""
    property string logsOf: ""
    property string logsText: ""
    property string appsOf: ""             // the toolbox whose apps are listed
    property var apps: []
    property string distro: "ubuntu"
    property string jobLine: ""
    readonly property var boxes: containers.filter(c => c.box)
    readonly property var others: containers.filter(c => !c.box)
    property var exportedApps: []          // "box:app" keys put in the menu this session
    onTabChanged: win.removing = ""        // an armed confirmation must not survive a tab switch
    onRemovingChanged: if (removing !== "") confirmTimer.restart()
    function exported(box, id) { return win.exportedApps.indexOf(box + ":" + id) >= 0; }
    function toggleExport(box, id, name) {
        const key = box + ":" + id;
        if (win.exported(box, id))
            win.run(["box-unexport", box, id], r => { if (r.ok) { win.exportedApps = win.exportedApps.filter(x => x !== key); Ui.containersExported = ""; win.note = Tr.t("%1 left your menu", name); } });
        else
            win.run(["box-export", box, id], r => { if (r.ok) { win.exportedApps = win.exportedApps.concat(key); Ui.containersExported = id; win.note = Tr.t("%1 is in your menu", name); } });
    }

    function refresh() { lister.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    Timer { interval: 5000; repeat: true; running: win.visible && !job.running; onTriggered: win.refresh() }
    Timer { id: confirmTimer; interval: 8000; onTriggered: win.removing = "" }

    Process {
        id: lister
        command: ["python3", win.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { return; }
                if (r.error) win.error = r.error;
                win.hasPodman = !!r.podman;
                win.hasDistrobox = !!r.distrobox;
                win.containers = r.containers || [];
                win.images = r.images || [];
                // a vanished item must not keep an armed delete or an open log
                // panel: a later container with the same name would inherit them
                if (win.logsOf !== "" && !win.containers.some(c => c.name === win.logsOf)) {
                    win.logsOf = "";
                    win.logsText = "";
                }
                if (win.removing !== "" && win.removing !== "__prune__" && !win.containers.some(c => c.name === win.removing))
                    win.removing = "";
                Ui.containersList = win.containers.map(c => (c.box ? "box:" : "") + c.name + ":" + c.state);
                Ui.containersImages = win.images.map(i => i.name);
            }
        }
    }
    Process {
        id: act
        property var after: null
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                win.error = r.error || "";
                if (act.after) act.after(r);
                win.refresh();
            }
        }
    }
    function run(args, after) {
        if (act.running) return;
        win.note = "";                 // a success note belongs to this action alone
        act.command = ["python3", win.tool].concat(args);
        act.after = after || null;
        act.running = true;
    }
    // the long ones (a toolbox made, upgraded): a line at a time
    Process {
        id: job
        property string what: ""
        stdout: SplitParser {
            onRead: line => {
                let r = {};
                try { r = JSON.parse(line); } catch (e) { return; }
                if (r.line) win.jobLine = r.line;
                if (r.error) win.error = r.error;
                if (r.ok) { Ui.containersDone = job.what + ":ok"; win.note = Tr.t("Done: %1", job.what); }
            }
        }
        onExited: { win.jobLine = ""; win.refresh(); }
    }
    function startJob(what, args) {
        if (job.running) return;
        win.error = "";
        job.what = what;
        job.command = ["python3", win.tool].concat(args);
        job.running = true;
    }
    function nextName(d) {
        let n = d, i = 2;
        while (win.containers.some(c => c.name === n)) n = d + "-" + i++;
        return n;
    }
    function enter(name) {
        Quickshell.execDetached(["xdg-terminal-exec", "distrobox", "enter", name]);
        Ui.containersEntered = name;
    }
    function showLogs(name) {
        if (win.logsOf === name) { win.logsOf = ""; return; }
        win.run(["logs", name], r => { win.logsOf = name; win.logsText = r.text || ""; });
    }
    function showApps(name) {
        if (win.appsOf === name) { win.appsOf = ""; return; }
        win.apps = [];
        win.appsOf = name;
        win.run(["box-apps", name], r => { win.apps = Array.isArray(r) ? r : []; Ui.containersApps = win.apps.map(a => a.id); });
    }
    function size(b) { return b > 1e9 ? (b / 1e9).toFixed(1) + " GB" : Math.round(b / 1e6) + " MB"; }

    // ---- the container-manager upgrade: stats, inspect, started/stopped filters, sort ----
    property string filter: "all"            // the containers tab: "all" | "running" | "stopped"
    property string sortKey: "name"          // containers: name | status; images: name | size
    property bool sortDesc: false
    property var statsOf: []                  // name -> {cpu, mem}, from `podman stats`
    property string inspected: ""            // the container whose details the panel shows
    property var inspectData: []

    function cmpKey(a, b) {
        let av, bv;
        if (win.sortKey === "status") { av = a.state === "running" ? 0 : 1; bv = b.state === "running" ? 0 : 1; }
        else if (win.sortKey === "size") { av = a.size || 0; bv = b.size || 0; }
        else { av = (a[win.sortKey] || "").toString().toLowerCase(); bv = (b[win.sortKey] || "").toString().toLowerCase(); }
        if (av === bv) { av = (a.name || "").toLowerCase(); bv = (b.name || "").toLowerCase(); }
        return av < bv ? -1 : (av > bv ? 1 : 0);
    }
    readonly property var visibleContainers: win.others.filter(c => win.filter === "all"
        || (win.filter === "running" ? c.state === "running" : c.state !== "running"))
    readonly property var sortedContainers: win.visibleContainers.slice().sort((a, b) => win.cmpKey(a, b) * (win.sortDesc ? -1 : 1))
    readonly property var sortedImages: win.images.slice().sort((a, b) => win.cmpKey(a, b) * (win.sortDesc ? -1 : 1))

    function statsText(name) { const s = win.statsOf[name]; return s ? [s.cpu, s.mem].filter(x => x).join(" ").trim() : ""; }
    function statsRun() {
        if (!win.hasPodman || win.tab !== "containers" || statsProc.running) return;
        statsProc.command = [Quickshell.env("SHANI_PODMAN") || "podman", "stats", "--no-stream", "--all", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}"];
        statsProc.running = true;
    }
    Process {
        id: statsProc
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of text.split("\n")) {
                    const p = line.split("|");
                    if (p[0]) m[p[0]] = { cpu: p[1] || "", mem: p[2] || "" };
                }
                win.statsOf = m;
            }
        }
    }
    Timer { id: statsTimer; interval: 20000; repeat: true; running: win.visible && win.hasPodman && win.tab === "containers"; onTriggered: win.statsRun() }

    function refreshLogs(name) {              // the log panel's own refresh; the poll keeps it live
        if (win.logsOf !== name) return;
        win.run(["logs", name], r => { if (win.logsOf === name) win.logsText = r.text || ""; });
    }
    Timer { id: logTimer; interval: 10000; running: win.logsOf !== ""; onTriggered: win.refreshLogs(win.logsOf) }

    function inspect(name) {
        if (win.inspected === name) { win.inspected = ""; return; }
        win.inspected = name;
        win.inspectData = [];
        inspectProc.command = [Quickshell.env("SHANI_PODMAN") || "podman", "inspect", name];
        inspectProc.running = true;
    }
    Process {
        id: inspectProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = [];
                try { d = JSON.parse(text); } catch (e) { d = []; }
                win.inspectData = Array.isArray(d) ? d : [];
            }
        }
    }
    function inspectRows(name) {
        const d = win.inspectData.find(x => x && (x.Names ? x.Names.indexOf(name) >= 0 : x.Name === name)) || win.inspectData[0] || {};
        const st = d.State || {};
        const status = typeof st === "string" ? st : (st.Status || "");
        const ports = (d.Ports || []).map(p => [(p.HostIp || p.host_ip || "").trim(), (p.HostPort || p.host_port || p.PublicPort || "")].filter(x => x).join(":") + "→" + (p.ContainerPort || p.container_port || p.PrivatePort || "")).filter(x => x);
        return [[Tr.t("Name"), d.Name], [Tr.t("Id"), (d.Id || "").slice(0, 12)], [Tr.t("State"), status], [Tr.t("Image"), d.Image], [Tr.t("Ports"), ports.join(", ")]].filter(r => r[1]);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(14)
        spacing: Theme.px(8)
        focus: true
        Keys.onEscapePressed: win.visible = false
        Keys.onPressed: event => { if (event.key === Qt.Key_F5) { event.accepted = true; win.refresh(); } }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [["boxes", Tr.t("Toolboxes")], ["containers", Tr.t("Containers")], ["images", Tr.t("Images")]]
                Choice { required property var modelData; text: modelData[1]; selected: win.tab === modelData[0]; onClicked: win.tab = modelData[0] }
            }
            Item { Layout.fillWidth: true }
            IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Read again"); onClicked: win.refresh() }
        }
        RowLayout {                            // the sort control: containers (status) or images (size)
            visible: win.tab === "containers" || win.tab === "images"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text { text: Tr.t("Sort"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Repeater {
                model: win.tab === "images" ? [["name", Tr.t("Name")], ["size", Tr.t("Size")]] : [["name", Tr.t("Name")], ["status", Tr.t("Status")]]
                Choice { required property var modelData; text: modelData[1]; selected: win.sortKey === modelData[0]; onClicked: win.sortKey = modelData[0] }
            }
            Choice { text: Tr.t("Descending"); selected: win.sortDesc; onClicked: win.sortDesc = !win.sortDesc }
        }
        Text {
            visible: !win.hasPodman || win.error !== "" || win.note !== "" || win.jobLine !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: !win.hasPodman ? Tr.t("Podman is not installed") : win.error !== "" ? win.error : win.jobLine !== "" ? win.jobLine : win.note
            color: win.error !== "" || !win.hasPodman ? Theme.danger : Theme.dim
            font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }

        // ---- toolboxes (Distrobox) ----
        ColumnLayout {
            visible: win.tab === "boxes" && win.hasDistrobox
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.t("A toolbox is a whole Linux that shares your home folder: install its packages without touching the system, and put its apps in your menu.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.distros
                    Choice { required property var modelData; text: modelData[1]; selected: win.distro === modelData[0]; onClicked: win.distro = modelData[0] }
                }
                Item { Layout.fillWidth: true }
                Button {
                    kind: "primary"
                    text: job.running && job.what.indexOf("create") === 0 ? Tr.t("Making it…") : Tr.t("New toolbox")
                    enabled: !job.running
                    onClicked: {
                        const d = win.distros.find(x => x[0] === win.distro);
                        const n = win.nextName(d[0]);
                        win.startJob("create " + n, ["box-create", n, d[2]]);
                    }
                }
            }
        }
        Text {
            visible: win.tab === "boxes" && !win.hasDistrobox
            text: Tr.t("Distrobox is not installed")
            color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Text {
            visible: win.tab === "boxes" && win.hasDistrobox && win.boxes.length === 0
            text: Tr.t("No toolboxes yet - pick a Linux above")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: blist
            visible: win.tab === "boxes"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.px(4)
            model: win.boxes
            delegate: ColumnLayout {
                id: brow
                required property var modelData
                width: blist.width
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Icon { name: "utilities-terminal"; size: Theme.px(22); color: brow.modelData.state === "running" ? Theme.accent : Theme.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: brow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: [brow.modelData.state === "running" ? Tr.t("running") : Tr.t("stopped"), brow.modelData.image].join("  ·  ")
                            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                    Button { text: Tr.t("Open"); onClicked: win.enter(brow.modelData.name) }
                    IconButton { icon: "view-app-grid"; size: Theme.px(26); tip: Tr.t("Its apps, for your menu"); onClicked: win.showApps(brow.modelData.name) }
                    IconButton { icon: "system-software-update"; size: Theme.px(26); tip: Tr.t("Update its packages"); enabled: !job.running; onClicked: win.startJob("upgrade " + brow.modelData.name, ["box-upgrade", brow.modelData.name]) }
                    IconButton {
                        visible: brow.modelData.state === "running"
                        icon: "media-playback-stop"; size: Theme.px(26); tip: Tr.t("Stop")
                        onClicked: { const name = brow.modelData.name; win.run(["stop", name], r => { if (r.ok) win.note = Tr.t("Stopped %1", name); }); }
                    }
                    IconButton {
                        icon: win.removing === brow.modelData.name ? "edit-delete" : "window-close"
                        size: Theme.px(26)
                        tip: win.removing === brow.modelData.name ? Tr.t("Click again: %1 and its apps are removed (your home folder stays)", brow.modelData.name) : Tr.t("Remove")
                        onClicked: { if (win.removing === brow.modelData.name) { win.removing = ""; win.run(["box-remove", brow.modelData.name]); } else win.removing = brow.modelData.name; }
                    }
                }
                ColumnLayout {
                    visible: win.appsOf === brow.modelData.name
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(30)
                    spacing: 2
                    Text {
                        visible: win.apps.length === 0
                        text: act.running ? Tr.t("Looking…") : Tr.t("No apps inside yet - install some in its terminal")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Repeater {
                        model: win.appsOf === brow.modelData.name ? win.apps : []
                        RowLayout {
                            id: arow
                            required property var modelData
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: arow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                            Button {
                                text: win.exported(brow.modelData.name, arow.modelData.id) ? Tr.t("Remove from menu") : Tr.t("Add to menu")
                                onClicked: win.toggleExport(brow.modelData.name, arow.modelData.id, arow.modelData.name)
                            }
                        }
                    }
                }
            }
        }

        // ---- containers (Podman) ----
        Text {
            visible: win.tab === "containers" && win.others.length === 0
            text: Tr.t("No containers - podman run, docker compose or an IDE's dev container show up here")
            wrapMode: Text.WordWrap; Layout.fillWidth: true
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Text {                                            // the filter narrows the list; the message above stays for "no containers at all"
            visible: win.tab === "containers" && win.others.length > 0 && win.sortedContainers.length === 0
            text: Tr.t("No containers match the filter")
            wrapMode: Text.WordWrap; Layout.fillWidth: true
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        RowLayout {
            visible: win.tab === "containers" && win.others.length > 0
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text { text: Tr.t("Show"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Repeater {
                model: [["all", Tr.t("All")], ["running", Tr.t("Running")], ["stopped", Tr.t("Stopped")]]
                Choice { required property var modelData; text: modelData[1]; selected: win.filter === modelData[0]; onClicked: win.filter = modelData[0] }
            }
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: clist
            visible: win.tab === "containers"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.px(4)
            model: win.sortedContainers
            delegate: ColumnLayout {
                id: crow
                required property var modelData
                readonly property bool up: modelData.state === "running"
                width: clist.width
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Icon { name: "package-x-generic"; size: Theme.px(22); color: crow.up ? Theme.accent : Theme.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: crow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: [crow.modelData.state, crow.modelData.image, crow.modelData.ports, win.statsText(crow.modelData.name)].filter(x => x).join("  ·  ")
                            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                    IconButton {
                        icon: crow.up ? "media-playback-stop" : "media-playback-start"; size: Theme.px(26); tip: crow.up ? Tr.t("Stop") : Tr.t("Start")
                        onClicked: {
                            const verb = crow.up ? "stop" : "start", name = crow.modelData.name;
                            win.run([verb, name], r => { if (r.ok) win.note = Tr.t("%1 %2", name, verb === "stop" ? Tr.t("stopped") : Tr.t("started")); });
                        }
                    }
                    IconButton { visible: crow.up; icon: "view-refresh"; size: Theme.px(26); tip: Tr.t("Restart"); onClicked: { const name = crow.modelData.name; win.run(["restart", name], r => { if (r.ok) win.note = Tr.t("Restarted %1", name); }); } }
                    IconButton { icon: "text-x-generic"; size: Theme.px(26); tip: Tr.t("Logs"); onClicked: win.showLogs(crow.modelData.name) }
                    IconButton { icon: "document-properties"; size: Theme.px(26); tip: Tr.t("Inspect"); onClicked: win.inspect(crow.modelData.name) }
                    IconButton {
                        icon: win.removing === crow.modelData.name ? "edit-delete" : "window-close"
                        size: Theme.px(26)
                        tip: win.removing === crow.modelData.name ? Tr.t("Click again: %1 is removed", crow.modelData.name) : Tr.t("Remove")
                        onClicked: { if (win.removing === crow.modelData.name) { win.removing = ""; win.run(["remove", crow.modelData.name]); } else win.removing = crow.modelData.name; }
                    }
                }
                Rectangle {
                    visible: win.logsOf === crow.modelData.name
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(180)
                    color: Theme.card
                    radius: Theme.px(6)
                    RowLayout {
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        height: Theme.px(22)
                        spacing: Theme.px(6)
                        IconButton { icon: "view-refresh"; size: Theme.px(20); tip: Tr.t("Read again"); onClicked: win.refreshLogs(crow.modelData.name) }
                    }
                    Flickable {
                        id: lf
                        anchors.top: parent.top; anchors.topMargin: Theme.px(24)
                        anchors.left: parent.left; anchors.leftMargin: Theme.px(6)
                        anchors.right: parent.right; anchors.rightMargin: Theme.px(6)
                        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.px(6)
                        clip: true
                        contentHeight: lt.implicitHeight
                        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                        Text {
                            id: lt
                            width: lf.width
                            wrapMode: Text.WrapAnywhere
                            text: win.logsOf === crow.modelData.name ? (win.logsText || Tr.t("Nothing logged")) : ""
                            color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                }
                ColumnLayout {                            // the inspect panel: name, id, state, image, ports
                    visible: win.inspected === crow.modelData.name
                    Layout.fillWidth: true
                    spacing: 1
                    Repeater {
                        model: win.inspectRows(crow.modelData.name)
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData[0]; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                            Text { text: modelData[1]; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        }
                    }
                }
            }
        }

        // ---- images ----
        RowLayout {
            visible: win.tab === "images"
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: Tr.t("%1 images, %2", win.images.length, win.size(win.images.reduce((s, i) => s + (i.size || 0), 0)))
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Button {
                text: win.removing === "__prune__" ? Tr.t("Click again: remove unused images") : Tr.t("Remove unused")
                enabled: win.images.some(i => !i.used)
                onClicked: {
                    if (win.removing === "__prune__") {
                        win.removing = "";
                        win.run(["prune"], r => { if (r.ok) win.note = Tr.t("%1 images removed", r.removed); });
                    } else win.removing = "__prune__";
                }
            }
        }
        EmptyState {
            visible: win.tab === "images" && win.images.length === 0
            icon: "media-optical"
            title: Tr.t("No images yet")
            subtitle: Tr.t("Images appear as containers run, or after a remove")
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: ilist
            visible: win.tab === "images"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: win.sortedImages
            delegate: RowLayout {
                id: irow
                required property var modelData
                width: ilist.width
                spacing: Theme.px(8)
                Icon { name: "media-optical"; size: Theme.px(20); color: Theme.dim }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: irow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                    Text {
                        text: [win.size(irow.modelData.size || 0), irow.modelData.used ? Tr.t("in use") : Tr.t("unused")].join("  ·  ")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                IconButton {
                    visible: !irow.modelData.used
                    icon: win.removing === irow.modelData.id ? "edit-delete" : "window-close"
                    size: Theme.px(26)
                    tip: win.removing === irow.modelData.id ? Tr.t("Click again: the image is removed") : Tr.t("Remove")
                    onClicked: { if (win.removing === irow.modelData.id) { win.removing = ""; win.run(["image-remove", irow.modelData.id]); } else win.removing = irow.modelData.id; }
                }
            }
        }
    }
}
