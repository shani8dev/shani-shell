// The global Shortcut centre: Settings > Keyboard shortcuts.
// What niri really has is read from its config (as niri's own overlay names them);
// search, category filters, preview cards, the reassign confirm, favourites,
// per-binding parameters, recently used, export as text/JSON and the empty
// states are this centre's own, on top of those.
// Press the keys, pick what a bind does - an app, or one of a few things people want.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "NiriBinds.js" as NiriBinds

ColumnLayout {
    id: page
    spacing: Theme.px(12)
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
    function takenBy(k, skipKey) {
        const n = norm(k);
        const skip = skipKey ? norm(skipKey) : null;
        const b = binds.find(x => norm(x.key) === n && norm(x.key) !== skip);
        if (b) return b.title;
        const c = Array.from(d.customBinds || []).find(x => norm(x.key) === n && norm(x.key) !== skip);
        return c ? (c.title || c.command) : "";
    }
    function pretty(k) { return String(k).replace(/\bMod\b/, "Super").replace(/\+/g, " + "); }

    // ---- search + category filters ----------------------------------------------
    TextField { id: find; Layout.fillWidth: true; placeholder: Tr.t("Find a shortcut - screenshot, close, workspace…") }
    readonly property string filterQ: find.text.trim().toLowerCase()
    // search: title, key, and - on your own binds - the command and parameter
    function searchMatches(b) {
        const q = page.filterQ;
        return q === "" || [b.title, b.key, b.command, b.param].some(x => String(x || "").toLowerCase().indexOf(q) >= 0);
    }
    function categoryOf(title) {
        const t = String(title || "").toLowerCase();
        if (/terminal|files|file manager|mail|browser|music|video|photo|photos|gallery|editor|writer|calendar|tasks|notes|lens|reader/.test(t))
            return Tr.t("Apps");
        if (/window|workspace|move|resize|minimis|minimiz|close|fullscreen|focus|layout|tiling|desktop/.test(t))
            return Tr.t("Windows");
        if (/screenshot|color|display|monitor|screen|capture|annotation/.test(t))
            return Tr.t("Screen");
        return Tr.t("Tools");
    }
    readonly property var cats: (function () {
        const s = [];
        page.binds.forEach(b => { const c = page.categoryOf(b.title); if (s.indexOf(c) < 0) s.push(c); });
        return s;
    })()
    property string cat: "all"
    readonly property var filtered: page.binds.filter(b => (page.cat === "all" || page.categoryOf(b.title) === page.cat) && page.searchMatches(b))

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Keyboard shortcuts") }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        visible: page.binds.length > 0
        Choice { text: Tr.t("All"); selected: page.cat === "all"; onClicked: page.cat = "all" }
        Repeater { model: page.cats; Choice { required property string modelData; text: modelData; selected: page.cat === modelData; onClicked: page.cat = modelData } }
    }
    Repeater {
        model: page.filtered
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Theme.px(12)
            Accessible.role: Accessible.StaticText
            Accessible.name: page.pretty(modelData.key) + "  " + modelData.title
            Text { text: page.pretty(modelData.key); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale; Layout.preferredWidth: Theme.px(190) }
            Text { text: modelData.title; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; Layout.fillWidth: true; elide: Text.ElideRight
                   Accessible.role: Accessible.StaticText; Accessible.name: modelData.title }
        }
    }
    Text { visible: page.binds.length === 0; text: Tr.t("No binds found in your niri config yet"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; Layout.fillWidth: true
           Accessible.role: Accessible.StaticText; Accessible.name: Tr.t("No binds found in your niri config yet") }
    Text { visible: page.binds.length > 0 && page.filtered.length === 0; text: Tr.t("No shortcuts match that search"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; Layout.fillWidth: true
           Accessible.role: Accessible.StaticText; Accessible.name: Tr.t("No shortcuts match that search") }

    // ---- your own: preview cards ------------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Your own shortcuts") }
    Repeater {
        model: page.sortedBinds
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Theme.px(12)
            Text { text: page.pretty(modelData.key); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale; Layout.preferredWidth: Theme.px(190) }
            IconButton {
                icon: modelData.fav ? "starred" : "star"
                tip: modelData.fav ? Tr.t("Remove from your favourites") : Tr.t("Add to your favourites")
                size: Theme.px(28)
                onClicked: page.favToggle(modelData)
            }
            ColumnLayout {
                spacing: Theme.px(2)
                Text { text: modelData.title || modelData.command; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; Layout.fillWidth: true; elide: Text.ElideRight
                       Accessible.name: modelData.title || modelData.command }
                Text { visible: page.commandOf(modelData) !== "" && page.commandOf(modelData) !== (modelData.title || modelData.command);
                       text: page.commandOf(modelData); color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale; Layout.fillWidth: true; elide: Text.ElideRight
                       Accessible.name: page.commandOf(modelData) }
            }
            IconButton { icon: "media-playback-start"; size: Theme.px(28); tip: Tr.t("Run now"); onClicked: page.runNow(modelData) }
            IconButton { icon: "edit-rename"; size: Theme.px(28); tip: Tr.t("Reassign"); onClicked: page.startReassign(modelData) }
            IconButton { icon: "list-remove"; size: Theme.px(28); tip: Tr.t("Remove it"); onClicked: page.removeBind(modelData) }
        }
    }
    Text { visible: page.sortedBinds.length === 0; text: Tr.t("No shortcuts yet - press a combo below"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; Layout.fillWidth: true
           Accessible.role: Accessible.StaticText; Accessible.name: Tr.t("No shortcuts yet - press a combo below") }

    // ---- reassign confirm ----------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        visible: page.pendingReassign !== null
        spacing: Theme.px(12)
        Text { text: page.pendingReassign ? Tr.t("Move it from %1 to %2?").arg(page.pendingReassign.oldKey).arg(page.pendingReassign.newKey) : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
        Button { kind: "primary"; text: Tr.t("Move it"); onClicked: page.confirmReassign() }
        Button { text: Tr.t("Cancel"); onClicked: page.cancelReassign() }
    }

    // ---- export ----------------------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(8)
        Button { text: Tr.t("Copy all as text"); onClicked: page.exportText() }
        Button { text: Tr.t("Copy all as JSON"); onClicked: page.exportJson() }
        Text { visible: page.exported !== ""; text: page.exported; color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
               Accessible.role: Accessible.StaticText; Accessible.name: page.exported }
    }

    // ---- 1. press the keys ------------------------------------------------------------
    property string combo: ""
    property bool capturing: false
    property string reassignTarget: ""      // the key of the custom bind being reassigned
    property var pendingReassign: null      // { title, oldKey, newKey, key } while a reassign waits for confirm
    readonly property string conflict: combo === "" ? "" : takenBy(combo, reassignTarget)
    readonly property var reassigningTarget: reassignTarget !== "" ? (d.customBinds || []).find(x => norm(x.key) === reassignTarget) || null : null
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
        implicitHeight: Theme.px(48)
        radius: Theme.px(12)
        color: page.capturing ? Theme.accentSoft : Theme.hover
        border.color: page.conflict !== "" ? Theme.danger : page.capturing ? Theme.accent : "transparent"
        focus: page.capturing
        Accessible.role: Accessible.Button
        Accessible.name: page.reassigningTarget ? Tr.t("Press the keys to move %1").arg(page.reassigningTarget.title || page.reassigningTarget.command)
                                                : Tr.t("Press the keys for a new shortcut")
        Accessible.onPressAction: { page.capturing = true; forceActiveFocus(); }
        Text {
            anchors.centerIn: parent
            text: page.reassigningTarget ? Tr.t("Press the keys to move %1").arg(page.reassigningTarget.title || page.reassigningTarget.command)
                : page.capturing && page.combo === "" ? Tr.t("Press the keys now - for example Super and a letter")
                : page.combo !== "" ? page.pretty(page.combo) : Tr.t("Click here, then press the keys for a new shortcut")
            color: page.combo !== "" ? Theme.text : Theme.dim
            font.family: page.combo !== "" ? Theme.mono : Theme.font
            font.pixelSize: Theme.px(13) * Theme.fontScale
        }
        MouseArea { anchors.fill: parent; onClicked: { page.capturing = true; page.combo = ""; parent.forceActiveFocus(); } }
        KeyFocus { onActivated: { page.capturing = true; page.combo = ""; parent.forceActiveFocus(); } }
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
            page.onCaptured();
            e.accepted = true;
        }
    }
    Text {
        visible: page.conflict !== ""
        Layout.fillWidth: true
        // name what owns the key (title/app) and show the exact combo it stole
        text: Tr.t("That one is already taken: %1. Try another.").arg(page.conflict + " (" + page.pretty(page.combo) + ")")
        color: Theme.danger
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }

    // ---- 2. what it does: an app, a few ready ones, or a command of your own ----------
    property var action: null              // { title, command }
    Flow {
        visible: page.combo !== "" && page.conflict === ""
        Layout.fillWidth: true
        spacing: Theme.px(6)
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
            page.action = { title: Tr.t("Open %1").arg(e ? e.name : id), command: Launch.tool + " " + id.replace(/\.desktop$/, "") };
        }
    }
    TextField {
        id: paramArg
        visible: page.combo !== "" && page.conflict === ""
        Layout.fillWidth: true
        placeholder: Tr.t("Optional parameter, appended to the command")
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
            page.d.customBinds = Array.from(page.d.customBinds || []).concat([{ key: page.combo, title: page.action.title, command: page.action.command,
                                                                                param: paramArg.text !== "" ? paramArg.text : "" }]);
            page.combo = "";
            page.action = null;
            paramArg.text = "";
        }
    }

    // ---- your own, as data: sorting, params, run, export --------------------------------
    readonly property var sortedBinds: Array.from(d.customBinds || []).sort((a, b) => {
        if (Number(b.fav) !== Number(a.fav)) return Number(b.fav) - Number(a.fav);
        const au = Number(a.lastUsed || 0), bu = Number(b.lastUsed || 0);
        if (au !== bu) return bu - au;
        return String(b.key).localeCompare(String(a.key));
    })
    function commandOf(b) { return [String(b.command || "").trim(), b.param ? String(b.param).trim() : ""].filter(x => x !== "").join(" "); }
    function favToggle(bind) {
        const list = Array.from(d.customBinds || []);
        const i = list.findIndex(x => norm(x.key) === norm(bind.key));
        if (i >= 0) list[i] = Object.assign({}, list[i], { fav: !list[i].fav });
        d.customBinds = list;
    }
    function removeBind(bind) {
        d.customBinds = Array.from(d.customBinds || []).filter(x => norm(x.key) !== norm(bind.key));
    }
    function startReassign(bind) {
        page.reassignTarget = page.norm(bind.key);
        page.capturing = true;
        page.combo = "";
    }
    function onCaptured() {
        if (page.reassignTarget !== "")
            page.pendingReassign = { title: page.reassigningTarget ? (page.reassigningTarget.title || page.reassigningTarget.command) : "",
                                     oldKey: page.pretty(page.reassignTarget), newKey: page.pretty(page.combo), key: page.combo };
    }
    function confirmReassign() {
        const p = page.pendingReassign;
        if (!p || !page.reassignTarget) return;
        const list = Array.from(page.d.customBinds || []);
        const i = list.findIndex(x => page.norm(x.key) === page.reassignTarget);
        if (i >= 0) list[i] = Object.assign({}, list[i], { key: p.key });
        page.d.customBinds = list;
        page.reassignTarget = "";
        page.pendingReassign = null;
    }
    function cancelReassign() { page.reassignTarget = ""; page.pendingReassign = null; }
    function setLastUsed(bind) {
        const list = Array.from(d.customBinds || []);
        const i = list.findIndex(x => norm(x.key) === norm(bind.key));
        if (i >= 0) list[i] = Object.assign({}, list[i], { lastUsed: Date.now() });
        d.customBinds = list;
    }
    Process {
        id: runProcess
        property var toRun: null
        running: !!toRun
        command: toRun ? ["sh", "-c", page.commandOf(toRun)] : []
        onExited: { if (toRun) { page.setLastUsed(toRun); toRun = null; } }
    }
    function runNow(b) { runProcess.toRun = b; }
    function exportText() {
        const lines = page.binds.map(b => page.pretty(b.key) + "  " + (b.title || ""))
            .concat(page.sortedBinds.map(b => page.pretty(b.key) + "  " + (b.title || b.command) + (page.commandOf(b) !== "" ? "  (" + page.commandOf(b) + ")" : "")));
        Quickshell.clipboardText = lines.join("\n");
        page.exported = Tr.t("Copied as text");
    }
    function exportJson() {
        Quickshell.clipboardText = JSON.stringify(page.binds.map(b => ({ key: b.key, title: b.title }))
            .concat(page.sortedBinds.map(b => ({ key: b.key, title: b.title || b.command, command: b.command || "", param: b.param || "", fav: !!b.fav }))), null, 2);
        page.exported = Tr.t("Copied as JSON");
    }
    property string exported: ""
}
