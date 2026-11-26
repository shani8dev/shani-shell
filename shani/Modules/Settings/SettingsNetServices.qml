// Settings > Network services: what is listening, announced, served or sent.
// Read-only from bridge/system_net.py; each section links to the page that
// owns the setting, so this page never becomes a second editor.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import "../../Common/ToolPath.js" as ToolPath

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_NET_TOOL"), "system_net.py")

    property string section: "inbound"
    property var netData: ({})
    property var errors: ({})
    property var shownRows: []
    property int pending: 0

    readonly property var sections: [
        { id: "inbound", title: Tr.t("Open ports"), hint: Tr.t("What can reach this computer from elsewhere"), cat: "firewall", open: Tr.t("Open the firewall settings") },
        { id: "avahi", title: Tr.t("Nearby discovery"), hint: Tr.t("What this computer announces and hears on the local network"), cat: "sharing", open: Tr.t("Open the sharing settings") },
        { id: "caddy", title: Tr.t("Sites served here"), hint: Tr.t("The sites this computer serves, and the file that describes them"), cat: "apps", open: Tr.t("Open the app settings") },
        { id: "cloudflared", title: Tr.t("Outgoing tunnels"), hint: Tr.t("Tunnels this computer uses to reach the wider network"), cat: "network", open: Tr.t("Open the network settings") },
        { id: "mail", title: Tr.t("Sending mail"), hint: Tr.t("How messages leave this computer"), cat: "apps", open: Tr.t("Open the app settings") }
    ]
    readonly property var current: (sections.find(s => s.id === page.section) || sections[0])

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function publish() {
        const d = page.netData;
        const i = d.inbound || {}, a = d.avahi || {}, c = d.caddy || {}, t = d.cloudflared || {}, m = d.mail || {};
        const o = Object.assign({}, Ui.systemState || {});
        o.netservices = {
            ports: Array.isArray(i.ports) ? i.ports : [], sshd: i.sshd || "",
            avahiActive: !!a.active, caddySites: Array.isArray(c.sites) ? c.sites : [],
            tunnels: Array.isArray(t.tunnels) ? t.tunnels : [], relay: m.relay || ""
        };
        Ui.systemState = o;
    }
    function load() {
        page.pending = 5;
        [pInbound, pAvahi, pCaddy, pCloud, pMail].forEach(p => { p.running = false; p.running = true; });
    }
    function done() { if (page.pending > 0) page.pending--; }
    function parsed(verb, text) {
        let r = {};
        try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("Could not read this section") }; }
        const d = Object.assign({}, page.netData); d[verb] = r; page.netData = d;
        const err = Object.assign({}, page.errors); err[verb] = r.error || ""; page.errors = err;
        page.rebuild();
    }
    function stateText(v) {
        if (typeof v === "boolean") return v ? Tr.t("On") : Tr.t("Off");
        const s = String(v || "").toLowerCase();
        if (s === "yes" || s === "active" || s === "running" || s === "on") return Tr.t("On");
        if (s === "no" || s === "inactive" || s === "stopped" || s === "off") return Tr.t("Off");
        return s || Tr.t("Not known");
    }
    function nameOf(x) {
        if (x === null || x === undefined) return "";
        if (typeof x === "object") return String(x.name || x.port || x.site || x.domain || x.id || x.value || "");
        return String(x);
    }
    function detailOf(x) {
        if (x === null || typeof x !== "object") return "";
        return String(x.reach || x.scope || x.address || x.addr || x.state || x.detail || x.host || x.process || "");
    }
    function rebuild() {
        const d = page.netData, rows = [];
        if (page.section === "inbound") {
            const i = d.inbound || {};
            for (const p of (Array.isArray(i.ports) ? i.ports : []))
                rows.push({ icon: "network-wired", title: page.nameOf(p) || Tr.t("Open port"), subtitle: page.detailOf(p) });
            rows.push({ icon: "system-users", title: Tr.t("Sign-in from elsewhere"), subtitle: Tr.t("Someone on another computer signing in here"), trailing: page.stateText(i.sshd) });
            rows.push({ icon: "network-workgroup", title: Tr.t("Passing messages on"), subtitle: Tr.t("This computer forwards traffic for others"), trailing: page.stateText(i.forwarding) });
        } else if (page.section === "avahi") {
            const a = d.avahi || {};
            rows.push({ icon: "network-wireless", title: Tr.t("Available"), subtitle: Tr.t("This computer finds others nearby"), trailing: page.stateText(a.active) });
            for (const s of (Array.isArray(a.services) ? a.services : []))
                rows.push({ icon: "network-wireless", title: page.nameOf(s) || Tr.t("Nearby service"), subtitle: page.detailOf(s) });
        } else if (page.section === "caddy") {
            const c = d.caddy || {};
            rows.push({ icon: "application-x-executable", title: Tr.t("Installed"), trailing: page.stateText(c.installed) });
            rows.push({ icon: "text-x-generic", title: Tr.t("Configuration file"), subtitle: c.file || "" });
            rows.push({ icon: "dialog-ok", title: Tr.t("Configuration check"), trailing: c.valid ? Tr.t("Valid") : Tr.t("Needs attention") });
            for (const s of (Array.isArray(c.sites) ? c.sites : []))
                rows.push({ icon: "web-browser", title: page.nameOf(s) || Tr.t("Site"), subtitle: page.detailOf(s) });
        } else if (page.section === "cloudflared") {
            const t = d.cloudflared || {};
            rows.push({ icon: "application-x-executable", title: Tr.t("Installed"), trailing: page.stateText(t.installed) });
            rows.push({ icon: "text-x-generic", title: Tr.t("Configuration file"), trailing: t.config ? Tr.t("Set") : Tr.t("Not set") });
            rows.push({ icon: "dialog-password", title: Tr.t("Credentials"), trailing: t.credentials ? Tr.t("Set") : Tr.t("Not set") });
            for (const s of (Array.isArray(t.tunnels) ? t.tunnels : []))
                rows.push({ icon: "network-server", title: page.nameOf(s) || Tr.t("Tunnel"), subtitle: page.detailOf(s) });
        } else if (page.section === "mail") {
            const m = d.mail || {};
            const relayText = m.relay === "smart host" ? Tr.t("Through a mail server")
                            : m.relay === "direct" ? Tr.t("Direct") : Tr.t("Not known");
            rows.push({ icon: "mail-send", title: Tr.t("Sending"), subtitle: m.detail || "", trailing: relayText });
            rows.push({ icon: "network-server", title: Tr.t("Mail server"), subtitle: m.host || "" });
        }
        page.shownRows = rows;
        page.publish();
    }

    Process {
        id: pInbound; command: ["python3", page.tool, "inbound"]
        stdout: StdioCollector { onStreamFinished: page.parsed("inbound", text) }
        onExited: page.done()
    }
    Process {
        id: pAvahi; command: ["python3", page.tool, "avahi"]
        stdout: StdioCollector { onStreamFinished: page.parsed("avahi", text) }
        onExited: page.done()
    }
    Process {
        id: pCaddy; command: ["python3", page.tool, "caddy"]
        stdout: StdioCollector { onStreamFinished: page.parsed("caddy", text) }
        onExited: page.done()
    }
    Process {
        id: pCloud; command: ["python3", page.tool, "cloudflared"]
        stdout: StdioCollector { onStreamFinished: page.parsed("cloudflared", text) }
        onExited: page.done()
    }
    Process {
        id: pMail; command: ["python3", page.tool, "mail"]
        stdout: StdioCollector { onStreamFinished: page.parsed("mail", text) }
        onExited: page.done()
    }

    Picks {
        label: Tr.t("Look at")
        options: sections.map(s => ({ label: s.title, value: s.id }))
        current: page.section
        onPicked: v => { page.section = v; page.rebuild(); }
    }
    BusyNote { Layout.fillWidth: true; visible: page.pending > 0; note: Tr.t("Loading…"); iconSize: Theme.px(16) }
    SettingsSection {
        Layout.fillWidth: true
        title: page.current.title
        hint: page.current.hint
        Repeater {
            model: page.shownRows
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: modelData.icon || "preferences-system"
                title: modelData.title
                subtitle: modelData.subtitle || ""
                trailing: modelData.trailing || ""
            }
        }
        EmptyState {
            visible: page.shownRows.length === 0 && page.pending === 0
            icon: "preferences-system"
            title: Tr.t("Nothing to show")
            subtitle: Tr.t("This part has no details on this computer.")
        }
        ListRow {
            Layout.fillWidth: true
            icon: "go-next"
            title: page.current.open
            subtitle: Tr.t("The setting is changed there; this page only reads it")
            trailing: Tr.t("Open")
            onClicked: Ui.openSettings(page.current.cat)
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: (page.errors[page.section] || "") !== ""
            tone: "error"
            text: page.errors[page.section] || ""
            accessibleRole: Accessible.AlertMessage
        }
    }
}
