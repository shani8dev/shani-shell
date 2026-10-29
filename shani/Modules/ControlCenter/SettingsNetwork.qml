// Settings > Network: the proxy (GNOME's org.gnome.system.proxy, which GTK,
// GIO, Firefox and Chromium read — and http_proxy & co. in
// ~/.config/environment.d for terminal tools, from the next login) and the
// DNS servers of the connection in use (NetworkManager, nmcli). Everything
// else about a connection: nm-connection-editor.
import Quickshell
import Quickshell.Io
import QtQuick
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
    onActiveChanged: if (active) { readConn.running = true; readSaved(); }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) { readConn.running = true; readSaved(); }

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
    function useDns(servers) {
        setDns.command = ["sh", "-c", 'u="$1"; s="$2"; if [ -n "$s" ]; then nmcli connection modify "$u" ipv4.dns "$s" ipv4.ignore-auto-dns yes
            else nmcli connection modify "$u" ipv4.dns "" ipv4.ignore-auto-dns no; fi && nmcli connection up "$u" >/dev/null', "sh", conn, servers];
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
                case "$t" in 802-11-wireless|802-3-ethernet|gsm) ;; *) continue;; esac
                printf "%s\t%s\t%s\t%s\t%s\n" "$u" "$t" "$a" "$(nmcli -g connection.metered connection show "$u" 2>/dev/null)" "$n"; done']
        stdout: StdioCollector {
            onStreamFinished: page.saved = text.trim().split("\n").filter(x => x).map(l => {
                const f = l.split("\t");
                return { uuid: f[0], type: f[1], auto: f[2] === "yes", metered: f[3] === "yes", name: f.slice(4).join("\t").replace(/\\:/g, ":") };
            })
        }
    }
    Process { id: modifySaved; onExited: page.readSaved() }
    function modify(uuid, args) {
        modifySaved.command = ["nmcli", "connection"].concat(args[0] === "delete" ? ["delete", uuid] : ["modify", uuid].concat(args));
        modifySaved.running = true;
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
                Icon { name: net.modelData.type === "802-11-wireless" ? "network-wireless" : net.modelData.type === "gsm" ? "network-cellular" : "network-wired"; size: 18; color: Theme.dim }
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
        Repeater {
            model: page.d.proxyMode === "manual" ? [{ key: "proxyHttp", label: Tr.t("HTTP proxy — host:port") }, { key: "proxyHttps", label: Tr.t("HTTPS proxy — host:port (empty: the HTTP one)") }, { key: "proxySocks", label: Tr.t("SOCKS proxy — host:port") }] : []
            TextField {
                required property var modelData
                Layout.fillWidth: true
                placeholder: page.d[modelData.key] || modelData.label
                onAccepted: { page.d[modelData.key] = text.trim(); text = ""; }
            }
        }
        TextField {
            Layout.fillWidth: true
            visible: page.d.proxyMode === "auto"
            placeholder: page.d.proxyPac || "Configuration URL — http://…/proxy.pac"
            onAccepted: { page.d.proxyPac = text.trim(); text = ""; }
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
        Flow {
            Layout.fillWidth: true
            visible: page.conn !== ""
            spacing: 6
            Repeater {
                model: [{ label: Tr.t("Automatic"), value: "" }, { label: Tr.t("Cloudflare"), value: "1.1.1.1 1.0.0.1" }, { label: Tr.t("Quad9"), value: "9.9.9.9 149.112.112.112" }, { label: Tr.t("Google"), value: "8.8.8.8 8.8.4.4" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.dns === modelData.value
                    onClicked: page.useDns(modelData.value)
                }
            }
        }
        TextField {
            Layout.fillWidth: true
            visible: page.conn !== ""
            placeholder: Tr.t("Your own DNS servers — 192.168.1.1 9.9.9.9")
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
