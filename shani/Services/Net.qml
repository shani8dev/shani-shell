pragma Singleton
// Wi-Fi and wired state come from Quickshell's NetworkManager client. What it
// does not cover — airplane mode (rfkill), hotspot and VPN (nmcli) — follows
// their own event streams (`rfkill event`, `nmcli monitor`), never a poll loop.
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

Singleton {
    id: root

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired) || null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wiredConnected: wiredDevice !== null && wiredDevice.connected
    readonly property var networks: wifiDevice ? wifiDevice.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)) : []
    readonly property var activeWifi: networks.find(n => n.connected) || null
    readonly property real signal: activeWifi ? activeWifi.signalStrength : 0
    readonly property bool online: Networking.connectivity === NetworkConnectivity.Full

    property bool airplane: false
    property bool hotspotOn: false
    property string hotspotSsid: ""
    property var vpns: []           // [{ name, active }]
    readonly property bool vpnActive: vpns.some(v => v.active)
    readonly property bool hasWifi: wifiDevice !== null

    readonly property string icon: {
        if (airplane)
            return "airplane-mode";
        if (wiredConnected)
            return "network-wired";
        if (!wifiEnabled)
            return "network-wireless-disabled";
        if (!activeWifi)
            return "network-wireless-offline";
        const s = signal;
        return s > 0.75 ? "network-wireless-signal-excellent" : s > 0.5 ? "network-wireless-signal-good"
             : s > 0.25 ? "network-wireless-signal-ok" : "network-wireless-signal-weak";
    }
    readonly property string label: airplane ? "Airplane mode" : wiredConnected ? "Wired"
        : activeWifi ? activeWifi.name : (wifiEnabled ? "Not connected" : "Wi-Fi off")

    function setWifi(on) {
        Networking.wifiEnabled = on;
    }
    function scan(on) {
        if (wifiDevice)
            wifiDevice.scannerEnabled = on;
    }
    function setAirplane(on) {
        Quickshell.execDetached(["rfkill", on ? "block" : "unblock", "all"]);
    }
    function setHotspot(on) {
        if (on)
            Quickshell.execDetached(["nmcli", "device", "wifi", "hotspot", "ssid", (Quickshell.env("HOSTNAME") || "shani") + "-hotspot"]);
        else
            Quickshell.execDetached(["nmcli", "connection", "down", "Hotspot"]);
    }
    function setVpn(name, on) {
        Quickshell.execDetached(["nmcli", "connection", on ? "up" : "down", name]);
    }
    function editConnections() {
        Quickshell.execDetached(["nm-connection-editor"]);
    }

    function refresh() {
        rfkillList.running = true;
        nmList.running = true;
    }

    Process {
        id: rfkillList
        running: true
        command: ["rfkill", "-J", "-o", "TYPE,SOFT"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const devs = JSON.parse(text).rfkilldevices || [];
                    const radios = devs.filter(d => d.type === "wlan" || d.type === "bluetooth" || d.type === "wwan");
                    root.airplane = radios.length > 0 && radios.every(d => d.soft === "blocked");
                } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: ["rfkill", "event"]
        stdout: SplitParser { onRead: _ => rfkillDebounce.restart() }
    }
    Timer { id: rfkillDebounce; interval: 200; onTriggered: rfkillList.running = true }

    Process {
        id: nmList
        running: true
        command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = [];
                let hs = false, ssid = "";
                for (const line of text.trim().split("\n")) {
                    // nmcli -t escapes ':' inside fields as '\:'
                    const f = line.split(/(?<!\\):/).map(s => s.replace(/\\:/g, ":"));
                    if (f.length < 3)
                        continue;
                    if (f[1] === "vpn" || f[1] === "wireguard")
                        v.push({ name: f[0], active: f[2] === "yes" });
                    if (f[0] === "Hotspot" && f[2] === "yes") {
                        hs = true;
                        ssid = f[0];
                    }
                }
                root.vpns = v;
                root.hotspotOn = hs;
                root.hotspotSsid = ssid;
            }
        }
    }
    Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: _ => nmDebounce.restart() }
    }
    Timer { id: nmDebounce; interval: 300; onTriggered: nmList.running = true }
}
