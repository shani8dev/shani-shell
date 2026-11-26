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
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
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
    property int done: 0
    property bool busy: false

    // Writes go through a plain-data stage first. Only {text, sha256} reaches
    // the administrator helper; no raw sudoers or mapping text is typed here.
    property bool noteOk: true
    property string note: ""
    readonly property bool sudoBusy: sudoersStageProc.running || (adminProc.running && adminProc.action === "sudoers")
    readonly property bool mapBusy: smartcardStageProc.running || (adminProc.running && adminProc.action === "mapping")

    property var people: page.peopleFromState()
    property var accounts: page.accountsFromState()
    property string sudoersWho: ""
    property string sudoersRunas: "ALL"
    property string sudoersTags: "NOPASSWD"
    property var sudoersCommands: []
    property string sudoersCustom: ""
    property int sudoersSelected: -1
    property bool addingGrant: false

    property bool mappingAdding: false
    property int mappingSelected: -1
    property string mappingIdentity: ""
    property string mappingLogin: ""
    property string typedConfirm: ""

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function load() {
        page.results = ({});
        page.done = 0;
        page.busy = true;
        publish();
        directoryProc.running = false; directoryProc.running = true;
        kerberosProc.running = false; kerberosProc.running = true;
        smartcardProc.running = false; smartcardProc.running = true;
        privilegesProc.running = false; privilegesProc.running = true;
        sudoersProc.running = false; sudoersProc.running = true;
        sshdProc.running = false; sshdProc.running = true;
        lsmProc.running = false; lsmProc.running = true;
        sshkeysProc.running = false; sshkeysProc.running = true;
        totpProc.running = false; totpProc.running = true;
    }
    function store(verb, text) {
        let r = {};
        try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("This section could not be read") }; }
        const o = Object.assign({}, page.results); o[verb] = r; page.results = o;
        page.done = page.done + 1;
        if (page.done >= page.verbs.length) page.busy = false;
        publish();
    }
    function yn(x) { return x ? Tr.t("yes") : Tr.t("no"); }
    function reply(text) {
        try { return JSON.parse(text) || {}; }
        catch (e) { return { error: Tr.t("Could not read the reply") }; }
    }
    function setNote(ok, text) { page.noteOk = !!ok; page.note = text || ""; publish(); }
    function peopleFromState() {
        const s = Ui.systemState || {};
        const raw = s.users || (s.access && s.access.users) || [];
        if (!Array.isArray(raw)) return [];
        const names = [];
        for (const u of raw) {
            const n = typeof u === "string" ? u : (u && (u.name || u.user || u.login)) || "";
            if (n && names.indexOf(String(n)) < 0) names.push(String(n));
        }
        return names;
    }
    function accountsFromState() {
        const out = page.people.slice();
        const me = Quickshell.env("USER") || "";
        if (me && out.indexOf(me) < 0) out.push(me);
        const sc = page.results.smartcard || {};
        for (const m of (sc.mappings || [])) {
            const n = m && (m.login || m.user);
            if (n && out.indexOf(String(n)) < 0) out.push(String(n));
        }
        return out;
    }
    function cleanSudoersRow(r) {
        return {
            who: String(r.who || ""), runas: String(r.runas || ""),
            tags: Array.isArray(r.tags) ? r.tags.slice() : [],
            commands: Array.isArray(r.commands) ? r.commands.slice() : []
        };
    }
    function toggleCommand(v) {
        const a = page.sudoersCommands.slice();
        const i = a.indexOf(v);
        if (i >= 0) a.splice(i, 1); else a.push(v);
        page.sudoersCommands = a;
    }
    function stageSudoers(rows) {
        const su = page.results.sudoers || {};
        sudoersStageProc.payload = JSON.stringify({
            rows: rows.map(r => page.cleanSudoersRow(r)),
            other: Array.isArray(su.other) ? su.other.slice() : []
        });
        sudoersStageProc.gotReply = false;
        sudoersStageProc.running = true;
        page.setNote(true, "");
    }
    function addGrant() {
        const who = page.sudoersWho.trim();
        const custom = page.sudoersCustom.trim();
        const commands = page.sudoersCommands.slice();
        if (custom !== "") {
            if (custom.charAt(0) !== "/") {
                page.setNote(false, Tr.t("A command must be a full path, starting with /.")); return;
            }
            if (commands.indexOf(custom) < 0) commands.push(custom);
        }
        if (who === "" || commands.length === 0) {
            page.setNote(false, Tr.t("Choose a person and at least one command first.")); return;
        }
        const rows = (page.results.sudoers || {}).rows || [];
        const all = rows.map(r => page.cleanSudoersRow(r));
        all.push({ who: who, runas: page.sudoersRunas, tags: [page.sudoersTags], commands: commands });
        page.stageSudoers(all);
    }
    function removeGrant(index) {
        const rows = ((page.results.sudoers || {}).rows || []).slice();
        if (index < 0 || index >= rows.length) return;
        const all = rows.filter((r, i) => i !== index).map(r => page.cleanSudoersRow(r));
        page.sudoersSelected = -1;
        page.stageSudoers(all);
    }
    function mappingList() {
        const sc = page.results.smartcard || {};
        const out = [];
        for (const m of (sc.mappings || [])) {
            const identity = m && (m.identity || m.name || m.user || "");
            const login = m && (m.login || m.user || "");
            if (identity && login) out.push({ identity: String(identity), login: String(login) });
        }
        return out;
    }
    function startMappingForm(edit) {
        page.mappingAdding = true;
        const list = page.mappingList();
        const m = edit ? list[page.mappingSelected] : null;
        page.mappingIdentity = m ? m.identity : "";
        page.mappingLogin = m ? m.login : (page.accounts.length ? page.accounts[0] : "");
        page.typedConfirm = "";
        page.setNote(true, "");
    }
    function saveMapping() {
        const identity = page.mappingIdentity.trim();
        const login = page.mappingLogin.trim();
        if (identity === "" || login === "") {
            page.setNote(false, Tr.t("Enter a card identity and a person first.")); return;
        }
        if (page.typedConfirm.trim() !== "CONFIRM") {
            page.setNote(false, Tr.t("Type CONFIRM to allow this change.")); return;
        }
        const all = page.mappingList();
        if (page.mappingSelected >= 0 && page.mappingSelected < all.length)
            all[page.mappingSelected] = { identity: identity, login: login };
        else all.push({ identity: identity, login: login });
        smartcardStageProc.payload = JSON.stringify({ mappings: all });
        smartcardStageProc.gotReply = false;
        smartcardStageProc.running = true;
        page.setNote(true, "");
    }
    function removeMapping(index) {
        if (page.typedConfirm.trim() !== "CONFIRM") {
            page.setNote(false, Tr.t("Type CONFIRM to allow this change.")); return;
        }
        const all = page.mappingList().filter((m, i) => i !== index);
        smartcardStageProc.payload = JSON.stringify({ mappings: all });
        smartcardStageProc.gotReply = false;
        smartcardStageProc.running = true;
        page.mappingSelected = -1;
        page.typedConfirm = "";
        page.setNote(true, "");
    }
    function readerState(s) {
        if (s === "tool_missing") return Tr.t("Reader check is not installed");
        if (s === "daemon_down") return Tr.t("Card reader service is not running");
        if (s === "no_reader") return Tr.t("No card reader found");
        if (s === "ready") return Tr.t("Ready for a card");
        return Tr.t("Reader state is not known");
    }
    function cardReady() {
        const sc = page.results.smartcard || {};
        const readers = sc.readers || [];
        return !!sc.pamPkcs11 && readers.some(r => r && r.state === "ready");
    }
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
            for (const r of (sc.readers || []))
                out.push({ k: Tr.t("Card reader"), v: String(r && r.name || Tr.t("Reader")) + " · " + page.readerState(r && r.state) });
            out.push({ k: Tr.t("Card sign-in module"), v: page.yn(sc.pamPkcs11) });
            out.push({ k: Tr.t("Card sign-in"), v: page.cardReady() ? Tr.t("ready") : Tr.t("not ready") });
            out.push({ k: Tr.t("Mapping file"), v: String(sc.mappingPath || "") });
            if (sc.mappingMode) out.push({ k: Tr.t("Mapping file permissions"), v: String(sc.mappingMode) });
            if (sc.mappingOwner) out.push({ k: Tr.t("Mapping file owner"), v: String(sc.mappingOwner) });
            break;
        }
        case "auth": {
            for (const r of (pr.rules || []))
                out.push({ k: r.file || Tr.t("Rule"), v: (r.actions || []).join(", ") });
            if (su.path) out.push({ k: Tr.t("Rules file"), v: su.path });
            const lines = su.text ? String(su.text).split("\n").filter(l => l.trim() !== "") : [];
            for (const line of lines.slice(0, 40)) out.push({ k: Tr.t("Rule"), v: line });
            out.push({ k: Tr.t("Managed grants"), v: String((su.rows || []).length) });
            out.push({ k: Tr.t("Rules not read"), v: String((su.unreadable || []).length) });
            for (const r of (su.rows || [])) {
                if (r && r.warning === "all_commands")
                    out.push({ k: Tr.t("Grant for %1", String(r.who || "")), v: Tr.t("can run any command") });
            }
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
            out.push({ k: Tr.t("Code sign-in in PAM"), v: page.yn(totp.pamWired) });
            out.push({ k: Tr.t("PAM stacks"), v: (totp.pamStacks || []).join(", ") || Tr.t("none") });
            out.push({ k: Tr.t("Code settings file"), v: String(totp.usersfile || "") });
            out.push({ k: Tr.t("Can read the file"), v: page.yn(totp.readable) });
            out.push({ k: Tr.t("File permissions"), v: String(totp.mode || "") });
            out.push({ k: Tr.t("File owner"), v: String(totp.owner || "") });
            out.push({ k: Tr.t("Code tool"), v: String(totp.toolVersion || "") });
            if (totp.unknown) {
                out.push({ k: Tr.t("People using codes"), v: Tr.t("not known — the file is protected") });
            } else {
                out.push({ k: Tr.t("People using codes"), v: String((totp.users || []).length) });
                out.push({ k: Tr.t("Lines skipped"), v: String(totp.skipped || 0) });
            }
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
        id: directoryProc
        command: ["python3", page.tool, "directory"]
        stdout: StdioCollector { id: directoryOut }
        onExited: code => page.store("directory", directoryOut.text)
    }

    Process {
        id: kerberosProc
        command: ["python3", page.tool, "kerberos"]
        stdout: StdioCollector { id: kerberosOut }
        onExited: code => page.store("kerberos", kerberosOut.text)
    }

    Process {
        id: smartcardProc
        command: ["python3", page.tool, "smartcard"]
        stdout: StdioCollector { id: smartcardOut }
        onExited: code => page.store("smartcard", smartcardOut.text)
    }

    Process {
        id: privilegesProc
        command: ["python3", page.tool, "privileges"]
        stdout: StdioCollector { id: privilegesOut }
        onExited: code => page.store("privileges", privilegesOut.text)
    }

    Process {
        id: sudoersProc
        command: ["python3", page.tool, "sudoers"]
        stdout: StdioCollector { id: sudoersOut }
        onExited: code => page.store("sudoers", sudoersOut.text)
    }

    Process {
        id: sshdProc
        command: ["python3", page.tool, "sshd"]
        stdout: StdioCollector { id: sshdOut }
        onExited: code => page.store("sshd", sshdOut.text)
    }

    Process {
        id: lsmProc
        command: ["python3", page.tool, "lsm"]
        stdout: StdioCollector { id: lsmOut }
        onExited: code => page.store("lsm", lsmOut.text)
    }

    Process {
        id: sshkeysProc
        command: ["python3", page.tool, "sshkeys"]
        stdout: StdioCollector { id: sshkeysOut }
        onExited: code => page.store("sshkeys", sshkeysOut.text)
    }

    Process {
        id: totpProc
        command: ["python3", page.tool, "totp"]
        stdout: StdioCollector { id: totpOut }
        onExited: code => page.store("totp", totpOut.text)
    }

    // ---- two-step writes: stage plain data, then hand text + sha256 to root --
    Process {
        id: sudoersStageProc; stdinEnabled: true
        property string payload: ""; property bool gotReply: false
        command: ["python3", page.tool, "sudoers-stage"]
        stdout: StdioCollector { onStreamFinished: {
            sudoersStageProc.gotReply = true;
            const r = page.reply(text);
            if (r.refuse || r.error || !r.text || !r.sha256) {
                page.setNote(false, String(r.error || Tr.t("Could not prepare the grant change")));
                return;
            }
            adminProc.action = "sudoers";
            adminProc.payload = JSON.stringify({ text: r.text, sha256: r.sha256 });
            adminProc.gotReply = false;
            adminProc.command = page.adminCmd.concat(["sudoers-set"]);
            adminProc.running = true;
        } }
        stderr: StdioCollector { id: sudoersStageErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; payload = "";
            if (code !== 0 && !gotReply)
                page.setNote(false, String(sudoersStageErr.text.trim().split("\n").pop() || Tr.t("Could not prepare the grant change")));
        }
    }

    Process {
        id: smartcardStageProc; stdinEnabled: true
        property string payload: ""; property bool gotReply: false
        command: ["python3", page.tool, "smartcard-stage"]
        stdout: StdioCollector { onStreamFinished: {
            smartcardStageProc.gotReply = true;
            const r = page.reply(text);
            if (r.refuse || r.error || !r.text || !r.sha256) {
                page.setNote(false, String(r.error || Tr.t("Could not prepare the card sign-in change")));
                return;
            }
            adminProc.action = "mapping";
            adminProc.payload = JSON.stringify({ text: r.text, sha256: r.sha256 });
            adminProc.gotReply = false;
            adminProc.command = page.adminCmd.concat(["pkcs11-mapping-set"]);
            adminProc.running = true;
        } }
        stderr: StdioCollector { id: smartcardStageErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; payload = "";
            if (code !== 0 && !gotReply)
                page.setNote(false, String(smartcardStageErr.text.trim().split("\n").pop() || Tr.t("Could not prepare the card sign-in change")));
        }
    }

    Process {
        id: adminProc; stdinEnabled: true
        property string payload: ""; property string action: ""
        property bool gotReply: false
        stdout: StdioCollector { onStreamFinished: {
            adminProc.gotReply = true;
            const r = page.reply(text);
            if (!r.ok) {
                page.setNote(false, String(r.error || Tr.t("The change was not saved")));
                return;
            }
            const granting = adminProc.action === "sudoers";
            page.setNote(true, granting ? Tr.t("Grant saved.") : Tr.t("Card sign-in mapping saved."));
            page.addingGrant = false;
            page.mappingAdding = false;
            page.mappingIdentity = ""; page.mappingLogin = ""; page.typedConfirm = "";
            page.sudoersCustom = ""; page.sudoersCommands = [];
            if (granting) { sudoersProc.running = false; sudoersProc.running = true; }
            else { smartcardProc.running = false; smartcardProc.running = true; }
        } }
        stderr: StdioCollector { id: adminErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; payload = "";
            if (code !== 0 && !gotReply)
                page.setNote(false, String(adminErr.text.trim().split("\n").pop() || Tr.t("The change was not saved")));
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Access and sign-in")
        hint: Tr.t("How this computer finds accounts, signs people in and grants rights.")
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: page.topics
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.topic === modelData.v
                    onClicked: { page.topic = modelData.v; page.note = ""; page.sudoersSelected = -1; page.mappingSelected = -1; page.publish(); }
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
            Accessible.name: Tr.t("Open Security settings for sudo rules and password policy")
            onClicked: Ui.settingsCat = "security"
        }
    }

    // ---- authorisation: pick a grant, add one, or remove one ----------------
    SettingsSection {
        Layout.fillWidth: true
        visible: page.topic === "auth"
        title: Tr.t("Grants")
        hint: Tr.t("Pick a grant to change it. Saving asks for an administrator password.")
        BusyNote { Layout.fillWidth: true; visible: page.sudoBusy; note: Tr.t("Saving…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.note !== ""
            tone: page.noteOk ? "ok" : "error"
            text: page.note
            accessibleRole: Accessible.AlertMessage
        }
        Repeater {
            model: ((page.results.sudoers || {}).rows || []).map((r, i) => Object.assign({ rowIndex: i }, r))
            ColumnLayout {
                id: grantRow
                required property var modelData
                property int rowIndex: modelData.rowIndex
                Layout.fillWidth: true
                spacing: Theme.px(4)
                ListRow {
                    Layout.fillWidth: true
                    icon: "security-high"
                    selected: page.sudoersSelected === grantRow.rowIndex
                    title: String(grantRow.modelData.who || "")
                    subtitle: "(" + String(grantRow.modelData.runas || "") + ") "
                        + (grantRow.modelData.tags || []).join(", ") + " "
                        + (grantRow.modelData.commands || []).join(", ")
                    Accessible.name: Tr.t("Grant for %1", String(grantRow.modelData.who || ""))
                    onClicked: page.sudoersSelected = page.sudoersSelected === grantRow.rowIndex ? -1 : grantRow.rowIndex
                }
                InfoBanner {
                    Layout.fillWidth: true
                    visible: grantRow.modelData.warning === "all_commands"
                    tone: "warn"
                    text: Tr.t("This grant can run any command.")
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.sudoersSelected === grantRow.rowIndex
                    spacing: Theme.px(6)
                    ConfirmButton {
                        implicitWidth: Theme.px(200); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                        kind: "danger"
                        text: Tr.t("Remove this grant")
                        value: String(grantRow.rowIndex)
                        enabled: !page.sudoBusy
                        Accessible.name: Tr.t("Remove the grant for %1", String(grantRow.modelData.who || ""))
                        onConfirmed: id => page.removeGrant(Number(id))
                    }
                    Button {
                        text: Tr.t("Close")
                        Accessible.name: Tr.t("Close grant actions")
                        onClicked: page.sudoersSelected = -1
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }
        EmptyState {
            visible: !page.busy && !page.sudoBusy && !page.addingGrant && ((page.results.sudoers || {}).rows || []).length === 0
            icon: "security-high"; title: Tr.t("No grants yet")
            subtitle: Tr.t("No managed grant was found in the rules file.")
        }
        Button {
            visible: !page.addingGrant
            text: Tr.t("Add a grant…")
            Accessible.name: Tr.t("Add a new grant")
            enabled: !page.sudoBusy
            onClicked: { page.addingGrant = true; page.sudoersSelected = -1; page.sudoersWho = ""; }
        }
        ColumnLayout {
            visible: page.addingGrant
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Picks {
                visible: page.people.length > 0
                label: Tr.t("Who")
                options: page.people
                current: page.sudoersWho
                onPicked: v => page.sudoersWho = String(v)
            }
            TextField {
                visible: page.people.length === 0
                Layout.fillWidth: true
                placeholder: Tr.t("User name")
                label: Tr.t("Who this grant is for")
                text: page.sudoersWho
                onTextChanged: page.sudoersWho = text
                error: page.sudoersWho !== "" && !/^[A-Za-z_][A-Za-z0-9._-]*$/.test(page.sudoersWho) ? Tr.t("Use a user name such as alex.") : ""
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice {
                    text: "(ALL)"
                    accessibleName: Tr.t("Any account")
                    selected: page.sudoersRunas === "ALL"
                    onClicked: page.sudoersRunas = "ALL"
                }
                Choice {
                    text: "root"
                    accessibleName: Tr.t("The root account")
                    selected: page.sudoersRunas === "root"
                    onClicked: page.sudoersRunas = "root"
                }
                Choice {
                    text: Tr.t("This account")
                    accessibleName: Tr.t("This account")
                    selected: page.sudoersRunas === (Quickshell.env("USER") || "this")
                    onClicked: page.sudoersRunas = Quickshell.env("USER") || "this"
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice {
                    text: "NOPASSWD"
                    accessibleName: Tr.t("No password needed")
                    selected: page.sudoersTags === "NOPASSWD"
                    onClicked: page.sudoersTags = "NOPASSWD"
                }
                Choice {
                    text: "PASSWD"
                    accessibleName: Tr.t("Ask for a password")
                    selected: page.sudoersTags === "PASSWD"
                    onClicked: page.sudoersTags = "PASSWD"
                }
            }
            Picks {
                label: Tr.t("Commands")
                options: [
                    { label: "systemctl", value: "/usr/bin/systemctl" },
                    { label: "journalctl", value: "/usr/bin/journalctl" },
                    { label: "mount", value: "/usr/bin/mount" },
                    { label: "umount", value: "/usr/bin/umount" },
                    { label: "reboot", value: "/usr/bin/reboot" },
                    { label: "poweroff", value: "/usr/bin/poweroff" }
                ]
                current: page.sudoersCommands.length ? page.sudoersCommands[page.sudoersCommands.length - 1] : ""
                onPicked: v => page.toggleCommand(String(v))
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Another command (full path, optional)")
                label: Tr.t("Another command")
                text: page.sudoersCustom
                onTextChanged: page.sudoersCustom = text
                error: page.sudoersCustom.trim() !== "" && page.sudoersCustom.trim().charAt(0) !== "/" ? Tr.t("Start with / for a full path.") : ""
            }
            ListRow {
                Layout.fillWidth: true
                visible: page.sudoersCommands.length > 0
                interactive: false
                icon: "object-select-symbolic"
                title: Tr.t("Chosen commands")
                subtitle: page.sudoersCommands.join(", ")
                Accessible.name: Tr.t("Chosen commands")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button {
                    text: Tr.t("Cancel")
                    Accessible.name: Tr.t("Cancel the new grant")
                    onClicked: { page.addingGrant = false; page.sudoersWho = ""; page.sudoersCustom = ""; page.sudoersCommands = []; }
                }
                Button {
                    kind: "primary"
                    text: Tr.t("Add grant")
                    Accessible.name: Tr.t("Save the new grant")
                    enabled: !page.sudoBusy
                    onClicked: page.addGrant()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // ---- sign-in: readers, the hardware verdict and card mappings ----------
    SettingsSection {
        Layout.fillWidth: true
        visible: page.topic === "signin"
        title: Tr.t("Card readers")
        hint: Tr.t("What this computer sees when someone signs in with a card.")
        Repeater {
            model: ((page.results.smartcard || {}).readers || [])
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "card"
                title: String(modelData.name || Tr.t("Card reader"))
                subtitle: page.readerState(modelData.state)
                Accessible.name: Tr.t("Card reader %1", String(modelData.name || ""))
            }
        }
        InfoBanner {
            Layout.fillWidth: true
            tone: page.cardReady() ? "ok" : "warn"
            text: page.cardReady() ? Tr.t("Cards can sign in on this computer.")
                                   : Tr.t("Cards cannot sign in yet. Check the reader and the sign-in setup.")
            accessibleRole: Accessible.StaticText
        }
        ListRow {
            Layout.fillWidth: true
            visible: !!(page.results.smartcard || {}).mappingPath
            interactive: false
            icon: "folder"
            title: Tr.t("Mapping file")
            subtitle: String((page.results.smartcard || {}).mappingPath || "")
                + " · " + String((page.results.smartcard || {}).mappingMode || "")
                + " · " + String((page.results.smartcard || {}).mappingOwner || "")
            Accessible.name: Tr.t("Card mapping file")
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: page.topic === "signin"
        title: Tr.t("Card sign-in mappings")
        hint: Tr.t("Which account a card opens. Every change needs the word CONFIRM.")
        BusyNote { Layout.fillWidth: true; visible: page.mapBusy; note: Tr.t("Saving…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.note !== ""
            tone: page.noteOk ? "ok" : "error"
            text: page.note
            accessibleRole: Accessible.AlertMessage
        }
        Repeater {
            model: page.mappingList().map((m, i) => Object.assign({ rowIndex: i }, m))
            ColumnLayout {
                id: mapRow
                required property var modelData
                property int rowIndex: modelData.rowIndex
                Layout.fillWidth: true
                spacing: Theme.px(4)
                ListRow {
                    Layout.fillWidth: true
                    icon: "avatar-default"
                    selected: page.mappingSelected === mapRow.rowIndex
                    title: String(mapRow.modelData.identity || "")
                    subtitle: Tr.t("Signs in as %1").arg(String(mapRow.modelData.login || ""))
                    Accessible.name: Tr.t("Card identity %1", String(mapRow.modelData.identity || ""))
                    onClicked: page.mappingSelected = page.mappingSelected === mapRow.rowIndex ? -1 : mapRow.rowIndex
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.mappingSelected === mapRow.rowIndex
                    spacing: Theme.px(6)
                    Button {
                        text: Tr.t("Edit")
                        Accessible.name: Tr.t("Edit the card mapping for %1", String(mapRow.modelData.identity || ""))
                        onClicked: page.startMappingForm(true)
                    }
                    ConfirmButton {
                        implicitWidth: Theme.px(200); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                        kind: "danger"
                        text: Tr.t("Remove mapping")
                        value: String(mapRow.rowIndex)
                        enabled: !page.mapBusy && page.typedConfirm.trim() === "CONFIRM"
                        Accessible.name: Tr.t("Remove the card mapping for %1", String(mapRow.modelData.identity || ""))
                        onConfirmed: id => page.removeMapping(Number(id))
                    }
                    Button {
                        text: Tr.t("Close")
                        Accessible.name: Tr.t("Close mapping actions")
                        onClicked: page.mappingSelected = -1
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }
        TextField {
            Layout.fillWidth: true
            visible: page.mappingAdding || page.mappingSelected >= 0
            placeholder: Tr.t("Type CONFIRM to allow a mapping change")
            label: Tr.t("Typed confirmation")
            text: page.typedConfirm
            onTextChanged: page.typedConfirm = text
            error: page.typedConfirm !== "" && page.typedConfirm.trim() !== "CONFIRM" ? Tr.t("Type CONFIRM exactly.") : ""
        }
        Button {
            visible: !page.mappingAdding
            text: Tr.t("Add a card mapping…")
            Accessible.name: Tr.t("Add a new card mapping")
            enabled: !page.mapBusy
            onClicked: page.startMappingForm(false)
        }
        ColumnLayout {
            visible: page.mappingAdding
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Picks {
                label: Tr.t("Account")
                options: page.accounts
                current: page.mappingLogin
                onPicked: v => page.mappingLogin = String(v)
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Card identity")
                label: Tr.t("Card identity")
                text: page.mappingIdentity
                onTextChanged: page.mappingIdentity = text
                error: page.mappingIdentity.indexOf("->") >= 0 || page.mappingIdentity.indexOf("\n") >= 0
                    ? Tr.t("Use a plain identity, with no arrow or line break.") : ""
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button {
                    text: Tr.t("Cancel")
                    Accessible.name: Tr.t("Cancel the card mapping change")
                    onClicked: { page.mappingAdding = false; page.mappingIdentity = ""; page.mappingLogin = ""; page.typedConfirm = ""; }
                }
                Button {
                    kind: "primary"
                    text: Tr.t("Save mapping")
                    Accessible.name: Tr.t("Save the card sign-in mapping")
                    enabled: !page.mapBusy && page.typedConfirm.trim() === "CONFIRM"
                    onClicked: page.saveMapping()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // ---- keys: PAM wiring and the sign-in-code file, never a secret ---------
    SettingsSection {
        Layout.fillWidth: true
        visible: page.topic === "keys" && !!(page.results.totp || {}).usersfile
        title: Tr.t("Sign-in codes")
        hint: Tr.t("How this computer checks one-time codes. Shared secrets are never shown.")
        InfoBanner {
            Layout.fillWidth: true
            tone: (page.results.totp || {}).unknown ? "warn" : "info"
            text: (page.results.totp || {}).unknown
                ? Tr.t("The code file is protected, so the number of people using codes is not known.")
                : Tr.t("Code settings are read from the file named below.")
            accessibleRole: Accessible.StaticText
        }
        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "preferences-system"
            title: Tr.t("Wired into sign-in")
            subtitle: page.yn((page.results.totp || {}).pamWired)
                + " · " + (((page.results.totp || {}).pamStacks || []).join(", ") || Tr.t("no stacks named"))
            Accessible.name: Tr.t("One-time codes wired into sign-in")
        }
    }
}
