// The VPN client panel: the NetworkManager connections bridge/vpn.py reports,
// with connect/disconnect, an autoconnect switch, profile import through the
// shell's own FilePicker, per-connection counters and a two-step delete. The
// Gateway window can embed this Item next to its peers; the service owns all
// process work, so this surface only renders state and asks for changes.
//
// A system-bus SecretAgent (automatic VPN credentials) is out of scope here.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Services

Item {
    id: panel
    property int statsIndex: 0
    property string pendingDelete: ""

    function stateText(state) {
        return state === "activated" ? Tr.t("Connected")
             : state === "activating" ? Tr.t("Connecting…")
             : state === "deactivating" ? Tr.t("Disconnecting…")
             : Tr.t("Disconnected");
    }
    function stateTone(state) {
        return state === "activated" ? "ok" : state === "activating" ? "warn" : "neutral";
    }
    function pad(n) { const s = String(n); return s.length < 2 ? "0" + s : s; }
    function humanBytes(n) {
        const v = Number(n) || 0;
        return v >= 1e9 ? (v / 1e9).toFixed(2) + " GB"
             : v >= 1e6 ? (v / 1e6).toFixed(1) + " MB"
             : v >= 1e3 ? (v / 1e3).toFixed(1) + " KB"
             : Math.round(v) + " B";
    }
    function duration(s) {
        const n = Number(s) || 0;
        const h = Math.floor(n / 3600), m = Math.floor((n % 3600) / 60);
        return h > 0 ? h + ":" + pad(m) + ":" + pad(n % 60) : m + ":" + pad(n % 60);
    }
    function statsLine(name) {
        const s = Vpn.stats[name];
        if (!s || !s.connected) return "";
        const parts = [Tr.t("↓ %1").arg(panel.humanBytes(s.rxBytes)),
                       Tr.t("↑ %1").arg(panel.humanBytes(s.txBytes)),
                       Tr.t("Up %1").arg(panel.duration(s.uptime))];
        if (s.peer) parts.push(Tr.t("Peer %1").arg(s.peer));
        return parts.join("  ·  ");
    }

    function importProfile() {
        FilePicker.open({ mode: "open", title: Tr.t("Import a VPN profile"),
            filters: ["ovpn", "conf"],
            onPicked: paths => { if (paths.length) Vpn.importFile(paths[0]); } });
    }
    function toggleVpn(c) {
        if (!c || !c.name) return;
        Vpn.toggle(c.name, c.state !== "activated");
    }
    function askDelete(name) {
        if (!name || Vpn.busy) return;
        panel.pendingDelete = name;
        deleteConfirm.open();
    }
    function setAutoconnect(name, on) { Vpn.setAutoconnect(name, on); }

    // one stats query per tick, rotated over the active connections; the
    // service's busy guard drops ticks that arrive before the last answer
    Timer {
        id: statsTick
        interval: 5000
        repeat: true
        running: panel.visible
        onTriggered: {
            const active = Vpn.connections.filter(c => c.state === "activated");
            if (!active.length) return;
            panel.statsIndex = (panel.statsIndex + 1) % active.length;
            Vpn.refreshStats(active[panel.statsIndex].name);
        }
    }
    onVisibleChanged: if (visible) { Vpn.refresh(); statsTick.trigger(); }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.px(10)

        RowLayout {
            Layout.fillWidth: true
            SectionTitle { Layout.fillWidth: true; text: Tr.t("VPN connections") }
            Button {
                text: Tr.t("Import profile")
                enabled: !Vpn.busy && Vpn.available
                onClicked: panel.importProfile()
                Accessible.name: Tr.t("Import a VPN profile")
                KeyFocus { name: parent.Accessible.name; onActivated: panel.importProfile() }
            }
            Button {
                text: Tr.t("Refresh")
                enabled: !Vpn.busy
                onClicked: Vpn.refresh()
                Accessible.name: Tr.t("Refresh VPN connections")
                KeyFocus { name: parent.Accessible.name; onActivated: Vpn.refresh() }
            }
        }

        InfoBanner {
            objectName: "vpn-error"
            Layout.fillWidth: true
            visible: Vpn.error !== ""
            tone: "error"
            iconName: "dialog-error"
            title: Tr.t("Could not load VPN connections")
            text: Vpn.error
        }
        InfoBanner {
            objectName: "vpn-note"
            Layout.fillWidth: true
            visible: Vpn.note !== "" && Vpn.error === ""
            tone: "accent"
            text: Vpn.note
        }

        ListView {
            id: connList
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            spacing: Theme.px(4)
            model: Vpn.connections
            delegate: Rectangle {
                id: row
                required property var modelData
                width: connList.width; height: Theme.px(100)
                radius: Theme.radiusSmall; color: Theme.surface1
                Accessible.role: Accessible.ListItem
                Accessible.name: row.modelData.name + ", " + (row.modelData.type || "vpn")
                    + ", " + panel.stateText(row.modelData.state)

                ColumnLayout {
                    anchors { fill: parent; margins: Theme.px(6) }
                    spacing: Theme.px(2)
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            color: Theme.text; elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale
                        }
                        StatusPill {
                            text: panel.stateText(row.modelData.state)
                            tone: panel.stateTone(row.modelData.state)
                        }
                    }
                    Text {
                        objectName: "vpn-detail"
                        Layout.fillWidth: true
                        text: row.modelData.type + " · "
                            + (row.modelData.autoconnect ? Tr.t("Autoconnect on") : Tr.t("Autoconnect off"))
                        color: Theme.dim; elide: Text.ElideRight
                        font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                    Text {
                        objectName: "vpn-stats"
                        Layout.fillWidth: true
                        visible: panel.statsLine(row.modelData.name) !== ""
                        text: panel.statsLine(row.modelData.name)
                        color: Theme.dim; elide: Text.ElideRight
                        font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale
                        Accessible.name: text
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.px(4)
                        Button {
                            text: row.modelData.state === "activated" ? Tr.t("Disconnect") : Tr.t("Connect")
                            enabled: !Vpn.busy
                            onClicked: panel.toggleVpn(row.modelData)
                            Accessible.name: (row.modelData.state === "activated" ? Tr.t("Disconnect from ") : Tr.t("Connect to ")) + row.modelData.name
                            KeyFocus { name: parent.Accessible.name; onActivated: panel.toggleVpn(row.modelData) }
                        }
                        SwitchRow {
                            Layout.fillWidth: true
                            text: Tr.t("Autoconnect")
                            checked: !!row.modelData.autoconnect
                            enabled: !Vpn.busy
                            onToggled: on => panel.setAutoconnect(row.modelData.name, on)
                        }
                        Button {
                            text: Tr.t("Delete")
                            enabled: !Vpn.busy
                            onClicked: panel.askDelete(row.modelData.name)
                            Accessible.name: Tr.t("Delete VPN connection %1").arg(row.modelData.name)
                            KeyFocus { name: parent.Accessible.name; onActivated: panel.askDelete(row.modelData.name) }
                        }
                    }
                }
            }
            EmptyState {
                objectName: "vpn-empty"
                anchors.centerIn: parent
                visible: !Vpn.available || (Vpn.probed && connList.count === 0 && Vpn.error === "")
                icon: "network-vpn"
                title: !Vpn.available ? Tr.t("VPN is unavailable")
                                      : Tr.t("No VPN connections")
                subtitle: !Vpn.available ? Tr.t("Install NetworkManager's nmcli to manage VPNs here")
                                         : Tr.t("Import an .ovpn or .conf profile, or add one in NetworkManager")
                actionText: !Vpn.available ? Tr.t("Try again") : Tr.t("Import profile")
                onAction: !Vpn.available ? Vpn.refresh() : panel.importProfile()
            }
        }

        Dialog {
            id: deleteConfirm
            anchors.centerIn: parent
            width: Math.min(panel.width * 0.8, Theme.px(400))
            title: Tr.t("Delete VPN connection?")
            modal: true
            standardButtons: Dialog.Cancel | Dialog.Ok
            onAccepted: { if (panel.pendingDelete) Vpn.remove(panel.pendingDelete); panel.pendingDelete = ""; }
            onRejected: panel.pendingDelete = ""
            contentItem: ColumnLayout {
                spacing: Theme.px(12)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Remove %1 from NetworkManager? The profile file stays on disk.")
                        .arg(panel.pendingDelete)
                    color: Theme.text; wrapMode: Text.Wrap
                    font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                }
            }
        }
    }
}
