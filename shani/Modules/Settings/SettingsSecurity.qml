// Settings > Security: posture read as it is, plus safe policy edits via shani-admin.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/ToolPath.js" as ToolPath
import "../../Common/Format.js" as Format

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property string pwNote: ""
    property bool pwNoteOk: false
    property bool pwBusy: false
    property string hostsText: ""
    property string hostsNote: ""
    property bool hostsNoteOk: false
    property bool hostsBusy: false
    property string sudoersText: ""
    property string sudoersNote: ""
    property bool sudoersNoteOk: false
    property bool sudoersBusy: false
    // Parsed view of the same drop-in, beside the raw editor below.
    readonly property string accessTool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_ACCESS_TOOL"), "system_access.py")
    property var sudoersRows: []
    property var sudoersOther: []
    property var sudoersUnreadable: []
    property var rowsSnapshot: []
    // Grant form: every value has a click path; typing is only for a custom name.
    property var commonCommands: ["ALL", "/usr/bin/systemctl", "/usr/bin/journalctl", "/usr/bin/mount", "/usr/bin/umount"]
    property string selectedWho: "root"
    property string customWho: ""
    readonly property string grantWho: page.customWho.trim() !== "" ? page.customWho.trim() : page.selectedWho
    property string grantRunas: "ALL"
    property string grantTag: "PASSWD"
    property var grantCommands: []
    property string customCommand: ""
    readonly property bool grantValid: page.whoError() === "" && page.commandError() === "" && page.grantCommands.length > 0
    readonly property bool rowsAllowAll: page.sudoersRows.some(r => r && r.warning === "all_commands")
    property string aaNote: ""
    property bool aaBusy: false
    property bool auditdOn: false
    property bool auditdLoaded: false
    property string auditProfile: "unknown"
    property bool auditProfileBusy: false
    property string auditProfileNote: ""
    property bool auditProfileNoteOk: false
    // auditd state comes from one read: an empty ausearch is only fair when
    // auditd is running and its log is real
    property var auditInfo: ({})
    property bool auditBusy: false
    property bool auditLoaded: false
    readonly property string auditTool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_HEALTH_TOOL"), "system_health.py")
    // The raw audit log records moved here from Background services: same read
    // bridge (system_background.py), just a different home on the page.
    readonly property string bgTool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_BG_TOOL"), "system_background.py")
    property var auditLogRows: []
    property bool auditLogLoaded: false
    // "off" removes the shell-managed rules file: ask for a second click
    property string confirmingAudit: ""
    Timer { id: auditConfirmTimer; interval: 4000; onTriggered: page.confirmingAudit = "" }
    property var coredump: ({})
    property string faillockNote: ""
    property bool faillockNoteOk: false
    property bool faillockBusy: false
    onActiveChanged: if (active) { SecurityInfo.refresh(); syncPw(); page.loadHosts(); page.loadSudoers(); page.loadFaillock(); page.loadLoginDefs(); page.loadAuditProfile(); page.loadAudit(); page.loadAuditLog(); }
    Component.onCompleted: if (active) { SecurityInfo.refresh(); syncPw(); page.loadHosts(); page.loadSudoers(); page.loadFaillock(); page.loadLoginDefs(); page.loadAuditProfile(); page.loadAudit(); page.loadAuditLog(); }

    readonly property var r: SecurityInfo.report || ({})
    readonly property var aa: r.apparmor || ({})
    readonly property var pw: r.pwquality || ({})
    readonly property var au: r.audit || ({})

    function syncPw() {
        const s = (SecurityInfo.report.pwquality || {}).settings || {};
        minlen.text = s.minlen || ""; difok.text = s.difok || "";
        dcredit.text = s.dcredit || ""; ucredit.text = s.ucredit || "";
        lcredit.text = s.lcredit || ""; ocredit.text = s.ocredit || "";
    }
    Connections { target: SecurityInfo; function onReportChanged() { page.syncPw(); } }

    // policy fields are optional, but a value that is there must be a whole number
    function wholeNumberError(t) {
        const v = t.text.trim();
        return v !== "" && !/^\d+$/.test(v) ? Tr.t("Use a whole number") : "";
    }

    // A refusal is printed as JSON on stdout by both helpers. Read the plain
    // message instead of guessing a tone from the wording.
    function errorFromJson(text) {
        try { const d = JSON.parse(text); if (d && d.error) return String(d.error); } catch (e) {}
        return "";
    }
    function knownAccounts() {
        const acc = (Ui.systemState && Ui.systemState.access) || {};
        const src = (acc.totp && acc.totp.users) || [];
        const out = [];
        for (const u of src) {
            const n = u && u.user;
            if (n && out.indexOf(n) < 0) out.push(n);
        }
        if (out.indexOf("root") < 0) out.unshift("root");
        return out;
    }
    function runasOptions() {
        const out = [{ label: Tr.t("Any user"), value: "ALL" }, { label: Tr.t("Root"), value: "root" }];
        for (const n of page.knownAccounts())
            if (n !== "root" && !out.some(o => o.value === n)) out.push({ label: n, value: n });
        return out;
    }
    function whoError() {
        return /^%?[A-Za-z0-9._-]{1,64}$/.test(page.grantWho)
            ? "" : Tr.t("Use a plain account name, like alice. Start with % for a group.");
    }
    function commandError() {
        const v = page.customCommand.trim();
        if (v === "") return "";
        const head = v.split(/\s+/)[0];
        if (head !== "ALL" && !head.startsWith("/")) return Tr.t("Start with / or use ALL");
        if (/[;|&$`\\\n\r]/.test(v)) return Tr.t("Do not use shell symbols in a command");
        return "";
    }
    function toggleCommand(c) {
        const a = page.grantCommands.slice();
        const i = a.indexOf(c);
        if (i >= 0) a.splice(i, 1); else a.push(c);
        page.grantCommands = a;
    }
    function addCustomCommand() {
        const c = page.customCommand.trim();
        if (c === "" || page.commandError() !== "") return;
        if (page.grantCommands.indexOf(c) < 0) {
            const a = page.grantCommands.slice(); a.push(c); page.grantCommands = a;
        }
        page.customCommand = "";
    }
    function rowSubtitle(row) {
        const r = row || {};
        const tags = (r.tags || []).length ? (r.tags || []).join(" ") + " " : "";
        return tags + (r.commands || []).join(", ");
    }
    property bool pwValid: [minlen, difok, dcredit, ucredit, lcredit, ocredit].every(f => /^\s*$|^\d+$/.test(f.text))

    Process {
        id: pwSave
        stdinEnabled: true
        property string payload: ""
        stdout: StdioCollector { id: pwOut }
        stderr: StdioCollector { id: pwErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; page.pwBusy = false;
            page.pwNoteOk = code === 0; page.pwNote = code === 0 ? Tr.t("Password policy saved") : (pwErr.text.trim().split("\n").pop() || Tr.t("Could not save"));
            SecurityInfo.refresh();
        }
    }
    function savePw() {
        const s = {};
        const add = (k, t) => { const v = t.text.trim(); if (v !== "") s[k] = v; };
        add("minlen", minlen); add("difok", difok); add("dcredit", dcredit);
        add("ucredit", ucredit); add("lcredit", lcredit); add("ocredit", ocredit);
        page.pwBusy = true; page.pwNote = "";
        pwSave.payload = JSON.stringify({ settings: s });
        pwSave.command = page.adminCmd.concat(["pwquality-set"]);
        pwSave.running = true;
    }

    Process { id: hostsRead; command: ["cat", "/etc/hosts"]; stdout: StdioCollector { onStreamFinished: { page.hostsText = text; hostsEdit.text = text; } } }
    function loadHosts() { hostsRead.running = false; hostsRead.running = true; }
    Process {
        id: hostsSaveProc
        stdinEnabled: true
        property string payload: ""
        stdout: StdioCollector { id: hostsOut }
        stderr: StdioCollector { id: hostsErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; page.hostsBusy = false; page.hostsNoteOk = code === 0;
            page.hostsNote = code === 0 ? Tr.t("Hosts saved")
                : (page.errorFromJson(hostsOut.text) || hostsErr.text.trim().split("\n").pop() || Tr.t("Could not save"));
            if (code === 0) page.loadHosts();
        }
    }
    function saveHosts() { page.hostsBusy = true; page.hostsNote = ""; hostsSaveProc.payload = JSON.stringify({ text: page.hostsText }); hostsSaveProc.command = page.adminCmd.concat(["hosts-set"]); hostsSaveProc.running = true; }

    Process { id: sudoersRead; command: ["sh","-c","cat /etc/sudoers.d/50-shani-shell 2>/dev/null || true"]; stdout: StdioCollector { onStreamFinished: { page.sudoersText = text; sudoersEdit.text = text; } } }
    Process { id: auditdRead; command: ["sh","-c","systemctl is-active auditd 2>/dev/null || true"]; stdout: StdioCollector { onStreamFinished: { page.auditdOn = text.trim() === "active"; page.auditdLoaded = true; } } }
    Process { id: auditdSet; stdinEnabled: true; property string payload: ""; onStarted: { write(payload + "\n"); stdinEnabled = false; } onExited: code => { stdinEnabled = true; auditdRead.running = false; auditdRead.running = true; SecurityInfo.refresh(); if (code !== 0) page.aaNote = Tr.t("Could not change auditd"); } }
    Process {
        id: auditProfileRead
        command: ["sh", "-c", "p=/etc/audit/rules.d/50-shani-shell.rules; if [ ! -e \"$p\" ]; then echo off; else m=$(grep -m1 '^# shani-shell-profile:' \"$p\" 2>/dev/null | sed 's/^# shani-shell-profile: *//'); if [ -n \"$m\" ]; then echo \"$m\"; else echo unknown; fi; fi"]
        stdout: StdioCollector { onStreamFinished: { const v = text.trim(); page.auditProfile = v || "unknown"; } }
    }
    function loadAuditProfile() { auditProfileRead.running = false; auditProfileRead.running = true; }

    Process {
        id: auditProc
        command: ["python3", page.auditTool, "audit"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                page.auditLoaded = true;
                page.auditBusy = false;
                page.auditInfo = d.have === true ? d : { have: false, error: d.error || Tr.t("Could not read the audit state"), records: [], verdict: "unresolved" };
                page.publishAudit();
            }
        }
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0) {
                page.auditLoaded = true;
                page.auditBusy = false;
                page.auditInfo = { have: false, error: Tr.t("Could not read the audit state"), records: [], verdict: "unresolved" };
                page.publishAudit();
            }
        }
    }
    function loadAudit() { page.auditBusy = true; auditProc.running = false; auditProc.running = true; page.publishAudit(); }
    function auditRecords() {
        const rs = Array.isArray(page.auditInfo.records) ? page.auditInfo.records : [];
        return rs.slice(0, 25);
    }
    function auditLogLabel() {
        if (!page.auditLoaded || page.auditInfo.have !== true) return Tr.t("not read");
        const present = page.auditInfo.log_present;
        if (present === null || present === undefined) return Tr.t("not read");
        if (!present) return Tr.t("No audit log");
        const size = page.auditInfo.log_size;
        return size === null || size === undefined ? Tr.t("Audit log present") : Format.humanSize(size, "si");
    }
    function publishAudit() {
        const o = Object.assign({}, Ui.systemState || {});
        o.securityAudit = {
            verdict: page.auditInfo.verdict || "unresolved",
            active: page.auditInfo.active || "",
            records: Array.isArray(page.auditInfo.records) ? page.auditInfo.records : [],
            log: page.auditLogRows.map(e => e.type || ""),
            error: page.auditInfo.error || ""
        };
        Ui.systemState = o;
    }

    function loadAuditLog() { bgAuditProc.running = false; bgAuditProc.running = true; }
    Process {
        id: bgAuditProc
        command: ["python3", page.bgTool, "audit"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("This section could not be read") }; }
                page.auditLogRows = Array.isArray(r.events) ? r.events : [];
                page.auditLogLoaded = true;
                page.publishAudit();
            }
        }
    }

    Process {
        id: auditProfileSet
        stdinEnabled: true
        property string payload: ""
        stdout: StdioCollector { id: auditProfileOut }
        stderr: StdioCollector { id: auditProfileErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; page.auditProfileBusy = false;
            if (code === 0) {
                try { const d = JSON.parse(auditProfileOut.text); if (d.profile) page.auditProfile = d.profile; } catch (e) { page.loadAuditProfile(); }
                page.auditProfileNote = Tr.t("Audit profile saved");
            } else {
                page.auditProfileNote = auditProfileErr.text.trim().split("\n").pop() || Tr.t("Could not save audit profile");
            }
        }
    }
    function saveAuditProfile(name) {
        page.auditProfileBusy = true; page.auditProfileNote = "";
        auditProfileSet.payload = JSON.stringify({ profile: name });
        auditProfileSet.command = page.adminCmd.concat(["audit-profile-set"]);
        auditProfileSet.running = true;
    }
    Process { id: coredumpRead; command: ["sh","-c","f=/etc/systemd/coredump.conf.d/50-shani-shell.conf; [ -r \"$f\" ] && grep -v '^#' \"$f\" | grep '=' || true"]; stdout: StdioCollector { onStreamFinished: { const o={}; for (const l of text.split("\n")) { const m=l.match(/^([^=]+)=(.*)$/); if(m) o[m[1].trim()]=m[2].trim(); } page.coredump=o; } } }
    Process { id: coredumpSet; stdinEnabled: true; property string payload: ""; stderr: StdioCollector { id: coredumpErr } onStarted: { write(payload+"\n"); stdinEnabled=false; } onExited: code => { stdinEnabled=true; coredumpRead.running=false; coredumpRead.running=true; page.aaNote = code===0 ? Tr.t("Coredump settings saved") : (coredumpErr.text.trim().split("\n").pop()||Tr.t("Could not save")); } }
    function saveCoredump(key, value) { const o=Object.assign({}, page.coredump); o[key]=value; coredumpSet.payload=JSON.stringify({settings:o}); coredumpSet.command=page.adminCmd.concat(["coredump-set"]); coredumpSet.running=true; }
    // Structured read of the same drop-in. It never edits the raw editor; that
    // path below stays available for hand-written rules.
    Process {
        id: sudoersParsedRead
        command: ["python3", page.accessTool, "sudoers"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) {}
                page.sudoersRows = Array.isArray(d.rows) ? d.rows : [];
                page.sudoersOther = Array.isArray(d.other) ? d.other : [];
                page.sudoersUnreadable = Array.isArray(d.unreadable) ? d.unreadable : [];
            }
        }
    }
    function loadSudoers() {
        sudoersRead.running = false; sudoersRead.running = true;
        sudoersParsedRead.running = false; sudoersParsedRead.running = true;
    }
    Process {
        id: sudoersSaveProc; stdinEnabled: true; property string payload: ""
        stdout: StdioCollector { id: sudoersOut } stderr: StdioCollector { id: sudoersErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; page.sudoersBusy = false; page.sudoersNoteOk = code === 0;
            page.sudoersNote = code === 0 ? Tr.t("Sudo rules saved")
                : (page.errorFromJson(sudoersOut.text) || sudoersErr.text.trim().split("\n").pop() || Tr.t("Could not save"));
            if (page.formSaving) {
                page.formSaving = false;
                if (code !== 0) page.sudoersRows = page.rowsSnapshot;
            }
            if (code === 0) page.loadSudoers();
        }
    }
    property bool formSaving: false
    function saveSudoers() {
        page.formSaving = false;
        page.sudoersBusy = true; page.sudoersNote = "";
        sudoersSaveProc.payload = JSON.stringify({ text: page.sudoersText });
        sudoersSaveProc.command = page.adminCmd.concat(["sudoers-set"]);
        sudoersSaveProc.running = true;
    }
    // Stage the whole rule list first: the bridge returns the exact text and
    // its digest, which the privileged writer checks before touching the file.
    Process {
        id: sudoersStageProc; stdinEnabled: true; property string payload: ""
        stdout: StdioCollector { id: sudoersStageOut }
        stderr: StdioCollector { id: sudoersStageErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            const reason = page.errorFromJson(sudoersStageOut.text)
                || sudoersStageErr.text.trim().split("\n").pop();
            let d = {};
            if (code === 0) { try { d = JSON.parse(sudoersStageOut.text) || {}; } catch (e) {} }
            if (code !== 0 || d.refuse || d.error || !d.text || !d.sha256) {
                page.sudoersBusy = false; page.formSaving = false;
                page.sudoersRows = page.rowsSnapshot;
                page.sudoersNoteOk = false;
                page.sudoersNote = reason || (d.refuse ? String(d.refuse) : "") || d.error || Tr.t("Could not check the sudo rules");
                return;
            }
            sudoersSaveProc.payload = JSON.stringify({ text: d.text, sha256: d.sha256 });
            sudoersSaveProc.command = page.adminCmd.concat(["sudoers-set"]);
            sudoersSaveProc.running = true;
        }
    }
    function applyRows() {
        page.rowsSnapshot = page.sudoersRows;
        page.formSaving = true;
        page.sudoersBusy = true; page.sudoersNote = "";
        sudoersStageProc.payload = JSON.stringify({ rows: page.sudoersRows, other: page.sudoersOther });
        sudoersStageProc.command = ["python3", page.accessTool, "sudoers-stage"];
        sudoersStageProc.running = true;
    }
    function addRule() {
        if (!page.grantValid) return;
        const tags = page.grantTag === "NOPASSWD" ? ["NOPASSWD"] : [];
        const cmds = page.grantCommands.slice();
        const rows = page.sudoersRows.slice();
        rows.push({ who: page.grantWho, runas: page.grantRunas, tags: tags, commands: cmds,
            raw: "", nopasswd: tags.indexOf("NOPASSWD") >= 0,
            warning: cmds.indexOf("ALL") >= 0 ? "all_commands" : "" });
        page.sudoersRows = rows;
        page.grantCommands = [];
        page.applyRows();
    }
    function removeRow(i) {
        const rows = page.sudoersRows.slice();
        if (i < 0 || i >= rows.length) return;
        rows.splice(i, 1);
        page.sudoersRows = rows;
        page.applyRows();
    }

    Process {
        id: aaProc; stdinEnabled: true; property string payload: ""
        stderr: StdioCollector { id: aaErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.aaBusy = false; page.aaNote = code === 0 ? Tr.t("AppArmor profile updated") : (aaErr.text.trim().split("\n").pop() || Tr.t("AppArmor change failed")); SecurityInfo.refresh(); }
    }
    function setAa(mode) { page.aaBusy = true; page.aaNote = ""; aaProc.payload = JSON.stringify({ profile: aaProfile.text.trim(), mode: mode }); aaProc.command = page.adminCmd.concat(["apparmor-set"]); aaProc.running = true; }

    function _kv(text, key) {
        const m = String(text || "").match(new RegExp("^\\s*" + key + "\\s*=\\s*(\\S+)", "m"));
        return m ? m[1] : "";
    }
    property bool evenDenyRoot: false
    Process { id: faillockRead; command: ["cat", "/etc/security/faillock.conf"]; stdout: StdioCollector { onStreamFinished: { denyField.text = page._kv(text, "deny"); unlockField.text = page._kv(text, "unlock_time"); failIntervalField.text = page._kv(text, "fail_interval"); page.evenDenyRoot = page._kv(text, "even_deny_root") === "1"; } } }
    function loadFaillock() { faillockRead.running = false; faillockRead.running = true; }
    Process {
        id: faillockSaveProc; stdinEnabled: true; property string payload: ""
        stderr: StdioCollector { id: faillockErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.faillockBusy = false; page.faillockNoteOk = code === 0; page.faillockNote = code === 0 ? Tr.t("Faillock policy saved") : (faillockErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) page.loadFaillock(); }
    }
    function saveFaillock() {
        const s = {};
        const add = (k, t) => { const v = t.text.trim(); if (v !== "") s[k] = v; };
        add("deny", denyField); add("unlock_time", unlockField); add("fail_interval", failIntervalField);
        s.even_deny_root = page.evenDenyRoot;
        page.faillockBusy = true; page.faillockNote = "";
        faillockSaveProc.payload = JSON.stringify({ settings: s });
        faillockSaveProc.command = page.adminCmd.concat(["faillock-set"]);
        faillockSaveProc.running = true;
    }

    property string loginDefsNote: ""
    property bool loginDefsNoteOk: false
    property bool loginDefsBusy: false
    function _ld(text, key) {
        const m = String(text || "").match(new RegExp("^\\s*" + key + "\\s+(\\S+)", "m"));
        return m ? m[1] : "";
    }
    Process { id: loginDefsRead; command: ["cat", "/etc/login.defs"]; stdout: StdioCollector { onStreamFinished: { passMaxField.text = page._ld(text, "PASS_MAX_DAYS"); passMinField.text = page._ld(text, "PASS_MIN_DAYS"); passWarnField.text = page._ld(text, "PASS_WARN_AGE"); loginRetriesField.text = page._ld(text, "LOGIN_RETRIES"); loginTimeoutField.text = page._ld(text, "LOGIN_TIMEOUT"); } } }
    function loadLoginDefs() { loginDefsRead.running = false; loginDefsRead.running = true; }
    Process {
        id: loginDefsSaveProc; stdinEnabled: true; property string payload: ""
        stderr: StdioCollector { id: loginDefsErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.loginDefsBusy = false; page.loginDefsNoteOk = code === 0; page.loginDefsNote = code === 0 ? Tr.t("Login defaults saved") : (loginDefsErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) page.loadLoginDefs(); }
    }
    function saveLoginDefs() {
        const s = {};
        const add = (k, t) => { const v = t.text.trim(); if (v !== "") s[k] = v; };
        add("PASS_MAX_DAYS", passMaxField); add("PASS_MIN_DAYS", passMinField); add("PASS_WARN_AGE", passWarnField);
        add("LOGIN_RETRIES", loginRetriesField); add("LOGIN_TIMEOUT", loginTimeoutField);
        page.loginDefsBusy = true; page.loginDefsNote = "";
        loginDefsSaveProc.payload = JSON.stringify({ settings: s });
        loginDefsSaveProc.command = page.adminCmd.concat(["login-defs-set"]);
        loginDefsSaveProc.running = true;
    }

    // Disk encryption, TPM unlock and Secure Boot keys: one page in the
    // Security category, reading gen-efi through its own bridge. It keeps its
    // state to itself; no secret ever reaches this page's neighbours.
    SettingsEncryptionBoot { Layout.fillWidth: true; active: page.active }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Security")
        hint: Tr.t("What the kernel, sign-in and audit subsystems report. Policy edits go through administrator authorisation.")


    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Kernel security (LSM)")
        Text { Layout.fillWidth: true; visible: !!(r.lsm && r.lsm.length); text: r.lsm && r.lsm.length ? r.lsm.join(", ") : ""; color: Theme.text; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
        InfoBanner {
            Layout.fillWidth: true
            visible: !r.lsm || !r.lsm.length
            tone: "warn"
            title: Tr.t("The kernel did not report its security modules")
            text: Tr.t("This can be normal in a container or a locked-down kernel. The checks below still work.")
            Button { text: Tr.t("Retry"); onClicked: SecurityInfo.refresh() }
        }

    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("AppArmor")
        ColumnLayout {
            Layout.fillWidth: true; spacing: Theme.px(2)
            ListRow { Layout.fillWidth: true; interactive: false; icon: "security-high"; title: Tr.t("Service"); subtitle: aa.active || Tr.t("unknown") }
            ListRow { Layout.fillWidth: true; interactive: false; icon: "security-high"; title: Tr.t("Profiles"); subtitle: aa.profiles ? Tr.t("%1 loaded, %2 enforcing", Object.keys(aa.profiles).length, aa.enforcing || 0) : (aa.note || Tr.t("No profile report available")) }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            TextField { id: aaProfile; Layout.fillWidth: true; placeholder: Tr.t("Profile name (from aa-status)") }
            Button { text: Tr.t("Complain"); enabled: !page.aaBusy && aaProfile.text.trim() !== ""; onClicked: page.setAa("complain") }
            Button { text: Tr.t("Enforce"); kind: "primary"; enabled: !page.aaBusy && aaProfile.text.trim() !== ""; onClicked: page.setAa("enforce") }
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.aaNote !== ""
            tone: page.aaNote.indexOf("failed") >= 0 ? "error" : "ok"
            text: page.aaNote
        }

    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Password policy")
        ListRow { Layout.fillWidth: true; interactive: false; icon: "dialog-password"; title: Tr.t("pwquality config"); subtitle: pw.present ? pw.file : Tr.t("No /etc/security/pwquality.conf") }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "dialog-password"; title: Tr.t("PAM wired"); subtitle: pw.pam_wired ? Tr.t("pam_pwquality appears in PAM") : Tr.t("pam_pwquality not found in PAM — policy may not be enforced") }
        GridLayout {
            Layout.fillWidth: true; columns: 2; columnSpacing: Theme.px(8); rowSpacing: Theme.px(6)
            Text { text: Tr.t("Minimum length"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: minlen; Layout.fillWidth: true; placeholder: "8"; error: page.wholeNumberError(minlen) }
            Text { text: Tr.t("Different from old (difok)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: difok; Layout.fillWidth: true; placeholder: "1"; error: page.wholeNumberError(difok) }
            Text { text: Tr.t("Digits (dcredit)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: dcredit; Layout.fillWidth: true; placeholder: "0"; error: page.wholeNumberError(dcredit) }
            Text { text: Tr.t("Uppercase (ucredit)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: ucredit; Layout.fillWidth: true; placeholder: "0"; error: page.wholeNumberError(ucredit) }
            Text { text: Tr.t("Lowercase (lcredit)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: lcredit; Layout.fillWidth: true; placeholder: "0"; error: page.wholeNumberError(lcredit) }
            Text { text: Tr.t("Other (ocredit)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: ocredit; Layout.fillWidth: true; placeholder: "0"; error: page.wholeNumberError(ocredit) }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            InfoBanner {
                Layout.fillWidth: true
                visible: page.pwNote !== ""
                tone: page.pwNoteOk ? "ok" : "error"
                text: page.pwNote
            }
            Item { Layout.fillWidth: true; visible: page.pwNote === "" }
            Button { text: Tr.t("Save policy"); kind: "primary"; enabled: !page.pwBusy && page.pwValid; busy: page.pwBusy; onClicked: page.savePw() }
        }

    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Audit")
        ColumnLayout {
            Layout.fillWidth: true; spacing: Theme.px(2)
            ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("auditd"); subtitle: au.active || Tr.t("unknown") }
            ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("enabled"); subtitle: au.enabled || Tr.t("unknown") }
            ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("Running now"); subtitle: page.auditLoaded && page.auditInfo.have === true ? (page.auditInfo.active || Tr.t("unknown")) : Tr.t("not read") }
            ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("Enabled at boot"); subtitle: page.auditLoaded && page.auditInfo.have === true ? (page.auditInfo.enabled || Tr.t("unknown")) : Tr.t("not read") }
            ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("Audit log"); subtitle: page.auditLogLabel() }
            SwitchRow { Layout.fillWidth: true; visible: page.auditdLoaded; text: Tr.t("Enable auditd"); hint: Tr.t("System audit logging service"); checked: page.auditdOn; onToggled: on => { auditdSet.payload = JSON.stringify({ enabled: on }); auditdSet.command = page.adminCmd.concat(["auditd-set"]); auditdSet.running = true; } }
            ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("Audit profile"); subtitle: page.auditProfile }
        }
        Text { Layout.fillWidth: true; text: Tr.t("Predefined audit rules managed by shani-shell. Off removes the shell-managed rules file."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            Repeater {
                model: ["off", "minimal", "baseline"]
                Button {
                    required property string modelData
                    text: page.confirmingAudit === modelData ? Tr.t("Tap again to remove rules") : Tr.t(modelData)
                    kind: page.auditProfile === modelData ? "primary" : (page.confirmingAudit === modelData ? "danger" : "plain")
                    enabled: !page.auditProfileBusy
                    onClicked: {
                        if (modelData === "off" && page.auditProfile !== "off" && page.confirmingAudit !== "off") {
                            page.confirmingAudit = "off";
                            auditConfirmTimer.restart();
                            return;
                        }
                        page.confirmingAudit = "";
                        page.saveAuditProfile(modelData);
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.auditProfileNote !== ""
            tone: page.auditProfileNoteOk ? "ok" : "error"
            text: page.auditProfileNote
        }

        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            Item { Layout.fillWidth: true }
            IconButton {
                icon: "view-refresh"
                size: Theme.px(28)
                tip: Tr.t("Read audit state again")
                Accessible.name: Tr.t("Read audit state again")
                enabled: !page.auditBusy
                onClicked: page.loadAudit()
            }
        }
        BusyNote { Layout.fillWidth: true; visible: page.auditBusy; note: Tr.t("Reading audit state…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.auditLoaded && page.auditInfo.have === false
            tone: "error"
            title: Tr.t("Audit state could not be read")
            text: page.auditInfo.error || Tr.t("No reason was given")
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.auditLoaded && page.auditInfo.have === true && page.auditInfo.verdict === "not-running"
            tone: "warn"
            text: Tr.t("auditd is not running, so nothing is being recorded. This is not a computer with nothing to report.")
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.auditLoaded && page.auditInfo.have === true && page.auditInfo.verdict === "no-log"
            tone: "warn"
            text: Tr.t("There is no audit log on this computer, so no events can be shown.")
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.auditLoaded && page.auditInfo.have === true && page.auditInfo.verdict === "empty-log"
            tone: "warn"
            text: Tr.t("The audit log is empty, so no events were recorded.")
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.auditLoaded && page.auditInfo.have === true && page.auditInfo.verdict === "unresolved"
            tone: "warn"
            text: Tr.t("The audit state could not be read, so no claim is made about events.")
        }
        Text {
            Layout.fillWidth: true
            visible: page.auditLoaded && page.auditInfo.have === true && page.auditRecords().length > 0
            text: Tr.t("Recent audit events")
            color: Theme.text; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Repeater {
            model: page.auditRecords()
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 0
                ListRow {
                    Layout.fillWidth: true; interactive: false; icon: "document-open-recent"
                    title: modelData.type || Tr.t("Event")
                    subtitle: modelData.time || ""
                }
                Text {
                    Layout.fillWidth: true; Layout.leftMargin: Theme.px(36)
                    visible: !!modelData.detail
                    text: modelData.detail
                    color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: page.auditLoaded && page.auditInfo.have === true && page.auditInfo.truncated === true
            text: Tr.t("Showing the first %1 events; the rest are in the audit log", 25)
            color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        EmptyState {
            Layout.fillWidth: true
            visible: page.auditLoaded && page.auditInfo.have === true && page.auditInfo.verdict === "genuine" && page.auditRecords().length === 0 && !page.auditBusy
            icon: "dialog-ok"
            title: Tr.t("Nothing to report")
            subtitle: Tr.t("Audit logging is working and has no events.")
        }

    }

    // The raw log records, moved here from Background services. They are shown
    // word for word, with no grading or verdict of their own.
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Audit log records")
        hint: Tr.t("Records shown word for word, with no grading or verdict.")
        EmptyState {
            Layout.fillWidth: true
            visible: page.auditLogLoaded && page.auditLogRows.length === 0
            icon: "format-list-unordered"
            title: Tr.t("No audit records")
            subtitle: Tr.t("No audit records were reported.")
        }
        Repeater {
            model: page.auditLogRows
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                ListRow {
                    Layout.fillWidth: true
                    interactive: false
                    icon: "format-list-unordered"
                    title: modelData.type || Tr.t("Record")
                    subtitle: modelData.time || ""
                }
                Text {
                    Layout.fillWidth: true
                    visible: (modelData.detail || "") !== ""
                    text: modelData.detail || ""
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Coredumps")
        Text { Layout.fillWidth: true; text: Tr.t("Managed in /etc/systemd/coredump.conf.d/50-shani-shell.conf."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        Repeater {
            model: [{k:"Storage",ph:"none"},{k:"ProcessSizeMax",ph:"0"},{k:"MaxUse",ph:"1G"}]
            RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: Theme.px(6)
                Text { Layout.preferredWidth: Theme.px(160); text: modelData.k; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
                TextField { id: cdVal; Layout.fillWidth: true; text: (page.coredump && page.coredump[modelData.k]) || ""; placeholder: modelData.ph }
                Button { text: Tr.t("Save"); enabled: !coredumpSet.running; busy: coredumpSet.running; onClicked: page.saveCoredump(modelData.k, cdVal.text.trim()) }
            }
        }

    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Hosts")
        Text { Layout.fillWidth: true; text: Tr.t("Static name mappings in /etc/hosts. Each line: IP address, then hostnames."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        Text { Layout.fillWidth: true; text: Tr.t("The addresses 127.0.0.1, 127.0.1.1 and ::1 are always kept."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: Theme.px(140)
            radius: Theme.radiusSmall; color: Theme.surface1; border.width: 1; border.color: hostsEdit.activeFocus ? Theme.accent : Theme.stroke
            TextEdit {
                id: hostsEdit; anchors.fill: parent; anchors.margins: Theme.px(8)
                color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale
                wrapMode: TextEdit.NoWrap; selectByMouse: true
                onTextChanged: if (page.hostsText !== text) page.hostsText = text
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            InfoBanner {
                Layout.fillWidth: true
                visible: page.hostsNote !== ""
                tone: page.hostsNoteOk ? "ok" : "error"
                text: page.hostsNote
            }
            Item { Layout.fillWidth: true; visible: page.hostsNote === "" }
            Button { text: Tr.t("Reload"); enabled: !page.hostsBusy; onClicked: page.loadHosts() }
            Button { text: Tr.t("Save hosts"); kind: "primary"; enabled: !page.hostsBusy; busy: page.hostsBusy; onClicked: page.saveHosts() }
        }

    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Sudo rules")
        Text { Layout.fillWidth: true; text: Tr.t("Managed drop-in /etc/sudoers.d/50-shani-shell. Checked with visudo before and after saving; a failed check rolls back."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: Theme.px(120)
            radius: Theme.radiusSmall; color: Theme.surface1; border.width: 1; border.color: sudoersEdit.activeFocus ? Theme.accent : Theme.stroke
            TextEdit { id: sudoersEdit; anchors.fill: parent; anchors.margins: Theme.px(8); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale; wrapMode: TextEdit.NoWrap; selectByMouse: true; onTextChanged: if (page.sudoersText !== text) page.sudoersText = text }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            InfoBanner {
                Layout.fillWidth: true
                visible: page.sudoersNote !== ""
                tone: page.sudoersNoteOk ? "ok" : "error"
                text: page.sudoersNote
            }
            Item { Layout.fillWidth: true; visible: page.sudoersNote === "" }
            Button { text: Tr.t("Reload"); enabled: !page.sudoersBusy; onClicked: page.loadSudoers() }
            Button { text: Tr.t("Save sudo rules"); kind: "primary"; enabled: !page.sudoersBusy; busy: page.sudoersBusy; onClicked: page.saveSudoers() }
        }

    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Who can run commands as another user")
        hint: Tr.t("Pick an account, who it may act as, and the commands it may run. The rule is written to the same sudo drop-in as the raw text above.")

        BusyNote { Layout.fillWidth: true; visible: page.sudoersBusy; note: Tr.t("Checking and saving the sudo rules...") }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.sudoersNote !== ""
            tone: page.sudoersNoteOk ? "ok" : "error"
            text: page.sudoersNote
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.rowsAllowAll
            tone: "warn"
            title: Tr.t("Some rules allow every command")
            text: Tr.t("A rule marked All commands lets that account run anything. Remove it if only a few commands are needed.")
        }

        EmptyState {
            Layout.fillWidth: true
            visible: page.sudoersRows.length === 0 && !page.sudoersBusy
            icon: "security-high"
            title: Tr.t("No command rules yet")
            subtitle: Tr.t("Add a rule below when someone needs to run a command as another user.")
        }

        ColumnLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            visible: page.sudoersRows.length > 0
            Repeater {
                model: page.sudoersRows
                ListRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    interactive: false
                    icon: "security-high"
                    title: Tr.t("%1 may run as %2", modelData.who || "?", modelData.runas || Tr.t("any user"))
                    subtitle: page.rowSubtitle(modelData)
                    trailing: modelData.warning === "all_commands" ? Tr.t("All commands") : ""
                    ConfirmButton {
                        Accessible.name: Tr.t("Remove the rule for %1", modelData.who || "")
                        implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                        implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                        text: Tr.t("Remove")
                        armedText: Tr.t("Tap again to remove")
                        kind: armed ? "danger" : "plain"
                        interval: 4000
                        enabled: !page.sudoersBusy
                        onConfirmed: page.removeRow(index)
                    }
                }
            }
        }

        Text { Layout.fillWidth: true; text: Tr.t("Lines this page does not manage are kept as they are."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        ColumnLayout {
            Layout.fillWidth: true; spacing: Theme.px(2)
            Repeater {
                model: page.sudoersOther
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    visible: String(modelData).trim() !== ""
                    interactive: false
                    icon: "document-open-recent"
                    title: Tr.t("Kept line")
                    subtitle: String(modelData).trim()
                }
            }
            Repeater {
                model: page.sudoersUnreadable
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    visible: String(modelData).trim() !== ""
                    interactive: false
                    icon: "dialog-warning"
                    title: Tr.t("Kept but not understood")
                    subtitle: String(modelData).trim()
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true; columns: 2; columnSpacing: Theme.px(8); rowSpacing: Theme.px(6)
            Text { text: Tr.t("Who"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Picks {
                    label: Tr.t("Known accounts")
                    options: page.knownAccounts()
                    current: page.selectedWho
                    onPicked: v => { page.selectedWho = v; page.customWho = ""; }
                }
                TextField {
                    id: grantWhoField
                    Layout.fillWidth: true
                    label: Tr.t("Or type an account name")
                    placeholder: Tr.t("user name")
                    text: page.customWho
                    onTextChanged: page.customWho = text
                    error: page.whoError()
                }
            }
            Text { text: Tr.t("Run as"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Picks {
                options: page.runasOptions()
                current: page.grantRunas
                onPicked: v => page.grantRunas = v
            }
            Text { text: Tr.t("Password"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Picks {
                options: [{ label: Tr.t("Ask for a password"), value: "PASSWD" }, { label: Tr.t("Never ask"), value: "NOPASSWD" }]
                current: page.grantTag
                onPicked: v => page.grantTag = v
            }
            Text { text: Tr.t("Commands"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Flow {
                    Layout.fillWidth: true; spacing: Theme.px(6)
                    Repeater {
                        model: page.commonCommands
                        Choice {
                            required property string modelData
                            columns: 3
                            text: modelData
                            selected: page.grantCommands.indexOf(modelData) >= 0
                            Accessible.name: modelData === "ALL" ? Tr.t("Any command") : Tr.t("Command %1", modelData)
                            onClicked: page.toggleCommand(modelData)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.px(6)
                    TextField {
                        id: grantCommandField
                        Layout.fillWidth: true
                        label: Tr.t("Or type a command path")
                        placeholder: Tr.t("/usr/bin/systemctl")
                        text: page.customCommand
                        onTextChanged: page.customCommand = text
                        error: page.commandError()
                        onAccepted: page.addCustomCommand()
                    }
                    Button { text: Tr.t("Add command"); enabled: page.customCommand.trim() !== "" && page.commandError() === ""; onClicked: page.addCustomCommand() }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            Item { Layout.fillWidth: true }
            Button { text: Tr.t("Add rule"); kind: "primary"; enabled: !page.sudoersBusy && page.grantValid; busy: page.sudoersBusy; onClicked: page.addRule() }
        }

    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Account lockout (faillock)")
        Text { Layout.fillWidth: true; text: Tr.t("Managed in /etc/security/faillock.conf. Values apply to PAM faillock."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        GridLayout {
            Layout.fillWidth: true; columns: 2; columnSpacing: Theme.px(8); rowSpacing: Theme.px(6)
            Text { text: Tr.t("Deny after failures"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: denyField; Layout.fillWidth: true; placeholder: "3" }
            Text { text: Tr.t("Unlock time (s)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: unlockField; Layout.fillWidth: true; placeholder: "600" }
            Text { text: Tr.t("Fail interval (s)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: failIntervalField; Layout.fillWidth: true; placeholder: "900" }
            Text { text: Tr.t("Even deny root"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Button { text: page.evenDenyRoot ? Tr.t("Enabled") : Tr.t("Disabled"); onClicked: page.evenDenyRoot = !page.evenDenyRoot }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            InfoBanner {
                Layout.fillWidth: true
                visible: page.faillockNote !== ""
                tone: page.faillockNoteOk ? "ok" : "error"
                text: page.faillockNote
            }
            Item { Layout.fillWidth: true; visible: page.faillockNote === "" }
            Button { text: Tr.t("Reload"); enabled: !page.faillockBusy; onClicked: page.loadFaillock() }
            Button { text: Tr.t("Save faillock"); kind: "primary"; enabled: !page.faillockBusy; busy: page.faillockBusy; onClicked: page.saveFaillock() }
        }

    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Login defaults")
        Text { Layout.fillWidth: true; text: Tr.t("Managed keys in /etc/login.defs. Only the listed keys are changed."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        GridLayout {
            Layout.fillWidth: true; columns: 2; columnSpacing: Theme.px(8); rowSpacing: Theme.px(6)
            Text { text: Tr.t("PASS_MAX_DAYS"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: passMaxField; Layout.fillWidth: true; placeholder: "99999" }
            Text { text: Tr.t("PASS_MIN_DAYS"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: passMinField; Layout.fillWidth: true; placeholder: "0" }
            Text { text: Tr.t("PASS_WARN_AGE"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: passWarnField; Layout.fillWidth: true; placeholder: "7" }
            Text { text: Tr.t("LOGIN_RETRIES"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: loginRetriesField; Layout.fillWidth: true; placeholder: "5" }
            Text { text: Tr.t("LOGIN_TIMEOUT"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: loginTimeoutField; Layout.fillWidth: true; placeholder: "60" }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            InfoBanner {
                Layout.fillWidth: true
                visible: page.loginDefsNote !== ""
                tone: page.loginDefsNoteOk ? "ok" : "error"
                text: page.loginDefsNote
            }
            Item { Layout.fillWidth: true; visible: page.loginDefsNote === "" }
            Button { text: Tr.t("Reload"); enabled: !page.loginDefsBusy; onClicked: page.loadLoginDefs() }
            Button { text: Tr.t("Save login defaults"); kind: "primary"; enabled: !page.loginDefsBusy; busy: page.loginDefsBusy; onClicked: page.saveLoginDefs() }
        }
    }
}
