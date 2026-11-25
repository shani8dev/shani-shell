// Screen and layout: what kind of screen this is (Settings > Displays has the
// same pick) and a few ways to set the desktop up for it, each a picture of what
// you will get and a plain list of what it changes. Picking a kind of screen
// tries it and the layout that suits it; Keep holds both, Cancel puts both back. Every layout only sets things
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
import "../../Common/FormFactor.js" as FF

PanelWindow {
    id: root
    visible: Ui.layoutSwitcher && !Lock.locked && !Polkit.active   // a password prompt comes first
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.alpha("#000000", 0.45)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-layout-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }

    // the layouts and what they own: Services/Layouts (one list for this, the
    // memory of each situation's layout, and the tests)
    readonly property var corners: Layouts.corners
    readonly property var presets: Layouts.presets
    readonly property var keys: Layouts.keys

    property int sel: 0
    // the kind of screen: this output's pick ("auto" when it is told by itself)
    readonly property string output: screen ? screen.name : Niri.focusedOutput
    readonly property var kinds: FF.PROFILES
    // a TV and a handheld open on the ten-foot home (TvHome): a layout is for
    // when you go from it to the desktop. What each kind is, in a line.
    readonly property var kindNotes: ({
        computer: Tr.t("A desk monitor: mouse and keyboard, windows side by side."),
        laptop: Tr.t("A laptop: its own screen, often small; Focus keeps it clear."),
        tablet: Tr.t("Fingers first: bigger targets, edge swipes, the screen keyboard."),
        handheld: Tr.t("Opens on the arm's-length home, driven by its controller; the layout is for its desktop."),
        phone: Tr.t("A phone-sized screen: a compact bar, apps full screen, Quick Settings from the top."),
        tv: Tr.t("Opens on the TV home, driven by a remote or a controller; the layout is for its desktop."),
        board: Tr.t("A classroom board: the bar at the bottom, within reach; swipe in from the left or right edge for the tools, up from the bottom for the apps."),
        projector: Tr.t("Shown to a room: bigger, nothing on the edges; Presenting keeps notifications away.")
    })
    readonly property string kind: (Settings.data.formFactors || {})[output] || "auto"
    readonly property string kindNow: FormFactor.of(output).profile
    property string kindBefore: "auto"
    property bool kindTried: false
    function tryKind(k) {
        FormFactor.choose(root.output, k);
        kindTried = k !== kindBefore;
        const now = k === "auto" ? FormFactor.detected(root.output) : k;
        // the one made for this kind, else the first that suits it
        let i = presets.findIndex(x => x.made === now);
        if (i < 0) i = presets.findIndex(x => x.suits.indexOf(now) >= 0);
        if (i >= 0) tryOn(i);
    }
    // the layouts shown: the ones for this kind of screen (made for it first),
    // and whatever is chosen now; "Show all layouts" lists the rest
    property bool showAll: false
    property bool showFamiliar: false
    readonly property var shown: {
        const all = presets.map((x, i) => i);
        if (showAll) return all;
        if (showFamiliar) {
            const fam = all.filter(i => presets[i].familiar);
            for (const i of [sel, now]) if (i >= 0 && fam.indexOf(i) < 0) fam.push(i);
            return fam;
        }
        const mine = all.filter(i => presets[i].made === kindNow)
            .concat(all.filter(i => presets[i].made !== kindNow && presets[i].suits.indexOf(kindNow) >= 0));
        for (const i of [sel, now]) if (i >= 0 && mine.indexOf(i) < 0) mine.push(i);
        return mine;
    }
    function step(d) {
        const at = Math.max(0, shown.indexOf(sel));
        tryOn(shown[(at + d + shown.length * 3) % shown.length]);
    }
    property var before: ({})          // the settings as they were when this opened
    property bool tried: false
    readonly property var p: presets[sel]

    function snapshot() { return Layouts.snapshot(); }
    function put(set) { Layouts.put(set); }
    function same(set, cur) { return Layouts.same(set, cur); }
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
    function keep() { Settings.data.layoutPreset = presets[sel].id; tried = false; kindTried = false; Ui.layoutSwitcher = false; }
    function cancel() {
        if (tried) put(before);
        if (kindTried) FormFactor.choose(root.output, kindBefore);
        tried = false; kindTried = false; Ui.layoutSwitcher = false;
    }
    // what this layout changes, against what you had, in words
    function changes(set) {
        const was = before, out = [];
        const names = { clock: Tr.t("clock"), agenda: Tr.t("agenda"), weather: Tr.t("weather"), media: Tr.t("music"), stats: Tr.t("system use"), note: Tr.t("note"), battery: Tr.t("battery"), clocks: Tr.t("world clocks") };
        const w = a => a.length ? a.map(x => names[x] || x).join(", ") : Tr.t("none");
        const vis = { always: Tr.t("always there"), smart: Tr.t("there until a window is moved over it"), hide: Tr.t("hidden until the pointer rests on the edge") };
        if (set.dock !== was.dock || set.dockVisibility !== was.dockVisibility)
            out.push(!set.dock ? Tr.t("No dock — open apps with Super+Space") : Tr.t("The dock: ") + vis[set.dockVisibility]);
        if (set.barEdge !== was.barEdge && set.barEdge !== "auto")
            out.push(set.barEdge === "bottom" ? Tr.t("The bar along the bottom") : Tr.t("The bar along the top"));
        if (set.barSearch !== was.barSearch)
            out.push(set.barSearch ? Tr.t("A box to ask or search in the bar") : Tr.t("No search box in the bar"));
        if (set.barApps !== was.barApps)
            out.push(set.barApps === "off" ? Tr.t("No apps in the bar") : set.barApps === "center" ? Tr.t("Your apps in the middle of the bar") : Tr.t("Your apps in the bar, after the apps button"));
        if (set.railContent !== was.railContent && set.leftRail)
            out.push(set.railContent === "apps" ? Tr.t("Your apps down the left edge") : Tr.t("Your workspaces down the left edge"));
        if (set.leftRail !== was.leftRail)
            out.push(set.leftRail ? (set.railContent === "apps" ? Tr.t("Your apps down the left edge") : Tr.t("Your workspaces down the left edge")) : set.dock && set.dockVisibility !== "hide" ? Tr.t("Your workspaces in the dock") : Tr.t("Your workspaces in the bar"));
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
    // closed any way but Keep (Esc, a click outside, Back, another panel opening,
    // the IPC): what was tried on is taken off again - only Keep keeps
    onVisibleChanged: {
        if (visible) { opened(); return; }
        isOpen = false;
        if (tried) put(before);
        if (kindTried) FormFactor.choose(root.output, kindBefore);
        tried = false; kindTried = false;
        Ui.layoutTrying = "";
    }
    // the window's own keys, whichever item has focus after niri reloads its config
    Shortcut { sequences: ["Escape"]; enabled: root.visible; onActivated: root.cancel() }
    Shortcut { sequences: ["Return", "Enter"]; enabled: root.visible; onActivated: { if (!root.tried) root.tryOn(root.sel); root.keep(); } }
    // once per opening: made on first use it is created visible, and then also
    // told it became visible - a second run would take what was just tried on as
    // "how it was", and Cancel would put the tried layout back
    property bool isOpen: false
    function opened() {
        if (!Settings.loaded || isOpen)
            return;
        isOpen = true;
        before = snapshot();
        tried = false;
        kindBefore = kind;
        kindTried = false;
        showAll = false;
        showFamiliar = false;
        const m = matching();
        sel = m >= 0 ? m : Math.max(0, presets.findIndex(x => x.id === Settings.data.layoutPreset));
        Ui.layoutTrying = presets[sel].id;
        // asked for one by name (`qs ipc call shani layoutUse <id>`): tried on at once
        const asked = presets.findIndex(x => x.id === Ui.layoutAsked);
        Ui.layoutAsked = "";
        if (asked >= 0) { showAll = true; tryOn(asked); }
        keysItem.forceActiveFocus();
    }
    readonly property int now: visible ? matching() : -1

    // a small picture of a layout, drawn from the very settings it sets
    component Mini: Rectangle {
        id: mini
        property var s: ({})
        property string kind: "computer"         // drawn as this kind of screen shows it
        readonly property bool barBottom: kind === "board" || s.barEdge === "bottom"
        readonly property bool railHere: !!s.leftRail && ["phone", "tv", "handheld", "projector"].indexOf(kind) < 0
        readonly property real barH: (s.barVisibility === "hide" ? 1.5 : 7) * u
        Accessible.ignored: true
        readonly property real u: width / 160          // drawn on a 160×100 screen
        readonly property var wd: s.desktopWidgets || []
        radius: 6 * u
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.alpha(Theme.accent, 0.55) }
            GradientStop { position: 1; color: Theme.alpha(Theme.accent, 0.15) }
        }
        // the bar, with the Island in the middle
        Rectangle { width: parent.width; height: mini.barH; y: mini.barBottom ? parent.height - height : 0; color: Theme.alpha("#000000", 0.45); clip: true
            Rectangle { visible: !mini.barBottom; anchors.centerIn: parent; width: 22 * mini.u; height: 4 * mini.u; radius: height / 2; color: "#000000" }
            Row { visible: !mini.railHere && (!mini.s.dock || mini.s.dockVisibility === "hide")
                x: 4 * mini.u; anchors.verticalCenter: parent.verticalCenter; spacing: 1.5 * mini.u
                Repeater { model: 3; Rectangle { width: 2.5 * mini.u; height: width; radius: width / 2; color: Theme.alpha("#ffffff", 0.7) } } }
            // the bar as a taskbar: app icons after the apps button, or in the middle
            Row { visible: !!mini.s.barApps && mini.s.barApps !== "off"
                x: mini.s.barApps === "center" && mini.barBottom ? (parent.width - width) / 2 : 9 * mini.u
                anchors.verticalCenter: parent.verticalCenter; spacing: 1 * mini.u
                Rectangle { visible: !!mini.s.barSearch; width: 16 * mini.u; height: 4 * mini.u; radius: height / 2; color: Theme.alpha(Theme.text, 0.35) }
                Repeater { model: 5; Rectangle { width: 4 * mini.u; height: width; radius: 1 * mini.u; color: Qt.hsla(index / 5, 0.55, 0.62, 1) } } }
            Rectangle { visible: !!mini.s.showSysStats; x: parent.width - 30 * mini.u; anchors.verticalCenter: parent.verticalCenter; width: 10 * mini.u; height: 2 * mini.u; color: Theme.alpha("#ffffff", 0.6) }
            Rectangle { x: parent.width - 16 * mini.u; anchors.verticalCenter: parent.verticalCenter; width: 12 * mini.u; height: 2 * mini.u; color: Theme.alpha("#ffffff", 0.8) }
        }
        // the left rail: the workspaces, a slim pill down the left edge
        readonly property real railW: railHere ? 7 * u : 0
        Rectangle {
            visible: mini.railHere
            x: 1.5 * mini.u
            anchors.verticalCenter: parent.verticalCenter
            width: 4.5 * mini.u
            height: 18 * mini.u
            radius: 2 * mini.u
            color: Theme.alpha(Theme.bg, 0.7)
            Column { anchors.centerIn: parent; spacing: 1.5 * mini.u
                Repeater { model: mini.s.railContent === "apps" ? 0 : 3; Rectangle { width: 2.5 * mini.u; height: width; radius: width / 2; color: index === 0 ? Theme.accent : Theme.alpha(Theme.text, 0.5) } }
                Repeater { model: mini.s.railContent === "apps" ? 4 : 0; Rectangle { width: 3 * mini.u; height: width; radius: 0.8 * mini.u; color: index === 0 ? Theme.accent : Qt.hsla(index / 4, 0.55, 0.62, 1) } } }
        }
        // the left column, as on the real desktop: widgets from the top, then files
        readonly property int nw: Math.min(3, wd.length)
        readonly property int ni: s.desktopIcons ? (s.deskStacks ? 2 : 3) : 0
        readonly property real colW: nw ? 26 * u : (ni ? 9 * u : 0)
        Column {
            x: mini.railW + 3 * mini.u; y: (mini.barBottom ? 3 : 10) * mini.u; spacing: 2 * mini.u
            Repeater { model: mini.nw
                Rectangle { width: 24 * mini.u; height: 11 * mini.u; radius: 3 * mini.u; color: Theme.alpha("#ffffff", 0.35); border.width: 1; border.color: Theme.alpha("#ffffff", 0.4) } }
            Repeater { model: mini.ni
                Rectangle { width: 6 * mini.u; height: width; radius: 1.5 * mini.u; color: Theme.alpha("#ffffff", 0.75) } }
        }
        // windows: half width side by side, or one full width
        Row {
            x: mini.railW + mini.colW + Math.max(2, (mini.s.winGaps || 0) / 3) * mini.u + (mini.colW ? 3 * mini.u : 0)
            y: (mini.barBottom ? 0 : mini.barH) + Math.max(1.5, (mini.s.winGaps || 0) / 3) * mini.u
            spacing: Math.max(1, (mini.s.winGaps || 0) / 3) * mini.u
            readonly property real h: mini.height - y - (mini.s.dock && mini.s.dockVisibility !== "hide" ? 14 : 4) * mini.u - (mini.barBottom ? mini.barH : 0)
            readonly property real w: mini.width - x - Math.max(2, (mini.s.winGaps || 0) / 3) * mini.u
            Repeater {
                model: mini.s.winDefaultWidth >= 1 ? 1 : 2
                Rectangle {
                    width: mini.s.winDefaultWidth >= 1 ? parent.w : (parent.w - parent.spacing) / 2 * (index ? 0.75 : 1)
                    height: parent.h
                    radius: 3 * mini.u
                    color: Theme.alpha(Theme.bg, 0.92)
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
            y: parent.height - height - (mini.s.dockVisibility === "hide" ? 1 : 2.5) * mini.u - (mini.barBottom ? mini.barH : 0)
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
        Keys.onLeftPressed: root.step(-1)
        Keys.onRightPressed: root.step(1)
        Keys.onUpPressed: root.step(-3)
        Keys.onDownPressed: root.step(3)
        MouseArea { objectName: "nav:pointer"; anchors.fill: parent; onClicked: root.cancel() }   // a click outside cancels; Escape does with keys
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
            anchors.margins: Theme.px(24)
            spacing: Theme.px(24)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Theme.px(14)
                Text { text: Tr.t("Screen and layout"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(20) * Theme.fontScale; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale
                    text: Tr.t("Pick one to try it on — your desktop changes at once. Keep it, or Cancel to go back. You can still change any part of it in Settings afterwards.") }
                // what kind of screen this is: the shell's size and its edges follow it
                Text { text: Tr.t("This screen is a"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.Medium }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: ["auto"].concat(root.kinds)
                        Choice {
                            required property string modelData
                            text: modelData === "auto" ? Tr.t("Automatic") + " (" + Tr.t(FF.label(FormFactor.detected(root.output))) + ")" : Tr.t(FF.label(modelData))
                            selected: root.kind === modelData
                            onClicked: root.tryKind(modelData)
                        }
                    }
                }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.kindNotes[root.kindNow] || ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Text { text: Tr.t("Layout"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.Medium }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: Theme.px(12)
                    columnSpacing: Theme.px(12)
                    Repeater {
                        model: root.shown
                        Rectangle {
                            id: tile
                            required property int modelData        // its place in root.presets
                            readonly property int pi: modelData
                            readonly property var preset: root.presets[pi]
                            readonly property bool chosen: root.sel === pi
                            Layout.fillWidth: true
                            implicitHeight: tcol.implicitHeight + 16
                            radius: Theme.radius
                            color: chosen ? Theme.alpha(Theme.accent, 0.16) : (ta.containsMouse ? Theme.hover : "transparent")
                            border.width: chosen ? 2 : 1
                            border.color: chosen ? Theme.accent : Theme.stroke
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: tile.preset.name
                            Accessible.checked: chosen
                            Accessible.onPressAction: root.tryOn(tile.pi)
                            Accessible.onToggleAction: root.tryOn(tile.pi)
                            ColumnLayout {
                                id: tcol
                                x: 8; y: 8
                                width: parent.width - 16
                                spacing: Theme.px(8)
                                Item { Layout.fillWidth: true; Layout.preferredHeight: width * 0.625
                                    Mini { anchors.centerIn: parent; height: parent.height; width: root.kindNow === "phone" ? height * 0.5 : parent.width; s: tile.preset.set; kind: root.kindNow } }
                                RowLayout {
                                    spacing: Theme.px(6)
                                    Icon { name: tile.preset.icon; size: Theme.px(16); color: tile.chosen ? Theme.accent : Theme.text }
                                    Text { text: tile.preset.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.Medium }
                                    Rectangle { visible: tile.preset.suits.indexOf(root.kindNow) >= 0; radius: Theme.px(8); color: tile.preset.made === root.kindNow ? Theme.alpha(Theme.accent, 0.25) : Theme.alpha(Theme.text, 0.1); implicitWidth: suitsL.implicitWidth + 12; implicitHeight: suitsL.implicitHeight + 4
                                        Text { id: suitsL; anchors.centerIn: parent; text: tile.preset.made === root.kindNow ? Tr.t("Best for this screen") : Tr.t("Also works here"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale } }
                                    Rectangle { visible: root.now === tile.pi && !root.tried; radius: Theme.px(8); color: Theme.alpha(Theme.accent, 0.25); implicitWidth: nowL.implicitWidth + 12; implicitHeight: nowL.implicitHeight + 4
                                        Text { id: nowL; anchors.centerIn: parent; text: Tr.t("Now"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale } }
                                }
                            }
                            MouseArea { id: ta; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tryOn(tile.pi) }
                        }
                    }
                }
                // which layouts: the ones for this screen, the familiar ones, or all
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Choice { text: Tr.t("Best for this screen"); selected: !root.showAll && !root.showFamiliar; onClicked: { root.showAll = false; root.showFamiliar = false; } }
                    Choice { text: Tr.t("Familiar layouts"); selected: root.showFamiliar; onClicked: { root.showAll = false; root.showFamiliar = true; } }
                    Choice { text: Tr.t("All %1", root.presets.length); selected: root.showAll; onClicked: { root.showFamiliar = false; root.showAll = true; } }
                }
                Text { visible: root.now < 0 && !root.tried; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    text: Tr.t("Your desktop is set up your own way right now, so none of these is marked. Cancel keeps it exactly as it is.") }
            }
            // the chosen layout: big picture, what it changes, Keep / Cancel
            ColumnLayout {
                Layout.preferredWidth: Theme.px(300)
                Layout.maximumWidth: Theme.px(300)
                Layout.fillHeight: true
                spacing: Theme.px(12)
                Item { Layout.fillWidth: true; Layout.preferredHeight: width * 0.625
                    Mini { anchors.centerIn: parent; height: parent.height; width: root.kindNow === "phone" ? height * 0.5 : parent.width; s: root.p.set; kind: root.kindNow } }
                Text { text: root.p.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(17) * Theme.fontScale; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.p.desc; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                Text { text: root.tried ? Tr.t("What changed") : Tr.t("What it changes"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.Medium }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: { const c = root.changes(root.p.set); return c.length ? c : [Tr.t("Nothing — this is how your desktop is now")]; }
                        RowLayout {
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Icon { name: "object-select-symbolic"; size: Theme.px(14); color: Theme.accent; Layout.alignment: Qt.AlignTop }
                            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    text: Tr.t("Arrows to look through them · Enter to keep · Esc to cancel") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Button { text: Tr.t("More settings…"); onClicked: { root.tried || root.kindTried ? root.keep() : root.cancel(); Ui.openSettings("personal"); } }
                    Item { Layout.fillWidth: true }
                    Button { text: Tr.t("Cancel"); kind: "outline"; onClicked: root.cancel() }
                    Button { text: root.tried || root.kindTried ? Tr.t("Keep this layout") : Tr.t("Use this layout"); kind: "primary"; onClicked: root.tried ? root.keep() : (root.tryOn(root.sel), root.keep()) }
                }
            }
        }
    }
}
