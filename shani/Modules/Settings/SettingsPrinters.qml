// Settings > Printers (Cassini hands its Printers page to this one inside the
// shell): the printers CUPS knows, which one is yours by default, a test page,
// your waiting jobs, adding one (system-config-printer, which finds network
// printers itself) and removing one (an administrator's, through polkit).
// CUPS's own commands throughout: lpstat, lpoptions, lp, cancel, lpadmin.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    property var printers: []            // [{ name, state, enabled, jobs }]
    property string defaultName: ""
    property bool cups: true
    property string note: ""
    onActiveChanged: if (active) list.running = true
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) list.running = true

    function run(cmd, done) { act.command = cmd; act.done = done || ""; act.running = true; }
    Process {
        id: list
        // lpstat -d is the person's default where they set one (lpoptions -d),
        // else the system's; plain `lpoptions` prints options, not a name
        command: ["sh", "-c", '[ -S /run/cups/cups.sock ] || { echo nocups; exit 0; }
            lpstat -p 2>/dev/null; lpstat -o 2>/dev/null | sed "s/^/job /"
            echo "default $(lpstat -d 2>/dev/null | sed -n "s/.*: //p")"']
        stdout: StdioCollector {
            onStreamFinished: {
                page.cups = text.indexOf("nocups") < 0;
                const ps = [], jobs = {};
                for (const l of text.split("\n")) {
                    let m = /^printer (\S+) (?:is )?(.*)$/.exec(l);
                    if (m) ps.push({ name: m[1], state: /disabled/.test(m[2]) ? Tr.t("Paused") : /printing/.test(m[2]) ? Tr.t("Printing") : Tr.t("Ready"), enabled: !/disabled/.test(m[2]), jobs: 0 });
                    m = /^job (\S+)-\d+\s/.exec(l);
                    if (m) jobs[m[1]] = (jobs[m[1]] || 0) + 1;
                    m = /^default (\S*)$/.exec(l);
                    if (m) page.defaultName = m[1];
                }
                ps.forEach(p => p.jobs = jobs[p.name] || 0);
                page.printers = ps;
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
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Printers") }
    Text {
        visible: !page.cups || page.printers.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: !page.cups ? Tr.t("The printing service (CUPS) is not running.")
            : Tr.t("No printers yet. Printers on the network usually appear by themselves; Add a printer finds the rest.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.printers
        ColumnLayout {
            id: pr
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            readonly property bool isDefault: modelData.name === page.defaultName
            RowLayout {
                spacing: 10
                Icon { name: "printer"; size: 20; color: pr.isDefault ? Theme.accent : Theme.text }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: pr.modelData.name.replace(/_/g, " "); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
                    Text {
                        text: pr.modelData.state + (pr.isDefault ? " · " + Tr.t("your default") : "")
                              + (pr.modelData.jobs ? " · " + Tr.t("%1 waiting", pr.modelData.jobs) : "")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Choice { visible: !pr.isDefault; text: Tr.t("Make default"); onClicked: page.run(["lpoptions", "-d", pr.modelData.name], Tr.t("%1 is your default printer", pr.modelData.name)) }
                Choice { text: Tr.t("Print a test page"); onClicked: page.run(["lp", "-d", pr.modelData.name, "/usr/share/cups/data/testprint"], Tr.t("Test page sent")) }
                Choice { visible: pr.modelData.jobs > 0; text: Tr.t("Cancel my jobs"); onClicked: page.run(["cancel", "-u", Quickshell.env("USER") || "", pr.modelData.name], Tr.t("Your jobs were cancelled")) }
                Choice { text: Tr.t("Queue"); onClicked: { Ui.closeAll(); Printing.openQueue(); } }
                Choice { text: Tr.t("Remove…"); onClicked: page.run(["pkexec", "lpadmin", "-x", pr.modelData.name], Tr.t("%1 removed", pr.modelData.name)) }
            }
        }
    }
    RowLayout {
        spacing: 8
        Button { text: Tr.t("Add a printer…"); onClicked: { Ui.closeAll(); Quickshell.execDetached(["system-config-printer"]); } }
        Button { text: Tr.t("Refresh"); onClicked: list.running = true }
    }
    Text {
        visible: page.note !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: page.note
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
