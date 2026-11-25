// Settings > Journal: journald storage policy (CRUD) + bounded log view.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property string storage: "auto"
    property string maxUse: ""
    property string forwardToSyslog: "yes"
    property string compress: "yes"
    property string seal: "yes"
    property string rateLimitIntervalSec: ""
    property string rateLimitBurst: ""
    property string note: ""
    property bool noteOk: false
    // Storage=none stops keeping logs on disk: a second click makes it deliberate
    property string confirmingStorage: ""
    Timer { id: storageConfirmTimer; interval: 4000; onTriggered: page.confirmingStorage = "" }
    property bool busy: false

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    Process {
        id: getProc; command: ["sh","-c","f=/etc/systemd/journald.conf.d/50-shani-shell.conf; [ -r \"$f\" ] && grep -E '^(Storage|SystemMaxUse|ForwardToSyslog|Compress|Seal|RateLimitIntervalSec|RateLimitBurst)=' \"$f\" || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                let st="auto", mu="", fwd="yes", cmp="yes", seal="yes", rli="", rlb="";
                for (const l of text.split("\n")) {
                    if (l.startsWith("Storage=")) st=l.slice(8).trim();
                    if (l.startsWith("SystemMaxUse=")) mu=l.slice(13).trim();
                    if (l.startsWith("ForwardToSyslog=")) fwd=l.slice(16).trim();
                    if (l.startsWith("Compress=")) cmp=l.slice(9).trim();
                    if (l.startsWith("Seal=")) seal=l.slice(5).trim();
                    if (l.startsWith("RateLimitIntervalSec=")) rli=l.slice(21).trim();
                    if (l.startsWith("RateLimitBurst=")) rlb=l.slice(16).trim();
                }
                page.storage=st; page.maxUse=mu; maxUseField.text=mu;
                page.forwardToSyslog=fwd; page.compress=cmp; page.seal=seal;
                page.rateLimitIntervalSec=rli; rateLimitIntervalField.text=rli;
                page.rateLimitBurst=rlb; rateLimitBurstField.text=rlb;
            }
        }
    }
    function load() { getProc.running = false; getProc.running = true; }
    Process {
        id: setProc; stdinEnabled: true; property string payload: ""
        stderr: StdioCollector { id: setErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.busy = false; page.note = code === 0 ? Tr.t("Journal settings saved") : (setErr.text.trim().split("\n").pop() || Tr.t("Could not save")); page.noteOk = code === 0; if (code === 0) load(); }
    }
    function save() {
        page.busy = true; page.note = "";
        const s = { Storage: page.storage, SystemMaxUse: maxUseField.text.trim() || "500M", ForwardToSyslog: page.forwardToSyslog, Compress: page.compress, Seal: page.seal };
        const rli = rateLimitIntervalField.text.trim(); if (rli !== "") s.RateLimitIntervalSec = rli;
        const rlb = rateLimitBurstField.text.trim(); if (rlb !== "") s.RateLimitBurst = rlb;
        setProc.payload = JSON.stringify({ settings: s });
        setProc.command = page.adminCmd.concat(["journald-set"]); setProc.running = true;
    }
    Process {
        id: vacProc; stdinEnabled: true; property string payload: ""
        stdout: StdioCollector { id: vacOut }
        stderr: StdioCollector { id: vacErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.busy = false; page.note = code === 0 ? (vacOut.text.trim().split("\n").pop() || Tr.t("Vacuum complete")) : (vacErr.text.trim().split("\n").pop() || Tr.t("Vacuum failed")); page.noteOk = code === 0; }
    }
    function vacuum() { page.busy = true; page.note = ""; vacProc.payload = JSON.stringify({ mode: "size", value: vacField.text.trim() || "500M" }); vacProc.command = page.adminCmd.concat(["journald-vacuum"]); vacProc.running = true; }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Journal")
        hint: Tr.t("Journal storage is managed by a systemd drop-in. Vacuum removes old entries; it does not change the limit.")

    Text { text: Tr.t("Storage"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Repeater {
            model: ["auto", "persistent", "volatile", "none"]
            Choice {
                required property var modelData
                text: page.confirmingStorage === modelData ? Tr.t("Tap again to stop storing") : modelData
                danger: page.confirmingStorage === modelData
                selected: page.storage === modelData
                onClicked: {
                    if (modelData === "none" && page.storage !== "none" && page.confirmingStorage !== "none") {
                        page.confirmingStorage = "none";
                        storageConfirmTimer.restart();
                        return;
                    }
                    page.confirmingStorage = "";
                    page.storage = modelData;
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Text { text: Tr.t("System max use"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField {
            id: maxUseField; Layout.fillWidth: true; placeholder: "500M"
            error: maxUseField.text.trim() !== "" && !/^\d+(\.\d+)?\s*[KMGT]?$/i.test(maxUseField.text.trim()) ? Tr.t("Use a size like 500M or 2G") : ""
        }
    }
    Text { text: Tr.t("Forward to syslog"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Repeater {
            model: ["yes", "no"]
            Choice { required property var modelData; text: modelData; selected: page.forwardToSyslog === modelData; onClicked: page.forwardToSyslog = modelData }
        }
    }
    Text { text: Tr.t("Compress"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Repeater {
            model: ["yes", "no"]
            Choice { required property var modelData; text: modelData; selected: page.compress === modelData; onClicked: page.compress = modelData }
        }
    }
    Text { text: Tr.t("Seal"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Repeater {
            model: ["yes", "no"]
            Choice { required property var modelData; text: modelData; selected: page.seal === modelData; onClicked: page.seal = modelData }
        }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Text { text: Tr.t("Rate limit interval"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField {
            id: rateLimitIntervalField; Layout.fillWidth: true; placeholder: "30s"
            error: rateLimitIntervalField.text.trim() !== "" && !/^\d+\s*(ms|min|s|m|h|d|w)?$/i.test(rateLimitIntervalField.text.trim()) ? Tr.t("Use a time like 30s or 5min") : ""
        }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Text { text: Tr.t("Rate limit burst"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField {
            id: rateLimitBurstField; Layout.fillWidth: true; placeholder: "10000"
            error: rateLimitBurstField.text.trim() !== "" && !/^\d+$/.test(rateLimitBurstField.text.trim()) ? Tr.t("Use a whole number") : ""
        }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        TextField {
            id: vacField; Layout.fillWidth: true; placeholder: Tr.t("Vacuum to size, e.g. 500M")
            error: vacField.text.trim() !== "" && !/^\d+(\.\d+)?\s*[KMGT]?$/i.test(vacField.text.trim()) ? Tr.t("Use a size like 500M or 2G") : ""
        }
        Button { text: Tr.t("Vacuum"); enabled: !page.busy && (/^\s*$|^\d+(\.\d+)?\s*[KMGT]?$/i).test(vacField.text.trim()); onClicked: page.vacuum() }
        Button { text: Tr.t("Save"); kind: "primary"; enabled: !page.busy && page.policyValid; busy: page.busy; onClicked: page.save() }
    }
    }
    property bool policyValid: /^\s*$|^\d+(\.\d+)?\s*[KMGT]?$/i.test(maxUseField.text.trim())
        && (/^\s*$|^\d+\s*(ms|min|s|m|h|d|w)?$/i).test(rateLimitIntervalField.text.trim())
        && /^\s*$|^\d+$/.test(rateLimitBurstField.text.trim())
    InfoBanner {
        Layout.fillWidth: true
        visible: page.note !== ""
        tone: page.noteOk ? "ok" : "error"
        text: page.note
    }

    // reading the log is the Logs app's (filters, search, an entry's details,
    // follow); this page keeps the journal's storage. Its own 80-line copy of a
    // log view was a second, smaller viewer.
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Read the log")
        SettingRow {
            Layout.fillWidth: true
            icon: "gnome-logs"
            title: Tr.t("Open Logs")
            subtitle: Tr.t("Everything the system wrote down, with filters and search")
            onClicked: { Ui.closeAll(); Ui.logs = true; }
        }
    }
}
