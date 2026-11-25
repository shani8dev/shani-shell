// The bar as a taskbar: your pinned and running apps in it (Services/Taskbar,
// the dock's own list), for the layouts where the bar is where apps live - a
// bottom taskbar with them at the start (as Windows 7 and KDE have it) or in
// the middle (as Windows 11 and ChromeOS do). A click starts an app, brings it
// forward or steps through its windows; the one in front is lit, a running one
// has a mark under it, as the dock marks them.
//
// With `search` on, the row starts with an ask-or-search box, where Windows 10
// kept Cortana's "Ask me anything" box and Windows 11 its Search: it opens the
// launcher, which searches everything and asks Chronoa what it cannot find.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Row {
    id: strip
    property real size: Theme.px(28)          // the icon; the button is a little bigger
    property bool above: false                // its hover labels go above (a bottom bar)
    property bool search: false               // an ask-or-search box first (Settings > barSearch)
    spacing: Theme.px(2)
    Accessible.role: Accessible.ToolBar
    Accessible.name: Tr.t("Apps")

    Rectangle {
        visible: strip.search
        width: Theme.px(200)
        height: strip.size + Theme.px(8)
        radius: height / 2
        color: searchArea.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.08)
        border.width: 1
        border.color: Theme.stroke
        Row {
            anchors { left: parent.left; leftMargin: Theme.px(12); verticalCenter: parent.verticalCenter }
            spacing: Theme.px(8)
            Icon { name: "system-search"; size: Theme.px(16); color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
            Text { text: Tr.t("Ask me anything"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: searchArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.IBeamCursor; onClicked: Ui.toggleLauncher("") }
        Hint { above: strip.above; text: Tr.t("Search your apps, files and settings, or ask Chronoa"); keys: "Super + Space" }
        KeyFocus { name: Tr.t("Ask me anything"); onActivated: Ui.toggleLauncher("") }
        Accessible.role: Accessible.Button
        Accessible.name: Tr.t("Ask me anything, or search")
        Accessible.onPressAction: Ui.toggleLauncher("")
    }
    Repeater {
        model: Taskbar.items
        Item {
            id: app
            required property var modelData
            readonly property bool open: modelData.windows.length > 0
            readonly property bool front: modelData.windows.some(w => w.id === Niri.focusedWindowId)
            readonly property string label: modelData.entry ? modelData.entry.name : modelData.id
            width: strip.size + Theme.px(12)
            height: strip.size + Theme.px(8)
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusSmall
                color: app.front ? Theme.alpha(Theme.accent, 0.22) : (area.containsMouse ? Theme.hover : "transparent")
            }
            AppIcon {
                anchors.centerIn: parent
                implicitSize: strip.size * (area.pressed ? 0.92 : 1)
                icon: app.modelData.entry ? app.modelData.entry.icon : app.modelData.id
                name: app.label
            }
            // running: a short mark under it; in front: a longer one
            Rectangle {
                visible: app.open
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                width: app.front ? Theme.px(16) : Theme.px(6)
                height: Theme.px(3)
                radius: height / 2
                color: app.front ? Theme.accent : Theme.dim
                Behavior on width { NumberAnimation { duration: Theme.anim } }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: e => {
                    if (e.button === Qt.MiddleButton && app.modelData.entry) Launch.app(app.modelData.entry.id);
                    else Taskbar.activate(app.modelData);
                }
            }
            Hint { above: strip.above; text: app.label + (app.modelData.windows.length > 1 ? " · " + Tr.t("%1 windows", app.modelData.windows.length) : "") }
            KeyFocus { name: app.label; onActivated: Taskbar.activate(app.modelData) }
            Accessible.role: Accessible.Button
            Accessible.name: app.label + (app.open ? ", " + Tr.t("open") : "")
            Accessible.onPressAction: Taskbar.activate(app.modelData)
        }
    }
}
