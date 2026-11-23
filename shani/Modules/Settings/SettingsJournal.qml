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
    property string note: ""
    property bool busy: false
    property string logText: ""

    onActiveChanged: if (active) { load(); loadLog(); }
    Component.onCompleted: if (active) { load(); loadLog(); }

    Process {
        id: getProc; command: page.adminCmd.concat(["journald-get"])
        stdout: StdioCollector { onStreamFinished: { try { const s = (JSON.parse(text).settings) || {}; page.storage = s.Storage || "auto"; page.maxUse = s.SystemMaxUse || ""; maxUseField.text = page.maxUse; } catch(e) {} } }
    }
    function load() { getProc.running = false; getProc.running = true; }
    Process {
        id: setProc; stdinEnabled: true; property string payload: ""
        stderr: StdioCollector { id: setErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.busy = false; page.note = code === 0 ? Tr.t("Journal settings saved") : (setErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) load(); }
    }
    function save() { page.busy = true; page.note = ""; setProc.payload = JSON.stringify({ settings: { Storage: page.storage, SystemMaxUse: maxUseField.text.trim() || "500M" } }); setProc.command = page.adminCmd.concat(["journald-set"]); setProc.running = true; }
    Process {
        id: vacProc; stdinEnabled: true; property string payload: ""
        stdout: StdioCollector { id: vacOut }
        stderr: StdioCollector { id: vacErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; page.busy = false; page.note = code === 0 ? (vacOut.text.trim().split("\n").pop() || Tr.t("Vacuum complete")) : (vacErr.text.trim().split("\n").pop() || Tr.t("Vacuum failed")); }
    }
    function vacuum() { page.busy = true; page.note = ""; vacProc.payload = JSON.stringify({ mode: "size", value: vacField.text.trim() || "500M" }); vacProc.command = page.adminCmd.concat(["journald-vacuum"]); vacProc.running = true; }
    Process { id: logProc; command: ["journalctl", "-n", "80", "--no-pager", "-o", "short"]; stdout: StdioCollector { onStreamFinished: page.logText = text } }
    function loadLog() { logProc.running = false; logProc.running = true; }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Journal") }
    Text { Layout.fillWidth: true; text: Tr.t("Journal storage is managed by a systemd drop-in. Vacuum removes old entries; it does not change the limit."); color: Theme.dim; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }

    Text { text: Tr.t("Storage"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Repeater {
            model: ["auto", "persistent", "volatile", "none"]
            Choice { required property var modelData; text: modelData; selected: page.storage === modelData; onClicked: page.storage = modelData }
        }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        Text { text: Tr.t("System max use"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: maxUseField; Layout.fillWidth: true; placeholder: "500M" }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.px(6)
        TextField { id: vacField; Layout.fillWidth: true; placeholder: Tr.t("Vacuum to size, e.g. 500M") }
        Button { text: Tr.t("Vacuum"); enabled: !page.busy; onClicked: page.vacuum() }
        Button { text: Tr.t("Save"); kind: "primary"; enabled: !page.busy; onClicked: page.save() }
    }
    Text { Layout.fillWidth: true; visible: page.note !== ""; text: page.note; color: page.note.indexOf("failed") >= 0 || page.note.indexOf("Could not") >= 0 ? Theme.danger : Theme.accent; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Recent log") }
    RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } Button { text: Tr.t("Refresh"); onClicked: page.loadLog() } }
    Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: Theme.px(220)
        radius: Theme.radiusSmall; color: Theme.surface1; border.width: 1; border.color: Theme.stroke
        Flickable {
            anchors.fill: parent; anchors.margins: Theme.px(8); clip: true; contentHeight: logBody.implicitHeight
            Text { id: logBody; width: parent.width; text: page.logText || Tr.t("No log loaded."); color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale; wrapMode: Text.WrapAnywhere }
        }
    }
}
