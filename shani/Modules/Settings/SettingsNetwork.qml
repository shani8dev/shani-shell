// Settings > Network: the proxy (GNOME's org.gnome.system.proxy, which GTK,
// GIO, Firefox and Chromium read — and http_proxy & co. in
// ~/.config/environment.d for terminal tools, from the next login) and the
// DNS servers of the connection in use (NetworkManager, nmcli). Everything
// else about a connection: nm-connection-editor.
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data
    property string conn: ""              // the active connection's UUID
    property string connName: ""
    property string dns: ""               // its own DNS servers ("" = from the network)
    property string note: ""

    onActiveChanged: if (active) { readConn.running = true; readSaved(); readVpnAuto(); }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) { readConn.running = true; readSaved(); readVpnAuto(); }

    // ---- proxy (applied by the Proxy service) ----------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Data used"); visible: page.usage !== "" }
    Text {
        Layout.fillWidth: true
        visible: page.usage !== ""
        text: page.usage
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 13 * Theme.fontScale
    }

    Process {
        id: readConn
        command: ["sh", "-c", 'l=$(nmcli -t -f UUID,TYPE,NAME connection show --active 2>/dev/null | grep -E ":(802-11-wireless|802-3-ethernet):" | head -1)
            [ -n "$l" ] || exit 0; u=${l%%:*}; echo "$u"; echo "${l#*:*:}"; nmcli -g ipv4.dns connection show "$u"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                page.conn = l[0] || "";
                page.connName = l[1] || "";
                page.dns = (l[2] || "").replace(/,/g, " ").trim();
            }
        }
    }
    Process {
        id: setDns
        stderr: StdioCollector { id: dnsErr }
        onExited: code => { page.note = code === 0 ? "" : (dnsErr.text.trim().split("\n").pop() || "not changed"); readConn.running = true; }
    }
    // servers: IPv4 and IPv6 addresses, space between ("" = the network's own). Both
    // families are set, so a network with IPv6 does not ask its own DNS around it.
    function useDns(servers) {
        const all = String(servers || "").trim().split(/\s+/).filter(x => x);
        const v4 = all.filter(x => x.indexOf(":") < 0).join(" "), v6 = all.filter(x => x.indexOf(":") >= 0).join(" ");
        setDns.command = ["sh", "-c", 'u="$1"; a="$2"; b="$3"
            if [ -n "$a$b" ]; then nmcli connection modify "$u" ipv4.dns "$a" ipv4.ignore-auto-dns yes ipv6.dns "$b" ipv6.ignore-auto-dns yes
            else nmcli connection modify "$u" ipv4.dns "" ipv4.ignore-auto-dns no ipv6.dns "" ipv6.ignore-auto-dns no; fi && nmcli connection up "$u" >/dev/null', "sh", conn, v4, v6];
        setDns.running = true;
    }
    property string usage: ""
    function bytes(n) { return n >= 1e9 ? (n / 1e9).toFixed(1) + " GB" : n >= 1e6 ? Math.round(n / 1e6) + " MB" : Math.round(n / 1e3) + " kB"; }
    Process {
        running: page.active
        // --oneline b: version;iface;day;rx;tx;total;rate;month;rx;tx;total;rate;… (bytes)
        command: ["sh", "-c", 'command -v vnstat >/dev/null || exit 0; for i in $(vnstat --iflist 1 2>/dev/null); do vnstat --oneline b -i "$i" 2>/dev/null; done']
        stdout: StdioCollector {
            onStreamFinished: {
                let day = 0, month = 0;
                for (const l of text.trim().split("\n")) {
                    const f = l.split(";");
                    if (f.length > 10 && !/^(lo|veth|docker|br-|virbr|tun|tap)/.test(f[1])) {
                        day += parseFloat(f[5]) || 0;
                        month += parseFloat(f[10]) || 0;
                    }
                }
                page.usage = text.trim() ? "Today " + page.bytes(day) + " · this month " + page.bytes(month) : "";
            }
        }
    }
    // ---- saved networks (Pantheon, Android): join on its own or not, and metered
    // - "limit background data", which NetworkManager tells apps (GNOME Software,
    // Flatpak and the updater hold back their downloads) - or forget it
    property var saved: []                // [{ uuid, name, type, auto, metered }]
    function readSaved() { if (!listSaved.running) listSaved.running = true; }
    Process {
        id: listSaved
        command: ["sh", "-c", 'nmcli -t -f UUID,TYPE,AUTOCONNECT,NAME connection show 2>/dev/null | while IFS= read -r l; do
                u=${l%%:*}; r=${l#*:}; t=${r%%:*}; r=${r#*:}; a=${r%%:*}; n=${r#*:}
                case "$t" in 802-11-wireless|802-3-ethernet|gsm|bluetooth) ;; *) continue;; esac
                apn=""; home=""
                if [ "$t" = gsm ]; then
                    apn=$(nmcli -g gsm.apn connection show "$u" 2>/dev/null)
                    home=$(nmcli -g gsm.home-only connection show "$u" 2>/dev/null)
                fi
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$u" "$t" "$a" "$(nmcli -g connection.metered connection show "$u" 2>/dev/null)" "$n" "$apn" "$home"; done']
        stdout: StdioCollector {
            onStreamFinished: page.saved = text.trim().split("\n").filter(x => x).map(l => {
                const f = l.split("\t");
                return { uuid: f[0], type: f[1], auto: f[2] === "yes", metered: f[3] === "yes", name: f.slice(4, -2).join("\t").replace(/\\:/g, ":"),
                         apn: f[f.length - 2] || "", homeOnly: f[f.length - 1] || "" };
            })
        }
    }
    Process { id: modifySaved; onExited: page.readSaved() }
    property var vpnAuto: ({})
    function readVpnAuto() { if (!vpnAutoProc.running) vpnAutoProc.running = true; }
    Process {
        id: vpnAutoProc
        command: ["sh", "-c", 'nmcli -t -f NAME,TYPE,AUTOCONNECT connection show 2>/dev/null | while IFS= read -r l; do n=${l%%:*}; r=${l#*:}; t=${r%%:*}; a=${r#*:}; case "$t" in vpn|wireguard) printf "%s\\t%s\\n" "$n" "$a";; esac; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of text.trim().split("\n")) {
                    if (!line) continue;
                    const f = line.split("\t");
                    m[f[0]] = f[1] === "yes";
                }
                page.vpnAuto = m;
            }
        }
    }
    function setVpnAuto(name, on) {
        Quickshell.execDetached(["nmcli", "connection", "modify", name, "connection.autoconnect", on ? "yes" : "no"]);
        readVpnAuto();
    }
    function modify(uuid, args) {
        modifySaved.command = ["nmcli", "connection"].concat(args[0] === "delete" ? ["delete", uuid] : ["modify", uuid].concat(args));
        modifySaved.running = true;
    }
    EmptyState {
        Layout.fillWidth: true
        visible: page.saved.length === 0
        icon: "network-wireless"
        title: Tr.t("No saved networks yet")
        subtitle: Tr.t("Connect to a Wi-Fi network or plug in a cable; it will appear here.")
    }
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Saved networks"); visible: page.saved.length > 0 }
    Repeater {
        model: page.saved
        ColumnLayout {
            id: net
            required property var modelData
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Icon { name: net.modelData.type === "802-11-wireless" ? "network-wireless" : net.modelData.type === "gsm" ? "network-cellular" : net.modelData.type === "bluetooth" ? "bluetooth-active" : "network-wired"; size: 18; color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    text: net.modelData.name
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
                Button { text: Tr.t("Forget"); onClicked: page.modify(net.modelData.uuid, ["delete"]) }
            }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Connect automatically")
                checked: net.modelData.auto
                onToggled: on => page.modify(net.modelData.uuid, ["connection.autoconnect", on ? "yes" : "no"])
            }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Limit background data")
                hint: Tr.t("A metered connection: apps and updates hold back large downloads")
                checked: net.modelData.metered
                onToggled: on => page.modify(net.modelData.uuid, ["connection.metered", on ? "yes" : "unknown"])
            }
            // mobile (SIM) connections: the operator's APN and roaming
            ColumnLayout {
                visible: net.modelData.type === "gsm"
                Layout.fillWidth: true
                spacing: 6
                Text { text: Tr.t("APN — tap one, or type your own"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Choice {
                        text: Tr.t("Automatic (operator)")
                        selected: (net.modelData.apn || "") === ""
                        onClicked: page.modify(net.modelData.uuid, ["gsm.apn", ""])
                    }
                    Choice {
                        text: "internet"
                        selected: net.modelData.apn === "internet"
                        onClicked: page.modify(net.modelData.uuid, ["gsm.apn", "internet"])
                    }
                    Choice {
                        text: "JioNet"
                        selected: net.modelData.apn === "jionet"
                        onClicked: page.modify(net.modelData.uuid, ["gsm.apn", "jionet"])
                    }
                    Choice {
                        text: "airtelgprs.com"
                        selected: net.modelData.apn === "airtelgprs.com"
                        onClicked: page.modify(net.modelData.uuid, ["gsm.apn", "airtelgprs.com"])
                    }
                    Choice {
                        text: "vi-internet"
                        selected: net.modelData.apn === "vi-internet"
                        onClicked: page.modify(net.modelData.uuid, ["gsm.apn", "vi-internet"])
                    }
                    Choice {
                        text: Tr.t("Other…")
                        selected: ["", "internet", "jionet", "airtelgprs.com", "vi-internet"].indexOf(net.modelData.apn || "") < 0
                        onClicked: { }
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    visible: ["", "internet", "jionet", "airtelgprs.com", "vi-internet"].indexOf(net.modelData.apn || "") < 0
                    text: net.modelData.apn
                    placeholder: Tr.t("Type your APN")
                    onAccepted: page.modify(net.modelData.uuid, ["gsm.apn", text.trim()])
                }
            }
            SwitchRow {
                Layout.fillWidth: true
                visible: net.modelData.type === "gsm"
                text: Tr.t("Use data only in the home network")
                hint: Tr.t("no mobile data while roaming")
                checked: net.modelData.homeOnly === "yes"
                onToggled: on => page.modify(net.modelData.uuid, ["gsm.home-only", on ? "yes" : "no"])
            }
        }
    }

    // ---- hotspot (toggled in the sidebar / bar; here: how it is called) -------
    SectionTitle { Layout.fillWidth: true; visible: Net.hasWifi; text: Tr.t("Hotspot") }
    Text {
        Layout.fillWidth: true
        visible: Net.hasWifi
        text: Tr.t("A Wi-Fi hotspot for other devices. Turn it on from the sidebar or the bar; the name and band are asked when it starts.")
        wrapMode: Text.Wrap
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    TextField {
        Layout.fillWidth: true
        visible: Net.hasWifi
        text: page.d.hotspotName
        placeholder: Tr.t("Hotspot name — tap a suggestion")
        onAccepted: page.d.hotspotName = text.trim()
    }
    // a label above the chips, not among them: a child as wide as its Flow makes the Flow re-lay out itself forever
    Text { Layout.fillWidth: true; visible: Net.hasWifi; text: Tr.t("Suggestions:"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        visible: Net.hasWifi
        spacing: 6
        Choice {
            text: (Quickshell.env("HOSTNAME") || "shani") + "-hotspot"
            selected: page.d.hotspotName === (Quickshell.env("HOSTNAME") || "shani") + "-hotspot"
            onClicked: page.d.hotspotName = (Quickshell.env("HOSTNAME") || "shani") + "-hotspot"
        }
        Choice {
            text: Tr.t("My phone")
            selected: page.d.hotspotName === Tr.t("My phone")
            onClicked: page.d.hotspotName = Tr.t("My phone")
        }
        Choice {
            text: Tr.t("Guest Wi-Fi")
            selected: page.d.hotspotName === Tr.t("Guest Wi-Fi")
            onClicked: page.d.hotspotName = Tr.t("Guest Wi-Fi")
        }
        Choice {
            text: Tr.t("Work")
            selected: page.d.hotspotName === Tr.t("Work")
            onClicked: page.d.hotspotName = Tr.t("Work")
        }
    }
    Flow {
        Layout.fillWidth: true
        visible: Net.hasWifi
        spacing: 6
        Repeater {
            model: [{ id: "auto", label: Tr.t("Automatic band") }, { id: "bg", label: "2.4 GHz" }, { id: "a", label: "5 GHz" }]
            Choice {
                required property var modelData
                text: modelData.label
                selected: page.d.hotspotBand === modelData.id
                onClicked: page.d.hotspotBand = modelData.id
            }
        }
    }

    // ---- mobile data (a SIM modem, when there is one) -------------------------
    SectionTitle { Layout.fillWidth: true; visible: Net.hasModem; text: Tr.t("Mobile data") }
    Text {
        Layout.fillWidth: true
        visible: Net.hasModem
        text: Modem.modem ? (Modem.modem.operator || "Operator") + " · " + (Modem.modem.signal || 0) + "%" + (Modem.modem.state ? " · " + Modem.modem.state : "")
            : Tr.t("No modem found")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    SwitchRow {
        Layout.fillWidth: true
        visible: Net.hasModem
        text: Tr.t("Mobile data on")
        hint: Tr.t("the modem's WWAN radio")
        checked: Net.wwanOn
        onToggled: on => Net.setMobile(on)
    }
    Text {
        Layout.fillWidth: true
        visible: Net.hasModem
        text: Tr.t("APN and roaming are set per connection in the saved list above.")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10 * Theme.fontScale
    }

    // ---- VPN -------------------------------------------------------------------
    SectionTitle { Layout.fillWidth: true; visible: Net.vpns.length > 0; text: Tr.t("VPN") }
    Repeater {
        model: Net.vpns
        ColumnLayout {
            id: vpnRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Icon { name: "network-vpn"; size: 18; color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    text: vpnRow.modelData.name + (vpnRow.modelData.active ? " · " + Tr.t("connected") : "")
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
                Button {
                    text: vpnRow.modelData.active ? Tr.t("Disconnect") : Tr.t("Connect")
                    onClicked: Net.setVpn(vpnRow.modelData.name, !vpnRow.modelData.active)
                }
            }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Connect automatically")
                checked: page.vpnAuto[vpnRow.modelData.name] === true
                onToggled: on => page.setVpnAuto(vpnRow.modelData.name, on)
            }
        }
    }

    // ---- privacy and power ------------------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Privacy & power") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Random MAC addresses on Wi-Fi")
        hint: Tr.t("a different address for each saved network — harder to follow you between places")
        checked: page.d.wifiMacRandom
        onToggled: on => { page.d.wifiMacRandom = on; Net.setMacRandom(on); }
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Wake on LAN")
        hint: Tr.t("a network packet can wake a wired computer from sleep (magic packet)")
        checked: page.d.wakeOnLan
        onToggled: on => { page.d.wakeOnLan = on; Net.setWakeOnLan(on); }
    }

    // ---- bluetooth auto-connect -------------------------------------------------
    SectionTitle { Layout.fillWidth: true; visible: Bluetooth.defaultAdapter !== null; text: Tr.t("Bluetooth") }
    SwitchRow {
        Layout.fillWidth: true
        visible: Bluetooth.defaultAdapter !== null
        text: Tr.t("Connect devices automatically")
        hint: Tr.t("headphones and keyboards reconnect on their own when they come back in range")
        checked: page.d.bluetoothAutoConnect
        onToggled: on => page.d.bluetoothAutoConnect = on
    }
    SwitchRow {
        Layout.fillWidth: true
        visible: Bluetooth.defaultAdapter !== null
        text: Tr.t("Bluetooth at sign-in")
        hint: Tr.t("the adapter powers on when you log in")
        checked: page.d.bluetoothOnBoot
        onToggled: on => page.d.bluetoothOnBoot = on
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: Bluetooth.defaultAdapter !== null
        spacing: 2
        FolderPicker {
            label: Tr.t("Files from Bluetooth go to")
            placeholder: Tr.t("Downloads (default)")
            value: page.d.obexDir
            onPicked: p => page.d.obexDir = p
        }
    }

    Advanced {
        Layout.fillWidth: true
        hint: Tr.t("Proxy, DNS servers, connection details")
        SectionTitle { Layout.fillWidth: true; text: Tr.t("Proxy") }
        RowLayout {
            spacing: 6
            Repeater {
                model: [{ label: Tr.t("Off"), value: "none" }, { label: Tr.t("Manual"), value: "manual" }, { label: Tr.t("Automatic (PAC)"), value: "auto" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.d.proxyMode === modelData.value
                    onClicked: page.d.proxyMode = modelData.value
                }
            }
        }
        ColumnLayout {
            visible: page.d.proxyMode === "manual"
            Layout.fillWidth: true
            spacing: 12
            Text { text: Tr.t("HTTP proxy (host:port)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Choice { text: Tr.t("Automatic (Tor)"); selected: page.d.proxyHttp === "127.0.0.1:9050"; onClicked: page.d.proxyHttp = "127.0.0.1:9050" }
                Choice { text: Tr.t("Corporate (ask IT)"); selected: page.d.proxyHttp === "proxy.company.local:8080"; onClicked: page.d.proxyHttp = "proxy.company.local:8080" }
                Choice { text: Tr.t("Other…"); selected: !["127.0.0.1:9050", "proxy.company.local:8080", ""].includes(page.d.proxyHttp || ""); onClicked: {} }
            }
            TextField {
                Layout.fillWidth: true
                visible: !["127.0.0.1:9050", "proxy.company.local:8080", ""].includes(page.d.proxyHttp || "")
                placeholder: page.d.proxyHttp || "host:port — e.g. proxy.example.com:8080"
                onAccepted: { page.d.proxyHttp = text.trim(); text = ""; }
            }
            Text { text: Tr.t("HTTPS proxy (empty: use the HTTP one)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
            TextField {
                Layout.fillWidth: true
                placeholder: page.d.proxyHttps || "host:port"
                onAccepted: { page.d.proxyHttps = text.trim(); text = ""; }
            }
            Text { text: Tr.t("SOCKS proxy (host:port)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
            TextField {
                Layout.fillWidth: true
                placeholder: page.d.proxySocks || "host:port"
                onAccepted: { page.d.proxySocks = text.trim(); text = ""; }
            }
        }
        ColumnLayout {
            visible: page.d.proxyMode === "auto"
            Layout.fillWidth: true
            spacing: 6
            Text { text: Tr.t("Configuration URL"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
            TextField {
                Layout.fillWidth: true
                placeholder: page.d.proxyPac || "http://…/proxy.pac"
                onAccepted: { page.d.proxyPac = text.trim(); text = ""; }
            }
        }

        // ---- DNS of the connection in use ----------------------------------------------

        // ---- data used (vnstat, which shani-tools-network runs) --------------------
        SectionTitle { Layout.fillWidth: true; text: Tr.t("DNS") }
        Text {
            Layout.fillWidth: true
            text: page.conn ? "For " + page.connName + ": " + (page.dns || "from the network") : "Not connected."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
        }
        // what each does, in a line: picked with a tap, the servers behind it shown small
        Repeater {
            model: page.conn === "" ? [] : [
                { label: Tr.t("Automatic"), hint: Tr.t("From your network - the router or your provider"), value: "" },
                { label: Tr.t("Fast"), hint: Tr.t("Cloudflare - quick, and does not keep a record of where you go"), value: "1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001" },
                { label: Tr.t("Blocks harmful sites"), hint: Tr.t("Quad9 - known malware and phishing sites do not open"), value: "9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9" },
                { label: Tr.t("Blocks ads"), hint: Tr.t("AdGuard - ads and trackers stopped for every app, not only the browser"), value: "94.140.14.14 94.140.15.15 2a10:50c0::ad1:ff 2a10:50c0::ad2:ff" },
                { label: Tr.t("Safe for family"), hint: Tr.t("Cloudflare for Families - adult sites and malware blocked"), value: "1.1.1.3 1.0.0.3 2606:4700:4700::1113 2606:4700:4700::1003" },
                { label: Tr.t("Google"), hint: Tr.t("Google Public DNS"), value: "8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844" }]
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: modelData.value === "" ? "network-workgroup" : "network-server"
                title: modelData.label
                subtitle: modelData.hint
                // the IPv4 part is what nmcli reports back for the connection
                selected: page.dns === modelData.value.split(" ").filter(x => x.indexOf(":") < 0).join(" ")
                onClicked: page.useDns(modelData.value)
            }
        }
        TextField {
            Layout.fillWidth: true
            visible: page.conn !== ""
            placeholder: Tr.t("Or your own servers - e.g. 192.168.1.1 (Enter to use)")
            onAccepted: if (/^[\d.:a-fA-F\s]+$/.test(text.trim())) { page.useDns(text.trim()); text = ""; }
        }
        Text {
            Layout.fillWidth: true
            visible: page.note !== ""
            text: page.note
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 11 * Theme.fontScale
        }
        Button { text: Tr.t("Advanced connection settings…"); onClicked: { Ui.closeAll(); Net.editConnections(); } }
    }
}
