pragma Singleton
// The proxy chosen in Settings > Network, applied whether or not the page was
// ever opened: GNOME's org.gnome.system.proxy (GTK, GIO, Firefox, Chromium) and
// http_proxy & co. in ~/.config/environment.d for terminal tools (next login).
// Values travel in the child's environment, never in argv: `ps` sees no host,
// PAC URL or credential, and any future auth field joins the same map.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var d: Settings.data

    // Plain hostname/IP + a real port. Userinfo ("user:pass@host"), schemes,
    // shell metacharacters and out-of-range ports are rejected, so nothing
    // that looks like a credential can reach gsettings or the environment file.
    function hostPort(s) {
        const m = /^\s*([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:.]+\]):([0-9]{1,5})\s*$/.exec(s || "");
        if (!m) return ["", "0"];
        const port = Number(m[2]);
        return port >= 1 && port <= 65535 ? [m[1], m[2]] : ["", "0"];
    }

    // Only the two modes gsettings understands. "system" (or any stray value)
    // means "don't override the system" — the same as Off.
    function effectiveMode() {
        const m = String(root.d.proxyMode || "");
        return m === "manual" || m === "auto" ? m : "none";
    }

    // A PAC URL is executable code: accept only fetchable schemes, never e.g.
    // javascript: or a bare string the user typed by mistake.
    function effectivePac() {
        const u = String(root.d.proxyPac || "").trim();
        return /^(https?|file):\/\//i.test(u) ? u : "";
    }

    readonly property var httpTarget: root.hostPort(root.d.proxyHttp)
    readonly property var httpsTarget: root.hostPort(root.d.proxyHttps)
    readonly property var socksTarget: root.hostPort(root.d.proxySocks)

    readonly property var proxyEnv: ({
        SH_PROXY_MODE: root.effectiveMode(),
        SH_PROXY_PAC: root.effectivePac(),
        SH_PROXY_HTTP_HOST: root.httpTarget[0],
        SH_PROXY_HTTP_PORT: root.httpTarget[1],
        SH_PROXY_HTTPS_HOST: root.httpsTarget[1] !== "0" ? root.httpsTarget[0] : root.httpTarget[0],
        SH_PROXY_HTTPS_PORT: root.httpsTarget[1] !== "0" ? root.httpsTarget[1] : root.httpTarget[1],
        SH_PROXY_SOCKS_HOST: root.socksTarget[0],
        SH_PROXY_SOCKS_PORT: root.socksTarget[1]
    })

    // A var binding emits a fresh object on any setting change; re-run so the
    // new proxy applies immediately instead of waiting for the next login.
    onProxyEnvChanged: if (Settings.loaded) proxy.running = true

    Process {
        id: proxy
        running: Settings.loaded
        command: ["sh", "-c", 'p=org.gnome.system.proxy
            e="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/50-shani-proxy.conf"
            mode="$SH_PROXY_MODE"
            gsettings set $p mode "$mode"
            if [ "$mode" = auto ] && [ -n "$SH_PROXY_PAC" ]; then
                gsettings set $p autoconfig-url "$SH_PROXY_PAC"
            else
                gsettings set $p autoconfig-url ""
            fi
            if [ "$mode" = manual ]; then
                gsettings set $p.http host "$SH_PROXY_HTTP_HOST"; gsettings set $p.http port "$SH_PROXY_HTTP_PORT"
                gsettings set $p.https host "$SH_PROXY_HTTPS_HOST"; gsettings set $p.https port "$SH_PROXY_HTTPS_PORT"
                gsettings set $p.socks host "$SH_PROXY_SOCKS_HOST"; gsettings set $p.socks port "$SH_PROXY_SOCKS_PORT"
                if [ -n "$SH_PROXY_HTTP_HOST" ]; then
                    mkdir -p "${e%/*}"
                    umask 077
                    printf "http_proxy=http://%s:%s/\\nhttps_proxy=http://%s:%s/\\nHTTP_PROXY=http://%s:%s/\\nHTTPS_PROXY=http://%s:%s/\\nno_proxy=localhost,127.0.0.1,::1\\n" \\
                        "$SH_PROXY_HTTP_HOST" "$SH_PROXY_HTTP_PORT" \\
                        "$SH_PROXY_HTTPS_HOST" "$SH_PROXY_HTTPS_PORT" \\
                        "$SH_PROXY_HTTP_HOST" "$SH_PROXY_HTTP_PORT" \\
                        "$SH_PROXY_HTTPS_HOST" "$SH_PROXY_HTTPS_PORT" > "$e"
                    chmod 600 "$e"
                else
                    rm -f "$e"
                fi
            else
                for k in http https socks; do gsettings set $p.$k host ""; gsettings set $p.$k port 0; done
                rm -f "$e"
            fi']
        environment: root.proxyEnv
    }
}
