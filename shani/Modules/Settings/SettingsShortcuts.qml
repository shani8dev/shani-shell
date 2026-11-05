// Keyboard shortcuts: the ones niri really has (read from its config, as niri's own
// overlay names them - a hand-written list here had gone wrong: it called Emoji
// "Settings" and listed keys bound to nothing), and shortcuts of your own: press
// the keys, pick what they do - an app, or one of a few things people want.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import "NiriBinds.js" as NiriBinds

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data

    // ---- what niri has ----------------------------------------------------------
    property var binds: []                 // [{ key, title }]
    readonly property string configPath: Quickshell.env("SHANI_NIRI_CONFIG") || ""
    Process {
        running: page.active
        command: ["sh", "-c", 'f="$1"; [ -n "$f" ] || { f="$HOME/.config/niri/config.kdl"; [ -f "$f" ] || f=/etc/niri/config.kdl; }; cat "$f"', "sh", page.configPath]
        stdout: StdioCollector { onStreamFinished: { page.binds = NiriBinds.parse(text); Ui.shortcutsListed = page.binds.length; } }
    }
    function norm(k) { return String(k).toLowerCase().split("+").sort().join("+"); }
    function takenBy(k) {
        const n = norm(k);
        const b = binds.find(x => norm(x.key) === n);
        if (b) return b.title;
        const c = Array.from(d.customBinds || []).find(x => norm(x.key) === n);
        return c ? (c.title || c.command) : "";
    }
    function pretty(k) { return String(k).replace(/\bMod\b/, "Super").replace(/\+/g, " + "); }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Keyboard shortcuts") }
    TextField { id: find; Layout.fillWidth: true; placeholder: Tr.t("Find a shortcut - screenshot, close, workspace…") }
    Repeater {
        model: page.binds.filter(b => { const q = find.text.trim().toLowerCase(); return q === "" || b.title.toLowerCase().indexOf(q) >= 0 || b.key.toLowerCase().indexOf(q) >= 0; })
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 12
            Text { text: page.pretty(modelData.key); color: Theme.text; font.family: Theme.mono; font.pixelSize: 11 * Theme.fontScale; Layout.preferredWidth: 190 }
            Text { text: modelData.title; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.fillWidth: true; elide: Text.ElideRight
                   Accessible.role: Accessible.StaticText; Accessible.name: modelData.title }
        }
    }

    // ---- your own ---------------------------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Your own shortcuts") }
    Repeater {
        model: Array.from(page.d.customBinds || [])
        ListRow {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            icon: "input-keyboard"
            title: page.pretty(modelData.key)
            subtitle: modelData.title || modelData.command
            onClicked: page.d.customBinds = Array.from(page.d.customBinds).filter((_, i) => i !== index)
            Hint { text: Tr.t("Click to remove it") }
        }
    }

    // 1. press the keys
    property string combo: ""
    property bool capturing: false
    readonly property string conflict: combo === "" ? "" : takenBy(combo)
    function keyName(e) {
        if (e.key >= Qt.Key_A && e.key <= Qt.Key_Z) return String.fromCharCode(e.key);
        if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) return String.fromCharCode(e.key);
        if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F12) return "F" + (e.key - Qt.Key_F1 + 1);
        return ({ [Qt.Key_Space]: "Space", [Qt.Key_Return]: "Return", [Qt.Key_Tab]: "Tab", [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right",
                  [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up",
                  [Qt.Key_PageDown]: "Page_Down", [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert", [Qt.Key_Comma]: "Comma",
                  [Qt.Key_Period]: "Period", [Qt.Key_Slash]: "Slash", [Qt.Key_Minus]: "Minus", [Qt.Key_Equal]: "Equal",
                  [Qt.Key_Semicolon]: "Semicolon", [Qt.Key_Apostrophe]: "Apostrophe", [Qt.Key_BracketLeft]: "BracketLeft",
                  [Qt.Key_BracketRight]: "BracketRight", [Qt.Key_Backslash]: "Backslash", [Qt.Key_QuoteLeft]: "Grave" })[e.key] || "";
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 48
        radius: 12
        color: page.capturing ? Theme.accentSoft : Theme.hover
        border.color: page.conflict !== "" ? Theme.danger : page.capturing ? Theme.accent : "transparent"
        focus: page.capturing
        Accessible.role: Accessible.Button
        Accessible.name: Tr.t("Press the keys for a new shortcut")
        Accessible.onPressAction: { page.capturing = true; forceActiveFocus(); }
        Text {
            anchors.centerIn: parent
            text: page.capturing && page.combo === "" ? Tr.t("Press the keys now - for example Super and a letter")
                : page.combo !== "" ? page.pretty(page.combo) : Tr.t("Click here, then press the keys for a new shortcut")
            color: page.combo !== "" ? Theme.text : Theme.dim
            font.family: page.combo !== "" ? Theme.mono : Theme.font
            font.pixelSize: 13 * Theme.fontScale
        }
        MouseArea { anchors.fill: parent; onClicked: { page.capturing = true; page.combo = ""; parent.forceActiveFocus(); } }
        Keys.onPressed: e => {
            if (!page.capturing)
                return;
            const k = page.keyName(e);
            if (k === "")
                return;                     // a modifier on its own: wait for the key
            const mods = (e.modifiers & Qt.MetaModifier ? ["Mod"] : []).concat(e.modifiers & Qt.ControlModifier ? ["Ctrl"] : [])
                .concat(e.modifiers & Qt.AltModifier ? ["Alt"] : []).concat(e.modifiers & Qt.ShiftModifier ? ["Shift"] : []);
            if (mods.length === 0 && !/^F\d+$/.test(k))
                return;                     // a bare letter would stop it being typed anywhere
            page.combo = mods.concat([k]).join("+");
            page.capturing = false;
            e.accepted = true;
        }
    }
    Text {
        visible: page.conflict !== ""
        Layout.fillWidth: true
        text: Tr.t("That one is already taken: %1. Try another.").arg(page.conflict)
        color: Theme.danger
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }

    // 2. what it does: an app, a few ready ones, or a command of your own
    property var action: null              // { title, command }
    Flow {
        visible: page.combo !== "" && page.conflict === ""
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [{ title: Tr.t("Open a terminal"), command: page.d.terminal || "foot" },
                    { title: Tr.t("Open my files"), command: "xdg-open \"$HOME\"" },
                    { title: Tr.t("Screenshot of the whole screen"), command: "niri msg action screenshot-screen" },
                    { title: Tr.t("Lock the screen"), command: "qs -c shani ipc call shani lock" },
                    { title: Tr.t("Do Not Disturb on or off"), command: "qs -c shani ipc call shani dnd" }]
            Choice {
                required property var modelData
                text: modelData.title
                selected: page.action !== null && page.action.command === modelData.command
                onClicked: page.action = modelData
            }
        }
    }
    AppPicker {
        visible: page.combo !== "" && page.conflict === ""
        Layout.fillWidth: true
        label: Tr.t("Or open an app")
        onPicked: id => {
            const e = DesktopEntries.byId(id);
            page.action = { title: Tr.t("Open %1").arg(e ? e.name : id), command: "gtk-launch " + id.replace(/\.desktop$/, "") };
        }
    }
    TextField {
        visible: page.combo !== "" && page.conflict === ""
        Layout.fillWidth: true
        placeholder: Tr.t("Or a command of your own - Enter to use it")
        onAccepted: if (text.trim() !== "") page.action = { title: text.trim(), command: text.trim() }
    }
    Button {
        visible: page.combo !== "" && page.conflict === ""
        kind: "primary"
        enabled: page.action !== null
        text: page.action ? Tr.t("Add %1 - %2").arg(page.pretty(page.combo)).arg(page.action.title) : Tr.t("Pick what it does")
        onClicked: {
            page.d.customBinds = Array.from(page.d.customBinds || []).concat([{ key: page.combo, title: page.action.title, command: page.action.command }]);
            page.combo = "";
            page.action = null;
        }
    }
}
