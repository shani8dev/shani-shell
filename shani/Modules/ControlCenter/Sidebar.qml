// The sidebar (after Budgie's Raven): one column sliding in from the right edge,
// everything you reach for without opening an app. Top to bottom: the hour and
// the power row, sliders, the quick-settings tiles and their detail lists, a
// calendar, what is playing, and the notifications — each with "Ask Chronoa".
// A tile appears only where it can work (no flashlight on a desktop, no
// auto-rotate without an accelerometer).
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import Quickshell.Bluetooth
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Notifications

PanelWindow {
    id: win
    screen: Ui.screen
    visible: Ui.controlCenter || slide.x < width
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-sidebar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Ui.controlCenter ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.data.blur && Ui.controlCenter ? sideRegion : null
    Region { id: sideRegion; item: slide; radius: Theme.radiusLarge }

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    readonly property var bt: Bluetooth.defaultAdapter
    property string confirm: ""        // the power action waiting for a second click

    // click outside closes
    MouseArea {
        anchors.fill: parent
        onClicked: Ui.closeAll()
    }

    Glass {
        id: slide
        strong: true
        width: 420
        y: Theme.barHeight + 18
        height: parent.height - y - 10
        x: Ui.controlCenter ? parent.width - width - 10 : parent.width + 10
        radius: Theme.radiusLarge
        Behavior on x {
            NumberAnimation {
                duration: Ui.controlCenter ? Theme.animEnter : Theme.animExit
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Ui.controlCenter ? Theme.emphasized : Theme.emphasizedExit
            }
        }
        opacity: Ui.controlCenter ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Ui.controlCenter ? Theme.animEnter / 2 : Theme.animExit } }
        focus: Ui.controlCenter
        Keys.onEscapePressed: Ui.closeAll()

        MouseArea { anchors.fill: parent }   // swallow clicks so they don't close

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col
                width: flick.width
                spacing: 14

                // ---- header ---------------------------------------------------
                SidebarHeader { Layout.fillWidth: true; sidebar: win; sidebarClock: clock }

                // ---- sliders --------------------------------------------------
                SidebarSliders { Layout.fillWidth: true; sidebar: win }

                // ---- tiles ----------------------------------------------------
                SidebarTiles { Layout.fillWidth: true; sidebar: win }

                // ---- detail lists -------------------------------------------
                SidebarDetails { Layout.fillWidth: true; sidebar: win; visible: Ui.expanded !== "" }

                // ---- quick notes ---------------------------------------------------
                SidebarNotes { Layout.fillWidth: true }

                // a section with nothing to show takes no room (its own content's
                // condition, lifted here: QML's visible is the effective one, so a
                // section cannot ask its hidden children)
                // ---- screen time -------------------------------------------------
                SidebarScreenTime { Layout.fillWidth: true; visible: Settings.data.screenTime && ScreenTime.todayTotal >= 60 }

                // ---- shelf: the newest screenshots, recordings, downloads -------
                SidebarShelf { Layout.fillWidth: true; visible: Shelf.items.length > 0 }

                // ---- drives ------------------------------------------------------
                SidebarDrives { Layout.fillWidth: true; visible: Drives.drives.length > 0 }

                // ---- calendar --------------------------------------------------
                SidebarCalendar { Layout.fillWidth: true; sidebarClock: clock }

                // ---- now playing ------------------------------------------------
                SidebarNowPlaying { Layout.fillWidth: true; sidebar: win; visible: win.player !== null }

                // ---- notifications ------------------------------------------
                SidebarNotifications { Layout.fillWidth: true }

                Item { implicitHeight: 4 }
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
