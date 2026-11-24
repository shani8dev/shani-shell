// Settings > Security: posture read as it is, plus safe policy edits via shani-admin.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property string pwNote: ""
    property bool pwBusy: false
    property string hostsText: ""
    property string hostsNote: ""
    property bool hostsBusy: false
    property string sudoersText: ""
    property string sudoersNote: ""
    property bool sudoersBusy: false
    property string aaNote: ""
    property bool aaBusy: false
    property bool auditdOn: false
    property bool auditdLoaded: false
    property var coredump: ({})
    property string faillockNote: ""
    property bool faillockBusy: false
    onActiveChanged: if (active) { SecurityInfo.refresh(); syncPw(); page.loadHosts(); page.loadSudoers(); page.loadFaillock(); page.loadLoginDefs(); }
    Component.onCompleted: if (active) { SecurityInfo.refresh(); syncPw(); page.loadHosts(); page.loadSudoers(); page.loadFaillock(); page.loadLoginDefs(); }

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

    Process {
        id: pwSave
        stdinEnabled: true
        property string payload: ""
        stdout: StdioCollector { id: pwOut }
        stderr: StdioCollector { id: pwErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; page.pwBusy = false;
            page.pwNote = code === 0 ? Tr.t("Password policy saved") : (pwErr.text.trim().split("\n").pop() || Tr.t("Could not save"));
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
        onExited: code => { stdinEnabled = true; page.hostsBusy = false; page.hostsNote = code === 0 ? Tr.t("Hosts saved") : (hostsErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) page.loadHosts(); }
    }
    function saveHosts() { page.hostsBusy = true; page.hostsNote = ""; hostsSaveProc.payload = JSON.stringify({ text: page.hostsText }); hostsSaveProc.command = page.adminCmd.concat(["hosts-set"]); hostsSaveProc.running = true; }

    Process { id: sudoersRead; command: ["sh","-c","cat /etc/sudoers.d/50-shani-shell 2>/dev/null || true"]; stdout: StdioCollector { onStreamFinished: { page.sudoersText = text; sudoersEdit.text = text; } } }
    Process { id: auditdRead; command: ["sh","-c","systemctl is-active auditd 2>/dev/null || true"]; stdout: StdioCollector { onStreamFinished: { page.auditdOn = text.trim() === "active"; page.auditdLoaded = true; } } }
    Process { id: auditdSet; stdinEnabled: true; property string payload: ""; onStarted: { write(payload + "\n"); stdinEnabled = false; } onExited: code => { stdinEnabled = true; auditdRead.running = false; auditdRead.running = true; SecurityInfo.refresh(); if (code !== 0) page.aaNote = Tr.t("Could not change auditd"); } }
    Process { id: coredumpRead; command: ["sh","-c","f=/etc/systemd/coredump.conf.d/50-shani-shell.conf; [ -r \"$f\" ] && grep -v '^#' \"$f\" | grep '=' || true"]; stdout: StdioCollector { onStreamFinished: { const o={}; for (const l of text.split("\n")) { const m=l.match(/^([^=]+)=(.*)$/); if(m) o[m[1].trim()]=m[2].trim(); } page.coredump=o; } } }
    Process { id: coredumpSet; stdinEnabled: true; property string payload: ""; stderr: StdioCollector { id: coredumpErr } onStarted: { write(payload+"\n"); stdinEnabled=false; } onExited: code => { stdinEnabled=true; coredumpRead.running=false; coredumpRead.running=true; page.aaNote = code===0 ? Tr.t("Coredump settings saved") : (coredumpErr.text.trim().split("\n").pop()||Tr.t("Could not save")); } }
    function saveCoredump(key, value) { const o=Object.assign({}, page.coredump); o[key]=value; coredumpSet.payload=JSON.stringify({settings:o}); coredumpSet.command=page.adminCmd.concat(["coredump-set"]); coredumpSet.running=true; }
    function loadSudoers() { sudoersRead.running = false; sudoersRead.running = true; }
    Process {
        id: sudoersSaveProc; stdinEnabled: true; property string payload: ""
        stdout: StdioCollector { } stderr: StdioCollector { id: sudoersErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.sudoersBusy = false; page.sudoersNote = code === 0 ? Tr.t("Sudo rules saved") : (sudoersErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) page.loadSudoers(); }
    }
    function saveSudoers() { page.sudoersBusy = true; page.sudoersNote = ""; sudoersSaveProc.payload = JSON.stringify({ text: page.sudoersText }); sudoersSaveProc.command = page.adminCmd.concat(["sudoers-set"]); sudoersSaveProc.running = true; }

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
        onExited: code => { stdinEnabled = true; page.faillockBusy = false; page.faillockNote = code === 0 ? Tr.t("Faillock policy saved") : (faillockErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) page.loadFaillock(); }
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
        onExited: code => { stdinEnabled = true; page.loginDefsBusy = false; page.loginDefsNote = code === 0 ? Tr.t("Login defaults saved") : (loginDefsErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) page.loadLoginDefs(); }
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

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Security") }
    Text { Layout.fillWidth: true; text: Tr.t("What the kernel, sign-in and audit subsystems report. Policy edits go through administrator authorisation."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Kernel security (LSM)") }
    Text { Layout.fillWidth: true; text: (r.lsm && r.lsm.length) ? r.lsm.join(", ") : Tr.t("Could not read /sys/kernel/security/lsm."); color: Theme.text; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("AppArmor") }
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
    Text { Layout.fillWidth: true; visible: page.aaNote !== ""; text: page.aaNote; color: page.aaNote.indexOf("failed") >= 0 ? Theme.danger : Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Password policy") }
    ListRow { Layout.fillWidth: true; interactive: false; icon: "dialog-password"; title: Tr.t("pwquality config"); subtitle: pw.present ? pw.file : Tr.t("No /etc/security/pwquality.conf") }
    ListRow { Layout.fillWidth: true; interactive: false; icon: "dialog-password"; title: Tr.t("PAM wired"); subtitle: pw.pam_wired ? Tr.t("pam_pwquality appears in PAM") : Tr.t("pam_pwquality not found in PAM — policy may not be enforced") }
    GridLayout {
        Layout.fillWidth: true; columns: 2; columnSpacing: Theme.px(8); rowSpacing: Theme.px(6)
        Text { text: Tr.t("Minimum length"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: minlen; Layout.fillWidth: true; placeholder: "8" }
        Text { text: Tr.t("Different from old (difok)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: difok; Layout.fillWidth: true; placeholder: "1" }
        Text { text: Tr.t("Digits (dcredit)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: dcredit; Layout.fillWidth: true; placeholder: "0" }
        Text { text: Tr.t("Uppercase (ucredit)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: ucredit; Layout.fillWidth: true; placeholder: "0" }
        Text { text: Tr.t("Lowercase (lcredit)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: lcredit; Layout.fillWidth: true; placeholder: "0" }
        Text { text: Tr.t("Other (ocredit)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: ocredit; Layout.fillWidth: true; placeholder: "0" }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Text { Layout.fillWidth: true; text: page.pwNote; color: page.pwNote.indexOf("saved") >= 0 ? Theme.accent : Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; visible: page.pwNote !== "" }
        Item { Layout.fillWidth: true; visible: page.pwNote === "" }
        Button { text: Tr.t("Save policy"); kind: "primary"; enabled: !page.pwBusy; onClicked: page.savePw() }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Audit") }
    ColumnLayout {
        Layout.fillWidth: true; spacing: Theme.px(2)
        ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("auditd"); subtitle: au.active || Tr.t("unknown") }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("enabled"); subtitle: au.enabled || Tr.t("unknown") }
        SwitchRow { Layout.fillWidth: true; visible: page.auditdLoaded; text: Tr.t("Enable auditd"); hint: Tr.t("System audit logging service"); checked: page.auditdOn; onToggled: on => { auditdSet.payload = JSON.stringify({ enabled: on }); auditdSet.command = page.adminCmd.concat(["auditd-set"]); auditdSet.running = true; } }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Coredumps") }
    Text { Layout.fillWidth: true; text: Tr.t("Managed in /etc/systemd/coredump.conf.d/50-shani-shell.conf."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    Repeater {
        model: [{k:"Storage",ph:"none"},{k:"ProcessSizeMax",ph:"0"},{k:"MaxUse",ph:"1G"}]
        RowLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: Theme.px(6)
            Text { Layout.preferredWidth: Theme.px(160); text: modelData.k; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: cdVal; Layout.fillWidth: true; text: page.coredump[modelData.k] || ""; placeholder: modelData.ph }
            Button { text: Tr.t("Save"); onClicked: page.saveCoredump(modelData.k, cdVal.text.trim()) }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Hosts") }
    Text { Layout.fillWidth: true; text: Tr.t("Static name mappings in /etc/hosts. Each line: IP address, then hostnames."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
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
        Text { Layout.fillWidth: true; text: page.hostsNote; color: page.hostsNote.indexOf("saved") >= 0 ? Theme.accent : Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; visible: page.hostsNote !== "" }
        Item { Layout.fillWidth: true; visible: page.hostsNote === "" }
        Button { text: Tr.t("Reload"); enabled: !page.hostsBusy; onClicked: page.loadHosts() }
        Button { text: Tr.t("Save hosts"); kind: "primary"; enabled: !page.hostsBusy; onClicked: page.saveHosts() }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Sudo rules") }
    Text { Layout.fillWidth: true; text: Tr.t("Managed drop-in /etc/sudoers.d/50-shani-shell. Checked with visudo before and after saving; a failed check rolls back."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: Theme.px(120)
        radius: Theme.radiusSmall; color: Theme.surface1; border.width: 1; border.color: sudoersEdit.activeFocus ? Theme.accent : Theme.stroke
        TextEdit { id: sudoersEdit; anchors.fill: parent; anchors.margins: Theme.px(8); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale; wrapMode: TextEdit.NoWrap; selectByMouse: true; onTextChanged: if (page.sudoersText !== text) page.sudoersText = text }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Text { Layout.fillWidth: true; text: page.sudoersNote; color: page.sudoersNote.indexOf("saved") >= 0 ? Theme.accent : Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; visible: page.sudoersNote !== "" }
        Item { Layout.fillWidth: true; visible: page.sudoersNote === "" }
        Button { text: Tr.t("Reload"); enabled: !page.sudoersBusy; onClicked: page.loadSudoers() }
        Button { text: Tr.t("Save sudo rules"); kind: "primary"; enabled: !page.sudoersBusy; onClicked: page.saveSudoers() }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Account lockout (faillock)") }
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
        Text { Layout.fillWidth: true; text: page.faillockNote; color: page.faillockNote.indexOf("saved") >= 0 ? Theme.accent : Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; visible: page.faillockNote !== "" }
        Item { Layout.fillWidth: true; visible: page.faillockNote === "" }
        Button { text: Tr.t("Reload"); enabled: !page.faillockBusy; onClicked: page.loadFaillock() }
        Button { text: Tr.t("Save faillock"); kind: "primary"; enabled: !page.faillockBusy; onClicked: page.saveFaillock() }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Login defaults") }
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
        Text { Layout.fillWidth: true; text: page.loginDefsNote; color: page.loginDefsNote.indexOf("saved") >= 0 ? Theme.accent : Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; visible: page.loginDefsNote !== "" }
        Item { Layout.fillWidth: true; visible: page.loginDefsNote === "" }
        Button { text: Tr.t("Reload"); enabled: !page.loginDefsBusy; onClicked: page.loadLoginDefs() }
        Button { text: Tr.t("Save login defaults"); kind: "primary"; enabled: !page.loginDefsBusy; onClicked: page.saveLoginDefs() }
    }
}
