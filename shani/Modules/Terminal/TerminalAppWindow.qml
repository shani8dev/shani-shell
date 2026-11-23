// Terminal: a SSH connection manager. List hosts, add/edit/delete/pin hosts,
// generate/import keys, test connections, and connect. Uses Services/TerminalApp.
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
        win.editId = h.id;
    }
    function relativeTime(ms) {
        if (!ms) return "";
        const s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (s < 60) return Tr.t("just now");
        if (s < 3600) return Tr.t("%1 min ago", Math.floor(s / 60));
        if (s < 86400) return Tr.t("%1 h ago", Math.floor(s / 3600));
        return Tr.t("%1 d ago", Math.floor(s / 86400));
    }

    onVisibleChanged: if (visible) TerminalApp.refresh()

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Ui.terminalApp = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(16)
        spacing: Theme.px(8)

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: Tr.t("Terminal")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(16) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            Button { text: Tr.t("Refresh"); flat: true; onClicked: TerminalApp.refresh() }
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
                        Button { text: Tr.t("Connect"); kind: "primary"; onClicked: TerminalApp.connect(modelData) }
                        Button { text: Tr.t("Test"); enabled: !TerminalApp.busy && modelData.type !== "serial"; onClicked: TerminalApp.testConnection(modelData, (ok, msg) => win.hostNote = (ok === "ok" ? Tr.t("Connected to %1", modelData.name) : Tr.t("Test failed: %1", msg))) }
                        IconButton { icon: "folder-remote"; size: Theme.px(26); tip: Tr.t("Browse files on this host"); onClicked: Files.connectServer("ssh://" + modelData.user + "@" + modelData.host + ":" + modelData.port + "/", "", "", "") }
                        IconButton { icon: "go-previous"; tip: Tr.t("Edit"); onClicked: win.editHost(modelData) }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }

            // text
            Text { visible: TerminalApp.error !== ""; text: TerminalApp.error; color: Theme.red; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Text { visible: win.hostNote !== ""; text: win.hostNote; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }

            // find a host by name, address or user
            TextField {
                Layout.fillWidth: true
                visible: TerminalApp.hosts.length > 3
                placeholder: Tr.t("Find a host…")
                text: win.hostQuery
                onTextChanged: win.hostQuery = text
            }

            // all hosts list
            ListView {
                id: hostList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                reuseItems: true
                cacheBuffer: 400
                model: TerminalApp.hosts.filter(h => !win.hostQuery || [h.name, h.host, h.user].some(x => String(x || "").toLowerCase().includes(win.hostQuery.toLowerCase())))
                delegate: Rectangle {
                    required property var modelData
                    width: hostList.width
                    height: Theme.px(52)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(8) }
                        spacing: Theme.px(8)
                        Icon { name: modelData.pinned ? "pinned" : "document-preview"; size: Theme.px(18); color: modelData.pinned ? Theme.accent : Theme.dim }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: modelData.user + "@" + modelData.host + (modelData.port !== 22 ? ":" + modelData.port : "") + (modelData.key ? " · " + Tr.t("key") : "") + (modelData.lastConnected ? " · " + Tr.t("Used %1", win.relativeTime(modelData.lastConnected)) : "") + (modelData.status === "failed" ? " · " + Tr.t("Unreachable") : modelData.status === "ok" ? " · " + Tr.t("Reachable") : ""); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Button { text: Tr.t("Connect"); kind: "outline"; onClicked: TerminalApp.connect(modelData) }
                        Button { text: Tr.t("Test"); enabled: !TerminalApp.busy && modelData.type !== "serial"; onClicked: TerminalApp.testConnection(modelData, (ok, msg) => win.hostNote = (ok === "ok" ? Tr.t("Connected to %1", modelData.name) : Tr.t("Test failed: %1", msg))) }
                        IconButton { icon: "folder-remote"; size: Theme.px(26); tip: Tr.t("Browse files on this host"); onClicked: Files.connectServer("ssh://" + modelData.user + "@" + modelData.host + ":" + modelData.port + "/", "", "", "") }
                        IconButton { icon: "object-select"; size: Theme.px(26); tip: modelData.pinned ? Tr.t("Unpin") : Tr.t("Pin"); onClicked: TerminalApp.togglePin(modelData.id) }
                        IconButton { icon: "go-previous"; size: Theme.px(26); tip: Tr.t("Edit"); onClicked: win.editHost(modelData) }
                        IconButton { icon: "edit-clear-all"; size: Theme.px(26); tip: Tr.t("Delete"); onClicked: TerminalApp.deleteHost(modelData.id) }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: hostList.count === 0
                    icon: "folder-remote"
                    // a search that matches nothing is not an empty address book
                    title: TerminalApp.hosts.length === 0 ? Tr.t("No SSH hosts yet") : Tr.t("No hosts match your search")
                    subtitle: TerminalApp.hosts.length === 0
                        ? Tr.t("Add one to connect to remote machines. Also works with serial ports.")
                        : Tr.t("Try a different name, address or user.")
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
                                proxyJump: o.proxyJump, forwardAgent: o.forwardAgent, x11: o.x11, compression: o.compression, extraOpts: o.extraOpts });
                            win.editId = "";
                        } else {
                            TerminalApp.addHost(win.newHostName, win.newHostAddr, parseInt(win.newHostPort) || 22, win.newHostUser, win.newHostKey, "ssh", o);
                        }
                        win.newHostName = ""; win.newHostAddr = ""; win.newHostUser = ""; win.newHostPort = ""; win.newHostKey = "";
                        win.newHostProxyJump = ""; win.newHostExtraOpts = ""; win.newHostForwardAgent = false; win.newHostX11 = false; win.newHostCompression = false;
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
                    }
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
                TextField { id: tunLocal; Layout.preferredWidth: Theme.px(90); placeholder: win.tunnelMode === "R" ? Tr.t("Port on server") : Tr.t("Local port") }
                TextField { id: tunRemoteHost; Layout.fillWidth: true; visible: win.tunnelMode !== "D"; placeholder: Tr.t("Destination host") }
                TextField { id: tunRemotePort; Layout.preferredWidth: Theme.px(90); visible: win.tunnelMode !== "D"; placeholder: Tr.t("Destination port") }
                Button {
                    text: Tr.t("Start tunnel")
                    kind: "primary"
                    enabled: TerminalApp.hosts.length > 0 && tunLocal.text.trim() !== ""
                        && (win.tunnelMode === "D" || (tunRemoteHost.text.trim() !== "" && tunRemotePort.text.trim() !== ""))
                    onClicked: {
                        const h = TerminalApp.hosts.find(x => x.id === win.tunnelHostId) || TerminalApp.hosts[0];
                        TerminalApp.tunnel(h, tunLocal.text.trim(), tunRemoteHost.text.trim(), tunRemotePort.text.trim(), win.tunnelMode);
                        tunLocal.text = ""; tunRemoteHost.text = ""; tunRemotePort.text = "";
                    }
                }
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
            ListView {
                id: snippetList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: TerminalApp.snippets
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
                        icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy command")
                        onClicked: { Quickshell.clipboardText = modelData.command; win.snippetNote = Tr.t("Copied %1", modelData.name) }
                    }
                    IconButton { icon: "edit-clear-all"; size: Theme.px(26); tip: Tr.t("Delete"); onClicked: TerminalApp.deleteSnippet(modelData.name) }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: snippetList.count === 0
                    icon: "edit-copy"
                    title: Tr.t("No SSH snippets")
                    subtitle: Tr.t("Save a command you use often")
                }
            }
            Text {
                visible: win.snippetNote !== ""
                Layout.fillWidth: true
                text: win.snippetNote
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }
    }
}
