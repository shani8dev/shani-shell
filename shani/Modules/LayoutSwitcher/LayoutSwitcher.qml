// Desktop layouts: a few ways to set this desktop up, each a picture of what you
// will get and a plain list of what it changes. Every layout only sets things
// this shell has (dock, desktop widgets and icons, hot corners, window spacing
// and width, Smart Touch), so what the picture shows is what you get.
// Clicking a layout tries it on at once; Keep holds it, Cancel or Esc puts back
// what you had. Opened from the launcher, Personalisation, or `qs ipc call
// shell layoutSwitcher`.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: root
    visible: Ui.layoutSwitcher && !Lock.locked && !Polkit.active   // a password prompt comes first
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.alpha("#000000", 0.45)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-layout-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }

    readonly property var corners: ["hotCornerTopLeft", "hotCornerTopRight", "hotCornerBottomLeft", "hotCornerBottomRight"]
    function cornersAll(tl) { return { hotCornerTopLeft: tl, hotCornerTopRight: "none", hotCornerBottomLeft: "none", hotCornerBottomRight: "none" } }
    readonly property var presets: [
        { id: "default", name: Tr.t("Shani"), icon: "start-here", desc: Tr.t("The bar, and a dock that steps aside only when a window is moved over it. A clock on a clear desktop; windows open side by side."),
          set: Object.assign({ dock: true, dockVisibility: "smart", barVisibility: "always", dockIconSize: 48, desktopWidgets: ["clock"], desktopIcons: false, deskStacks: false,
                 winGaps: 12, winFocusRing: 2, winDefaultWidth: 0.5, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false }, cornersAll("overview")) },
        { id: "classic", name: Tr.t("Classic"), icon: "user-desktop", desc: Tr.t("Like most computers: each window opens full width, your files and drives on the desktop, the dock always there."),
          set: Object.assign({ dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 48, desktopWidgets: ["clock", "agenda", "weather"], desktopIcons: true, deskStacks: false,
                 winGaps: 8, winFocusRing: 2, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false }, cornersAll("none")) },
        { id: "focus", name: Tr.t("Focus"), icon: "view-fullscreen", desc: Tr.t("Nothing but your work: the dock waits at the bottom edge, the bar steps aside for a window over it, an empty desktop."),
          set: Object.assign({ dock: true, dockVisibility: "hide", barVisibility: "smart", dockIconSize: 48, desktopWidgets: [], desktopIcons: false, deskStacks: false,
                 winGaps: 16, winFocusRing: 2, winDefaultWidth: 0.5, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false }, cornersAll("overview")) },
        { id: "tiling", name: Tr.t("Tiling"), icon: "view-grid", desc: Tr.t("For the keyboard: no dock, tight gaps, a strong focus ring, focus follows the pointer."),
          set: Object.assign({ dock: false, dockVisibility: "hide", barVisibility: "always", dockIconSize: 48, desktopWidgets: [], desktopIcons: false, deskStacks: false,
                 winGaps: 6, winFocusRing: 3, winDefaultWidth: 0.5, winFocusFollowsMouse: true, assistiveTouch: false, showSysStats: true }, cornersAll("none")) },
        { id: "dashboard", name: Tr.t("Dashboard"), icon: "view-list-details", desc: Tr.t("Everything at a glance: agenda, weather, music, a note, system use; files grouped into stacks."),
          set: Object.assign({ dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 44, desktopWidgets: ["clock", "agenda", "weather", "media", "stats", "note"], desktopIcons: true, deskStacks: true,
                 winGaps: 12, winFocusRing: 2, winDefaultWidth: 0.5, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: true }, cornersAll("overview")) },
        { id: "touch", name: Tr.t("Touch"), icon: "input-tablet", desc: Tr.t("For fingers: big dock icons, full-width windows, the Smart Touch button, no hot corners to brush by mistake."),
          set: Object.assign({ dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 64, desktopWidgets: ["clock", "media"], desktopIcons: false, deskStacks: false,
                 winGaps: 12, winFocusRing: 0, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: true, showSysStats: false }, cornersAll("none")) }
    ]
    readonly property var keys: Object.keys(presets[0].set)

    property int sel: 0
    property var before: ({})          // the settings as they were when this opened
    property bool tried: false
    readonly property var p: presets[sel]

    function snapshot() { const o = {}; for (const k of keys) { const v = Settings.data[k]; o[k] = Array.isArray(v) || (v && typeof v === "object" && v.length !== undefined) ? Array.from(v) : v; } return o; }
    function put(set) { for (const k in set) Settings.data[k] = Array.isArray(set[k]) ? set[k].slice() : set[k]; }
    function same(set, cur) { for (const k in set) { if (JSON.stringify(set[k]) !== JSON.stringify(cur[k])) return false; } return true; }
    // which layout the desktop is in now, or -1 when it has been changed by hand
    function matching() { const cur = snapshot(); return presets.findIndex(x => same(x.set, cur)); }
    function tryOn(i) { sel = i; Ui.layoutTrying = presets[i].id; put(presets[i].set); tried = true; }
    // **A layout rewrites niri's config, and niri reloads it - which takes the
    // keyboard focus off this surface.** Measured 2026-11-07: 2 of 12 runs lost
    // the Return key that followed, leaving the panel open with the layout on
    // screen but no key reaching it. Toggling the request makes niri grant it
    // again; `Niri.configLoaded` is the only signal that says the reload landed.
    Connections {
        target: Niri
        function onConfigLoaded(failed) {
            if (!root.visible)
                return;
            WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
            retake.restart();
        }
    }
    Timer {
        id: retake
        interval: 50
        onTriggered: {
            WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive;
            keysItem.forceActiveFocus();
        }
    }
    function keep() { Settings.data.layoutPreset = presets[sel].id; tried = false; Ui.layoutSwitcher = false; }
    function cancel() { if (tried) put(before); tried = false; Ui.layoutSwitcher = false; }
    // what this layout changes, against what you had, in words
    function changes(set) {
        const was = before, out = [];
        const names = { clock: Tr.t("clock"), agenda: Tr.t("agenda"), weather: Tr.t("weather"), media: Tr.t("music"), stats: Tr.t("system use"), note: Tr.t("note"), battery: Tr.t("battery"), clocks: Tr.t("world clocks") };
        const w = a => a.length ? a.map(x => names[x] || x).join(", ") : Tr.t("none");
        const vis = { always: Tr.t("always there"), smart: Tr.t("there until a window is moved over it"), hide: Tr.t("hidden until the pointer rests on the edge") };
        if (set.dock !== was.dock || set.dockVisibility !== was.dockVisibility)
            out.push(!set.dock ? Tr.t("No dock — open apps with Super+Space") : Tr.t("The dock: ") + vis[set.dockVisibility]);
        if (set.barVisibility !== was.barVisibility) out.push(Tr.t("The bar: ") + vis[set.barVisibility]);
        if (set.dock && set.dockIconSize !== was.dockIconSize) out.push(set.dockIconSize > was.dockIconSize ? Tr.t("Bigger dock icons") : Tr.t("Smaller dock icons"));
        if (JSON.stringify(set.desktopWidgets) !== JSON.stringify(was.desktopWidgets)) out.push(Tr.t("Desktop widgets: ") + w(set.desktopWidgets));
        if (set.desktopIcons !== was.desktopIcons || set.deskStacks !== was.deskStacks)
            out.push(!set.desktopIcons ? Tr.t("No files on the desktop") : set.deskStacks ? Tr.t("Desktop files grouped into stacks by kind") : Tr.t("Files and drives on the desktop"));
        if (set.winDefaultWidth !== was.winDefaultWidth) out.push(set.winDefaultWidth >= 1 ? Tr.t("New windows open full width") : Tr.t("New windows open at half width, side by side"));
        if (set.winGaps !== was.winGaps) out.push(Tr.t("Space between windows: ") + set.winGaps + " px");
        if (set.winFocusRing !== was.winFocusRing) out.push(set.winFocusRing ? Tr.t("Focus ring: ") + set.winFocusRing + " px" : Tr.t("No focus ring"));
        if (set.winFocusFollowsMouse !== was.winFocusFollowsMouse) out.push(set.winFocusFollowsMouse ? Tr.t("Pointing at a window focuses it") : Tr.t("Click a window to focus it"));
        if (corners.some(k => set[k] !== was[k])) out.push(set.hotCornerTopLeft === "none" ? Tr.t("Hot corners off") : Tr.t("Top-left corner opens the overview"));
        if (set.assistiveTouch !== was.assistiveTouch) out.push(set.assistiveTouch ? Tr.t("Smart Touch button on screen") : Tr.t("Smart Touch button off"));
        if (set.showSysStats !== was.showSysStats) out.push(set.showSysStats ? Tr.t("CPU and memory in the bar") : Tr.t("No CPU and memory in the bar"));
        return out;
    }

    // made on first use (shell.qml), so already visible when created: open the same way
    Component.onCompleted: if (visible) opened()
    onVisibleChanged: { if (visible) opened(); else Ui.layoutTrying = ""; }
    function opened() {
        if (!Settings.loaded)
            return;
        before = snapshot();
        tried = false;
        const m = matching();
        sel = m >= 0 ? m : Math.max(0, presets.findIndex(x => x.id === Settings.data.layoutPreset));
        Ui.layoutTrying = presets[sel].id;
        keysItem.forceActiveFocus();
    }
    readonly property int now: visible ? matching() : -1

    // a small picture of a layout, drawn from the very settings it sets
    component Mini: Rectangle {
        id: mini
        property var s: ({})
        readonly property real u: width / 160          // drawn on a 160×100 screen
        readonly property var wd: s.desktopWidgets || []
        radius: 6 * u
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.alpha(Theme.accent, 0.55) }
            GradientStop { position: 1; color: Theme.alpha(Theme.accent, 0.15) }
        }
        // the bar, with the Island in the middle
        Rectangle { width: parent.width; height: (mini.s.barVisibility === "hide" ? 1.5 : 7) * mini.u; color: Theme.alpha("#000000", 0.45); clip: true
            Rectangle { anchors.centerIn: parent; width: 22 * mini.u; height: 4 * mini.u; radius: height / 2; color: "#000000" }
            Row { x: 4 * mini.u; anchors.verticalCenter: parent.verticalCenter; spacing: 1.5 * mini.u
                Repeater { model: 3; Rectangle { width: 2.5 * mini.u; height: width; radius: width / 2; color: Theme.alpha("#ffffff", 0.7) } } }
            Rectangle { visible: !!mini.s.showSysStats; x: parent.width - 30 * mini.u; anchors.verticalCenter: parent.verticalCenter; width: 10 * mini.u; height: 2 * mini.u; color: Theme.alpha("#ffffff", 0.6) }
            Rectangle { x: parent.width - 16 * mini.u; anchors.verticalCenter: parent.verticalCenter; width: 12 * mini.u; height: 2 * mini.u; color: Theme.alpha("#ffffff", 0.8) }
        }
        // the left column, as on the real desktop: widgets from the top, then files
        readonly property int nw: Math.min(3, wd.length)
        readonly property int ni: s.desktopIcons ? (s.deskStacks ? 2 : 3) : 0
        readonly property real colW: nw ? 26 * u : (ni ? 9 * u : 0)
        Column {
            x: 3 * mini.u; y: 10 * mini.u; spacing: 2 * mini.u
            Repeater { model: mini.nw
                Rectangle { width: 24 * mini.u; height: 11 * mini.u; radius: 3 * mini.u; color: Theme.alpha("#ffffff", 0.35); border.width: 1; border.color: Theme.alpha("#ffffff", 0.4) } }
            Repeater { model: mini.ni
                Rectangle { width: 6 * mini.u; height: width; radius: 1.5 * mini.u; color: Theme.alpha("#ffffff", 0.75) } }
        }
        // windows: half width side by side, or one full width
        Row {
            x: mini.colW + Math.max(2, (mini.s.winGaps || 0) / 3) * mini.u + (mini.colW ? 3 * mini.u : 0)
            y: 7 * mini.u + Math.max(1.5, (mini.s.winGaps || 0) / 3) * mini.u
            spacing: Math.max(1, (mini.s.winGaps || 0) / 3) * mini.u
            readonly property real h: mini.height - y - (mini.s.dock && mini.s.dockVisibility !== "hide" ? 14 : 4) * mini.u
            readonly property real w: mini.width - x - Math.max(2, (mini.s.winGaps || 0) / 3) * mini.u
            Repeater {
                model: mini.s.winDefaultWidth >= 1 ? 1 : 2
                Rectangle {
                    width: mini.s.winDefaultWidth >= 1 ? parent.w : (parent.w - parent.spacing) / 2 * (index ? 0.75 : 1)
                    height: parent.h
                    radius: 3 * mini.u
                    color: Theme.alpha(Theme.dark ? "#2a2a2e" : "#fafafa", 0.92)
                    border.width: index === 0 && mini.s.winFocusRing ? Math.max(1, mini.s.winFocusRing / 2 * mini.u) : 0
                    border.color: Theme.accent
                    Rectangle { x: 4 * mini.u; y: 4 * mini.u; width: parent.width * 0.4; height: 2 * mini.u; color: Theme.alpha(Theme.text, 0.25) }
                    Rectangle { x: 4 * mini.u; y: 8 * mini.u; width: parent.width * 0.6; height: 2 * mini.u; color: Theme.alpha(Theme.text, 0.15) }
                }
            }
            opacity: 0.85
        }
        // the dock: a pill that stays, or a thin line where it waits
        Rectangle {
            visible: !!mini.s.dock
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - (mini.s.dockVisibility === "hide" ? 1 : 2.5) * mini.u
            readonly property real cell: (mini.s.dockIconSize || 48) / 48 * 6 * mini.u
            width: mini.s.dockVisibility === "hide" ? 40 * mini.u : cell * 6 + 8 * mini.u
            height: mini.s.dockVisibility === "hide" ? 1.5 * mini.u : cell + 3 * mini.u
            radius: height / 2.5
            color: Theme.alpha("#000000", 0.4)
            border.width: 1; border.color: Theme.alpha("#ffffff", 0.25)
            Row { visible: mini.s.dockVisibility !== "hide"; anchors.centerIn: parent; spacing: mini.u
                Repeater { model: 5; Rectangle { width: parent.parent.cell; height: width; radius: width / 3.5; color: Qt.hsla(index / 5, 0.55, 0.62, 1) } } }
        }
        // Smart Touch
        Rectangle { visible: !!mini.s.assistiveTouch; x: parent.width - 16 * mini.u; y: parent.height * 0.55; width: 9 * mini.u; height: width; radius: width / 2
            color: Theme.alpha("#000000", 0.5); border.width: 1.5 * mini.u; border.color: Theme.alpha("#ffffff", 0.8) }
        // hot corner
        Rectangle { visible: mini.s.hotCornerTopLeft && mini.s.hotCornerTopLeft !== "none"; width: 6 * mini.u; height: width; radius: width / 2; x: -width / 2; y: -width / 2; color: Theme.accent }
    }

    Item {
        id: keysItem
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.cancel()
        Keys.onReturnPressed: root.tried ? root.keep() : root.tryOn(root.sel)
        Keys.onLeftPressed: root.tryOn((root.sel + root.presets.length - 1) % root.presets.length)
        Keys.onRightPressed: root.tryOn((root.sel + 1) % root.presets.length)
        Keys.onUpPressed: root.tryOn((root.sel + root.presets.length - 3) % root.presets.length)
        Keys.onDownPressed: root.tryOn((root.sel + 3) % root.presets.length)
        MouseArea { anchors.fill: parent; onClicked: root.cancel() }
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 980)
        height: Math.min(parent.height - 48, body.implicitHeight + 48)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }       // a click on the card is not a click outside
        RowLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 24
            spacing: 24
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 14
                Text { text: Tr.t("Desktop layout"); color: Theme.text; font.family: Theme.font; font.pixelSize: 20 * Theme.fontScale; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale
                    text: Tr.t("Pick one to try it on — your desktop changes at once. Keep it, or Cancel to go back. You can still change any part of it in Settings afterwards.") }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 12
                    columnSpacing: 12
                    Repeater {
                        model: root.presets
                        Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool chosen: root.sel === index
                            Layout.fillWidth: true
                            implicitHeight: tcol.implicitHeight + 16
                            radius: Theme.radius
                            color: chosen ? Theme.alpha(Theme.accent, 0.16) : (ta.containsMouse ? Theme.hover : "transparent")
                            border.width: chosen ? 2 : 1
                            border.color: chosen ? Theme.accent : Theme.stroke
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.name
                            Accessible.checked: chosen
                            Accessible.onPressAction: root.tryOn(index)
                            Accessible.onToggleAction: root.tryOn(index)
                            ColumnLayout {
                                id: tcol
                                x: 8; y: 8
                                width: parent.width - 16
                                spacing: 8
                                Mini { Layout.fillWidth: true; Layout.preferredHeight: width * 0.625; s: tile.modelData.set }
                                RowLayout {
                                    spacing: 6
                                    Icon { name: tile.modelData.icon; size: 16; color: tile.chosen ? Theme.accent : Theme.text }
                                    Text { text: tile.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 * Theme.fontScale; font.weight: Font.Medium }
                                    Rectangle { visible: root.now === tile.index && !root.tried; radius: 8; color: Theme.alpha(Theme.accent, 0.25); implicitWidth: nowL.implicitWidth + 12; implicitHeight: nowL.implicitHeight + 4
                                        Text { id: nowL; anchors.centerIn: parent; text: Tr.t("Now"); color: Theme.text; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale } }
                                }
                            }
                            MouseArea { id: ta; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tryOn(tile.index) }
                        }
                    }
                }
                Text { visible: root.now < 0 && !root.tried; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale
                    text: Tr.t("Your desktop is set up your own way right now, so none of these is marked. Cancel keeps it exactly as it is.") }
            }
            // the chosen layout: big picture, what it changes, Keep / Cancel
            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.maximumWidth: 300
                Layout.fillHeight: true
                spacing: 12
                Mini { Layout.fillWidth: true; Layout.preferredHeight: width * 0.625; s: root.p.set }
                Text { text: root.p.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 17 * Theme.fontScale; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.p.desc; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
                Text { text: root.tried ? Tr.t("What changed") : Tr.t("What it changes"); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale; font.weight: Font.Medium }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: { const c = root.changes(root.p.set); return c.length ? c : [Tr.t("Nothing — this is how your desktop is now")]; }
                        RowLayout {
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 6
                            Icon { name: "object-select-symbolic"; size: 14; color: Theme.accent; Layout.alignment: Qt.AlignTop }
                            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale
                    text: Tr.t("Arrows to look through them · Enter to keep · Esc to cancel") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button { text: Tr.t("More settings…"); onClicked: { root.tried ? root.keep() : root.cancel(); Ui.openSettings("personal"); } }
                    Item { Layout.fillWidth: true }
                    Button { text: Tr.t("Cancel"); kind: "outline"; onClicked: root.cancel() }
                    Button { text: root.tried ? Tr.t("Keep") : Tr.t("Use this"); kind: "primary"; onClicked: root.tried ? root.keep() : (root.tryOn(root.sel), root.keep()) }
                }
            }
        }
    }
}
