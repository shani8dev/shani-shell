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
    onActiveChanged: if (active) { SecurityInfo.refresh(); syncPw(); page.loadHosts(); }
    Component.onCompleted: if (active) { SecurityInfo.refresh(); syncPw(); page.loadHosts(); }

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
}
