// Settings > Printers (the shell owns printers inside the
// shell): the printers CUPS knows, which one is yours by default, a test page,
// your waiting jobs, adding one and removing one (an administrator's, through
// polkit). Adding: the printers on the network that announce themselves (CUPS's
// ippfind, mDNS), or an address typed in, set up driverless - IPP Everywhere,
// what every printer of the last decade speaks (`lpadmin -m everywhere`), so no
// system-config-printer and no driver to pick.
// CUPS's own commands throughout: lpstat, lpoptions, lp, cancel, lpadmin, ippfind.
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
    property var printers: []            // [{ name, state, enabled, jobs }]
    property string defaultName: ""
    property bool cups: true
    property string note: ""
    property var devices: []             // the addresses the printers already set up print to
    property var found: null             // [{ name, uri }] while adding; null = not adding
    property bool finding: false
    property var pendingAuth: null       // credentials stored after lpadmin succeeds
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property bool cupsBrowsed: false
    property bool cupsBrowsedLoaded: false
    onActiveChanged: if (active) { list.running = true; optsRead.running = true; cbGet.running = false; cbGet.running = true; }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) { list.running = true; optsRead.running = true; cbGet.running = false; cbGet.running = true; }
    Process { id: cbGet; command: page.adminCmd.concat(["cups-browsed-get"]); stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); page.cupsBrowsed = !!d.enabled; page.cupsBrowsedLoaded = true; } catch(e) {} } } }
    Process { id: cbSet; stdinEnabled: true; property string payload: ""; onStarted: { write(payload + "\n"); stdinEnabled = false; } onExited: code => { stdinEnabled = true; cbGet.running = false; cbGet.running = true; if (code !== 0) page.note = Tr.t("Could not change printer discovery"); } }

    function run(cmd, done) { act.command = cmd; act.done = done || ""; act.running = true; }
    // each printer's defaults for you (system-config-printer's Printer Options):
    // paper, two-sided, colour - lpoptions keeps them in ~/.cups/lpoptions, no administrator
    property var opts: ({})              // name -> { media, sides, "print-color-mode", "printer-is-shared" }
    Process {
        id: optsRead
        command: ["sh", "-c", 'for p in $(lpstat -p 2>/dev/null | awk "/^printer /{print \\$2}"); do printf "%s\t%s\n" "$p" "$(lpoptions -p "$p" 2>/dev/null)"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                for (const l of text.split("\n")) {
                    const [name, rest] = l.split("\t");
                    if (!name) continue;
                    const o = {};
                    // (no String.matchAll in Qt's JavaScript: a loop of exec)
                    const re = /([\w-]+)=('[^']*'|\S+)/g;
                    let m;
                    while ((m = re.exec(rest || "")) !== null) o[m[1]] = m[2].replace(/^'|'$/g, "");
                    out[name] = o;
                }
                page.opts = out;
                Ui.printerOptions = Object.keys(out).map(n => n + ":" + (out[n].media || "") + ":" + (out[n].sides || "") + ":" + (out[n]["print-color-mode"] || ""));
            }
        }
    }
    function setOpt(name, key, value) { page.run(["lpoptions", "-p", name, "-o", key + "=" + value], Tr.t("%1: saved as your default", name.replace(/_/g, " "))); }
    Process {
        id: list
        // lpstat -d is the person's default where they set one (lpoptions -d),
        // else the system's; plain `lpoptions` prints options, not a name
        command: ["sh", "-c", '[ -S /run/cups/cups.sock ] || { echo nocups; exit 0; }
            lpstat -p 2>/dev/null; lpstat -o 2>/dev/null | sed "s/^/job /"; lpstat -v 2>/dev/null
            echo "default $(lpstat -d 2>/dev/null | sed -n "s/.*: //p")"']
        stdout: StdioCollector {
            onStreamFinished: {
                page.cups = text.indexOf("nocups") < 0;
                const ps = [], jobs = {}, devs = [];
                for (const l of text.split("\n")) {
                    let m = /^printer (\S+) (?:is )?(.*)$/.exec(l);
                    if (m) ps.push({ name: m[1], state: /disabled/.test(m[2]) ? Tr.t("Paused") : /printing/.test(m[2]) ? Tr.t("Printing") : Tr.t("Ready"), enabled: !/disabled/.test(m[2]), jobs: 0 });
                    m = /^job (\S+)-\d+\s/.exec(l);
                    if (m) jobs[m[1]] = (jobs[m[1]] || 0) + 1;
                    m = /^device for [^:]+: (\S+)$/.exec(l);
                    if (m) devs.push(m[1]);
                    m = /^default (\S*)$/.exec(l);
                    if (m) page.defaultName = m[1];
                }
                ps.forEach(p => p.jobs = jobs[p.name] || 0);
                page.printers = ps;
                page.devices = devs;
                // for the tests: name, state, default, waiting jobs
                Ui.printersSeen = ps.map(p => p.name + ":" + (p.name === page.defaultName ? "default:" : "") + p.jobs);
            }
        }
    }
    Process {
        id: act
        property string done: ""
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            page.note = code === 0 ? act.done : (actErr.text.trim().split("\n").pop() || Tr.t("That did not work"));
            list.running = true;
            optsRead.running = true;
            // lpoptions is per-user, so the credentials are stored only once
            // the administrator's lpadmin has created the queue
            const a = page.pendingAuth;
            page.pendingAuth = null;
            if (code === 0 && a) {
                authStore.command = ["lpoptions", "-p", a.name, "-o", "auth-info=" + a.user + ":" + a.password];
                authStore.running = true;
            }
        }
    }
    Process {
        id: authStore
        onExited: code => {
            if (code !== 0) page.note = Tr.t("Printer added, but the credentials could not be saved");
        }
    }

    // the printers the network announces (IPP over mDNS), each: name<TAB>address
    Process {
        id: finder
        command: ["sh", "-c", "exec ippfind _ipp._tcp _ipps._tcp -T 4 --exec printf '%s\\t%s\\n' '{service_name}' '{}' ';' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, out = [];
                for (const l of text.split("\n")) {
                    const [name, uri] = l.split("\t");
                    // (lpstat -v prints a file: address without its "file:")
                    if (!uri || seen[name] || page.devices.indexOf(uri) >= 0 || page.devices.indexOf(uri.replace(/^file:/, "")) >= 0) continue;
                    seen[name] = true;               // the same printer over ipp and ipps: once
                    out.push({ name: name, uri: uri });
                }
                page.found = out;
                page.finding = false;
                Ui.printersFound = out.map(p => p.name);
            }
        }
    }
    function startAdding() { page.found = []; page.finding = true; Ui.printersFound = []; finder.running = true; }
    // a queue name CUPS takes: letters, digits, - and _
    function queueName(s) { return (s || "Printer").replace(/[^A-Za-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 100) || "Printer"; }
    // a typed address: a host name or IP becomes ipp://<it>/ipp/print
    function uriOf(s) {
        s = s.trim();
        if (!s) return "";
        return /^[a-z]+:\/\//.test(s) ? s : "ipp://" + s + "/ipp/print";
    }
    function add(name, uri, user, password) {
        if (!uri) return;
        page.found = null;
        const q = queueName(name);
        const args = ["pkexec", "lpadmin", "-p", q, "-E", "-v", uri, "-m", "everywhere"];
        if (user && password) args.push("-o", "auth-info-required=username,password");
        page.run(args, Tr.t("%1 added", name));
        page.pendingAuth = (user && password) ? { name: q, user: user, password: password } : null;
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Printers") }
    SwitchRow {
        Layout.fillWidth: true
        visible: page.cupsBrowsedLoaded
        text: Tr.t("Discover network printers automatically")
        hint: Tr.t("cups-browsed service")
        checked: page.cupsBrowsed
        onToggled: on => { cbSet.payload = JSON.stringify({ enabled: on }); cbSet.command = page.adminCmd.concat(["cups-browsed-set"]); cbSet.running = true; }
    }
    Text {
        visible: !page.cups || page.printers.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: !page.cups ? Tr.t("The printing service (CUPS) is not running.")
            : Tr.t("No printers yet. Printers on the network usually appear by themselves; Add a printer finds the rest.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    Repeater {
        model: page.printers
        ColumnLayout {
            id: pr
            required property var modelData
            Layout.fillWidth: true
            spacing: Theme.px(4)
            property bool confirming: false
            Timer { interval: 3000; running: pr.confirming; onTriggered: pr.confirming = false }
            readonly property bool isDefault: modelData.name === page.defaultName
            RowLayout {
                spacing: Theme.px(10)
                Icon { name: "printer"; size: Theme.px(20); color: pr.isDefault ? Theme.accent : Theme.text }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: pr.modelData.name.replace(/_/g, " "); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                    Text {
                        text: pr.modelData.state + (pr.isDefault ? " · " + Tr.t("your default") : "")
                              + (pr.modelData.jobs ? " · " + Tr.t("%1 waiting", pr.modelData.jobs) : "")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice { visible: !pr.isDefault; text: Tr.t("Make default"); onClicked: page.run(["lpoptions", "-d", pr.modelData.name], Tr.t("%1 is your default printer", pr.modelData.name)) }
                Choice { text: Tr.t("Print a test page"); onClicked: page.run(["lp", "-d", pr.modelData.name, "/usr/share/cups/data/testprint"], Tr.t("Test page sent")) }
                Choice { visible: pr.modelData.jobs > 0; text: Tr.t("Cancel my jobs"); onClicked: page.run(["cancel", "-u", Quickshell.env("USER") || "", pr.modelData.name], Tr.t("Your jobs were cancelled")) }
                Choice { text: Tr.t("Queue"); onClicked: { Ui.closeAll(); Printing.openQueue(); } }
                Choice {
                    danger: true
                    text: pr.confirming ? Tr.t("Tap again to remove") : Tr.t("Remove…")
                    onClicked: {
                        if (pr.confirming) page.run(["pkexec", "lpadmin", "-x", pr.modelData.name], Tr.t("%1 removed", pr.modelData.name));
                        pr.confirming = !pr.confirming;
                    }
                }
            }
            // your defaults for it: paper, two-sided, colour; and whether others on the network may use it
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                readonly property var o: page.opts[pr.modelData.name] || ({})
                Repeater {
                    model: [["media", "A4", "A4"], ["media", "Letter", Tr.t("Letter")],
                            ["sides", "one-sided", Tr.t("One side")], ["sides", "two-sided-long-edge", Tr.t("Both sides")],
                            ["print-color-mode", "color", Tr.t("Colour")], ["print-color-mode", "monochrome", Tr.t("Black and white")]]
                    Choice {
                        required property var modelData
                        text: modelData[2]
                        selected: (parent.o[modelData[0]] || "") === modelData[1]
                        onClicked: page.setOpt(pr.modelData.name, modelData[0], modelData[1])
                    }
                }
                Choice {
                    text: Tr.t("Shared on the network")
                    selected: (parent.o["printer-is-shared"] || "") === "true"
                    onClicked: page.run(["pkexec", "lpadmin", "-p", pr.modelData.name, "-o", "printer-is-shared=" + (selected ? "false" : "true")],
                                        selected ? Tr.t("%1 is no longer shared", pr.modelData.name) : Tr.t("%1 is shared on the network", pr.modelData.name))
                }
            }
        }
    }
    RowLayout {
        spacing: Theme.px(8)
        Button { text: page.found === null ? Tr.t("Add a printer…") : Tr.t("Cancel"); onClicked: page.found === null ? page.startAdding() : page.found = null }
        Button { text: Tr.t("Refresh"); onClicked: list.running = true }
    }
    // adding: what the network offers, or an address typed in
    ColumnLayout {
        visible: page.found !== null
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: page.finding ? Tr.t("Looking on the network…")
                : (page.found || []).length ? Tr.t("Printers on the network:")
                : Tr.t("No other printer is announcing itself. Type its address (as on its own screen or settings page):")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: page.found || []
                Choice {
                    required property var modelData
                    text: modelData.name
                    onClicked: page.add(modelData.name, modelData.uri, userField.text.trim(), passField.text)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField { id: addr; Layout.fillWidth: true; placeholderText: Tr.t("Address, e.g. 192.168.1.20"); onAccepted: page.add(text.trim(), page.uriOf(text), userField.text.trim(), passField.text) }
            Button { text: Tr.t("Add"); enabled: addr.text.trim() !== ""; onClicked: page.add(addr.text.trim(), page.uriOf(addr.text), userField.text.trim(), passField.text) }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField { id: userField; Layout.fillWidth: true; placeholderText: Tr.t("Username (optional)") }
            TextField { id: passField; Layout.fillWidth: true; placeholderText: Tr.t("Password (optional)"); secret: true }
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.t("Credentials are saved in your CUPS settings (~/.cups/lpoptions).")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
    }
    Text {
        visible: page.note !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: page.note
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
}
