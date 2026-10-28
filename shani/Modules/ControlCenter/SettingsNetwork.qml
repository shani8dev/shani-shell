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
    onActiveChanged: if (active) readConn.running = true

    // ---- proxy ------------------------------------------------------------------
    readonly property var hostPort: s => { const m = /^\s*([^\s:]+):(\d+)\s*$/.exec(s || ""); return m ? [m[1], m[2]] : ["", "0"]; }
    Process {
        id: proxy
        running: Settings.loaded
        command: ["sh", "-c", 'p=org.gnome.system.proxy; mode="$1"
            gsettings set $p mode "$mode"; gsettings set $p autoconfig-url "$2"
            set -- "$@"; gsettings set $p.http host "$3"; gsettings set $p.http port "$4"
            gsettings set $p.https host "$5"; gsettings set $p.https port "$6"
            gsettings set $p.socks host "$7"; gsettings set $p.socks port "$8"
            e="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/50-shani-proxy.conf"
            if [ "$mode" = manual ] && [ -n "$3" ]; then mkdir -p "${e%/*}"
                printf "http_proxy=http://%s:%s/\\nhttps_proxy=http://%s:%s/\\nHTTP_PROXY=http://%s:%s/\\nHTTPS_PROXY=http://%s:%s/\\nno_proxy=localhost,127.0.0.1,::1\\n" "$3" "$4" "${5:-$3}" "${6:-$4}" "$3" "$4" "${5:-$3}" "${6:-$4}" > "$e"
            else rm -f "$e"; fi', "sh",
            page.d.proxyMode, page.d.proxyPac,
            page.hostPort(page.d.proxyHttp)[0], page.hostPort(page.d.proxyHttp)[1],
            page.hostPort(page.d.proxyHttps)[0], page.hostPort(page.d.proxyHttps)[1],
            page.hostPort(page.d.proxySocks)[0], page.hostPort(page.d.proxySocks)[1]]
        onCommandChanged: if (Settings.loaded) running = true
    }

    SectionTitle { Layout.fillWidth: true; text: "Proxy" }
    RowLayout {
        spacing: 6
        Repeater {
            model: [{ label: "Off", value: "none" }, { label: "Manual", value: "manual" }, { label: "Automatic (PAC)", value: "auto" }]
            Choice {
                required property var modelData
                text: modelData.label
                selected: page.d.proxyMode === modelData.value
                onClicked: page.d.proxyMode = modelData.value
            }
        }
    }
    Repeater {
        model: page.d.proxyMode === "manual" ? [{ key: "proxyHttp", label: "HTTP proxy — host:port" }, { key: "proxyHttps", label: "HTTPS proxy — host:port (empty: the HTTP one)" }, { key: "proxySocks", label: "SOCKS proxy — host:port" }] : []
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

    SectionTitle { Layout.fillWidth: true; text: "DNS" }
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
            model: [{ label: "Automatic", value: "" }, { label: "Cloudflare", value: "1.1.1.1 1.0.0.1" }, { label: "Quad9", value: "9.9.9.9 149.112.112.112" }, { label: "Google", value: "8.8.8.8 8.8.4.4" }]
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
        placeholder: "Your own DNS servers — 192.168.1.1 9.9.9.9"
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
    Button { text: "Advanced connection settings…"; onClicked: { Ui.closeAll(); Net.editConnections(); } }
}
