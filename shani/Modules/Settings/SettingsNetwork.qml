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
    spacing: Theme.px(12)
    property bool active: false
    readonly property var d: Settings.data
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property string conn: ""              // the active connection's UUID
    property string connName: ""
    property string dns: ""               // its own DNS servers ("" = from the network)
    property string dnsSearch: ""         // DNS search suffixes of this connection
    property string note: ""
    property bool noteOk: false           // success notes are informational, not an error
    property string resolvedNote: ""
    property bool resolvedNoteOk: false
    property bool resolvedBusy: false
    property bool btServiceEnabled: false
    property bool btServiceLoaded: false

    onActiveChanged: if (active) { readConn.running = true; readSaved(); readVpnAuto(); readCaps(); page.loadResolved(); btGet.running = false; btGet.running = true; }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) { readConn.running = true; readSaved(); readVpnAuto(); readCaps(); page.loadResolved(); btGet.running = false; btGet.running = true; }

    // ---- WWAN data cap (per SIM connection) ----------------------------------------
    // NetworkManager has no cap property, so the number is kept next to the
    // shell's settings; it is a reminder against the monthly usage read above.
    readonly property string capsFile: Settings.path.replace(/settings\.json$/, "wwan-caps.json")
    property var dataCaps: ({})              // connection UUID → GB per month
    function readCaps() { capsRead.running = true; }
    Process {
        id: capsRead
        command: ["sh", "-c", 'cat "$1" 2>/dev/null || echo "{}"', "sh", page.capsFile]
        stdout: StdioCollector {
            onStreamFinished: { try { const o = JSON.parse(text); page.dataCaps = (o && typeof o === "object" && !Array.isArray(o)) ? o : {}; } catch (e) { page.dataCaps = {}; } }
        }
    }
    function setCap(uuid, gb) {
        const o = Object.assign({}, page.dataCaps);
        const n = parseFloat(gb);
        if (isNaN(n) || n <= 0) delete o[uuid]; else o[uuid] = n;
        page.dataCaps = o;
        capsWrite.command = ["sh", "-c", 'mkdir -p "$1"; printf "%s" "$3" > "$2"', "sh",
            page.capsFile.substring(0, page.capsFile.lastIndexOf("/")), page.capsFile, JSON.stringify(o)];
        capsWrite.running = true;
    }
    Process { id: capsWrite }

    function _rkv(text, key) {
        const m = String(text || "").match(new RegExp("^\\s*" + key + "\\s*=\\s*(.*)$", "m"));
        return m ? m[1].trim() : "";
    }
    Process { id: resolvedRead; command: ["cat", "/etc/systemd/resolved.conf.d/50-shani-shell.conf"]; stdout: StdioCollector { onStreamFinished: { resolvedDnsField.text = page._rkv(text, "DNS"); resolvedFallbackField.text = page._rkv(text, "FallbackDNS"); resolvedDotField.text = page._rkv(text, "DNSOverTLS"); resolvedDnssecField.text = page._rkv(text, "DNSSEC"); } } }
    function loadResolved() { resolvedRead.running = false; resolvedRead.running = true; }
    Process {
        id: resolvedSaveProc; stdinEnabled: true; property string payload: ""
        stderr: StdioCollector { id: resolvedErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.resolvedBusy = false; page.resolvedNoteOk = code === 0; page.resolvedNote = code === 0 ? Tr.t("Resolved settings saved") : (resolvedErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) page.loadResolved(); }
    }
    function saveResolved() {
        const s = {};
        const add = (k, t) => { const v = t.text.trim(); if (v !== "") s[k] = v; };
        add("DNS", resolvedDnsField); add("FallbackDNS", resolvedFallbackField); add("DNSOverTLS", resolvedDotField); add("DNSSEC", resolvedDnssecField);
        page.resolvedBusy = true; page.resolvedNote = "";
        resolvedSaveProc.payload = JSON.stringify({ settings: s });
        resolvedSaveProc.command = page.adminCmd.concat(["resolved-set"]);
        resolvedSaveProc.running = true;
    }
    Process { id: btGet; command: page.adminCmd.concat(["bluetooth-get"]); stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); page.btServiceEnabled = !!d.enabled; page.btServiceLoaded = true; } catch(e) {} } } }
    Process { id: btSet; stdinEnabled: true; property string payload: ""; onStarted: { write(payload + "\n"); stdinEnabled = false; } onExited: code => { stdinEnabled = true; btGet.running = false; btGet.running = true; } }

    // ---- proxy (applied by the Proxy service) ----------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Data used"); visible: page.usage !== "" }
    Text {
        Layout.fillWidth: true
        visible: page.usage !== ""
        text: page.usage
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.px(13) * Theme.fontScale
    }

    Process {
        id: readConn
        command: ["sh", "-c", 'l=$(nmcli -t -f UUID,TYPE,NAME connection show --active 2>/dev/null | grep -E ":(802-11-wireless|802-3-ethernet):" | head -1)
            [ -n "$l" ] || exit 0; u=${l%%:*}; echo "$u"; echo "${l#*:*:}"; nmcli -g ipv4.dns connection show "$u"; echo "--"; nmcli -g ipv4.dns-search connection show "$u"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                const dash = l.indexOf("--");
                page.conn = l[0] || "";
                page.connName = l[1] || "";
                page.dns = (l.slice(2, dash < 0 ? undefined : dash).join("\n") || "").replace(/,/g, " ").trim();
                page.dnsSearch = (dash >= 0 ? l.slice(dash + 1).join("\n") : "").replace(/,/g, " ").trim();
            }
        }
    }
    Process {
        id: setDns
        stderr: StdioCollector { id: dnsErr }
        onExited: code => {
            if (code !== 0) {
                page.noteOk = false;
                page.note = dnsErr.text.trim().split("\n").pop() || Tr.t("not changed");
                readConn.running = true;
            } else
                dnsVerify.running = true;   // reconnect is not proof the new resolver works
        }
    }
    // one bounded lookup after applying, so a bad DNS address is not silent
    Process {
        id: dnsVerify
        command: ["sh", "-c", "sleep 1; timeout 5 getent hosts example.com >/dev/null 2>&1"]
        onExited: code => {
            page.noteOk = code === 0;
            page.note = code === 0 ? Tr.t("DNS applied — a test lookup worked")
                                   : Tr.t("DNS applied, but a test lookup failed — check the server addresses");
            readConn.running = true;
        }
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
    // DNS search domains: unqualified names are tried inside these suffixes
    // (NetworkManager's ipv4/ipv6.dns-search; "" clears them).
    function useDnsSearch(domains) {
        const v = String(domains || "").trim();
        setDns.command = ["sh", "-c", 'u="$1"; d="$2"; nmcli connection modify "$u" ipv4.dns-search "$d" ipv6.dns-search "$d" && nmcli connection up "$u" >/dev/null', "sh", conn, v];
        setDns.running = true;
    }
    property string usage: ""
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
                page.usage = text.trim() ? "Today " + Theme.bytes(day) + " · this month " + Theme.bytes(month) : "";
            }
        }
    }
    // ---- saved networks (Pantheon, Android): join on its own or not, and metered
    // - "limit background data", which NetworkManager tells apps (GNOME Software,
    // Flatpak and the updater hold back their downloads) - or forget it
    property var saved: []                // [{ uuid, name, type, auto, metered, zone }]
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
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$u" "$t" "$a" "$(nmcli -g connection.metered connection show "$u" 2>/dev/null)" "$(nmcli -g connection.zone connection show "$u" 2>/dev/null)" "$n" "$apn" "$home"; done']
        stdout: StdioCollector {
            onStreamFinished: page.saved = text.trim().split("\n").filter(x => x).map(l => {
                const f = l.split("\t");
                return { uuid: f[0], type: f[1], auto: f[2] === "yes", metered: f[3] === "yes", zone: (f[4] || "").toLowerCase(),
                         name: f.slice(5, -2).join("\t").replace(/\\:/g, ":"),
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
            // forgetting a network is not undoable: the password must be typed again
            RowLayout {
                Layout.fillWidth: true
                Icon { name: net.modelData.type === "802-11-wireless" ? "network-wireless" : net.modelData.type === "gsm" ? "network-cellular" : net.modelData.type === "bluetooth" ? "bluetooth-active" : "network-wired"; size: Theme.px(18); color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    text: net.modelData.name || net.modelData.type || net.modelData.uuid
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
                ConfirmButton {
                    id: forgetConfirm
                    implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                    implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    text: Tr.t("Forget")
                    armedText: Tr.t("Tap again to forget")
                    kind: forgetConfirm.armed ? "danger" : "plain"
                    interval: 4000
                    Accessible.name: text + " " + (net.modelData.name || net.modelData.type || net.modelData.uuid)
                    onConfirmed: page.modify(net.modelData.uuid, ["delete"])
                }
            }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Connect automatically")
                hint: Tr.t("Join this network when it is in range")
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
            // the firewall zone of this network (Ananta OS's "Shield", done by
            // NetworkManager and firewalld): every network is public - nothing
            // unsolicited comes in - unless marked as home, where your own
            // devices may find this computer and reach what it shares
            // (shani-settings' zones/home.xml). Takes effect at once.
            SwitchRow {
                Layout.fillWidth: true
                visible: net.modelData.type === "802-11-wireless" || net.modelData.type === "802-3-ethernet"
                text: Tr.t("Home network")
                hint: Tr.t("Your own devices here may find this computer and use what it shares. Leave off in cafés, offices and other places.")
                checked: net.modelData.zone === "home"
                onToggled: on => page.modify(net.modelData.uuid, ["connection.zone", on ? "home" : ""])
            }
            // mobile (SIM) connections: the operator's APN and roaming
            ColumnLayout {
                id: gsmSection
                property bool customApn: false
                visible: net.modelData.type === "gsm"
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("APN — tap one, or type your own"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
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
                        selected: gsmSection.customApn || ["", "internet", "jionet", "airtelgprs.com", "vi-internet"].indexOf(net.modelData.apn || "") < 0
                        onClicked: gsmSection.customApn = true
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    visible: gsmSection.customApn || ["", "internet", "jionet", "airtelgprs.com", "vi-internet"].indexOf(net.modelData.apn || "") < 0
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
            RowLayout {
                Layout.fillWidth: true
                visible: net.modelData.type === "gsm"
                spacing: Theme.px(6)
                Text { text: Tr.t("Monthly data cap (GB)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; Layout.preferredWidth: Theme.px(170) }
                TextField {
                    Layout.fillWidth: true
                    placeholder: page.dataCaps[net.modelData.uuid] ? String(page.dataCaps[net.modelData.uuid]) : Tr.t("No cap (Enter to keep, 0 to clear)")
                    onAccepted: { page.setCap(net.modelData.uuid, text.trim()); text = ""; }
                }
            }
        }
    }

    // ---- hotspot (toggled in the sidebar / bar; here: how it is called) -------
    SettingsSection {
        visible: Net.hasWifi
        title: Tr.t("Hotspot")
        hint: Tr.t("A Wi-Fi hotspot for other devices. Turn it on from the sidebar or the bar; the name and band are asked when it starts.")
        TextField {
        Layout.fillWidth: true
        visible: Net.hasWifi
        text: page.d.hotspotName
        placeholder: Tr.t("Hotspot name — tap a suggestion")
        onAccepted: page.d.hotspotName = text.trim()
    }
    // a label above the chips, not among them: a child as wide as its Flow makes the Flow re-lay out itself forever
    Text { Layout.fillWidth: true; visible: Net.hasWifi; text: Tr.t("Suggestions:"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        visible: Net.hasWifi
        spacing: Theme.px(6)
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
        spacing: Theme.px(6)
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
        font.pixelSize: Theme.px(12) * Theme.fontScale
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
        font.pixelSize: Theme.px(10) * Theme.fontScale
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
                Icon { name: "network-vpn"; size: Theme.px(18); color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    text: vpnRow.modelData.name + (vpnRow.modelData.active ? " · " + Tr.t("connected") : "")
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
                Button {
                    text: vpnRow.modelData.active ? Tr.t("Disconnect") : Tr.t("Connect")
                    onClicked: Net.setVpn(vpnRow.modelData.name, !vpnRow.modelData.active)
                }
            }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Connect automatically")
                hint: Tr.t("Start this VPN when the network it needs is available")
                checked: page.vpnAuto[vpnRow.modelData.name] === true
                onToggled: on => page.setVpnAuto(vpnRow.modelData.name, on)
            }
        }
    }

    // ---- privacy and power ------------------------------------------------------
    SettingsSection {
        title: Tr.t("Privacy & power")
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
    }

    // ---- bluetooth auto-connect -------------------------------------------------
    SettingsSection {
        visible: Bluetooth.defaultAdapter !== null
        title: Tr.t("Bluetooth")
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
    SwitchRow {
        Layout.fillWidth: true
        visible: Bluetooth.defaultAdapter !== null && page.btServiceLoaded
        text: Tr.t("Bluetooth service")
        hint: Tr.t("bluetooth.service enabled and running")
        checked: page.btServiceEnabled
        onToggled: on => { btSet.payload = JSON.stringify({ enabled: on }); btSet.command = page.adminCmd.concat(["bluetooth-set"]); btSet.running = true; }
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
    }

    Advanced {
        Layout.fillWidth: true
        hint: Tr.t("Proxy, DNS servers, connection details")
        SectionTitle { Layout.fillWidth: true; text: Tr.t("Proxy") }
        RowLayout {
            spacing: Theme.px(6)
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
            id: proxySection
            property bool customProxy: false
            visible: page.d.proxyMode === "manual"
            Layout.fillWidth: true
            spacing: Theme.px(12)
            Text { text: Tr.t("HTTP proxy (host:port)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice { text: Tr.t("Automatic (Tor)"); selected: page.d.proxyHttp === "127.0.0.1:9050"; onClicked: page.d.proxyHttp = "127.0.0.1:9050" }
                Choice { text: Tr.t("Corporate (ask IT)"); selected: page.d.proxyHttp === "proxy.company.local:8080"; onClicked: page.d.proxyHttp = "proxy.company.local:8080" }
                Choice { text: Tr.t("Other…"); selected: proxySection.customProxy || !["127.0.0.1:9050", "proxy.company.local:8080", ""].includes(page.d.proxyHttp || ""); onClicked: proxySection.customProxy = true }
            }
            TextField {
                Layout.fillWidth: true
                visible: proxySection.customProxy || !["127.0.0.1:9050", "proxy.company.local:8080", ""].includes(page.d.proxyHttp || "")
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
            spacing: Theme.px(6)
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
            font.pixelSize: Theme.px(12) * Theme.fontScale
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
            SettingRow {
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
            visible: page.conn !== ""
            text: Tr.t("Search domains: unqualified names are looked up inside these suffixes (e.g. home.arpa).")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
            wrapMode: Text.Wrap
        }
        TextField {
            Layout.fillWidth: true
            visible: page.conn !== ""
            placeholder: page.dnsSearch || Tr.t("Search domains, space separated (Enter to use)")
            text: page.dnsSearch
            onTextChanged: if (text !== page.dnsSearch) page.dnsSearch = text
            onAccepted: if (/^[\w.\-\s]+$/.test(text.trim())) { page.useDnsSearch(text.trim()); text = ""; }
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.note !== ""
            tone: page.noteOk ? "ok" : "error"
            text: page.note
        }
        SectionTitle { Layout.fillWidth: true; text: Tr.t("System DNS resolver (systemd-resolved)") }
        Text { Layout.fillWidth: true; text: Tr.t("Managed drop-in /etc/systemd/resolved.conf.d/50-shani-shell.conf. Restarted on save."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        GridLayout {
            Layout.fillWidth: true; columns: 2; columnSpacing: Theme.px(8); rowSpacing: Theme.px(6)
            Text { text: Tr.t("DNS"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: resolvedDnsField; Layout.fillWidth: true; placeholder: "1.1.1.1 9.9.9.9" }
            Text { text: Tr.t("Fallback DNS"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: resolvedFallbackField; Layout.fillWidth: true; placeholder: "1.0.0.1" }
            Text { text: Tr.t("DNS over TLS"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: resolvedDotField; Layout.fillWidth: true; placeholder: "no | yes | opportunistic" }
            Text { text: Tr.t("DNSSEC"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: resolvedDnssecField; Layout.fillWidth: true; placeholder: "no | yes | allow-downgrade" }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            InfoBanner {
                Layout.fillWidth: true
                visible: page.resolvedNote !== ""
                tone: page.resolvedNoteOk ? "ok" : "error"
                text: page.resolvedNote
            }
            Item { Layout.fillWidth: true; visible: page.resolvedNote === "" }
            Button { text: Tr.t("Reload"); enabled: !page.resolvedBusy; busy: page.resolvedBusy; onClicked: page.loadResolved() }
            Button { text: Tr.t("Save resolved"); kind: "primary"; enabled: !page.resolvedBusy; busy: page.resolvedBusy; onClicked: page.saveResolved() }
        }

        Button { text: Tr.t("Advanced connection settings…"); onClicked: { Ui.closeAll(); Net.editConnections(); } }
    }
}
