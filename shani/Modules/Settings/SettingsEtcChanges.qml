// Settings > System > System changes: what this machine changed in its own
// system files. The upper layer of the overlay belongs to root, so reading asks
// for authorisation; putting a file back is only queued for the next start,
// never done under the system that is running now. Paths used here come only
// from the list — no path is typed into this page.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import "../../Common/ToolPath.js" as ToolPath

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_MACHINE_TOOL"), "system_machine.py")
    property string verb: ""
    property bool busy: false
    property bool read: false
    property var changes: []
    property var pending: []
    property var restored: []
    property string currentPath: ""
    property string diffPath: ""
    property string diffText: ""
    property bool diffHidden: false
    property bool diffBinary: false
    property string note: ""
    property bool noteOk: true

    // No read on open: the honest reason is shown above, before asking.
    onActiveChanged: if (active) page.publish()
    Component.onCompleted: if (active) page.publish()

    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.etcchanges = {
            changes: page.changes.map(c => String(c && c.path || c || "")),
            diff: page.diffPath,
            restored: page.restored.map(p => String(p || "")),
            error: page.noteOk ? "" : page.note
        };
        Ui.systemState = o;
    }
    function paths(list) {
        return (Array.isArray(list) ? list : []).map(function (x) { return String(x && x.path || x || ""); });
    }
    function queued(path) { return page.pending.indexOf(path) >= 0; }
    function run(args, verb) {
        page.busy = true;
        page.verb = verb;
        proc.command = ["python3", page.tool].concat(args);
        proc.running = false;
        proc.running = true;
    }
    function load() { page.run(["etc-list"], "etc-list"); }
    function showDiff(path) {
        page.currentPath = path;
        page.diffPath = "";
        page.diffText = "";
        page.diffHidden = false;
        page.diffBinary = false;
        page.run(["etc-diff", path], "etc-diff");
    }
    function apply(r) {
        if (!r || typeof r !== "object") r = {};
        if (page.verb === "etc-list") {
            if (r.error || r.ok === false) {
                page.note = r.error || Tr.t("Could not read the system changes");
                page.noteOk = false;
            } else {
                page.read = true;
                page.changes = Array.isArray(r.changes) ? r.changes : [];
                page.pending = paths(r.pending);
                page.note = "";
                page.noteOk = true;
            }
        } else if (page.verb === "etc-diff") {
            page.diffPath = String(r.path || page.currentPath);
            page.diffHidden = r.hidden === true;
            page.diffBinary = r.binary === true;
            page.diffText = (page.diffHidden || page.diffBinary) ? "" : String(r.diff || "");
            page.note = r.error || "";
            page.noteOk = !r.error && r.ok !== false;
        } else {
            const changed = r.queued === (page.verb === "etc-restore");
            page.note = r.error || (changed
                ? (page.verb === "etc-restore" ? Tr.t("Queued for the next start") : Tr.t("Taken off the list"))
                : Tr.t("Nothing changed"));
            page.noteOk = !r.error && r.ok !== false;
            if (page.noteOk && changed) {
                const p = String(r.path || page.currentPath);
                if (page.verb === "etc-restore") page.restored = page.restored.concat([p]);
                else page.pending = page.pending.filter(function (x) { return x !== p; });
            }
        }
        page.publish();
    }
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("The answer could not be read") }; }
                page.apply(r);
            }
        }
        stderr: StdioCollector { id: errOut }
        onExited: code => {
            page.busy = false;
            if (code !== 0) {
                page.note = errOut.text.trim().split("\n").pop() || Tr.t("The request did not finish");
                page.noteOk = false;
                page.publish();
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("System changes")
        hint: Tr.t("Files this machine changed after it was built. Reading them needs authorisation; the system's own layer is root-owned.")

        InfoBanner {
            Layout.fillWidth: true
            visible: !page.read && !page.busy
            tone: "info"
            text: Tr.t("Nothing has been read yet. The button below asks for root because the overlay's upper layer belongs to the system.")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Read system changes")
                enabled: !page.busy
                busy: page.busy
                onClicked: page.load()
            }
            Button { text: Tr.t("Check again"); enabled: page.read && !page.busy; onClicked: page.load() }
        }
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Asking for the system changes…"); iconSize: Theme.px(16) }
        EmptyState {
            Layout.fillWidth: true
            visible: page.read && !page.busy && page.changes.length === 0 && page.note === ""
            icon: "document-open-recent"
            title: Tr.t("No changes reported")
            subtitle: Tr.t("This machine has not changed any files in its own system layer.")
        }
        Repeater {
            model: page.changes
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                selected: page.currentPath === String(modelData.path || modelData)
                icon: "document-open-recent"
                title: String(modelData.path || modelData)
                subtitle: [String(modelData.kind || ""), modelData.secret ? Tr.t("holds a secret") : "",
                    modelData.protected ? Tr.t("protected") : "",
                    (page.queued(String(modelData.path || modelData)) || modelData.pending) ? Tr.t("queued for next start") : ""]
                    .filter(function (x) { return x !== ""; }).join("  ·  ")
                onClicked: page.showDiff(String(modelData.path || modelData))
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("This file")
        hint: Tr.t("A file is put back at the next start. It is never changed under the system that is running now.")
        visible: page.diffPath !== ""

        InfoBanner {
            Layout.fillWidth: true
            visible: page.diffHidden || page.diffBinary
            tone: page.diffHidden ? "warn" : "info"
            text: page.diffHidden ? Tr.t("Hidden: this file holds a secret")
                                  : Tr.t("This file is not text; its difference cannot be shown here.")
        }
        ScrollView {
            id: diffScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Theme.px(180), diffText.implicitHeight + Theme.px(12))
            visible: !page.diffHidden && !page.diffBinary && page.diffText !== ""
            clip: true
            Text {
                id: diffText
                width: diffScroll.width
                text: page.diffText
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: Theme.px(10) * Theme.fontScale
                wrapMode: Text.NoWrap
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            ConfirmButton {
                id: restoreFile
                visible: page.currentPath !== "" && !page.queued(page.currentPath)
                implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                text: Tr.t("Put this file back")
                armedText: Tr.t("Tap again to queue it")
                kind: "danger"
                Accessible.name: Tr.t("Put %1 back at next start").arg(page.currentPath)
                onConfirmed: page.run(["etc-restore", page.currentPath], "etc-restore")
            }
            Button {
                visible: page.currentPath !== "" && page.queued(page.currentPath)
                text: Tr.t("Take it off the list")
                Accessible.name: Tr.t("Take %1 off the list").arg(page.currentPath)
                onClicked: page.run(["etc-cancel", page.currentPath], "etc-cancel")
            }
        }
    }
    InfoBanner {
        Layout.fillWidth: true
        visible: page.note !== ""
        tone: page.noteOk ? "ok" : "error"
        text: page.note
    }
}
