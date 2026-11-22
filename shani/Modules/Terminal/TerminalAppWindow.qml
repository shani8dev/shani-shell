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
                        IconButton { icon: "folder-remote"; size: Theme.px(26); tip: Tr.t("Browse files on this host"); onClicked: Files.connectServer("ssh://" + modelData.user + "@" + modelData.host + ":" + modelData.port + "/", "", "", "") }
                        IconButton { icon: "go-previous"; tip: Tr.t("Edit"); onClicked: { win.tab = "add"; win.newHostName = modelData.name; win.newHostAddr = modelData.host; win.newHostUser = modelData.user; win.newHostPort = String(modelData.port); win.newHostKey = modelData.key || ""; win.editId = modelData.id; } }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }

            // text
            Text { visible: TerminalApp.error !== ""; text: TerminalApp.error; color: Theme.red; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }

            // all hosts list
            ListView {
                id: hostList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                reuseItems: true
                cacheBuffer: 400
                model: TerminalApp.hosts
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
                            Text { text: modelData.user + "@" + modelData.host + (modelData.port !== 22 ? ":" + modelData.port : "") + (modelData.key ? " · " + Tr.t("key") : ""); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Button { text: Tr.t("Connect"); kind: "outline"; onClicked: TerminalApp.connect(modelData) }
                        IconButton { icon: "folder-remote"; size: Theme.px(26); tip: Tr.t("Browse files on this host"); onClicked: Files.connectServer("ssh://" + modelData.user + "@" + modelData.host + ":" + modelData.port + "/", "", "", "") }
                        IconButton { icon: "object-select"; size: Theme.px(26); tip: modelData.pinned ? Tr.t("Unpin") : Tr.t("Pin"); onClicked: TerminalApp.togglePin(modelData.id) }
                        IconButton { icon: "go-previous"; size: Theme.px(26); tip: Tr.t("Edit"); onClicked: { win.tab = "add"; win.newHostName = modelData.name; win.newHostAddr = modelData.host; win.newHostUser = modelData.user; win.newHostPort = String(modelData.port); win.newHostKey = modelData.key || ""; win.editId = modelData.id; } }
                        IconButton { icon: "edit-clear-all"; size: Theme.px(26); tip: Tr.t("Delete"); onClicked: TerminalApp.deleteHost(modelData.id) }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: hostList.count === 0
                    icon: "folder-remote"
                    title: Tr.t("No SSH hosts yet")
                    subtitle: Tr.t("Add one to connect to remote machines. Also works with serial ports.")
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
                }
                Button {
                    text: win.newHostName === "" && win.editId === "" ? Tr.t("Add host") : Tr.t("Save")
                    kind: "primary"
                    enabled: win.newHostAddr.trim() !== ""
                    onClicked: {
                        if (win.newHostName === "") win.newHostName = win.newHostAddr;
                        if (win.editId) {
                            TerminalApp.updateHost(win.editId, { name: win.newHostName, host: win.newHostAddr, port: parseInt(win.newHostPort) || 22, user: win.newHostUser, key: win.newHostKey });
                            win.editId = "";
                        } else {
                            TerminalApp.addHost(win.newHostName, win.newHostAddr, parseInt(win.newHostPort) || 22, win.newHostUser, win.newHostKey);
                        }
                        win.newHostName = ""; win.newHostAddr = ""; win.newHostUser = ""; win.newHostPort = ""; win.newHostKey = "";
                        win.tab = "hosts";
                    }
                }
                Button { visible: win.tab === "add"; text: Tr.t("Cancel"); flat: true; onClicked: { win.tab = "hosts"; win.editId = ""; } }
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
                text: Tr.t("Forward a local port to a host reachable from an SSH server. The tunnel runs in the background until you stop it.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
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
                TextField { id: tunLocal; Layout.preferredWidth: Theme.px(90); placeholder: Tr.t("Local port") }
                TextField { id: tunRemoteHost; Layout.fillWidth: true; placeholder: Tr.t("Remote host") }
                TextField { id: tunRemotePort; Layout.preferredWidth: Theme.px(90); placeholder: Tr.t("Remote port") }
                Button {
                    text: Tr.t("Start tunnel")
                    kind: "primary"
                    enabled: TerminalApp.hosts.length > 0 && tunLocal.text.trim() !== "" && tunRemoteHost.text.trim() !== "" && tunRemotePort.text.trim() !== ""
                    onClicked: {
                        const h = TerminalApp.hosts.find(x => x.id === win.tunnelHostId) || TerminalApp.hosts[0];
                        TerminalApp.tunnel(h, tunLocal.text.trim(), tunRemoteHost.text.trim(), tunRemotePort.text.trim());
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