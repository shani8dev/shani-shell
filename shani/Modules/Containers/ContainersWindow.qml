// Containers: toolboxes - a whole Ubuntu, Fedora, Arch or Debian sharing your
// home folder - made from a chip, opened in your terminal, their apps put in your
// menu, upgraded, removed; rootless containers and images (run, logs, pause,
// rename, save, stats, pods, volumes); and system machines and disk images,
// booted as a container or a virtual machine. Everything through the bridges,
// as you where possible - no administrator password. The Containers app owns
// the live inventory.
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
    property string group: "toolboxes"       // Containers, Toolboxes, Machines & VMs, Android
    property string tab: "boxes"              // the view inside the group
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

    // ---- starting a container: every value a pick, typing only for a custom one ----
    property bool newOpen: false
    property string newImage: "docker.io/library/nginx:latest"
    property string customImage: ""
    property string newPorts: "none"
    property string customPorts: ""
    property string newVolumes: "none"
    property string customVolumes: ""
    property string newEnv: "none"
    property string customEnv: ""
    property string newCommand: "default"
    property string customCommand: ""
    property string moreOf: ""             // the container whose extra actions are open
    property string followOf: ""           // the container whose logs are followed
    property var followLines: []
    property string logSearch: ""
    property string renameOf: ""
    property string renameName: ""
    property string customRename: ""
    property string commitOf: ""
    property string commitImage: ""
    property string customCommit: ""
    property string statsOfContainer: ""
    property var statsData: ({})
    property var boxInfo: ({})
    property string detailsOf: ""
    property string boxInstallOf: ""
    property string boxHome: "shared"
    property string boxNvidia: "no"
    property string boxHooks: "none"
    property string customHooks: ""
    property var pods: []
    property var volumes: []
    property string volumeName: ""
    property string customVolume: ""
    property var machines: []
    property var machineImages: []
    property bool hasMachinectl: false
    property bool hasImportctl: false
    property bool hasVmspawn: false
    property string machineView: "machines"
    property string imageUrl: "https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-basic.tar.zst"
    property string customUrl: ""
    property string pullName: "newmachine"
    property string customPullName: ""
    property string imageRenameOf: ""
    property string imageRenameName: ""
    property string customImageRename: ""
    property string pullType: "tar"
    property string vmFile: ""
    property string searchTerm: "nginx"
    property string customSearch: ""
    property var searchResults: []
    property string pullImage: ""
    property string customPull: ""
    property bool useGpu: false
    property bool cdiReady: false

    // ---- LXD system containers ----
    property var lxdInstances: []
    property bool lxdReady: false
    property bool hasLxc: false
    property string lxdImage: "ubuntu:24.04"
    property string customLxdImage: ""
    property string lxdName: ""
    // ---- Apptainer images ----
    property var sifImages: []
    property bool hasApptainer: false
    property string sifFolder: Quickshell.env("SHANI_APPTAINER_FOLDER") || ((Quickshell.env("HOME") || "") + "/Apptainer")
    property string apptainerRef: "docker://ubuntu:22.04"
    property string customApptainerRef: ""
    property string sifName: ""
    // ---- VMs ----
    property var domains: []
    property bool kvmOk: false
    property bool hasVirsh: false
    property bool hasViewer: false
    property bool hasBoxes: false
    property bool systemVms: false
    property string vmUri: "session"
    // ---- Android ----
    property var android: ({})
    // ---- compose and services ----
    property string composeFolder: ""
    property string serviceName: ""
    property string serviceImage: ""
    property string customServiceImage: ""
    property bool serviceGpu: false
    property var serviceStatus: ({})
    property var services: []

    onTabChanged: win.removing = ""        // an armed confirmation must not survive a tab switch
    Connections {
        target: win
        function onTabChanged() { win.moreOf = ""; win.refreshExtra(); }
    }
    onRemovingChanged: if (removing !== "") confirmTimer.restart()
    function exported(box, id) { return win.exportedApps.indexOf(box + ":" + id) >= 0; }
    function toggleExport(box, id, name) {
        const key = box + ":" + id;
        if (win.exported(box, id))
            win.run(["box-unexport", box, id], r => { if (r.ok) { win.exportedApps = win.exportedApps.filter(x => x !== key); Ui.containersExported = ""; win.note = Tr.t("%1 left your menu", name); } });
        else
            win.run(["box-export", box, id], r => { if (r.ok) { win.exportedApps = win.exportedApps.concat(key); Ui.containersExported = id; win.note = Tr.t("%1 is in your menu", name); } });
    }

    function subViews() {
        if (win.group === "toolboxes") return [["boxes", Tr.t("Toolboxes")], ["apptainer", Tr.t("HPC images")]]
        if (win.group === "containers") return [["containers", Tr.t("App containers")], ["images", Tr.t("Images")], ["pods", Tr.t("Pods")], ["volumes", Tr.t("Volumes")], ["compose", Tr.t("Compose")], ["services", Tr.t("Services")]]
        if (win.group === "machines") return [["machines", Tr.t("Machines")], ["images", Tr.t("Machine images")], ["vms", Tr.t("Virtual machines")], ["lxd", Tr.t("System containers")], ["boot", Tr.t("Boot a disk image")]]
        return []
    }
    function isMachineView(v) { return win.group === "machines" && ["machines", "images", "boot"].indexOf(v) >= 0; }
    function viewSelected(v) {
        return isMachineView(v) ? (win.tab === "machines" && win.machineView === v) : win.tab === v;
    }
    function selectView(v) {
        if (isMachineView(v)) { win.tab = "machines"; win.machineView = v; }
        else win.tab = v;
    }
    function go(group, tab) {
        win.group = group;                 // subViews() reads the new group
        if (!tab) {
            const views = win.subViews();
            tab = views.length ? views[0][0] : group;
        }
        win.group = group;
        selectView(tab);
    }
    function refresh() { lister.running = true; win.refreshExtra(); }
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
                if (r.ok) {
                    Ui.containersDone = job.what + ":ok";
                    win.note = Tr.t("Done: %1", job.what);
                    if (job.what.indexOf("service ") === 0) {
                        const n = job.what.slice(8);
                        if (win.services.indexOf(n) < 0) win.services = win.services.concat(n);
                    }
                }
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
    // pods, volumes and machines are read only when their tab is open
    Process {
        id: extraLister
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { return; }
                if (r.error) { win.error = r.error; return; }
                if (win.tab === "containers" && r.cdi !== undefined) win.cdiReady = !!r.cdi;
                if (Array.isArray(r.pods)) { win.pods = r.pods; Ui.containersPods = r.pods.map(p => p.name + ":" + p.status); }
                if (Array.isArray(r.volumes)) { win.volumes = r.volumes; Ui.containersVolumes = r.volumes.map(v => v.name); }
                if (Array.isArray(r.machines)) {
                    win.machines = r.machines;
                    win.machineImages = r.images || [];
                    win.hasMachinectl = !!r.machinectl;
                    win.hasImportctl = !!r.importctl;
                    win.hasVmspawn = !!r.vmspawn;
                    Ui.containersMachines = r.machines.map(m => m.name + ":" + m.state);
                    Ui.containersMachineImages = (r.images || []).map(i => i.name);
                }
                if (Array.isArray(r.instances)) {
                    win.lxdInstances = r.instances;
                    win.lxdReady = !!r.ready;
                    win.hasLxc = !!r.hasLxc;
                    Ui.containersLxd = r.instances.map(i => i.name + ":" + i.status);
                }
                if (win.tab === "apptainer" && Array.isArray(r.images)) {
                    win.sifImages = r.images;
                    win.hasApptainer = !!r.hasApptainer;
                    Ui.containersSif = r.images.map(i => i.name);
                }
                if (win.tab === "android" && r.available !== undefined) {
                    win.android = r;
                    Ui.containersAndroid = [(r.initialised ? Tr.t("ready") : Tr.t("not set up")), r.session];
                }
                if (Array.isArray(r.domains)) {
                    win.domains = r.domains;
                    win.kvmOk = !!r.kvm;
                    win.hasVirsh = !!r.hasVirsh;
                    win.hasViewer = !!r.hasViewer;
                    win.hasBoxes = !!r.hasBoxes;
                    win.systemVms = !!r.systemAllowed;
                    Ui.containersDomains = r.domains.map(d => d.name + ":" + d.state + ":" + d.uri);
                }
            }
        }
    }
    // live logs: a line at a time, stopped when the panel or the tab closes
    Process {
        id: followProc
        stdout: SplitParser {
            onRead: line => {
                if (!win.followOf) return;
                win.followLines = win.followLines.concat(line.slice(0, 200));
                if (win.followLines.length > 300) win.followLines = win.followLines.slice(-300);
                Ui.containersFollow = win.followLines.join("\n");
            }
        }
        onExited: { if (win.followOf) win.note = Tr.t("Log ended"); }
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

    function picked(value, custom) { return value === "custom" ? custom : (value === "none" ? "" : value); }
    function runContainer() {
        const name = win.nextName("app");
        const image = win.picked(win.newImage, win.customImage);
        const args = ["container-run", name, image];
        const ports = win.picked(win.newPorts, win.customPorts);
        const volumes = win.picked(win.newVolumes, win.customVolumes);
        const env = win.picked(win.newEnv, win.customEnv);
        const command = win.picked(win.newCommand, win.customCommand);
        if (ports) args.push("--ports", ports);
        if (volumes) args.push("--volumes", volumes);
        if (env) args.push("--env", env);
        if (command && command !== "default") args.push("--command", command);
        if (win.useGpu) args.push("--gpu");
        win.run(args, r => {
            if (r.ok) {
                Ui.containersStarted = name;
                win.newOpen = false;
                win.note = Tr.t("Started %1", name);
            }
        });
    }
    function openTerminal(argv, what) {
        if (!argv || !argv.length) return;
        Quickshell.execDetached(argv);
        Ui.containersTerminal = argv.join(" ");
        win.note = Tr.t("Opened a terminal for %1", what);
    }
    function shellInto(name) { win.run(["container-shell", name], r => { if (r.argv) win.openTerminal(r.argv, name); }); }
    function machineShell(name) { win.run(["machine-shell", name], r => { if (r.argv) win.openTerminal(r.argv, name); }); }
    function toggleFollow(name) {
        if (win.followOf === name) {
            win.followOf = "";
            followProc.running = false;
            win.followLines = [];
            return;
        }
        win.logsOf = name;
        win.followOf = name;
        win.followLines = [];
        win.logSearch = "";
        followProc.command = ["python3", win.tool, "logs-follow", name];
        followProc.running = true;
    }
    function followText(name) {
        const q = win.logSearch.toLowerCase();
        return win.followLines.filter(l => !q || l.toLowerCase().indexOf(q) >= 0).join("\n");
    }
    function logText(name) {
        const raw = win.followOf === name ? win.followLines.join("\n") : (win.logsText || "");
        const q = win.logSearch.toLowerCase();
        const lines = q ? raw.split("\n").filter(l => l.toLowerCase().indexOf(q) >= 0) : raw.split("\n");
        return lines.join("\n") || Tr.t("Nothing logged");
    }
    function showStats(name) {
        win.run(["container-stats", name], r => {
            win.statsOfContainer = name;
            win.statsData = { cpu: r.cpu || "", mem: r.mem || "" };
            Ui.containersStats = [r.cpu, r.mem].filter(x => x).join(" · ");
        });
    }
    function showBoxDetails(name) {
        win.detailsOf = name;
        win.run(["box-details", name], r => {
            win.boxInfo = r;
            Ui.containersDetails = [r.image, r.distro, r.size, r.created].filter(x => x).join(" · ");
        });
    }
    function installPackage(box, file) {
        win.startJob("install " + box, ["box-install", box, file]);
    }
    function searchImages() {
        const term = win.searchTerm === "custom" ? win.customSearch : win.searchTerm;
        if (!term) return;
        win.run(["image-search", term], r => {
            win.searchResults = Array.isArray(r) ? r : [];
            Ui.containersSearch = win.searchResults.map(i => i.name);
        });
    }
    function pullImageNamed(image) {
        if (!image) return;
        win.startJob("pull " + image, ["image-pull", image]);
    }
    function lxdLaunch() {
        const image = win.picked(win.lxdImage, win.customLxdImage);
        const name = win.lxdName !== "" ? win.lxdName : win.nextName(image.split(":")[0]);
        if (!image) return;
        win.run(["lxd-launch", image, name], r => { if (r.ok) win.note = Tr.t("Started %1", name); });
    }
    function vmUriArg() { return win.vmUri === "system" ? "qemu:///system" : "qemu:///session"; }
    function virtAction(verb, name) { win.run([verb, name, win.vmUriArg()]); }
    function virtConsole(name) {
        win.run(["virt-console", name, win.vmUriArg()], r => {
            if (!r.argv) return;
            Quickshell.execDetached(r.argv);
            Ui.containersTerminal = r.argv.join(" ");
        });
    }
    function openBoxes() {
        win.run(["virt-open-boxes"], r => {
            if (r.argv) Quickshell.execDetached(r.argv);
            else win.error = r.error || "";
        });
    }
    function apptainerOpen(file, mode) {
        win.run([mode === "shell" ? "apptainer-shell" : "apptainer-run", file], r => {
            if (r.argv) win.openTerminal(r.argv, file);
        });
    }
    function pickComposeFolder() {
        FilePicker.open({ mode: "open", title: Tr.t("A compose file"), filters: ["yaml", "yml"],
            onPicked: paths => { if (paths.length) win.composeFolder = paths[0].slice(0, paths[0].lastIndexOf("/")); } });
    }
    function composeAction(verb) {
        if (!win.composeFolder) return;
        win.startJob(verb + " compose", ["compose-" + verb, win.composeFolder]);
    }
    function serviceCreate() {
        const image = win.picked(win.serviceImage, win.customServiceImage);
        if (!image || !win.serviceName) return;
        const name = win.serviceName;
        const args = ["service-create", name, image];
        if (win.useGpu) args.push("--gpu");
        win.startJob("service " + name, args);
    }
    function serviceStatus(name) {
        win.run(["service-status", name], r => {
            win.serviceStatus = r;
            Ui.containersService = name + ":" + (r.active ? Tr.t("running") : Tr.t("stopped"));
        });
    }
    function refreshExtra() {
        if (extraLister.running) extraLister.running = false;   // a tab change wins over an old read
        let cmd = null;
        if (win.tab === "containers") cmd = ["gpu-status"];
        else if (win.tab === "pods") cmd = ["pod-list"];
        else if (win.tab === "volumes") cmd = ["volume-list"];
        else if (win.tab === "machines") cmd = ["machines-list"];
        else if (win.tab === "lxd") cmd = ["lxd-list"];
        else if (win.tab === "apptainer") cmd = ["apptainer-list", win.sifFolder];
        else if (win.tab === "vms") cmd = ["virt-list"];
        else if (win.tab === "android") cmd = ["waydroid-status"];
        if (!cmd) return;
        extraLister.command = ["python3", win.tool].concat(cmd);
        extraLister.running = true;
    }

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
        win.run(["container-inspect", name], r => { win.inspectData = [r]; });
    }
    function inspectRows(name) {
        const d = win.inspectData[0] || {};
        return [[Tr.t("Name"), d.name], [Tr.t("Id"), (d.id || "").slice(0, 12)],
                [Tr.t("State"), d.state], [Tr.t("Image"), d.image],
                [Tr.t("Ports"), d.ports], [Tr.t("Mounts"), d.mounts],
                [Tr.t("Command"), d.command]].filter(r => r[1]);
    }
    function boxDetailRows() {
        const d = win.boxInfo || {};
        return [[Tr.t("Image"), d.image], [Tr.t("System"), d.distro],
                [Tr.t("Size"), win.size(d.size || 0)], [Tr.t("Made"), d.created],
                [Tr.t("State"), d.state]].filter(r => r[1]);
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
                model: [["toolboxes", Tr.t("Toolboxes")], ["containers", Tr.t("Containers")],
                        ["machines", Tr.t("Machines & VMs")], ["android", Tr.t("Android")]]
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.group === modelData[0]
                    onClicked: win.go(modelData[0], win.group === modelData[0] ? win.tab : "")
                }
            }
            Item { Layout.fillWidth: true }
            IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Read again"); onClicked: win.refresh() }
        }
        RowLayout {
            visible: win.subViews().length > 1
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: win.subViews()
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.viewSelected(modelData[0])
                    onClicked: win.selectView(modelData[0])
                }
            }
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
        BusyNote {
            visible: job.running
            Layout.fillWidth: true
            note: Tr.t("Working: %1", job.what)
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
                        const args = ["box-create-options", n, d[2]];
                        if (win.boxHome === "separate") args.push("home");
                        if (win.boxNvidia === "yes") args.push("nvidia");
                        const hooks = win.picked(win.boxHooks, win.customHooks);
                        if (hooks && hooks !== "none") args.push("hooks=" + hooks);
                        win.startJob("create " + n, args);
                    }
                }
            }
            Picks {
                label: Tr.t("Home folder")
                options: [{ label: Tr.t("Shared"), value: "shared" }, { label: Tr.t("Separate"), value: "separate" }]
                current: win.boxHome
                onPicked: v => win.boxHome = v
            }
            SwitchRow {
                text: Tr.t("Use the graphics card")
                hint: Tr.t("Toolboxes share the graphics card without extra setup")
                checked: win.boxNvidia === "yes"
                onToggled: v => win.boxNvidia = v ? "yes" : "no"
            }
            Picks {
                label: Tr.t("On start")
                options: [{ label: Tr.t("Nothing"), value: "none" }, { label: Tr.t("Update packages"), value: "update" }, { label: Tr.t("Your own…"), value: "custom" }]
                current: win.boxHooks
                onPicked: v => win.boxHooks = v
            }
            TextField {
                visible: win.boxHooks === "custom"
                Layout.fillWidth: true
                label: Tr.t("Commands to run on start, separated by ;")
                text: win.customHooks
                onTextChanged: win.customHooks = text
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
                    IconButton {
                        icon: "document-open"; size: Theme.px(26); tip: Tr.t("Install a package file")
                        onClicked: {
                            const box = brow.modelData.name;
                            FilePicker.open({ mode: "open", title: Tr.t("A package file to install"), filters: ["deb", "rpm"],
                                onPicked: paths => { if (paths.length) win.installPackage(box, paths[0]); } });
                        }
                    }
                    IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Make a copy"); onClicked: { const name = brow.modelData.name; win.startJob("copy " + name, ["box-clone", name, win.nextName(name + "-copy")]); } }
                    IconButton { icon: "dialog-information"; size: Theme.px(26); tip: Tr.t("Details"); onClicked: win.showBoxDetails(brow.modelData.name) }
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
                ColumnLayout {
                    visible: win.detailsOf === brow.modelData.name
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(30)
                    spacing: 1
                    Repeater {
                        model: win.detailsOf === brow.modelData.name ? win.boxDetailRows() : []
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: modelData[0]; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                            Text { text: modelData[1]; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        }
                    }
                }
            }
        }

        // ---- containers (Podman) ----
        RowLayout {
            visible: win.tab === "containers" && win.hasPodman
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                text: win.newOpen ? Tr.t("Hide the form") : Tr.t("New container")
                checked: win.newOpen
                onClicked: win.newOpen = !win.newOpen
            }
            Item { Layout.fillWidth: true }
        }
        ColumnLayout {
            visible: win.tab === "containers" && win.newOpen && win.hasPodman
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Picks {
                label: Tr.t("Image")
                options: ["docker.io/library/nginx:latest", "docker.io/library/alpine:latest", "docker.io/library/ubuntu:24.04", "registry.fedoraproject.org/fedora:latest", { label: Tr.t("Your own…"), value: "custom" }]
                current: win.newImage
                onPicked: v => win.newImage = v
            }
            TextField {
                visible: win.newImage === "custom"
                Layout.fillWidth: true
                label: Tr.t("Image name")
                placeholder: Tr.t("For example: registry.example.org/my-app:1")
                text: win.customImage
                onTextChanged: win.customImage = text
            }
            Picks {
                label: Tr.t("Ports")
                options: [{ label: Tr.t("None"), value: "none" }, { label: Tr.t("Web: 8080 to 80"), value: "8080:80" }, { label: Tr.t("Your own…"), value: "custom" }]
                current: win.newPorts
                onPicked: v => win.newPorts = v
            }
            TextField {
                visible: win.newPorts === "custom"
                Layout.fillWidth: true
                label: Tr.t("Ports, like 8080:80, separate with a comma")
                text: win.customPorts
                onTextChanged: win.customPorts = text
            }
            Picks {
                label: Tr.t("Files to share")
                options: [{ label: Tr.t("None"), value: "none" }, { label: Tr.t("Projects folder"), value: "~/Projects:/work" }, { label: Tr.t("Your own…"), value: "custom" }]
                current: win.newVolumes
                onPicked: v => win.newVolumes = v
            }
            TextField {
                visible: win.newVolumes === "custom"
                Layout.fillWidth: true
                label: Tr.t("Folders, like /home/me/data:/data, separate with a comma")
                text: win.customVolumes
                onTextChanged: win.customVolumes = text
            }
            Picks {
                label: Tr.t("Settings")
                options: [{ label: Tr.t("None"), value: "none" }, { label: Tr.t("Time zone"), value: "TZ=UTC" }, { label: Tr.t("Your own…"), value: "custom" }]
                current: win.newEnv
                onPicked: v => win.newEnv = v
            }
            TextField {
                visible: win.newEnv === "custom"
                Layout.fillWidth: true
                label: Tr.t("Settings, like TZ=UTC, separate with a comma")
                text: win.customEnv
                onTextChanged: win.customEnv = text
            }
            Picks {
                label: Tr.t("Command")
                options: [{ label: Tr.t("Default"), value: "default" }, "sh", "bash", { label: Tr.t("Your own…"), value: "custom" }]
                current: win.newCommand
                onPicked: v => win.newCommand = v
            }
            TextField {
                visible: win.newCommand === "custom"
                Layout.fillWidth: true
                label: Tr.t("The command to run in the container")
                text: win.customCommand
                onTextChanged: win.customCommand = text
            }
            SwitchRow {
                text: Tr.t("Use the graphics card")
                hint: Tr.t("Needs a CDI setup for raw containers; a toolbox with a graphics card works without one")
                checked: win.useGpu
                onToggled: v => win.useGpu = v
            }
            Text {
                visible: win.useGpu && !win.cdiReady
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: Tr.t("The graphics card setup is missing here. Use a toolbox with the graphics card instead.")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Button {
                kind: "primary"
                text: Tr.t("Start container")
                enabled: !act.running && win.picked(win.newImage, win.customImage) !== ""
                onClicked: win.runContainer()
            }
        }
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
                    IconButton { icon: "utilities-terminal"; size: Theme.px(26); tip: Tr.t("Open a shell"); onClicked: win.shellInto(crow.modelData.name) }
                    Button {
                        text: Tr.t("More"); checked: win.moreOf === crow.modelData.name
                        onClicked: win.moreOf = win.moreOf === crow.modelData.name ? "" : crow.modelData.name
                    }
                    IconButton {
                        icon: win.removing === crow.modelData.name ? "edit-delete" : "window-close"
                        size: Theme.px(26)
                        tip: win.removing === crow.modelData.name ? Tr.t("Click again: %1 is removed", crow.modelData.name) : Tr.t("Remove")
                        onClicked: { if (win.removing === crow.modelData.name) { win.removing = ""; win.run(["remove", crow.modelData.name]); } else win.removing = crow.modelData.name; }
                    }
                }
                ColumnLayout {
                    visible: win.moreOf === crow.modelData.name
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(30)
                    spacing: Theme.px(4)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Button {
                            text: Tr.t("Pause"); enabled: crow.up && crow.modelData.state !== "paused"
                            onClicked: { const name = crow.modelData.name; win.run(["container-pause", name], r => { if (r.ok) win.note = Tr.t("Paused %1", name); }); }
                        }
                        Button {
                            text: Tr.t("Resume"); enabled: crow.modelData.state === "paused"
                            onClicked: { const name = crow.modelData.name; win.run(["container-resume", name], r => { if (r.ok) win.note = Tr.t("Resumed %1", name); }); }
                        }
                        Button {
                            text: Tr.t("Stop now"); enabled: crow.up
                            onClicked: { const name = crow.modelData.name; win.run(["container-kill", name], r => { if (r.ok) win.note = Tr.t("Stopped %1 at once", name); }); }
                        }
                        Button {
                            text: win.followOf === crow.modelData.name ? Tr.t("Stop following") : Tr.t("Read live logs")
                            onClicked: win.toggleFollow(crow.modelData.name)
                        }
                        Button { text: Tr.t("CPU and memory"); onClicked: win.showStats(crow.modelData.name) }
                    }
                    Text {
                        visible: win.statsOfContainer === crow.modelData.name
                        text: [win.statsData.cpu, win.statsData.mem].filter(x => x).join(" · ")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Picks {
                        label: Tr.t("Rename")
                        options: [{ label: Tr.t("Use %1").arg(win.nextName(crow.modelData.name)), value: "suggested" }, { label: Tr.t("Your own…"), value: "custom" }]
                        current: win.renameOf === crow.modelData.name ? win.renameName : ""
                        onPicked: v => { win.renameOf = crow.modelData.name; win.renameName = v; }
                    }
                    TextField {
                        visible: win.renameOf === crow.modelData.name && win.renameName === "custom"
                        Layout.fillWidth: true
                        label: Tr.t("A new name")
                        text: win.renameOf === crow.modelData.name ? win.customRename : ""
                        onTextChanged: win.customRename = text
                    }
                    Button {
                        text: Tr.t("Rename"); enabled: act.running === false
                        onClicked: {
                            const name = crow.modelData.name;
                            const to = win.renameName === "custom" ? win.customRename : win.nextName(name);
                            win.run(["container-rename", name, to], r => { if (r.ok) win.note = Tr.t("Renamed to %1", to); });
                        }
                    }
                    Picks {
                        label: Tr.t("Save as an image")
                        options: win.images.map(i => i.name).concat([{ label: Tr.t("Your own…"), value: "custom" }])
                        current: win.commitImage !== "" ? win.commitImage : (win.images.length ? win.images[0].name : "custom")
                        onPicked: v => win.commitImage = v
                    }
                    TextField {
                        visible: (win.commitImage !== "" ? win.commitImage : "custom") === "custom"
                        Layout.fillWidth: true
                        label: Tr.t("An image name")
                        text: win.customCommit
                        onTextChanged: win.customCommit = text
                    }
                    Button {
                        text: Tr.t("Save image"); enabled: act.running === false
                        onClicked: {
                            const name = crow.modelData.name;
                            const image = win.picked(win.commitImage !== "" ? win.commitImage : "custom", win.customCommit);
                            win.run(["container-commit", name, image], r => { if (r.ok) win.note = Tr.t("Saved %1", image); });
                        }
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
                        Choice {
                            text: win.followOf === crow.modelData.name ? Tr.t("Stop following") : Tr.t("Follow")
                            selected: win.followOf === crow.modelData.name
                            onClicked: win.toggleFollow(crow.modelData.name)
                        }
                        SearchField {
                            Layout.fillWidth: true
                            placeholder: Tr.t("Find in these lines")
                            text: win.logSearch
                            onTextChanged: win.logSearch = text
                        }
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
                            text: win.logsOf === crow.modelData.name ? win.logText(crow.modelData.name) : ""
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
        ColumnLayout {
            visible: win.tab === "images" && win.hasPodman
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Picks {
                label: Tr.t("Find an image")
                options: ["nginx", "alpine", "ubuntu", { label: Tr.t("Your own…"), value: "custom" }]
                current: win.searchTerm
                onPicked: v => win.searchTerm = v
            }
            TextField {
                visible: win.searchTerm === "custom"
                Layout.fillWidth: true
                label: Tr.t("What to look for")
                text: win.customSearch
                onTextChanged: win.customSearch = text
            }
            Button { text: Tr.t("Search"); onClicked: win.searchImages() }
            Repeater {
                model: win.searchResults
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: modelData.name + "  ·  " + (modelData.official ? Tr.t("official") : Tr.t("community")) + "  ·  " + modelData.stars
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Button { text: Tr.t("Fetch"); onClicked: win.pullImageNamed(modelData.name) }
                }
            }
            Picks {
                label: Tr.t("Or pick an image you saw")
                options: win.searchResults.map(i => i.name).concat(win.images.map(i => i.name)).concat([{ label: Tr.t("Your own…"), value: "custom" }])
                current: win.pullImage
                onPicked: v => win.pullImage = v
            }
            TextField {
                visible: win.pullImage === "custom"
                Layout.fillWidth: true
                label: Tr.t("Image to fetch by name")
                text: win.customPull
                onTextChanged: win.customPull = text
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Fetch by name"); enabled: win.picked(win.pullImage, win.customPull) !== "" && !job.running; onClicked: win.pullImageNamed(win.picked(win.pullImage, win.customPull)) }
            }
        }
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

        // ---- pods ----
        ColumnLayout {
            visible: win.tab === "pods" && win.hasPodman
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: Tr.t("A pod keeps a few containers together so they can share their network.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            EmptyState {
                visible: win.pods.length === 0
                icon: "package-x-generic"
                title: Tr.t("No pods yet")
                subtitle: Tr.t("Pods made outside this window show up here")
            }
            ListView {
                reuseItems: true
                id: podlist
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(4)
                model: win.pods
                delegate: ListRow {
                    required property var modelData
                    width: podlist.width
                    icon: "package-x-generic"
                    title: modelData.name
                    subtitle: modelData.status + "  ·  " + modelData.containers + " " + Tr.t("containers")
                    interactive: false
                    Button { text: modelData.status === "running" ? Tr.t("Stop") : Tr.t("Start"); onClicked: win.run([modelData.status === "running" ? "pod-stop" : "pod-start", modelData.name]) }
                    ConfirmButton {
                        text: Tr.t("Remove"); armedText: Tr.t("Tap again: remove")
                        Accessible.name: Tr.t("Remove pod %1", modelData.name)
                        width: Theme.px(110); height: Theme.px(32)
                        onConfirmed: win.run(["pod-remove", modelData.name])
                    }
                }
            }
        }

        // ---- volumes ----
        ColumnLayout {
            visible: win.tab === "volumes" && win.hasPodman
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: Tr.t("Volumes keep a container's files after it is removed.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Picks {
                    Layout.fillWidth: true
                    label: Tr.t("A new volume")
                    options: ["site", "cache", { label: Tr.t("Your own…"), value: "custom" }]
                    current: win.volumeName
                    onPicked: v => win.volumeName = v
                }
                TextField {
                    visible: win.volumeName === "custom"
                    Layout.fillWidth: true
                    label: Tr.t("Volume name")
                    text: win.customVolume
                    onTextChanged: win.customVolume = text
                }
                Button {
                    text: Tr.t("Create volume")
                    enabled: !act.running && win.picked(win.volumeName, win.customVolume) !== ""
                    onClicked: {
                        const name = win.picked(win.volumeName, win.customVolume);
                        win.run(["volume-create", name], r => { if (r.ok) win.note = Tr.t("Created %1", name); });
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: Tr.t("%1 volumes", win.volumes.length); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                ConfirmButton {
                    text: Tr.t("Remove unused"); armedText: Tr.t("Tap again: remove unused volumes")
                    enabled: win.volumes.some(v => v.size === 0)
                    onConfirmed: win.run(["volume-prune"], r => { if (r.ok) win.note = Tr.t("%1 volumes removed", r.removed); })
                }
            }
            EmptyState {
                visible: win.volumes.length === 0
                icon: "drive-harddisk"
                title: Tr.t("No volumes yet")
                subtitle: Tr.t("Create one above, or mount one when you start a container")
            }
            ListView {
                reuseItems: true
                id: vollist
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(4)
                model: win.volumes
                delegate: ListRow {
                    required property var modelData
                    width: vollist.width
                    icon: "drive-harddisk"
                    title: modelData.name
                    subtitle: win.size(modelData.size || 0) + "  ·  " + (modelData.driver || "")
                    interactive: false
                    ConfirmButton {
                        text: Tr.t("Remove"); armedText: Tr.t("Tap again: remove")
                        Accessible.name: Tr.t("Remove volume %1", modelData.name)
                        width: Theme.px(110); height: Theme.px(32)
                        onConfirmed: win.run(["volume-remove", modelData.name])
                    }
                }
            }
        }

        // ---- machines and disk images ----
        Text {
            visible: win.tab === "machines" && !win.hasMachinectl && !win.hasImportctl && !win.hasVmspawn
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: Tr.t("Machine tools are not installed on this computer")
            color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        ColumnLayout {
            visible: win.tab === "machines" && (win.hasMachinectl || win.hasImportctl || win.hasVmspawn)
            Layout.fillWidth: true
            spacing: Theme.px(6)
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: [["machines", Tr.t("Machines")], ["images", Tr.t("Machine images")], ["boot", Tr.t("Boot a disk image")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.machineView === modelData[0]
                        enabled: modelData[0] !== "machines" || win.hasMachinectl
                        onClicked: win.machineView = modelData[0]
                    }
                }
            }
            Text {
                visible: win.machineView === "machines" && !win.hasMachinectl
                text: Tr.t("Managing machines is not installed on this computer")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                visible: win.machineView === "boot" && !win.hasVmspawn
                text: Tr.t("Booting disk images is not installed on this computer")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            ColumnLayout {
                visible: win.machineView === "machines" && win.hasMachinectl
                Layout.fillWidth: true
                spacing: Theme.px(4)
                EmptyState {
                    visible: win.machines.length === 0
                    icon: "computer"
                    title: Tr.t("No machines running")
                    subtitle: Tr.t("Start one from the machine images")
                }
                ListView {
                    reuseItems: true
                    id: mlist
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.px(4)
                    model: win.machines
                    delegate: ListRow {
                        required property var modelData
                        width: mlist.width
                        icon: "computer"
                        title: modelData.name
                        subtitle: modelData.state === "unknown" ? Tr.t("state not shown") : modelData.state
                        interactive: false
                        Button { text: Tr.t("Start"); onClicked: win.run(["machine-start", modelData.name]) }
                        Button { text: Tr.t("Power off"); onClicked: win.run(["machine-poweroff", modelData.name]) }
                        Button { text: Tr.t("Restart"); onClicked: win.run(["machine-reboot", modelData.name]) }
                        Button { text: Tr.t("Open a shell"); onClicked: win.machineShell(modelData.name) }
                    }
                }
            }
            ColumnLayout {
                visible: win.machineView === "images" && win.hasImportctl
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: Tr.t("Fetch a ready-made Linux system, then start it as a machine.")
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Picks {
                    label: Tr.t("Where from")
                    options: [{ label: Tr.t("Arch Linux"), value: "https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-basic.tar.zst" },
                              { label: Tr.t("Your own…"), value: "custom" }]
                    current: win.imageUrl
                    onPicked: v => win.imageUrl = v
                }
                TextField {
                    visible: win.imageUrl === "custom"
                    Layout.fillWidth: true
                    label: Tr.t("A web address for the image")
                    text: win.customUrl
                    onTextChanged: win.customUrl = text
                }
                RowLayout {
                    Layout.fillWidth: true
                    Picks {
                        Layout.fillWidth: true
                        label: Tr.t("Image kind")
                        options: [{ label: Tr.t("Archive"), value: "tar" }, { label: Tr.t("Disk image"), value: "raw" }]
                        current: win.pullType
                        onPicked: v => win.pullType = v
                    }
                    Picks {
                        Layout.fillWidth: true
                        label: Tr.t("Name for it")
                        options: ["newmachine", { label: Tr.t("Your own…"), value: "custom" }]
                        current: win.pullName
                        onPicked: v => win.pullName = v
                    }
                    TextField {
                        visible: win.pullName === "custom"
                        Layout.fillWidth: true
                        label: Tr.t("A name for the machine image")
                        text: win.customPullName
                        onTextChanged: win.customPullName = text
                    }
                    Button {
                        text: Tr.t("Fetch machine image")
                        enabled: !job.running && win.pullName !== "" && win.picked(win.imageUrl, win.customUrl) !== ""
                        onClicked: {
                            const name = win.picked(win.pullName, win.customPullName);
                            win.startJob("fetch " + name, ["machine-image-pull", win.picked(win.imageUrl, win.customUrl), name, win.pullType]);
                        }
                    }
                }
                ListView {
                    reuseItems: true
                    id: imlist
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.px(4)
                    model: win.machineImages
                    delegate: ListRow {
                        required property var modelData
                        width: imlist.width
                        icon: "media-optical"
                        title: modelData.name
                        subtitle: [modelData.type, modelData.size].filter(x => x).join("  ·  ")
                        interactive: false
                        Button { text: Tr.t("Make a copy"); onClicked: win.run(["machine-image-clone", modelData.name, win.nextName(modelData.name + "-copy")]) }
                        Button {
                            text: Tr.t("Rename")
                            onClicked: { win.imageRenameOf = modelData.name; win.imageRenameName = "custom"; win.customImageRename = win.nextName(modelData.name); }
                        }
                        ConfirmButton {
                            text: Tr.t("Remove"); armedText: Tr.t("Tap again: remove")
                            Accessible.name: Tr.t("Remove machine image %1", modelData.name)
                            width: Theme.px(110); height: Theme.px(32)
                            onConfirmed: win.run(["machine-image-remove", modelData.name])
                        }
                    }
                }
                RowLayout {
                    visible: win.imageRenameOf !== ""
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: Tr.t("Rename %1", win.imageRenameOf); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    Picks {
                        Layout.fillWidth: true
                        label: Tr.t("New name")
                        options: [{ label: Tr.t("Use %1").arg(win.nextName(win.imageRenameOf)), value: "suggested" }, { label: Tr.t("Your own…"), value: "custom" }]
                        current: win.imageRenameName
                        onPicked: v => win.imageRenameName = v
                    }
                    TextField {
                        visible: win.imageRenameName === "custom"
                        Layout.fillWidth: true
                        label: Tr.t("A name for the machine image")
                        text: win.customImageRename
                        onTextChanged: win.customImageRename = text
                    }
                    Button {
                        text: Tr.t("Save name")
                        onClicked: {
                            const to = win.imageRenameName === "custom" ? win.customImageRename : win.nextName(win.imageRenameOf);
                            win.run(["machine-image-rename", win.imageRenameOf, to], r => { if (r.ok) win.imageRenameOf = ""; });
                        }
                    }
                }
            }
            ColumnLayout {
                visible: win.machineView === "boot" && win.hasVmspawn
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: Tr.t("Pick a disk image file. It opens in a terminal window; close that window to shut the machine down.")
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: win.vmFile !== "" ? win.vmFile : Tr.t("No disk image picked yet")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    Button {
                        text: Tr.t("Pick a disk image")
                        onClicked: FilePicker.open({ mode: "open", title: Tr.t("A disk image to boot"), filters: ["raw", "qcow2"],
                            onPicked: paths => { if (paths.length) win.vmFile = paths[0]; } });
                    }
                    Button {
                        text: Tr.t("Boot it")
                        enabled: win.vmFile !== ""
                        onClicked: win.run(["vmspawn-boot", win.vmFile], r => { if (r.argv) win.openTerminal(r.argv, win.vmFile); })
                    }
                }
            }
        }

        // ---- LXD system containers ----
        ColumnLayout {
            visible: win.tab === "lxd"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                visible: !win.hasLxc
                text: Tr.t("System containers are not installed on this computer")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Text {
                visible: win.hasLxc && !win.lxdReady
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: Tr.t("System containers need a first-time setup. Set them up with lxd init --auto. If your account is not in the lxd group, ask an administrator to add you, then sign out and back in.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Button {
                visible: win.hasLxc && !win.lxdReady
                text: Tr.t("Set up system containers")
                enabled: !job.running
                onClicked: win.startJob("set up system containers", ["lxd-init"])
            }
            Picks {
                label: Tr.t("System to start")
                options: [{ label: Tr.t("Ubuntu"), value: "ubuntu:24.04" }, { label: Tr.t("Debian"), value: "debian:bookworm" },
                          { label: Tr.t("Fedora"), value: "fedora:40" }, { label: Tr.t("Alpine"), value: "alpine:3.19" },
                          { label: Tr.t("Arch Linux"), value: "archlinux:current" }, { label: Tr.t("Your own…"), value: "custom" }]
                current: win.lxdImage
                onPicked: v => win.lxdImage = v
            }
            TextField {
                visible: win.lxdImage === "custom"
                Layout.fillWidth: true
                label: Tr.t("An image name, like ubuntu:24.04")
                text: win.customLxdImage
                onTextChanged: win.customLxdImage = text
            }
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    label: Tr.t("Name for the system")
                    text: win.lxdName
                    onTextChanged: win.lxdName = text
                }
                Button { text: Tr.t("Start system"); enabled: win.hasLxc && win.lxdReady && !act.running; onClicked: win.lxdLaunch() }
            }
            EmptyState {
                visible: win.hasLxc && win.lxdReady && win.lxdInstances.length === 0
                icon: "computer"
                title: Tr.t("No systems yet")
                subtitle: Tr.t("Pick one above to start it")
            }
            ListView {
                reuseItems: true
                id: lxdl
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(4)
                model: win.lxdInstances
                delegate: ListRow {
                    required property var modelData
                    width: lxdl.width
                    icon: "computer"
                    title: modelData.name
                    subtitle: [modelData.status, modelData.image, modelData.address].filter(x => x).join("  ·  ")
                    interactive: false
                    Button { text: Tr.t("Start"); onClicked: win.run(["lxd-start", modelData.name]) }
                    Button { text: Tr.t("Stop"); onClicked: win.run(["lxd-stop", modelData.name]) }
                    Button { text: Tr.t("Restart"); onClicked: win.run(["lxd-restart", modelData.name]) }
                    Button {
                        text: Tr.t("Open a shell")
                        onClicked: win.run(["lxd-shell", modelData.name], r => { if (r.argv) win.openTerminal(r.argv, modelData.name); })
                    }
                    ConfirmButton {
                        text: Tr.t("Delete"); armedText: Tr.t("Tap again: delete")
                        Accessible.name: Tr.t("Delete system %1", modelData.name)
                        width: Theme.px(110); height: Theme.px(32)
                        onConfirmed: win.run(["lxd-delete", modelData.name])
                    }
                }
            }
        }

        // ---- Apptainer images ----
        ColumnLayout {
            visible: win.tab === "apptainer"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                visible: !win.hasApptainer
                text: Tr.t("HPC images are not installed on this computer")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true; elide: Text.ElideMiddle
                    text: win.sifFolder
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Button {
                    text: Tr.t("Pick an image folder")
                    onClicked: FilePicker.open({ mode: "open", title: Tr.t("An HPC image"), filters: ["sif"],
                        onPicked: paths => { if (paths.length) win.sifFolder = paths[0].slice(0, paths[0].lastIndexOf("/")); } });
                }
            }
            Picks {
                label: Tr.t("Where from")
                options: [{ label: Tr.t("Ubuntu image"), value: "docker://ubuntu:22.04" },
                          { label: Tr.t("Alpine image"), value: "docker://alpine:3.19" },
                          { label: Tr.t("Your own…"), value: "custom" }]
                current: win.apptainerRef
                onPicked: v => win.apptainerRef = v
            }
            TextField {
                visible: win.apptainerRef === "custom"
                Layout.fillWidth: true
                label: Tr.t("A docker:// or oras:// address")
                text: win.customApptainerRef
                onTextChanged: win.customApptainerRef = text
            }
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    label: Tr.t("Name for the image")
                    text: win.sifName
                    onTextChanged: win.sifName = text
                }
                Button {
                    text: Tr.t("Fetch image")
                    enabled: !job.running && win.sifName !== ""
                    onClicked: win.startJob("fetch image", ["apptainer-pull", win.picked(win.apptainerRef, win.customApptainerRef), win.sifName, win.sifFolder])
                }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: Tr.t("These images use your graphics card automatically.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            EmptyState {
                visible: win.sifImages.length === 0
                icon: "media-optical"
                title: Tr.t("No images here yet")
                subtitle: Tr.t("Fetch one above, or pick another folder")
            }
            ListView {
                reuseItems: true
                id: sifl
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(4)
                model: win.sifImages
                delegate: ListRow {
                    required property var modelData
                    width: sifl.width
                    icon: "media-optical"
                    title: modelData.name
                    subtitle: win.size(modelData.size || 0)
                    interactive: false
                    Button { text: Tr.t("Run"); onClicked: win.apptainerOpen(modelData.path, "run") }
                    Button { text: Tr.t("Open a shell"); onClicked: win.apptainerOpen(modelData.path, "shell") }
                    ConfirmButton {
                        text: Tr.t("Remove"); armedText: Tr.t("Tap again: remove")
                        Accessible.name: Tr.t("Remove image %1", modelData.name)
                        width: Theme.px(110); height: Theme.px(32)
                        onConfirmed: win.run(["apptainer-remove", modelData.path])
                    }
                }
            }
        }

        // ---- virtual machines ----
        ColumnLayout {
            visible: win.tab === "vms"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                visible: !win.hasVirsh
                text: Tr.t("Virtual machine tools are not installed on this computer")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Text {
                visible: win.hasVirsh && !win.kvmOk
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: Tr.t("KVM is not usable here. The KVM check in Shani Cassini can diagnose and fix it.")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: win.systemVms ? [["session", Tr.t("My machines")], ["system", Tr.t("Shared machines")]] : [["session", Tr.t("My machines")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.vmUri === modelData[0]
                        onClicked: win.vmUri = modelData[0]
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: Tr.t("New virtual machine…")
                    enabled: win.hasBoxes
                    onClicked: win.openBoxes()
                }
            }
            Text {
                visible: !win.hasBoxes
                text: Tr.t("Install Boxes to make a new virtual machine")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            EmptyState {
                visible: win.domains.length === 0
                icon: "computer"
                title: Tr.t("No virtual machines yet")
                subtitle: Tr.t("Make one with Boxes, or one appears here from a manager")
            }
            ListView {
                reuseItems: true
                id: vml
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(4)
                model: win.domains
                delegate: ListRow {
                    required property var modelData
                    width: vml.width
                    icon: "computer"
                    title: modelData.name
                    subtitle: [modelData.state, modelData.uri].filter(x => x).join("  ·  ")
                    interactive: false
                    Button { text: Tr.t("Start"); onClicked: win.virtAction("virt-start", modelData.name) }
                    Button { text: Tr.t("Shut down"); onClicked: win.virtAction("virt-shutdown", modelData.name) }
                    Button { text: Tr.t("Force off"); onClicked: win.virtAction("virt-force-off", modelData.name) }
                    Button { text: Tr.t("Restart"); onClicked: win.virtAction("virt-reboot", modelData.name) }
                    Button { text: Tr.t("Console"); onClicked: win.virtConsole(modelData.name) }
                    ConfirmButton {
                        text: Tr.t("Remove"); armedText: Tr.t("Tap again: remove")
                        Accessible.name: Tr.t("Remove virtual machine %1", modelData.name)
                        width: Theme.px(110); height: Theme.px(32)
                        onConfirmed: win.run(["virt-remove", modelData.name, win.vmUriArg()])
                    }
                }
            }
        }

        // ---- Android ----
        ColumnLayout {
            visible: win.tab === "android"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                visible: win.android.available !== true
                text: Tr.t("Android support is not installed on this computer")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                visible: win.android.available === true
                text: Tr.t("Android is %1 and its session is %2").arg(win.android.initialised === true ? Tr.t("ready") : Tr.t("not set up")).arg(win.android.session || Tr.t("unknown"))
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Button {
                visible: win.android.available === true && win.android.initialised !== true && win.android.helper === true
                text: Tr.t("Set up Android")
                enabled: !job.running
                onClicked: win.startJob("set up Android", ["waydroid-init"])
            }
            Text {
                visible: win.android.available === true && win.android.initialised !== true && win.android.helper !== true
                text: Tr.t("The Android setup helper is not installed")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                visible: win.android.available === true && win.android.initialised === true
                Layout.fillWidth: true
                Button { text: Tr.t("Start session"); onClicked: win.run(["waydroid-start"]) }
                Button { text: Tr.t("Stop session"); onClicked: win.run(["waydroid-stop"]) }
                Button {
                    text: Tr.t("Open Android apps")
                    onClicked: win.run(["waydroid-ui"], r => { if (r.argv) { Quickshell.execDetached(r.argv); Ui.containersTerminal = r.argv.join(" "); } })
                }
            }
        }

        // ---- compose folders ----
        ColumnLayout {
            visible: win.tab === "compose"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true; elide: Text.ElideMiddle
                    text: win.composeFolder !== "" ? win.composeFolder : Tr.t("No folder picked yet")
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Button { text: Tr.t("Pick a compose file"); onClicked: win.pickComposeFolder() }
            }
            RowLayout {
                Layout.fillWidth: true
                Button { text: Tr.t("Start stack"); enabled: win.composeFolder !== "" && !job.running; onClicked: win.composeAction("up") }
                Button { text: Tr.t("Stop stack"); enabled: win.composeFolder !== "" && !job.running; onClicked: win.composeAction("down") }
                Button { text: Tr.t("Read its logs"); enabled: win.composeFolder !== "" && !job.running; onClicked: win.composeAction("logs") }
            }
            BusyNote { visible: job.running && job.what.indexOf("compose") >= 0; Layout.fillWidth: true; note: win.jobLine || Tr.t("Working…") }
        }

        // ---- user services (Quadlet) ----
        ColumnLayout {
            visible: win.tab === "services"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Picks {
                label: Tr.t("Image for the service")
                options: win.images.map(i => i.name).concat([{ label: Tr.t("Your own…"), value: "custom" }])
                current: win.serviceImage
                onPicked: v => win.serviceImage = v
            }
            TextField {
                visible: win.serviceImage === "custom"
                Layout.fillWidth: true
                label: Tr.t("An image name")
                text: win.customServiceImage
                onTextChanged: win.customServiceImage = text
            }
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    label: Tr.t("Service name")
                    text: win.serviceName
                    onTextChanged: win.serviceName = text
                }
                Button { text: Tr.t("Run as a service"); enabled: win.serviceName !== "" && !job.running; onClicked: win.serviceCreate() }
            }
            SwitchRow {
                text: Tr.t("Use the graphics card")
                hint: Tr.t("Only when a CDI setup is present")
                checked: win.serviceGpu
                onToggled: v => win.serviceGpu = v
            }
            Repeater {
                model: win.services
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Button { text: Tr.t("Status"); onClicked: win.serviceStatus(modelData) }
                    ConfirmButton {
                        text: Tr.t("Remove"); armedText: Tr.t("Tap again: remove")
                        Accessible.name: Tr.t("Remove service %1", modelData)
                        width: Theme.px(110); height: Theme.px(32)
                        onConfirmed: { win.run(["service-remove", modelData]); win.services = win.services.filter(x => x !== modelData); }
                    }
                }
            }
            Text {
                visible: Object.keys(win.serviceStatus).length > 0
                text: [win.serviceStatus.description, win.serviceStatus.active ? Tr.t("running") : Tr.t("stopped"), win.serviceStatus.sub].filter(x => x).join("  ·  ")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }
    }
}
