// Settings > Keyboard & input: compose and Caps Lock (xkb options), every
// keyboard shortcut — read from niri's own config, so the list is what the
// keys do — and the person's own: a key and a command, written as niri binds.
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
    readonly property var d: Settings.data
    readonly property string configPath: Quickshell.env("SHANI_NIRI_CONFIG") || "/etc/niri/config.kdl"
    property var binds: []                // [{ key, what }]

    component Picks: ColumnLayout {
        id: picks
        property string label
        property var options: []
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 6
        Text { text: picks.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: picks.options
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: String(picks.current) === String(modelData.value)
                    onClicked: picks.picked(modelData.value)
                }
            }
        }
    }

    // "    Mod+T hotkey-overlay-title="Terminal" { spawn "foot"; }" → Mod+T: Terminal
    FileView {
        path: page.active ? page.configPath : ""
        printErrors: false
        onLoaded: {
            const out = [];
            let inBinds = false;
            for (const line of text().split("\n")) {
                if (/^binds\s*\{/.test(line)) { inBinds = true; continue; }
                if (inBinds && /^\}/.test(line)) { inBinds = false; continue; }
                const m = inBinds && /^\s+([A-Za-z0-9+_]+)((?:\s+[\w-]+=(?:"[^"]*"|\S+))*)\s*\{\s*(.*?);?\s*\}\s*$/.exec(line);
                if (!m)
                    continue;
                const title = /hotkey-overlay-title="([^"]*)"/.exec(m[2]);
                out.push({ key: m[1], what: title ? title[1] : m[3].replace(/^spawn\s+/, "run ").replace(/"/g, "").replace(/-/g, " ") });
            }
            page.binds = out;
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Special keys") }
    Picks {
        label: Tr.t("Compose key (types é as Compose e ', ₹ as Compose = R …)")
        options: [{ label: Tr.t("None"), value: "" }, { label: Tr.t("Right Alt"), value: "ralt" }, { label: Tr.t("Right Super"), value: "rwin" }, { label: Tr.t("Menu"), value: "menu" }, { label: Tr.t("Caps Lock"), value: "caps" }]
        current: page.d.kbCompose
        onPicked: v => page.d.kbCompose = v
    }
    Picks {
        label: Tr.t("Caps Lock")
        options: [{ label: Tr.t("Caps Lock"), value: "" }, { label: Tr.t("Ctrl"), value: "ctrl:nocaps" }, { label: Tr.t("Escape"), value: "caps:escape" }, { label: Tr.t("Backspace"), value: "caps:backspace" }]
        current: page.d.kbCaps
        onPicked: v => page.d.kbCaps = v
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Keyboard shortcuts") }
    TextField { id: find; Layout.fillWidth: true; placeholder: Tr.t("Find a shortcut — screenshot, workspace, volume…") }
    Repeater {
        model: page.binds.concat(Array.from(page.d.customBinds || []).map(b => ({ key: b.key, what: (b.title || b.command) + "  (yours)" })))
            .filter(b => { const q = find.text.trim().toLowerCase(); return q === "" || (b.key + " " + b.what).toLowerCase().indexOf(q) >= 0; })
            .slice(0, find.text.trim() === "" ? 14 : 40)
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: keyText.implicitWidth + 14
                implicitHeight: 24
                radius: 6
                color: Theme.hover
                border.color: Theme.stroke
                Text { id: keyText; anchors.centerIn: parent; text: parent.parent.modelData.key.replace(/\+/g, " + "); color: Theme.text; font.family: Theme.mono; font.pixelSize: 11 * Theme.fontScale }
            }
            Text { Layout.fillWidth: true; text: parent.modelData.what; color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Your shortcuts") }
    Repeater {
        model: page.d.customBinds
        ListRow {
            id: cb
            required property var modelData
            required property int index
            Layout.fillWidth: true
            icon: "input-keyboard"
            title: modelData.key
            subtitle: (modelData.title ? modelData.title + " — " : "") + modelData.command
            IconButton {
                icon: "edit-delete"
                size: 24
                Accessible.name: "Remove " + cb.modelData.key
                onClicked: page.d.customBinds = Array.from(page.d.customBinds).filter((x, i) => i !== cb.index)
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField { id: newKey; Layout.preferredWidth: 130; placeholder: Tr.t("Mod+Alt+T") }
        TextField { id: newCmd; Layout.fillWidth: true; placeholder: Tr.t("Command — e.g. firefox --private-window") }
        Button {
            text: Tr.t("Add")
            readonly property string key: newKey.text.trim()
            readonly property bool taken: page.binds.some(b => b.key.toLowerCase() === key.toLowerCase())
            enabled: /^[A-Za-z0-9+_]+$/.test(key) && newCmd.text.trim() !== "" && !taken
            onClicked: {
                page.d.customBinds = Array.from(page.d.customBinds || []).concat([{ key: key, title: "", command: newCmd.text.trim() }]);
                newKey.text = "";
                newCmd.text = "";
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: newKey.text.trim() !== "" && page.binds.some(b => b.key.toLowerCase() === newKey.text.trim().toLowerCase())
        text: newKey.text.trim() + " already does something."
        color: Theme.danger
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
