// Settings > DNS: which name server actually answers, and the one to use.
// Read with bridge/system_net.py (resolver); changed with the shell's own
// admin tool (resolved-set), which asks for authorisation before writing.
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
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    readonly property string googleServers: "8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844"
    readonly property string cloudflareServers: "1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001"

    property string conf: ""
    property string target: ""
    property var servers: []
    property var search: []
    property string resolved: "unknown"
    property var links: []
    property string error: ""
    property string selection: "auto"
    property string note: ""
    property bool noteOk: false
    property bool busy: false

    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.dns = { target: page.target, servers: page.servers, resolved: page.resolved, error: page.error };
        Ui.systemState = o;
    }
    function stateText(v) {
        return v === "active" ? Tr.t("Answering now") : v === "inactive" ? Tr.t("Not answering") : Tr.t("Not checked");
    }
    function classify(s) {
        const v = Array.isArray(s) ? s.join(" ") : String(s || "");
        if (!v.trim()) return "auto";
        if (v.indexOf("8.8.8.8") >= 0) return "google";
        if (v.indexOf("1.1.1.1") >= 0) return "cloudflare";
        return "custom";
    }
    function load() {
        page.busy = true;
        readProc.running = false; readProc.running = true;
    }
    Process {
        id: readProc
        command: ["python3", page.tool, "resolver"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text) || {}; } catch (e) { r = { error: Tr.t("Could not read the name server settings") }; }
                page.conf = r.conf || "";
                page.target = r.target || "";
                page.servers = Array.isArray(r.servers) ? r.servers : [];
                page.search = Array.isArray(r.search) ? r.search : [];
                page.resolved = r.resolved || "unknown";
                page.links = Array.isArray(r.links) ? r.links : [];
                page.error = r.error || "";
                page.selection = page.classify(page.servers);
                customField.text = page.selection === "custom" ? page.servers.join(" ") : "";
                page.busy = false;
                page.publish();
            }
        }
        onExited: page.busy = false
    }
    Process {
        id: saveProc
        stdinEnabled: true
        property string payload: ""
        stderr: StdioCollector { id: saveErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            page.busy = false;
            page.noteOk = code === 0;
            page.note = code === 0 ? Tr.t("Name server saved") : (saveErr.text.trim().split("\n").pop() || Tr.t("Could not save the name server"));
            if (code === 0) page.load(); else page.publish();
        }
    }
    function apply() {
        const s = {};
        if (page.selection === "google") s.DNS = page.googleServers;
        else if (page.selection === "cloudflare") s.DNS = page.cloudflareServers;
        else if (page.selection === "custom") s.DNS = customField.text.trim();
        page.busy = true; page.note = "";
        saveProc.payload = JSON.stringify({ settings: s });
        saveProc.command = page.adminCmd.concat(["resolved-set"]);
        saveProc.running = true;
    }
    function pick(v) { page.selection = v; page.note = ""; page.publish(); }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Which name server answers")
        hint: Tr.t("The system may be using a file chosen elsewhere. This is the one in force right now.")
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Loading…"); iconSize: Theme.px(16) }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "network-server"; title: Tr.t("Answering state"); trailing: page.stateText(page.resolved) }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "network-server"; title: Tr.t("Server in use"); trailing: page.servers.join(" ") || Tr.t("Not found") }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "text-x-generic"; title: Tr.t("Settings file in use"); subtitle: page.conf; trailing: page.target }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "network-workgroup"; title: Tr.t("Network links"); subtitle: Tr.t("Connections these name servers belong to"); trailing: page.links.join(" ") }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "edit-find"; title: Tr.t("Search domains"); subtitle: Tr.t("Short names are looked up inside these"); trailing: page.search.join(" ") }
        InfoBanner { Layout.fillWidth: true; visible: page.error !== ""; tone: "error"; text: page.error; accessibleRole: Accessible.AlertMessage }
    }
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Choose name servers")
        hint: Tr.t("Changing this writes a system file, so your system will ask you to approve it first.")
        Picks {
            label: Tr.t("Use")
            options: [
                { label: Tr.t("From the network"), value: "auto" },
                { label: Tr.t("Google"), value: "google" },
                { label: Tr.t("Cloudflare"), value: "cloudflare" },
                { label: Tr.t("Custom"), value: "custom" }
            ]
            current: page.selection
            onPicked: v => page.pick(v)
        }
        TextField {
            id: customField
            Layout.fillWidth: true
            visible: page.selection === "custom"
            label: Tr.t("Your own name server")
            placeholder: Tr.t("One or more addresses, separated by spaces")
            error: visible && text.trim() !== "" && !/^[\d.:a-fA-F\s]+$/.test(text.trim()) ? Tr.t("Use addresses such as 192.168.1.1") : ""
            onAccepted: if (!error) page.apply()
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            Item { Layout.fillWidth: true }
            Button {
                text: Tr.t("Apply"); kind: "primary"
                enabled: !page.busy && (page.selection !== "custom" || (customField.text.trim() !== "" && !customField.error))
                busy: page.busy
                onClicked: page.apply()
            }
        }
        InfoBanner { Layout.fillWidth: true; visible: page.note !== ""; tone: page.noteOk ? "ok" : "error"; text: page.note }
    }
}
