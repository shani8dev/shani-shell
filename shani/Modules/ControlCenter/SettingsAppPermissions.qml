// Settings > Default apps > App permissions (after Flatseal): for each Flatpak
// app, what its sandbox lets it reach — the network, your home folder, all
// devices (webcams, game controllers), the system's files — as the app asked
// plus your changes, which are `flatpak override --user` and can be reset.
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
    property var apps: []                 // [{ id, name }]
    property string open: ""
    property var perms: ({})              // the open app's: { network, home, devices, host }
    onActiveChanged: if (active) list.running = true

    Process {
        id: list
        command: ["sh", "-c", 'command -v flatpak >/dev/null && flatpak list --app --columns=application,name 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: page.apps = text.trim().split("\n").filter(x => x.indexOf("\t") > 0)
                .map(l => ({ id: l.split("\t")[0], name: l.split("\t")[1] })).sort((a, b) => a.name.localeCompare(b.name))
        }
    }
    // flatpak info --show-permissions: the app's own [Context] with the user's overrides applied
    Process {
        id: show
        property string app: ""
        command: ["flatpak", "info", "--show-permissions", app]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text;
                const line = k => (new RegExp("^" + k + "=(.*)$", "m").exec(t) || [, ""])[1].split(";").filter(x => x);
                const fs = line("filesystems"), dev = line("devices"), sh = line("shared");
                page.perms = { network: sh.indexOf("network") >= 0, home: fs.some(x => /^(home|~)(:|$)/.test(x)) || fs.indexOf("host") >= 0,
                               devices: dev.indexOf("all") >= 0, host: fs.some(x => /^host(-os|-etc)?(:|$)/.test(x)) };
            }
        }
    }
    Process { id: change; onExited: { show.running = true; } }
    function openApp(id) {
        open = open === id ? "" : id;
        perms = {};
        if (open) { show.app = id; show.running = true; }
    }
    // what each switch writes
    readonly property var flags: ({
        network: [["--share=network"], ["--unshare=network"]],
        home: [["--filesystem=home"], ["--nofilesystem=home"]],
        devices: [["--device=all"], ["--nodevice=all"]],
        host: [["--filesystem=host"], ["--nofilesystem=host"]]
    })
    function set(key, on) {
        change.command = ["flatpak", "override", "--user"].concat(flags[key][on ? 0 : 1], [open]);
        change.running = true;
    }

    SectionTitle { Layout.fillWidth: true; text: "App permissions" }
    Text {
        Layout.fillWidth: true
        visible: page.apps.length === 0
        text: "No Flatpak apps installed."
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.apps
        ColumnLayout {
            id: arow
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            readonly property var entry: DesktopEntries.byId(modelData.id)
            ListRow {
                Layout.fillWidth: true
                icon: arow.entry && arow.entry.icon ? arow.entry.icon : "application-x-executable"
                title: arow.modelData.name
                subtitle: arow.modelData.id
                trailing: "›"
                onClicked: page.openApp(arow.modelData.id)
            }
            ColumnLayout {
                visible: page.open === arow.modelData.id && page.perms.network !== undefined
                Layout.leftMargin: 28
                Layout.fillWidth: true
                spacing: 2
                SwitchRow { Layout.fillWidth: true; text: "Internet"; checked: !!page.perms.network; onToggled: on => page.set("network", on) }
                SwitchRow { Layout.fillWidth: true; text: "Your home folder"; hint: "otherwise only what you open with it"; checked: !!page.perms.home; onToggled: on => page.set("home", on) }
                SwitchRow { Layout.fillWidth: true; text: "All devices"; hint: "webcams, game controllers, USB"; checked: !!page.perms.devices; onToggled: on => page.set("devices", on) }
                SwitchRow { Layout.fillWidth: true; text: "The whole system's files"; checked: !!page.perms.host; onToggled: on => page.set("host", on) }
                Button {
                    text: "Back to what the app asked for"
                    onClicked: { change.command = ["flatpak", "override", "--user", "--reset", page.open]; change.running = true; }
                }
            }
        }
    }
}
