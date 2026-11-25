// The gateway: the devices a person can hand something to, and the VPN link
// that reaches them. Peers come from the services that already discover them
// (Nearby on the LAN, the paired phone) - no discovery of our own. A peer is
// shown as a QR when the Qr service can make one, and always as a handle that
// can be read or copied. The VPN list below is NetworkManager, read live.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: Tr.t("Gateway")
    visible: Ui.gateway
    onGone: Ui.gateway = false
    implicitWidth: Theme.px(640)
    implicitHeight: Theme.px(720)

    property var peers: []
    property var recent: []
    property string search: ""
    property string peerError: ""
    property string note: ""
    property string pendingFile: ""     // a file handed over by Share, not a peer

    readonly property var formats: ["handle", "link", "address"]

    Timer { id: noteTimer; interval: 5000; onTriggered: win.note = "" }
    function flash(msg) { win.note = msg; noteTimer.restart(); }

    // ---- the peers -------------------------------------------------------------
    function peerHandle(p) {
        const name = p.alias || p.name || Tr.t("Nearby device");
        const key = p.fingerprint || p.id || p.ip || "";
        return key ? name + "@" + String(key).slice(0, 8) : name;
    }
    function peerAddress(p) {
        return p.ip && p.port ? p.ip + ":" + p.port : (p.address || "");
    }
    function peerObjects() {
        const out = [];
        if (typeof Nearby !== "undefined" && Nearby && Nearby.devices)
            Nearby.devices.forEach(d => out.push({
                id: d.fingerprint || d.ip || d.alias,
                name: d.alias || d.deviceModel || Tr.t("Nearby device"),
                handle: win.peerHandle(d),
                address: win.peerAddress(d),
                kind: "nearby"
            }));
        if (typeof Phone !== "undefined" && Phone && Phone.reachable)
            out.push({
                id: "phone", name: Phone.name || Tr.t("Phone"),
                handle: Phone.name || Tr.t("Phone"), address: "", kind: "phone"
            });
        return out;
    }
    function refreshPeers() {
        try {
            win.peers = win.peerObjects();
            win.peerError = "";
        } catch (e) {
            win.peerError = Tr.t("Peers could not be loaded") + ": " + String(e || "");
        }
    }
    // A gateway link, or the handle of a peer we actually know, can be handed
    // over on the clipboard. An arbitrary "user@host" (an email) is ordinary
    // text and is left alone; a prefill never invents a peer error.
    function looksLikeHandleOrUrl(text) {
        const s = String(text || "").trim();
        if (/^https?:\/\/\S+$/i.test(s)) return true;
        return win.peers.some(p => p.handle === s || p.name === s);
    }
    // A file handoff is explicit: Share writes "shani-gateway:<path>". A random
    // leading-"/" string is not a handoff, and the path is only accepted once
    // the file is confirmed to exist.
    function prefillFromClipboard() {
        const t = String(Quickshell.clipboardText || "").trim();
        if (!t) return false;
        if (win.looksLikeHandleOrUrl(t)) {
            const m = t.match(/\/peer\/([^/?#]+)/);
            win.search = m ? decodeURIComponent(m[1]) : t;
            win.flash(Tr.t("Prefilled from the clipboard"));
            return true;
        }
        const marker = "shani-gateway:";
        if (t.indexOf(marker) === 0) {
            const path = t.slice(marker.length).trim();
            if (path !== "") {
                handoffCheck.checkedPath = path;
                handoffCheck.command = ["sh", "-c", 'test -f "$1"', "sh", path];
                handoffCheck.running = false;
                handoffCheck.running = true;
                return true;
            }
        }
        return false;                           // no claim, no error, no search change
    }
    // a search narrows from the start of the name or the handle, not a substring
    function matchingPeers(q) {
        const s = String(q || "").trim().toLowerCase();
        if (!s) return win.peers;
        return win.peers.filter(p =>
            String(p.name).toLowerCase().indexOf(s) === 0
            || String(p.handle).toLowerCase().indexOf(s) === 0);
    }
    // X / Y / Z: the three ways a peer can be handed to someone else
    function peerFormats(p) {
        return {
            handle: p.handle || "",
            link: p.handle ? "https://gateway.local/peer/" + encodeURIComponent(p.handle) : "",
            address: p.address || ""
        };
    }
    function formatName(fmt) {
        switch (fmt) {
            case "handle": return Tr.t("Handle");
            case "link": return Tr.t("Link");
            case "address": return Tr.t("Address");
            default: return fmt;
        }
    }
    function copyPeer(p, fmt) {
        const f = win.peerFormats(p);
        const v = f[fmt] || "";
        if (!v) { win.flash(Tr.t("This peer has no %1").arg(win.formatName(fmt))); return false; }
        Quickshell.clipboardText = v;
        win.noteRecent(p);
        win.flash(Tr.t("Copied %1").arg(win.formatName(fmt)));
        return true;
    }
    function noteRecent(p) {
        if (!p) return;
        win.recent = [p].concat(win.recent.filter(x => x.id !== p.id)).slice(0, 6);
    }
    function showQr(p) {
        const text = win.peerFormats(p).handle;
        if (!text) { win.flash(Tr.t("This peer has no handle")); return false; }
        if (typeof Qr !== "undefined" && Qr && typeof Qr.show === "function") {
            Qr.show(p.name, text);
            return true;
        }
        // Textual fallback below always shows the handle; say why there is no code.
        win.flash(Tr.t("QR is unavailable - share the handle instead"));
        return false;
    }

    Process {
        id: handoffCheck
        property string checkedPath: ""
        command: []
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (code === 0) {
                win.pendingFile = handoffCheck.checkedPath;
                win.flash(Tr.t("File ready to send: %1").arg(win.pendingFile.split("/").pop()));
            }
        }
    }
    Component.onCompleted: win.refreshPeers()
    // consume on every open, not once per shell: a later Share handoff must work
    onVisibleChanged: if (visible) win.prefillFromClipboard()
    Connections { target: Nearby; function onDevicesChanged() { win.refreshPeers(); } }

    // ---- the VPN connections ---------------------------------------------------
    property var connections: []
    property string vpnNote: ""
    property bool vpnBusy: false

    function refreshVpn() { vpnList.running = false; vpnList.running = true; vpnBusy = true; }
    function flashVpn(msg) { win.vpnNote = msg; vpnTimer.restart(); }
    Timer { id: vpnTimer; interval: 6000; onTriggered: win.vpnNote = "" }
    function toggleVpn(c) {
        if (!c || !c.name) return;
        vpnAction.name = c.name;
        vpnAction.up = c.state !== "activated";
        vpnAction.command = ["nmcli", "connection", vpnAction.up ? "up" : "down", c.name];
        vpnAction.running = true;
        vpnBusy = true;
    }
    function vpnStateText(state) {
        return state === "activated" ? Tr.t("Connected")
             : state === "activating" ? Tr.t("Connecting…")
             : Tr.t("Disconnected");
    }
    Process {
        id: vpnList
        command: ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                win.connections = text.split("\n").filter(l => l.trim() !== "").map(l => {
                    const f = l.split(":");
                    return { name: f[0] || "", kind: f[1] || "", state: f[2] || "" };
                }).filter(c => /vpn|wireguard|tunnel|openvpn/i.test(c.kind));
                win.vpnBusy = false;
            }
        }
        stderr: StdioCollector { id: vpnListErr }
        onExited: code => {
            if (code !== 0)
                win.flashVpn(Tr.t("Could not read VPN connections")
                    + (vpnListErr.text.trim() ? ": " + vpnListErr.text.trim().split("\n").pop() : ""));
        }
    }
    Process {
        id: vpnAction
        property string name: ""
        property bool up: true
        stdout: StdioCollector { id: vpnActionOut }
        stderr: StdioCollector { id: vpnActionErr }
        onExited: code => {
            win.vpnBusy = false;
            const detail = (vpnActionErr.text || vpnActionOut.text).trim().split("\n").pop();
            win.flashVpn(code === 0
                ? (vpnAction.up ? Tr.t("Connected to %1").arg(vpnAction.name)
                                : Tr.t("Disconnected from %1").arg(vpnAction.name))
                : Tr.t("Could not change %1").arg(vpnAction.name) + (detail ? ": " + detail : ""));
            win.refreshVpn();
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { win.visible = false; Ui.gateway = false; }
        Keys.onPressed: e => { if (e.key === Qt.Key_F5) { win.refreshPeers(); win.refreshVpn(); e.accepted = true; } }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)

            // ---- peers ----------------------------------------------------------
            SectionTitle { Layout.fillWidth: true; text: Tr.t("Peers") }
            TextField {
                id: searchField
                objectName: "gateway-search"
                Layout.fillWidth: true
                label: Tr.t("Search peers by prefix")
                placeholder: Tr.t("Type the start of a name or handle")
                text: win.search
                onTextChanged: win.search = text
            }
            Text {
                Layout.fillWidth: true
                visible: win.peerError !== ""
                text: win.peerError
                color: Theme.danger; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: win.peerError
            }
            Text {
                Layout.fillWidth: true
                visible: win.note !== ""
                text: win.note
                color: Theme.accent; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: win.note
            }
            ListView {
                id: peerList
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                spacing: Theme.px(4)
                model: win.matchingPeers(win.search)
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: peerList.width; height: Theme.px(96); radius: Theme.radiusSmall
                    color: Theme.surface1
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + ", " + modelData.handle
                    ColumnLayout {
                        anchors { fill: parent; margins: Theme.px(8) }
                        spacing: Theme.px(3)
                        Text {
                            Layout.fillWidth: true; text: row.modelData.name
                            color: Theme.text; elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale
                        }
                        // the textual handle stays readable even without a QR code
                        Text {
                            objectName: "peer-handle"
                            Layout.fillWidth: true; text: row.modelData.handle
                            color: Theme.dim; elide: Text.ElideMiddle
                            font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.px(4)
                            Repeater {
                                model: win.formats
                                Button {
                                    required property string modelData
                                    text: win.formatName(modelData)
                                    onClicked: win.copyPeer(row.modelData, modelData)
                                    Accessible.name: Tr.t("Copy %1 of %2").arg(win.formatName(modelData)).arg(row.modelData.name)
                                    KeyFocus { name: parent.Accessible.name; onActivated: win.copyPeer(row.modelData, modelData) }
                                }
                            }
                            Button {
                                text: Tr.t("QR")
                                enabled: row.modelData.handle !== ""
                                onClicked: win.showQr(row.modelData)
                                Accessible.name: Tr.t("Show QR for %1").arg(row.modelData.name)
                                KeyFocus { name: parent.Accessible.name; onActivated: win.showQr(row.modelData) }
                            }
                        }
                    }
                    KeyFocus { name: row.Accessible.name; onActivated: win.copyPeer(row.modelData, "handle") }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: win.peers.length === 0 && win.peerError === ""
                    icon: "network-workgroup"
                    title: Tr.t("No peers found")
                    subtitle: Tr.t("Devices on this network appear here once they are discovered")
                    actionText: Tr.t("Scan again")
                    onAction: { if (typeof Nearby !== "undefined" && Nearby) Nearby.scan(); win.refreshPeers(); }
                }
                Text {
                    anchors.centerIn: parent
                    visible: win.peers.length > 0 && win.matchingPeers(win.search).length === 0
                    text: Tr.t("No peers match that prefix")
                    color: Theme.dim
                    font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                }
            }

            // ---- recent peers ---------------------------------------------------
            SectionTitle {
                Layout.fillWidth: true
                text: Tr.t("Recent peers") + (win.recent.length ? " (" + win.recent.length + ")" : "")
            }
            Flow {
                Layout.fillWidth: true; spacing: Theme.px(6)
                visible: win.recent.length > 0
                Repeater {
                    model: win.recent
                    Button {
                        required property var modelData
                        text: modelData.name
                        flat: true
                        onClicked: win.copyPeer(modelData, "handle")
                        Accessible.name: Tr.t("Recent peer: ") + modelData.name
                        KeyFocus { name: parent.Accessible.name; onActivated: win.copyPeer(modelData, "handle") }
                    }
                }
            }

            // ---- VPN status -----------------------------------------------------
            SectionTitle { Layout.fillWidth: true; text: Tr.t("VPN connections") }
            Text {
                Layout.fillWidth: true
                visible: win.vpnNote !== ""
                text: win.vpnNote
                color: Theme.danger; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: win.vpnNote
            }
            ListView {
                id: vpnList_
                Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight, Theme.px(180))
                clip: true
                model: win.connections
                delegate: Rectangle {
                    required property var modelData
                    width: vpnList_.width; height: Theme.px(48); radius: Theme.radiusSmall
                    color: Theme.surface1
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + ", " + win.vpnStateText(modelData.state)
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(6) }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text
                                   elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                            Text { Layout.fillWidth: true; text: win.vpnStateText(modelData.state); color: Theme.dim
                                   font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                        }
                        Button {
                            text: modelData.state === "activated" ? Tr.t("Disconnect") : Tr.t("Connect")
                            enabled: !win.vpnBusy
                            onClicked: win.toggleVpn(modelData)
                            Accessible.name: (modelData.state === "activated" ? Tr.t("Disconnect from ") : Tr.t("Connect to ")) + modelData.name
                            KeyFocus { name: parent.Accessible.name; onActivated: win.toggleVpn(modelData) }
                        }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: win.connections.length === 0 && win.vpnNote === ""
                    icon: "network-vpn"
                    title: Tr.t("No VPN connections")
                    subtitle: Tr.t("NetworkManager VPN and WireGuard connections appear here")
                    actionText: Tr.t("Refresh")
                    onAction: win.refreshVpn()
                }
            }
            Button { Layout.alignment: Qt.AlignRight; text: Tr.t("Refresh"); enabled: !win.vpnBusy; onClicked: { win.refreshPeers(); win.refreshVpn(); } }

            Component.onCompleted: { win.refreshVpn(); if (typeof Nearby !== "undefined" && Nearby) Nearby.scan(); }
        }
    }
}
