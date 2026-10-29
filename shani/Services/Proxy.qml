pragma Singleton
// The proxy chosen in Settings > Network, applied whether or not the page was
// ever opened: GNOME's org.gnome.system.proxy (GTK, GIO, Firefox, Chromium) and
// http_proxy & co. in ~/.config/environment.d for terminal tools (next login).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var d: Settings.data
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
            root.d.proxyMode, root.d.proxyPac,
            root.hostPort(root.d.proxyHttp)[0], root.hostPort(root.d.proxyHttp)[1],
            root.hostPort(root.d.proxyHttps)[0], root.hostPort(root.d.proxyHttps)[1],
            root.hostPort(root.d.proxySocks)[0], root.hostPort(root.d.proxySocks)[1]]
        onCommandChanged: if (Settings.loaded) running = true
    }

}
