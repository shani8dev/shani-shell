// One of the shell's apps, as a window of its own: niri tiles it, floats it,
// puts it in Alt+Tab and the overview, and it stays open while the launcher,
// the sidebar or another app is used - what an overlay panel could not do.
//
//   AppWindow { appName: "Text Editor"; doc: "notes.txt"; visible: Ui.textEditor; onGone: Ui.textEditor = false; … }
//
// `appName` is the app's name in bin/shani's APPS table: every shell window
// reaches niri as "org.quickshell", and Services/Niri gives each the id of its
// desktop entry by this title, so the dock, the switcher and the bar show the
// app's own icon and name. `doc` (a file, a folder) goes in front of it, as
// "notes.txt — Text Editor". What is declared inside fills the window.
//
// The header is the shell's own, in its colours: Qt's decoration (a white
// Adwaita bar that ignores the theme) is off for the shell's process
// (QT_WAYLAND_DISABLE_WINDOWDECORATION, shani-shell.service). Drag it to move
// the window, double-click it to maximise; minimise, maximise and close at
// its end; the edges resize a floating window. An app can put its own buttons
// in the header (`tools: [ … ]`) instead of a toolbar row of its own.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Services
import "../Services/ShellApps.js" as ShellApps

FloatingWindow {
    id: win
    property string appName: ""
    property string doc: ""
    property int margins: Theme.px(14)
    property bool header: true
    readonly property bool compact: width < Theme.px(600)
    // its sidebar (Common/SidePane): on a narrow window a menu button in the header opens it
    property var sidePane: null
    // closed by the compositor (Mod+Q, the bar's close button) or by the app itself
    signal gone()
    default property alias content: body.data
    property alias tools: toolStrip.actions
    // Uniform shortcuts: an app points Ctrl+F at its search field and Ctrl+R at
    // its refresh action (both default to null, so existing apps keep theirs).
    // Escape and Ctrl+W always go through requestClose() so the unsaved-work
    // guard cannot be bypassed. A child that handles a key first still wins.
    property var shortcutSearch: null
    property var shortcutRefresh: null
    readonly property alias body: body
    readonly property string desktopId: ShellApps.idFor(appName)
    readonly property var entry: desktopId !== "" ? DesktopEntries.byId(desktopId) : null

    title: doc !== "" ? doc + " — " + appName : appName
    implicitWidth: Theme.px(900)
    implicitHeight: Theme.px(640)
    // glass, as the rest of the shell: translucent over a blur of what is behind
    // nearly solid (docs/DESIGN.md: glass for panels over the desktop, solid
    // for app content): at 0.86 a bright wallpaper tinted every app brown
    color: Settings.blurWanted ? Theme.alpha(Theme.bg, 0.97) : Theme.bg
    BackgroundEffect.blurRegion: Settings.blurWanted ? whole : null
    Region { id: whole; item: frame }
    onVisibleChanged: { if (!visible) win.gone(); register(); }
    Component.onCompleted: {
        register();
        Ui.registerAppWindow(win.desktopId, {
            close: () => { win.requestClose(); },
            minimise: () => { Niri.minimiseWindowByTitle(win.title); }
        });
    }
    Component.onDestruction: { const r = Object.assign({}, Ui.navRoots); delete r[win.appName]; Ui.navRoots = r; Ui.unregisterAppWindow(win.desktopId); }
    // the content, by app, for Ui.navAudit (the tests' reach check)
    function register() {
        const r = Object.assign({}, Ui.navRoots);
        if (visible) r[win.appName] = frame; else delete r[win.appName];
        Ui.navRoots = r;
    }

    function toggleMaximised() { win.maximized = !win.maximized; }

    // Every close path (the X, Mod+Q, the dock) asks here first. The editor keeps
    // unsaved text in TextDocs across a window close, so offer Save / Discard.
    property bool closePending: false
    function canClose() {
        if (win.appName === "Text Editor" && TextDocs.unsaved > 0) {
            closePending = true;
            return false;
        }
        return true;
    }
    function requestClose() { if (canClose()) win.visible = false; }

    Item {
        id: frame
        anchors.fill: parent
        Accessible.role: Accessible.Window
        Accessible.name: win.title
        // Reach a scrolling toolbar without tabbing through a document's text.
        Keys.onPressed: e => {
            if (e.key === Qt.Key_F6) {
                Ui.focusFirst(e.modifiers & Qt.ShiftModifier || !toolStrip.visible ? body : toolStrip.row);
                e.accepted = true;
            }
            // the standard set shared by every app window: the app supplies the
            // search field and refresh action, closing goes through the guard
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F && win.shortcutSearch) {
                win.shortcutSearch.forceActiveFocus();
                e.accepted = true;
            }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_R && win.shortcutRefresh) {
                win.shortcutRefresh();
                e.accepted = true;
            }
            else if (e.key === Qt.Key_Escape) {
                win.requestClose();
                e.accepted = true;
            }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_W) {
                win.requestClose();
                e.accepted = true;
            }
            // the Menu key (a controller's X) on something with no menu of its own:
            // the window's menu - minimise, maximise, move, close - as a click in the header would
            // an arrow or Tab with nothing focused yet (the window just opened): the first
            // control takes it, so the d-pad starts somewhere instead of nowhere
            else if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right, Qt.Key_Tab, Qt.Key_Backtab].indexOf(e.key) >= 0
                     && (!win.activeFocusItem || win.activeFocusItem === frame || win.activeFocusItem === body)) {
                // only when nothing in the app has focus: a key a text field did
                // not accept still reaches the window, and must not yank focus
                // back to the first control (an arrow in a field moves within it)
                Ui.keyMovedAt = Date.now();
                Ui.focusFirst(body);
                e.accepted = true;
            }
            else if (e.key === Qt.Key_Menu) {
                Ui.windowMenuX = 200;
                Ui.windowMenu = true;
                e.accepted = true;
            }
        }

        // ---- the header: icon, title, the app's own buttons, the window's ----
        Rectangle {
            id: bar
            visible: win.header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: visible ? Math.max(Theme.px(42), Theme.touchTarget + Theme.space(2), toolStrip.visible ? toolStrip.implicitHeight : 0) : 0
            color: Theme.surface1
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }

            // the empty part of the header moves the window, and maximises it on a double click
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: win.startSystemMove()
                onDoubleClicked: win.toggleMaximised()
            }

            RowLayout {
                anchors { fill: parent; leftMargin: Theme.px(12); rightMargin: Theme.px(6) }
                spacing: Theme.px(8)
                WindowButton {
                    visible: win.compact && win.sidePane !== null
                    icon: "open-menu"
                    tip: win.sidePane ? win.sidePane.label : ""
                    onClicked: win.sidePane.open = !win.sidePane.open
                }
                Image {
                    Layout.preferredWidth: Theme.px(20)
                    Layout.preferredHeight: Theme.px(20)
                    sourceSize: Qt.size(40, 40)
                    source: win.entry && win.entry.icon ? Quickshell.iconPath(win.entry.icon, true) : ""
                    visible: source != ""
                }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: win.doc !== "" ? win.doc : win.appName
                    textFormat: Text.PlainText
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                    font.weight: Font.DemiBold
                    Accessible.ignored: true
                }
                Text {
                    visible: win.doc !== "" && !win.compact
                    Layout.maximumWidth: win.width * 0.25
                    text: win.appName
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                    rightPadding: Theme.px(6)
                    Accessible.ignored: true
                }
                ActionStrip {
                    id: toolStrip
                    visible: row.children.length > 0
                    Layout.maximumWidth: win.width * (win.compact ? 0.45 : 0.60)
                    spacing: Theme.space(1)
                }
                Rectangle { visible: toolStrip.visible; Layout.preferredWidth: 1; Layout.preferredHeight: Theme.px(20); color: Theme.border }
                WindowButton { visible: !win.compact; icon: "window-minimize"; tip: Tr.t("Minimise"); onClicked: Ui.minimise(win.desktopId) }
                WindowButton { visible: !win.compact; icon: win.maximized ? "window-restore" : "window-maximize"; tip: win.maximized ? Tr.t("Restore") : Tr.t("Maximise"); onClicked: win.toggleMaximised() }
                WindowButton { icon: "window-close"; tip: Tr.t("Close"); danger: true; onClicked: win.requestClose() }
            }
        }

        Item {
            id: body
            anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom }
            anchors.margins: win.margins
            focus: true
            // QtQuick.Controls inside an app (a field, a combo box, a spin box)
            // draw with the palette: left alone they are white boxes with
            // dark text on the shell's dark glass
            palette.window: Theme.bg
            palette.windowText: Theme.text
            palette.base: Theme.surface1
            palette.alternateBase: Theme.surface2
            palette.text: Theme.text
            palette.placeholderText: Theme.dim
            palette.button: Theme.surface2
            palette.buttonText: Theme.text
            palette.highlight: Theme.accent
            palette.highlightedText: Theme.accentInk
            palette.mid: Theme.border
            palette.dark: Theme.border
            palette.light: Theme.surface3
        }

        // ---- the edges and corners resize a floating window (niri sizes a tiled one) ----
        Repeater {
            model: [
                { e: Qt.TopEdge, x: 0, y: 0, w: -1, h: 5, c: Qt.SizeVerCursor },
                { e: Qt.BottomEdge, x: 0, y: -5, w: -1, h: 5, c: Qt.SizeVerCursor },
                { e: Qt.LeftEdge, x: 0, y: 0, w: 5, h: -1, c: Qt.SizeHorCursor },
                { e: Qt.RightEdge, x: -5, y: 0, w: 5, h: -1, c: Qt.SizeHorCursor },
                { e: Qt.TopEdge | Qt.LeftEdge, x: 0, y: 0, w: 10, h: 10, c: Qt.SizeFDiagCursor },
                { e: Qt.TopEdge | Qt.RightEdge, x: -10, y: 0, w: 10, h: 10, c: Qt.SizeBDiagCursor },
                { e: Qt.BottomEdge | Qt.LeftEdge, x: 0, y: -10, w: 10, h: 10, c: Qt.SizeBDiagCursor },
                { e: Qt.BottomEdge | Qt.RightEdge, x: -10, y: -10, w: 10, h: 10, c: Qt.SizeFDiagCursor }
            ]
            MouseArea {
                required property var modelData
                x: modelData.x < 0 ? frame.width + modelData.x : modelData.x
                y: modelData.y < 0 ? frame.height + modelData.y : modelData.y
                width: modelData.w < 0 ? frame.width : modelData.w
                height: modelData.h < 0 ? frame.height : modelData.h
                cursorShape: modelData.c
                enabled: !win.maximized
                onPressed: win.startSystemResize(modelData.e)
            }
        }

        // The unsaved-work choice. Shown only while a close is pending, over the
        // bottom of the app; every button clears the flag before acting.
        Rectangle {
            id: closeGuard
            visible: win.closePending
            z: 20
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: visible ? Math.max(Theme.px(42), Theme.touchTarget + Theme.px(8)) : 0
            color: Theme.surface2
            RowLayout {
                anchors { fill: parent; leftMargin: Theme.px(10); rightMargin: Theme.px(6) }
                spacing: Theme.px(6)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Save changes before closing?")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                    elide: Text.ElideRight
                }
                GuardButton { label: Tr.t("Cancel"); onClicked: win.closePending = false }
                GuardButton { label: Tr.t("Discard"); onClicked: { win.closePending = false; win.visible = false; } }
                GuardButton { label: Tr.t("Save"); primary: true; onClicked: { TextDocs.save(); win.closePending = false; win.visible = false; } }
            }
        }
    }

    component GuardButton: Rectangle {
        id: gb
        property string label
        property bool primary: false
        signal clicked()
        Layout.preferredHeight: Math.max(Theme.px(30), Theme.touchTarget)
        Layout.preferredWidth: gb.label.length * Theme.px(8) + Theme.px(24)
        radius: Theme.px(8)
        color: area.pressed ? Theme.pressed : area.containsMouse ? Theme.hover : (gb.primary ? Theme.accent : Theme.surface3)
        Text {
            anchors.centerIn: parent
            text: gb.label
            color: gb.primary ? Theme.accentInk : Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
        }
        Accessible.role: Accessible.Button
        Accessible.name: gb.label
        Accessible.onPressAction: gb.clicked()
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: gb.clicked() }
        KeyFocus { name: gb.label; onActivated: gb.clicked() }
    }

    component WindowButton: Rectangle {
        id: wb
        property string icon
        property string tip
        property bool danger: false
        signal clicked()
        Layout.preferredWidth: Math.max(Theme.px(30), Theme.touchTarget)
        Layout.preferredHeight: Math.max(Theme.px(30), Theme.touchTarget)
        radius: Theme.px(15)
        color: area.pressed ? (danger ? Theme.danger : Theme.pressed) : area.containsMouse ? (danger ? Theme.alpha(Theme.danger, 0.85) : Theme.hover) : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: tip
        Accessible.onPressAction: wb.clicked()
        Icon {
            anchors.centerIn: parent
            name: wb.icon
            size: Theme.px(16)
            color: wb.danger && area.containsMouse ? "white" : Theme.dim
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            onClicked: wb.clicked()
        }
        KeyFocus { name: wb.tip; onActivated: wb.clicked() }
        Hint { text: wb.tip }
    }
}
