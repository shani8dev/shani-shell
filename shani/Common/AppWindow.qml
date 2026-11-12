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
import "../Services/ShellApps.js" as ShellApps

FloatingWindow {
    id: win
    property string appName: ""
    property string doc: ""
    property int margins: 14
    property bool header: true
    // closed by the compositor (Mod+Q, the bar's close button) or by the app itself
    signal gone()
    default property alias content: body.data
    property alias tools: toolRow.data
    readonly property alias body: body
    readonly property string desktopId: ShellApps.idFor(appName)
    readonly property var entry: desktopId !== "" ? DesktopEntries.byId(desktopId) : null

    title: doc !== "" ? doc + " — " + appName : appName
    implicitWidth: 900
    implicitHeight: 640
    // glass, as the rest of the shell: translucent over a blur of what is behind
    color: Settings.blurWanted ? Theme.alpha(Theme.bg, 0.86) : Theme.bg
    BackgroundEffect.blurRegion: Settings.blurWanted ? whole : null
    Region { id: whole; item: frame }
    onVisibleChanged: if (!visible) win.gone()

    function toggleMaximised() { win.maximized = !win.maximized; }

    Item {
        id: frame
        anchors.fill: parent

        // ---- the header: icon, title, the app's own buttons, the window's ----
        Rectangle {
            id: bar
            visible: win.header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: visible ? 42 : 0
            color: Settings.blurWanted ? Theme.alpha(Theme.surface1, 0.7) : Theme.surface1
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }

            // the empty part of the header moves the window, and maximises it on a double click
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onPressed: m => { if (m.button === Qt.LeftButton) win.startSystemMove(); }
                onDoubleClicked: win.toggleMaximised()
                onClicked: m => { if (m.button === Qt.MiddleButton) win.visible = false; }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 6 }
                spacing: 8
                Image {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    sourceSize: Qt.size(40, 40)
                    source: win.entry && win.entry.icon ? Quickshell.iconPath(win.entry.icon, true) : ""
                    visible: source != ""
                }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 60
                    text: win.doc !== "" ? win.doc : win.appName
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                    font.weight: Font.DemiBold
                    Accessible.ignored: true
                }
                Text {
                    visible: win.doc !== ""
                    text: win.appName
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                    rightPadding: 6
                    Accessible.ignored: true
                }
                RowLayout {
                    id: toolRow
                    spacing: 2
                }
                Rectangle { visible: toolRow.children.length > 0; Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: Theme.border }
                WindowButton { icon: "window-minimize"; tip: Tr.t("Minimise"); onClicked: Ui.minimiseFocused() }
                WindowButton { icon: win.maximized ? "window-restore" : "window-maximize"; tip: win.maximized ? Tr.t("Restore") : Tr.t("Maximise"); onClicked: win.toggleMaximised() }
                WindowButton { icon: "window-close"; tip: Tr.t("Close"); danger: true; onClicked: win.visible = false }
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
            palette.placeholderText: Theme.faint
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
    }

    component WindowButton: Rectangle {
        id: wb
        property string icon
        property string tip
        property bool danger: false
        signal clicked()
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        radius: 15
        color: area.pressed ? (danger ? Theme.danger : Theme.pressed) : area.containsMouse ? (danger ? Theme.alpha(Theme.danger, 0.85) : Theme.hover) : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: tip
        Accessible.onPressAction: wb.clicked()
        Icon {
            anchors.centerIn: parent
            name: wb.icon
            size: 16
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
