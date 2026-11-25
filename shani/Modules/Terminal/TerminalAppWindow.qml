// Terminal: a SSH connection manager. List hosts, add/edit/delete/pin hosts,
// generate/import keys, test connections, and connect. Uses Services/TerminalApp.
// A "remote workstation" layer adds groups, health, search/sort, split host
// panes, session tabs, quick commands and tunnel conflict checks — all using
// the existing service API; no service or settings file is changed here.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Terminal"
    visible: Ui.terminalApp
    onGone: Ui.terminalApp = false
    implicitWidth: Theme.px(680)
    implicitHeight: Theme.px(620)

    // tab: "hosts" or "keys"
    property string tab: "hosts"
    property string newHostName: ""
    property string newHostAddr: ""
    property string newHostUser: ""
    property string newHostPort: ""
    property string newHostKey: ""
    property string newKeyName: ""
    property string tunnelHostId: ""
    property string snippetNote: ""
    property string hostQuery: ""
    property string hostNote: ""
    property string editId: ""
    property string tunnelMode: "L"
    // advanced per-host ssh options, kept with the host in hosts JSON
    property string newHostProxyJump: ""
    property string newHostExtraOpts: ""
    property bool newHostForwardAgent: false
    property bool newHostX11: false
    property bool newHostCompression: false

    // ---- remote-workstation state (window-local; the service is untouched) ----
    property string groupFilter: ""          // "" means every group
    property string newHostGroup: ""         // a host's group/tag in the form
    property string sortMode: "name"         // name | recent | status
    property string healthFilter: ""         // "" | ok | failed | untested
    property bool splitView: false
    property string splitGroup: ""
    property var panes: []                   // launched sessions: [{ id, name }]
    property int activePane: -1
    property string snippetQuery: ""
    property string snippetHostId: ""
    property string pasteError: ""
    property var testQueue: []
    property int testIndex: 0
    // shortcut: host delete confirm is coupled to keyboard Delete and global warning text, so per-row ConfirmButton would change behavior
    property string confirmingDelete: ""
    property bool showShortcuts: false

    function hostOpts() {
        return { proxyJump: win.newHostProxyJump.trim(), forwardAgent: win.newHostForwardAgent,
                 x11: win.newHostX11, compression: win.newHostCompression,
                 extraOpts: win.newHostExtraOpts.split(",").map(s => s.trim()).filter(s => s) };
    }
    function editHost(h) {
        win.tab = "add";
        win.newHostName = h.name; win.newHostAddr = h.host; win.newHostUser = h.user || "";
        win.newHostPort = String(h.port || 22); win.newHostKey = h.key || "";
        win.newHostProxyJump = h.proxyJump || ""; win.newHostExtraOpts = (h.extraOpts || []).join(", ");
        win.newHostForwardAgent = !!h.forwardAgent; win.newHostX11 = !!h.x11; win.newHostCompression = !!h.compression;
        win.newHostGroup = h.group || "";
        win.editId = h.id;
    }
    // groups are a field on the host record, written through the service's
    // updateHost(); they need no new service API and survive a shell restart
    function hostGroups() {
        const out = [""];
        for (const h of TerminalApp.hosts) {
            const g = String(h.group || "").trim();
            if (g && out.indexOf(g) < 0) out.push(g);
        }
        return out;
    }
    // one filter/search/sort path for both panes; group="" means "all groups"
    function visibleHosts(group) {
        const g = group === undefined ? win.groupFilter : group;
        const q = win.hostQuery.trim().toLowerCase();
        const list = TerminalApp.hosts.filter(h => {
            if (g && String(h.group || "") !== g) return false;
            if (win.healthFilter === "ok" && h.status !== "ok") return false;
            if (win.healthFilter === "failed" && h.status !== "failed") return false;
            if (win.healthFilter === "untested" && !!h.status) return false;
            return !q || [h.name, h.host, h.user, h.group, h.proxyJump].some(x => String(x || "").toLowerCase().includes(q));
        });
        if (win.sortMode === "recent") list.sort((a, b) => (b.lastConnected || 0) - (a.lastConnected || 0));
        else if (win.sortMode === "status") list.sort((a, b) => (a.status === "ok" ? 0 : 1) - (b.status === "ok" ? 0 : 1));
        else list.sort((a, b) => String(a.name || "").localeCompare(String(b.name || "")));
        return list;
    }
    function healthCount(which) {
        return TerminalApp.hosts.filter(h => which === "ok" ? h.status === "ok" : which === "failed" ? h.status === "failed" : !h.status).length;
    }
    // the dot is a second cue beside the written Reachable/Unreachable text
    function statusName(h) {
        return h.status === "ok" ? Tr.t("Reachable") : h.status === "failed" ? Tr.t("Unreachable") : Tr.t("Not tested");
    }
    // two forwards of the same mode on one port cannot both bind; refuse early
    function tunnelConflict(port, mode) {
        const p = parseInt(port, 10);
        if (!p) return null;
        return TerminalApp.tunnels.find(t => t.localPort === p && t.mode === mode) || null;
    }
    // the exact argv the service would run, shown so it can be pasted into any terminal
    function sshCommand(h) {
        return TerminalApp.sshArgs(h).map(x => String(x).indexOf(" ") >= 0 ? '"' + x + '"' : x).join(" ");
    }
    // accept a copied "user@host:port" (or bare host) into the add form
    function pasteHost() {
        const s = String(Quickshell.clipboardText || "").trim();
        const m = /^(?:([^@\s]+)@)?([^\s:]+)(?::(\d{1,5}))?$/.exec(s);
        if (!m) { win.pasteError = Tr.t("Clipboard is not a host (user@host:port)"); return; }
        win.newHostUser = m[1] || "";
        win.newHostAddr = m[2];
        win.newHostPort = m[3] || "22";
        win.newHostName = ""; win.newHostGroup = ""; win.editId = "";
        win.pasteError = ""; win.tab = "add";
    }
    // We do not own the Ui singleton source file or shell.qml, so there is no a handoff flag to carry
    // the host: write a clipboard marker and set Ui.netTools, the same flag
    // shell.qml's netToolsOpen() sets. NetTools consumes the marker on open.
    function openNetTools(host) {
        const h = String(host || "").trim();
        if (!h) return;
        Quickshell.clipboardText = "shani-nettools:" + h;
        Ui.closeAll();
        Ui.netTools = true;
    }
    function requestDelete(h) {
        if (!h || h.id === undefined) return;
        if (win.confirmingDelete !== h.id) { win.confirmingDelete = h.id; unconfirmDelete.restart(); return; }
        TerminalApp.deleteHost(h.id);
        win.confirmingDelete = "";
    }
    function closePane(id) {
        win.panes = win.panes.filter(p => p.id !== id);
        win.openedHosts = win.openedHosts.filter(x => x !== id);
    }
    function connectPane(id) {
        const h = TerminalApp.hosts.find(x => x.id === id);
        if (h) { win.noteLaunch(h); TerminalApp.connect(h); }
    }
    // testConnection has one callback slot; walk the list one at a time
    function testAll() {
        if (TerminalApp.busy || win.testQueue.length) return;
        win.testQueue = TerminalApp.hosts.filter(h => h.type !== "serial");
        win.testIndex = 0;
        win.testOne();
    }
    function testOne() {
        if (win.testIndex >= win.testQueue.length) { win.testQueue = []; win.testIndex = 0; return; }
        const h = win.testQueue[win.testIndex];
        TerminalApp.testConnection(h, (ok, msg) => {
            win.hostNote = Tr.t("Test %1 of %2 — %3", win.testIndex + 1, win.testQueue.length,
                                ok === "ok" ? Tr.t("Reachable") : Tr.t("Failed"));
            win.testIndex = win.testIndex + 1;
            win.testOne();
        });
    }
    // a saved command is copied, then its host is opened so it can be pasted
    function runSnippet(s) {
        if (!s) return;
        Quickshell.clipboardText = s.command;
        const h = TerminalApp.hosts.find(x => x.id === win.snippetHostId) || TerminalApp.hosts[0];
        if (h) {
            win.noteLaunch(h);
            TerminalApp.connect(h);
            win.snippetNote = Tr.t("Command copied — paste it in %1", h.name);
        } else win.snippetNote = Tr.t("Command copied to clipboard");
    }
    function relativeTime(ms) {
        if (!ms) return "";
        const s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (s < 60) return Tr.t("just now");
        if (s < 3600) return Tr.t("%1 min ago", Math.floor(s / 60));
        if (s < 86400) return Tr.t("%1 h ago", Math.floor(s / 3600));
        return Tr.t("%1 d ago", Math.floor(s / 86400));
    }

    // ssh/picocom run in their own windows, so the shell cannot tell whether a
    // session is still up; "launched from here this time" is the honest proxy
    property var openedHosts: []
    property bool confirmingClose: false
    Timer { id: unconfirmClose; interval: 4000; onTriggered: win.confirmingClose = false }
    Timer { id: unconfirmDelete; interval: 4000; onTriggered: win.confirmingDelete = "" }
    function noteLaunch(host) {
        if (host && host.id !== undefined && win.openedHosts.indexOf(host.id) < 0)
            win.openedHosts = win.openedHosts.concat([host.id]);
        if (host && host.id !== undefined && !win.panes.some(p => p.id === host.id))
            win.panes = win.panes.concat([{ id: host.id, name: host.name || host.host }]);
        if (host && host.id !== undefined) win.activePane = host.id;
    }
    function requestClose() {
        if (win.openedHosts.length > 0 && !win.confirmingClose) {
            win.confirmingClose = true;
            unconfirmClose.restart();
            return;
        }
        win.confirmingClose = false;
        win.openedHosts = [];
        win.panes = [];
        win.activePane = -1;
        win.confirmingDelete = "";
        Ui.terminalApp = false;
    }

    onVisibleChanged: {
        if (visible) TerminalApp.refresh();
        else { win.confirmingClose = false; win.openedHosts = []; win.panes = []; win.activePane = -1; win.confirmingDelete = ""; unconfirmClose.stop(); }
    }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: win.requestClose()
        // keyboard-first host navigation, as in a real terminal (arrows + Enter, / to find)
        Keys.onPressed: e => {
            if (e.modifiers & Qt.ControlModifier) {
                if (e.key === Qt.Key_F) {
                    if (win.tab === "hosts" && hostSearch.visible) hostSearch.input.forceActiveFocus();
                    else if (win.tab === "snippets") snipSearch.input.forceActiveFocus();
                    e.accepted = true;
                } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_4) {
                    win.tab = ["hosts", "keys", "tunnels", "snippets"][e.key - Qt.Key_1];
                    e.accepted = true;
                } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                    const tabs = ["hosts", "keys", "tunnels", "snippets"];
                    const i = Math.max(0, tabs.indexOf(win.tab));
                    win.tab = tabs[(i + (e.key === Qt.Key_Backtab ? tabs.length - 1 : 1)) % tabs.length];
                    e.accepted = true;
                } else if (e.key === Qt.Key_T) {
                    win.tab = "tunnels"; e.accepted = true;
                }
                return;
            }
            if (win.tab !== "hosts" || hostList.count === 0) return;
            if (e.key === Qt.Key_Down) { hostList.currentIndex = Math.min(hostList.count - 1, hostList.currentIndex + 1); e.accepted = true; }
            else if (e.key === Qt.Key_Up) { hostList.currentIndex = Math.max(0, hostList.currentIndex - 1); e.accepted = true; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                const h = hostList.model[hostList.currentIndex];
                if (h) { win.noteLaunch(h); TerminalApp.connect(h); }
                e.accepted = true;
            } else if (e.key === Qt.Key_Slash && hostSearch.visible) {
                hostSearch.input.forceActiveFocus(); e.accepted = true;
            } else if (e.key === Qt.Key_F2) {
                const h = hostList.model[hostList.currentIndex];
                if (h && !TerminalApp.busy && h.type !== "serial")
                    TerminalApp.testConnection(h, (ok, msg) => win.hostNote = (ok === "ok" ? Tr.t("Connected to %1", h.name) : Tr.t("Test failed: %1", msg)));
                e.accepted = true;
            } else if (e.key === Qt.Key_Delete) {
                win.requestDelete(hostList.model[hostList.currentIndex]);
                e.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(16)
        spacing: Theme.px(8)

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            // the title is the window's own (AppWindow's header), not repeated here
            Item { Layout.fillWidth: true }
            Button { text: Tr.t("Refresh"); flat: true; onClicked: TerminalApp.refresh() }
            Button {
                text: win.showShortcuts ? Tr.t("Hide shortcuts") : Tr.t("Shortcuts")
                flat: true; checked: win.showShortcuts
                onClicked: win.showShortcuts = !win.showShortcuts
            }
            Button {
                text: Tr.t("Add host"); kind: "primary"; flat: true
                onClicked: {
                    win.editId = "";
                    win.newHostName = ""; win.newHostAddr = ""; win.newHostUser = ""; win.newHostPort = ""; win.newHostKey = "";
                    win.newHostProxyJump = ""; win.newHostExtraOpts = ""; win.newHostGroup = "";
                    win.newHostForwardAgent = false; win.newHostX11 = false; win.newHostCompression = false;
                    win.tab = "add";
                }
            }
            Button {
                text: Tr.t("Import hosts…"); flat: true
                onClicked: FilePicker.open({ mode: "open", title: Tr.t("Hosts JSON"), onPicked: paths => { if (paths.length) TerminalApp.importHosts(paths[0]); } })
            }
            Button {
                text: Tr.t("Export hosts…"); flat: true
                onClicked: FilePicker.open({ mode: "save", title: Tr.t("Hosts JSON"), defaultName: "shani-terminal-hosts.json", onPicked: paths => { if (paths.length) TerminalApp.exportHosts(paths[0]); } })
            }
            Repeater {
                model: [["hosts", Tr.t("Hosts")], ["keys", Tr.t("Keys")], ["tunnels", Tr.t("Tunnels")], ["snippets", Tr.t("Snippets")]]
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.tab === modelData[0] || (modelData[0] === "hosts" && win.tab === "add")
                    onClicked: win.tab = modelData[0]
                }
            }
        }

        Text {
            visible: win.showShortcuts
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Tr.t("↑/↓ select · Enter connect · / find · Ctrl+F find · Ctrl+1…4 tab · Ctrl+Tab next tab · Ctrl+T tunnels · F2 test · Delete remove (twice) · Esc close")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            Accessible.name: text
        }

        // a second Esc is required before the manager closes while a session
        // launched from here may still be up in its own window
        Text {
            visible: win.confirmingClose
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Tr.t("A connection is open in another window — press Esc again to close")
            color: Theme.danger
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        // session tabs: the shells we launched, with reconnect and close
        Flow {
            visible: win.panes.length > 0
            Layout.fillWidth: true
            spacing: Theme.px(4)
            Repeater {
                model: win.panes
                RowLayout {
                    required property var modelData
                    spacing: 0
                    Choice {
                        text: modelData.name
                        selected: win.activePane === modelData.id
                        Accessible.name: Tr.t("Reconnect to %1", modelData.name)
                        onClicked: { win.activePane = modelData.id; win.connectPane(modelData.id) }
                    }
                    IconButton {
                        icon: "window-close"; size: Theme.px(18)
                        tip: Tr.t("Close session")
                        accessibleName: Tr.t("Close session %1", modelData.name)
                        onClicked: win.closePane(modelData.id)
                    }
                }
            }
        }

        // ---- hosts tab ----
        ColumnLayout {
            visible: win.tab === "hosts" || win.tab === "add"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(6)

            // pinned hosts
            Repeater {
                model: TerminalApp.hosts.filter(h => h.pinned)
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: Theme.px(48)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: Tr.t("Pinned host %1", modelData.name)
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(8) }
                        spacing: Theme.px(8)
                        Icon { name: "pinned"; size: Theme.px(16); color: Theme.accent }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold }
                            Text { text: modelData.user + "@" + modelData.host + (modelData.port !== 22 ? ":" + modelData.port : ""); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                        }
                        Button { text: Tr.t("Connect"); kind: "primary"; onClicked: { win.noteLaunch(modelData); TerminalApp.connect(modelData) } }
                        Button { text: Tr.t("Test"); enabled: !TerminalApp.busy && modelData.type !== "serial"; onClicked: TerminalApp.testConnection(modelData, (ok, msg) => win.hostNote = (ok === "ok" ? Tr.t("Connected to %1", modelData.name) : Tr.t("Test failed: %1", msg))) }
                        Button { text: Tr.t("Ping / DNS"); flat: true; onClicked: win.openNetTools(modelData.host) }
                        IconButton { icon: "folder-remote"; size: Theme.px(26); tip: Tr.t("Browse files on this host"); onClicked: Files.connectServer("ssh://" + modelData.user + "@" + modelData.host + ":" + modelData.port + "/", "", "", "") }
                        IconButton { icon: "go-previous"; tip: Tr.t("Edit"); onClicked: win.editHost(modelData) }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }

            // text
            Text { visible: TerminalApp.error !== ""; text: TerminalApp.error; color: Theme.red; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; Accessible.name: text }
            Text { visible: win.hostNote !== ""; text: win.hostNote; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; Accessible.name: text }
            Text {
                visible: win.pasteError !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: win.pasteError
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.name: text
            }
            Text {
                visible: win.confirmingDelete !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("Press Delete again to remove this host")
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.name: text
            }

            // host groups: one chip per group on a host record
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Repeater {
                    model: win.hostGroups()
                    Choice {
                        required property var modelData
                        text: modelData === "" ? Tr.t("All groups") : modelData
                        selected: win.groupFilter === modelData
                        onClicked: win.groupFilter = modelData
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: Tr.t("%1 reachable · %2 unreachable · %3 not tested", win.healthCount("ok"), win.healthCount("failed"), win.healthCount("untested"))
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                Accessible.name: text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button {
                    text: win.splitView ? Tr.t("Single pane") : Tr.t("Split panes")
                    flat: true; checked: win.splitView
                    onClicked: { win.splitView = !win.splitView; if (win.splitView && !win.splitGroup) win.splitGroup = win.groupFilter; }
                }
                Button {
                    text: TerminalApp.busy ? Tr.t("Testing…") : Tr.t("Test all")
                    flat: true
                    enabled: !TerminalApp.busy && win.testQueue.length === 0
                    onClicked: win.testAll()
                }
                Button { text: Tr.t("Paste host…"); flat: true; onClicked: win.pasteHost() }
                Item { Layout.fillWidth: true }
            }

            // find a host by name, address, user, group or ProxyJump
            SearchField {
                id: hostSearch
                Layout.fillWidth: true
                visible: TerminalApp.hosts.length > 3
                placeholder: Tr.t("Find a host…")
                label: Tr.t("Find a host")
                text: win.hostQuery
                onTextChanged: win.hostQuery = text
            }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Repeater {
                    model: [["name", Tr.t("Sort: Name")], ["recent", Tr.t("Sort: Recent")], ["status", Tr.t("Sort: Health")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.sortMode === modelData[0]
                        onClicked: win.sortMode = modelData[0]
                    }
                }
                Repeater {
                    model: [["", Tr.t("All health")], ["ok", Tr.t("Reachable")], ["failed", Tr.t("Unreachable")], ["untested", Tr.t("Not tested")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.healthFilter === modelData[0]
                        onClicked: win.healthFilter = modelData[0]
                    }
                }
            }

            Flow {
                visible: win.splitView
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text { text: Tr.t("Right pane:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                Repeater {
                    model: win.hostGroups()
                    Choice {
                        required property var modelData
                        text: modelData === "" ? Tr.t("All groups") : modelData
                        selected: win.splitGroup === modelData
                        onClicked: win.splitGroup = modelData
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(6)

                // all hosts list (the primary pane: arrows + Enter drive this one)
                ListView {
                    id: hostList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    reuseItems: true
                    cacheBuffer: 400
                    currentIndex: 0
                    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                    model: win.visibleHosts()
                    delegate: Rectangle {
                        id: hostRow
                        required property var modelData
                        width: hostList.width
                        height: Theme.px(52)
                        radius: Theme.radiusSmall
                        color: hostList.currentItem === hostRow ? Theme.alpha(Theme.accent, 0.14) : (rowArea.containsMouse ? Theme.hover : "transparent")
                        Accessible.role: Accessible.ListItem
                        Accessible.name: Tr.t("Host %1, %2", modelData.name, win.statusName(modelData))
                        RowLayout {
                            anchors { fill: parent; margins: Theme.px(8) }
                            spacing: Theme.px(8)
                            Icon { name: modelData.pinned ? "pinned" : "document-preview"; size: Theme.px(18); color: modelData.pinned ? Theme.accent : Theme.dim }
                            Rectangle {
                                Layout.preferredWidth: Theme.px(8); Layout.preferredHeight: Theme.px(8)
                                radius: width / 2
                                color: modelData.status === "ok" ? Theme.accent : modelData.status === "failed" ? Theme.red : Theme.faint
                                Accessible.role: Accessible.Graphic
                                Accessible.name: win.statusName(modelData)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: modelData.user + "@" + modelData.host + (modelData.port !== 22 ? ":" + modelData.port : "") + (modelData.key ? " · " + Tr.t("key") : "") + (modelData.group ? " · " + modelData.group : "") + (modelData.lastConnected ? " · " + Tr.t("Used %1", win.relativeTime(modelData.lastConnected)) : "") + (modelData.status === "failed" ? " · " + Tr.t("Unreachable") : modelData.status === "ok" ? " · " + Tr.t("Reachable") : ""); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            Button { text: Tr.t("Connect"); kind: "outline"; onClicked: { win.noteLaunch(modelData); TerminalApp.connect(modelData) } }
                            Button { text: Tr.t("Test"); enabled: !TerminalApp.busy && modelData.type !== "serial"; onClicked: TerminalApp.testConnection(modelData, (ok, msg) => win.hostNote = (ok === "ok" ? Tr.t("Connected to %1", modelData.name) : Tr.t("Test failed: %1", msg))) }
                            IconButton { icon: "network-transmit-receive"; size: Theme.px(26); tip: Tr.t("Ping / DNS"); accessibleName: Tr.t("Ping / DNS for %1", modelData.name); onClicked: win.openNetTools(modelData.host) }
                            IconButton { icon: "folder-remote"; size: Theme.px(26); tip: Tr.t("Browse files on this host"); onClicked: Files.connectServer("ssh://" + modelData.user + "@" + modelData.host + ":" + modelData.port + "/", "", "", "") }
                            IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy address"); onClicked: { const addr = modelData.user + "@" + modelData.host; Quickshell.clipboardText = addr; win.hostNote = Tr.t("Copied %1", addr) } }
                            IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy SSH command"); onClicked: { Quickshell.clipboardText = win.sshCommand(modelData); win.hostNote = Tr.t("Copied SSH command for %1", modelData.name) } }
                            IconButton { icon: "object-select"; size: Theme.px(26); tip: modelData.pinned ? Tr.t("Unpin") : Tr.t("Pin"); onClicked: TerminalApp.togglePin(modelData.id) }
                            IconButton { icon: "go-previous"; size: Theme.px(26); tip: Tr.t("Edit"); onClicked: win.editHost(modelData) }
                            IconButton { icon: "edit-clear-all"; size: Theme.px(26); tip: win.confirmingDelete === modelData.id ? Tr.t("Tap again to delete") : Tr.t("Delete"); onClicked: win.requestDelete(modelData) }
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    }
                    EmptyState {
                        anchors.centerIn: parent
                        visible: hostList.count === 0
                        icon: "folder-remote"
                        // a search that matches nothing is not an empty address book
                        title: TerminalApp.hosts.length === 0 ? Tr.t("No SSH hosts yet")
                            : ((win.groupFilter || win.healthFilter) ? Tr.t("No hosts match your filters") : Tr.t("No hosts match your search"))
                        subtitle: TerminalApp.hosts.length === 0
                            ? Tr.t("Add one to connect to remote machines. Also works with serial ports.")
                            : ((win.groupFilter || win.healthFilter) ? Tr.t("Clear a group or health filter to see more hosts.") : Tr.t("Try a different name, address or user."))
                    }
                }

                // second pane: an independent group, so two hosts sit side by side
                ListView {
                    id: hostListB
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.splitView
                    clip: true
                    reuseItems: true
                    model: win.visibleHosts(win.splitGroup)
                    delegate: Rectangle {
                        required property var modelData
                        width: hostListB.width
                        height: Theme.px(52)
                        radius: Theme.radiusSmall
                        color: Theme.alpha(Theme.accent, 0.10)
                        Accessible.role: Accessible.ListItem
                        Accessible.name: Tr.t("Right pane host %1", modelData.name)
                        RowLayout {
                            anchors { fill: parent; margins: Theme.px(8) }
                            spacing: Theme.px(8)
                            Rectangle {
                                Layout.preferredWidth: Theme.px(8); Layout.preferredHeight: Theme.px(8)
                                radius: width / 2
                                color: modelData.status === "ok" ? Theme.accent : modelData.status === "failed" ? Theme.red : Theme.faint
                                Accessible.role: Accessible.Graphic
                                Accessible.name: win.statusName(modelData)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: modelData.user + "@" + modelData.host + (modelData.group ? " · " + modelData.group : ""); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            Button { text: Tr.t("Connect"); kind: "outline"; onClicked: { win.noteLaunch(modelData); TerminalApp.connect(modelData) } }
                        }
                    }
                    EmptyState {
                        anchors.centerIn: parent
                        visible: hostListB.count === 0
                        icon: "folder-remote"
                        title: Tr.t("No hosts in this pane")
                        subtitle: Tr.t("Pick another group for the right pane")
                    }
                }
            }
        }

        // ---- add / edit form ----
        RowLayout {
            visible: win.tab === "add"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                TextField {
                    id: nameF
                    Layout.fillWidth: true
                    placeholder: Tr.t("Host name")
                    text: win.newHostName
                    onTextChanged: win.newHostName = text
                }
                TextField {
                    id: addrF
                    Layout.fillWidth: true
                    placeholder: Tr.t("Host address (e.g. server.example.com)")
                    text: win.newHostAddr
                    onTextChanged: win.newHostAddr = text
                }
                RowLayout {
                    spacing: Theme.px(6)
                    TextField {
                        Layout.preferredWidth: Theme.px(60)
                        placeholder: Tr.t("Port")
                        text: win.newHostPort
                        onTextChanged: win.newHostPort = text
                    }
                    TextField {
                        Layout.fillWidth: true
                        placeholder: Tr.t("User")
                        text: win.newHostUser
                        onTextChanged: win.newHostUser = text
                    }
                }
                TextField {
                    id: keyF
                    Layout.fillWidth: true
                    placeholder: Tr.t("SSH key (optional)")
                    text: win.newHostKey
                    onTextChanged: win.newHostKey = text
                }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Group / tag (optional)")
                    label: Tr.t("Group or tag")
                    text: win.newHostGroup
                    onTextChanged: win.newHostGroup = text
                }
                // advanced ssh options (ProxyJump, forwarding, X11, …)
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("ProxyJump (e.g. bastion.example.com)")
                    text: win.newHostProxyJump
                    onTextChanged: win.newHostProxyJump = text
                }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Extra -o options, comma separated (e.g. ServerAliveInterval=15)")
                    text: win.newHostExtraOpts
                    onTextChanged: win.newHostExtraOpts = text
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Choice { text: Tr.t("Forward agent"); selected: win.newHostForwardAgent; onClicked: win.newHostForwardAgent = !win.newHostForwardAgent }
                    Choice { text: "X11"; selected: win.newHostX11; onClicked: win.newHostX11 = !win.newHostX11 }
                    Choice { text: Tr.t("Compression"); selected: win.newHostCompression; onClicked: win.newHostCompression = !win.newHostCompression }
                }
            }
            Button {
                text: win.newHostName === "" && win.editId === "" ? Tr.t("Add host") : Tr.t("Save")
                kind: "primary"
                enabled: win.newHostAddr.trim() !== ""
                onClicked: {
                    if (win.newHostName === "") win.newHostName = win.newHostAddr;
                    const o = win.hostOpts();
                    if (win.editId) {
                        TerminalApp.updateHost(win.editId, { name: win.newHostName, host: win.newHostAddr, port: parseInt(win.newHostPort) || 22, user: win.newHostUser, key: win.newHostKey,
                            proxyJump: o.proxyJump, forwardAgent: o.forwardAgent, x11: o.x11, compression: o.compression, extraOpts: o.extraOpts, group: win.newHostGroup.trim() });
                        win.editId = "";
                    } else {
                        TerminalApp.addHost(win.newHostName, win.newHostAddr, parseInt(win.newHostPort) || 22, win.newHostUser, win.newHostKey, "ssh", o);
                        // addHost knows only its fixed fields; attach the group to the new record through updateHost
                        if (win.newHostGroup.trim())
                            TerminalApp.updateHost(TerminalApp.hosts[TerminalApp.hosts.length - 1].id, { group: win.newHostGroup.trim() });
                    }
                    win.newHostName = ""; win.newHostAddr = ""; win.newHostUser = ""; win.newHostPort = ""; win.newHostKey = "";
                    win.newHostProxyJump = ""; win.newHostExtraOpts = ""; win.newHostForwardAgent = false; win.newHostX11 = false; win.newHostCompression = false;
                    win.newHostGroup = "";
                    win.tab = "hosts";
                }
            }
            Button {
                visible: win.tab === "add"; text: Tr.t("Cancel"); flat: true
                onClicked: {
                    win.tab = "hosts"; win.editId = "";
                    // a cancelled edit must not seed the next "Add host" with the old host's data
                    win.newHostName = ""; win.newHostAddr = ""; win.newHostUser = ""; win.newHostPort = ""; win.newHostKey = "";
                    win.newHostProxyJump = ""; win.newHostExtraOpts = ""; win.newHostForwardAgent = false; win.newHostX11 = false; win.newHostCompression = false;
                    win.newHostGroup = "";
                }
            }
        }

            // ---- keys tab ----
        ColumnLayout {
            visible: win.tab === "keys"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(6)

            // generate form
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: genNameF
                    Layout.fillWidth: true
                    placeholder: Tr.t("Key name")
                    text: win.newKeyName
                    onTextChanged: win.newKeyName = text
                }
                Button {
                    text: Tr.t("Generate key")
                    enabled: win.newKeyName.trim() !== "" && !TerminalApp.busy
                    onClicked: TerminalApp.generateKey(win.newKeyName.trim(), 2048)
                }
                Button {
                    text: Tr.t("Import…")
                    onClicked: FilePicker.open({ mode: "open", onPicked: paths => { if (paths.length) TerminalApp.importKey(paths[0], paths[0].split("/").pop()); } })
                }
            }

            // key list
            ListView {
                id: keyList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: TerminalApp.keys
                delegate: Rectangle {
                    required property var modelData
                    width: keyList.width
                    height: Theme.px(48)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: Tr.t("SSH key %1", modelData.name)
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(8) }
                        spacing: Theme.px(8)
                        Icon { name: "text-x-generic"; size: Theme.px(18); color: Theme.dim }
                        Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: modelData.fingerprint.split(" ").pop() || ""; color: Theme.faint; font.family: Theme.mono; font.pixelSize: Theme.px(9) * Theme.fontScale; elide: Text.ElideRight; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignRight }
                        IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy path"); onClicked: Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", modelData.path]) }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: keyList.count === 0
                    icon: "text-x-generic"
                    title: Tr.t("No SSH keys")
                    subtitle: Tr.t("Generate a new key or import one from another computer")
                }
            }
        }

        // ---- tunnels tab ----
        ColumnLayout {
            visible: win.tab === "tunnels"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(6)

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.t("Forward a port through an SSH server: local (-L), remote (-R), or a dynamic SOCKS proxy (-D). It runs in the background until stopped.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["L", Tr.t("Local (-L)")], ["R", Tr.t("Remote (-R)")], ["D", Tr.t("SOCKS (-D)")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.tunnelMode === modelData[0]
                        onClicked: win.tunnelMode = modelData[0]
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: TerminalApp.hosts
                    Choice {
                        required property var modelData
                        text: modelData.name
                        selected: (win.tunnelHostId || TerminalApp.hosts[0]?.id) === modelData.id
                        onClicked: win.tunnelHostId = modelData.id
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                TextField { id: tunLocal; Layout.preferredWidth: Theme.px(90); placeholder: win.tunnelMode === "R" ? Tr.t("Port on server") : Tr.t("Local port"); label: Tr.t("Tunnel port") }
                TextField { id: tunRemoteHost; Layout.fillWidth: true; visible: win.tunnelMode !== "D"; placeholder: Tr.t("Destination host") }
                TextField { id: tunRemotePort; Layout.preferredWidth: Theme.px(90); visible: win.tunnelMode !== "D"; placeholder: Tr.t("Destination port") }
                Button {
                    text: Tr.t("Start tunnel")
                    kind: "primary"
                    enabled: TerminalApp.hosts.length > 0 && tunLocal.text.trim() !== ""
                        && (win.tunnelMode === "D" || (tunRemoteHost.text.trim() !== "" && tunRemotePort.text.trim() !== ""))
                        && !win.tunnelConflict(tunLocal.text, win.tunnelMode)
                    onClicked: {
                        const h = TerminalApp.hosts.find(x => x.id === win.tunnelHostId) || TerminalApp.hosts[0];
                        TerminalApp.tunnel(h, tunLocal.text.trim(), tunRemoteHost.text.trim(), tunRemotePort.text.trim(), win.tunnelMode);
                        tunLocal.text = ""; tunRemoteHost.text = ""; tunRemotePort.text = "";
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: !!win.tunnelConflict(tunLocal.text, win.tunnelMode)
                text: Tr.t("Port %1 is already forwarded by an active %2 tunnel — stop it first", tunLocal.text.trim(), win.tunnelMode === "D" ? "SOCKS" : win.tunnelMode)
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.name: text
            }
            ListView {
                id: tunnelList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: TerminalApp.tunnels
                delegate: RowLayout {
                    required property var modelData
                    width: tunnelList.width
                    spacing: Theme.px(8)
                    Icon { name: "network-workgroup"; size: Theme.px(18); color: Theme.dim }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { text: modelData.mode + " · " + modelData.localPort; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Button { text: Tr.t("Stop"); flat: true; onClicked: TerminalApp.stopTunnel(modelData.id) }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: tunnelList.count === 0
                    icon: "network-workgroup"
                    title: Tr.t("No active tunnels")
                    subtitle: Tr.t("Add one with the form above")
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("Tunnels run in the background; Shani cannot verify a dropped tunnel is still alive.")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                Accessible.name: text
            }
        }

        // ---- snippets tab ----
        ColumnLayout {
            visible: win.tab === "snippets"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(6)

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.t("Saved SSH commands — copy one into a terminal when you need it.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                TextField { id: snipName; Layout.preferredWidth: Theme.px(140); placeholder: Tr.t("Name") }
                TextField { id: snipCommand; Layout.fillWidth: true; placeholder: Tr.t("Command, e.g. ssh -L 8080:localhost:80 server") }
                Button {
                    text: Tr.t("Add")
                    kind: "primary"
                    enabled: snipName.text.trim() !== "" && snipCommand.text.trim() !== ""
                    onClicked: {
                        TerminalApp.addSnippet(snipName.text, snipCommand.text);
                        snipName.text = ""; snipCommand.text = "";
                    }
                }
            }
            SearchField {
                id: snipSearch
                Layout.fillWidth: true
                visible: TerminalApp.snippets.length > 3
                placeholder: Tr.t("Find a snippet…")
                label: Tr.t("Find a snippet")
                text: win.snippetQuery
                onTextChanged: win.snippetQuery = text
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text { text: Tr.t("Run on:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                Repeater {
                    model: TerminalApp.hosts
                    Choice {
                        required property var modelData
                        text: modelData.name
                        selected: (win.snippetHostId || TerminalApp.hosts[0]?.id) === modelData.id
                        onClicked: win.snippetHostId = modelData.id
                    }
                }
            }
            ListView {
                id: snippetList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: TerminalApp.snippets.filter(s => !win.snippetQuery || [s.name, s.command].some(x => String(x || "").toLowerCase().includes(win.snippetQuery.toLowerCase())))
                delegate: RowLayout {
                    required property var modelData
                    width: snippetList.width
                    spacing: Theme.px(8)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.command; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    }
                    IconButton {
                        icon: "go-next"; size: Theme.px(26)
                        tip: Tr.t("Copy command and connect to host")
                        onClicked: win.runSnippet(modelData)
                    }
                    IconButton {
                        icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy command")
                        onClicked: { Quickshell.clipboardText = modelData.command; win.snippetNote = Tr.t("Copied %1", modelData.name) }
                    }
                    IconButton { icon: "edit-clear-all"; size: Theme.px(26); tip: Tr.t("Delete"); onClicked: TerminalApp.deleteSnippet(modelData.name) }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: snippetList.count === 0
                    icon: "edit-copy"
                    title: TerminalApp.snippets.length === 0 ? Tr.t("No SSH snippets") : Tr.t("No snippets match your search")
                    subtitle: TerminalApp.snippets.length === 0 ? Tr.t("Save a command you use often") : Tr.t("Try a different name or command.")
                }
            }
            Text {
                visible: win.snippetNote !== ""
                Layout.fillWidth: true
                text: win.snippetNote
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.name: text
            }
        }
    }
}
