// Software > Command-line tools: git, Node.js, ripgrep and the rest, from Nix
// into your own profile (~/.nix-profile, on the @nix subvolume) the way
// shani-docs' software/nix.md does it - kept across OS updates and rollbacks,
// no password. The first install adds the nixpkgs channel. This was Settings >
// Developer tools, which ran the system's package manager (read-only on
// ShaniOS). Containers are the Containers app's (rootless Podman), not Docker.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: page
    spacing: Theme.px(8)
    property bool active: false
    property var store: null                 // the Software window: its bridge and job queue
    property var tools: []
    property bool loaded: false
    readonly property bool busy: !!store && store.job.indexOf("nix:") === 0

    function load() {
        if (!store) return;
        store.ask(["nix-tools"], r => {
            page.tools = Array.isArray(r) ? r : [];
            page.loaded = true;
            Ui.softwareTools = page.tools.filter(t => t.installed).map(t => t.attr);
        });
    }
    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()
    // a finished install or removal: look again
    Connections {
        target: page.store
        function onJobChanged() { if (page.active && page.store.job === "") page.load(); }
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.t("Everyday command-line tools, installed just for you with Nix. They stay through system updates and need no password.")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("body")
        }
        Button {
            visible: page.tools.some(t => t.nix)
            text: Tr.t("Update them")
            enabled: !!page.store && page.store.job === ""
            onClicked: page.store.runJob(["nix-upgrade"], "nix:all")
        }
    }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: contentHeight
        clip: true
        spacing: 2
        model: page.tools
        delegate: RowLayout {
            id: row
            required property var modelData
            width: list.width
            spacing: Theme.px(10)
            Accessible.role: Accessible.ListItem
            Accessible.name: row.modelData.name + ", " + (row.modelData.installed ? Tr.t("installed") : Tr.t("not installed"))
            Icon { name: "utilities-terminal"; size: Theme.px(28); color: row.modelData.installed ? Theme.accent : Theme.dim }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: row.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                Text { Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small")
                    text: row.modelData.about + "  ·  " + row.modelData.cmd
                        + (row.modelData.installed && !row.modelData.nix ? "  ·  " + Tr.t("part of the system") : "") }
            }
            Button {
                visible: !row.modelData.installed || row.modelData.nix
                text: page.store && page.store.job === "nix:" + row.modelData.attr ? Tr.t("Working…")
                    : row.modelData.nix ? Tr.t("Remove") : Tr.t("Install")
                kind: row.modelData.nix ? "outline" : "primary"
                enabled: !!page.store && page.store.job === ""
                onClicked: page.store.runJob([row.modelData.nix ? "nix-remove" : "nix-install", row.modelData.attr], "nix:" + row.modelData.attr)
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.t("Need a whole other distribution, or containers? The Containers app makes Distrobox toolboxes and runs Podman.")
            color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("small")
        }
        Button { text: Tr.t("Containers"); flat: true; onClicked: { Ui.closeAll(); Ui.containers = true; } }
    }
}
