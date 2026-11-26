// Settings > Access and sign-in: a short read of how this computer finds
// accounts, signs people in and grants rights. It never edits a file — sudo
// rules and password policy are edited in Security, keys stay where they are.
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

    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_ACCESS_TOOL"), "system_access.py")
    property string topic: "directory"
    property var topics: [
        { v: "directory", label: Tr.t("Directory") },
        { v: "signin", label: Tr.t("Sign-in methods") },
        { v: "auth", label: Tr.t("Authorisation") },
        { v: "remote", label: Tr.t("Remote login") },
        { v: "keys", label: Tr.t("Keys and codes") },
        { v: "kernel", label: Tr.t("Kernel security") }
    ]
    property var verbs: ["directory", "kerberos", "smartcard", "privileges", "sudoers", "sshd", "lsm", "sshkeys", "totp"]
    property var topicVerbs: ({
        directory: ["directory", "kerberos"], signin: ["smartcard"],
        auth: ["privileges", "sudoers"], remote: ["sshd"],
        keys: ["sshkeys", "totp"], kernel: ["lsm"]
    })
    property var results: ({})
    property int i: -1
    property bool busy: false

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function load() { page.i = -1; page.results = ({}); page.next(); }
    function next() {
        page.i++;
        if (page.i >= page.verbs.length) { page.busy = false; page.publish(); return; }
        page.busy = true;
        reader.verb = page.verbs[page.i];
        reader.command = ["python3", page.tool, reader.verb];
        reader.running = false;
        reader.running = true;
    }
    function yn(x) { return x ? Tr.t("yes") : Tr.t("no"); }
    function labelFor(v) {
        for (let j = 0; j < page.topics.length; j++)
            if (page.topics[j].v === v) return page.topics[j].label;
        return "";
    }
    function errorForTopic() {
        let s = "";
        for (const v of (page.topicVerbs[page.topic] || [])) {
            const e = ((page.results[v] || {}).error || "");
            if (e) s += (s ? " " : "") + e;
        }
        return s;
    }
    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        const d = page.results.directory || {};
        const k = page.results.kerberos || {};
        const sc = page.results.smartcard || {};
        const pr = page.results.privileges || {};
        const su = page.results.sudoers || {};
        const ssh = page.results.sshd || {};
        const ls = page.results.lsm || {};
        const keys = page.results.sshkeys || {};
        const totp = page.results.totp || {};
        o.access = {
            directory: d, kerberos: k, smartcard: sc, privileges: pr,
            sudoers: { path: su.path || "", lines: su.text ? String(su.text).split("\n") : [] },
            sshd: ssh, lsm: ls, sshkeys: keys, totp: totp, topic: page.topic
        };
        Ui.systemState = o;
    }

    // One line per fact. Only public facts: no TOTP seed, no private key.
    property var facts: page.computeFacts()
    function computeFacts() {
        const out = [];
        const d = page.results.directory || {};
        const k = page.results.kerberos || {};
        const sc = page.results.smartcard || {};
        const pr = page.results.privileges || {};
        const su = page.results.sudoers || {};
        const ssh = page.results.sshd || {};
        const ls = page.results.lsm || {};
        const keys = page.results.sshkeys || {};
        const totp = page.results.totp || {};
        switch (page.topic) {
        case "directory": {
            out.push({ k: Tr.t("Directory service"), v: d.sssd || Tr.t("not in use") });
            out.push({ k: Tr.t("LDAP service"), v: d.slapd || Tr.t("not in use") });
            out.push({ k: Tr.t("Name lookup"), v: d.nsswitch || "" });
            out.push({ k: Tr.t("Sign-in realm"), v: k.realm || Tr.t("not set") });
            out.push({ k: Tr.t("Domain realm"), v: k.domainRealm || "" });
            out.push({ k: Tr.t("Cached sign-ins"), v: k.cache || "" });
            out.push({ k: Tr.t("Loaded"), v: page.yn(k.loaded) });
            break;
        }
        case "signin": {
            out.push({ k: Tr.t("Card reader setup"), v: sc.mapper || Tr.t("not set") });
            out.push({ k: Tr.t("Card provider"), v: sc.provider || Tr.t("not set") });
            for (const m of (sc.mappings || []))
                out.push({ k: Tr.t("Card mapping"), v: (m && (m.name || m.user || m.mapper || JSON.stringify(m))) || "" });
            break;
        }
        case "auth": {
            for (const r of (pr.rules || []))
                out.push({ k: r.file || Tr.t("Rule"), v: (r.actions || []).join(", ") });
            if (su.path) out.push({ k: Tr.t("Rules file"), v: su.path });
            const lines = su.text ? String(su.text).split("\n").filter(l => l.trim() !== "") : [];
            for (const line of lines.slice(0, 40)) out.push({ k: Tr.t("Rule"), v: line });
            break;
        }
        case "remote": {
            if (ssh.path) out.push({ k: Tr.t("Settings file"), v: ssh.path });
            const set = ssh.settings || {};
            for (const key in set) out.push({ k: key, v: String(set[key]) });
            break;
        }
        case "keys": {
            for (const t of (keys.keys || []))
                out.push({ k: ((t.type || Tr.t("Key")) + " · " + (t.comment || "")).trim(), v: t.fingerprint || "" });
            for (const u of (totp.users || []))
                out.push({ k: u.user || Tr.t("Person"), v: page.yn(u.enabled) + " · " + (u.digits || "") + " " + Tr.t("digits") + " · " + (u.period || "") + "s" });
            break;
        }
        case "kernel": {
            out.push({ k: Tr.t("Active"), v: (ls.active || []).join(", ") || Tr.t("none") });
            out.push({ k: Tr.t("Available"), v: (ls.available || []).join(", ") || Tr.t("none") });
            break;
        }
        }
        return out;
    }

    Process {
        id: reader
        property string verb: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("This section could not be read") }; }
                const o = Object.assign({}, page.results); o[reader.verb] = r; page.results = o;
                page.publish();
                page.next();
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Access and sign-in")
        hint: Tr.t("How this computer finds accounts, signs people in and grants rights. Read only.")
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: page.topics
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.topic === modelData.v
                    onClicked: { page.topic = modelData.v; page.publish(); }
                }
            }
        }
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Reading…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.errorForTopic() !== ""
            tone: "error"
            text: page.errorForTopic()
            accessibleRole: Accessible.AlertMessage
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: page.labelFor(page.topic)
        EmptyState {
            visible: !page.busy && page.facts.length === 0 && page.topic !== "auth"
            icon: "preferences-system"; title: Tr.t("Nothing to show")
            subtitle: Tr.t("No details were reported for this topic.")
        }
        Repeater {
            model: page.facts
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                title: modelData.k
                subtitle: modelData.v
            }
        }
        // sudo rules and password policy are edited here, not a second time here
        ListRow {
            Layout.fillWidth: true
            visible: page.topic === "auth"
            icon: "security-high"
            title: Tr.t("Edit sudo rules and password policy")
            subtitle: Tr.t("Open Security settings")
            onClicked: Ui.settingsCat = "security"
        }
    }
}
