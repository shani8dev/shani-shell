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
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Modules.Notifications
import "../../Common/Gestures.js" as G

PanelWindow {
    id: win
    screen: Ui.screen
    Accessible.role: Accessible.Pane
    Accessible.name: Tr.t("Control centre")
    // a phone: the sidebar is a shade that covers the screen, so while it is
    // closed it must not be there at all - a transparent window would still
    // take the taps meant for the desktop
    readonly property bool narrow: FormFactor.focused.profile === "phone"
    visible: Ui.controlCenter || (!narrow && slide.x < width) || (narrow && slide.y < win.height - 1)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-sidebar"
    WlrLayershell.layer: WlrLayer.Overlay
    // while it is open it owns the keyboard: OnDemand let the arrows reach the
    // window behind the shade, so the d-pad walked out of the grid and B
    // (Escape) closed nothing
    WlrLayershell.keyboardFocus: Ui.controlCenter ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && Ui.controlCenter ? sideRegion : null
    Region { id: sideRegion; item: slide; radius: Theme.radiusLarge }

    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)

    readonly property var player: Media.current
    // the compass reads only while this is open
    Binding { target: Compass; property: "wanted"; value: Ui.controlCenter }
    readonly property var bt: Bluetooth.defaultAdapter
    property string confirm: ""        // the power action waiting for a second click

    // click outside closes
    MouseArea {
        objectName: "nav:pointer"          // a click outside closes it; Escape (a pad's B) does with keys
        anchors.fill: parent
        onClicked: Ui.closeAll()
    }

    Glass {
        id: slide
        strong: true
        // never wider than the screen (a phone's is ~412)
        readonly property bool narrow: win.narrow
        width: narrow ? parent.width : Math.min(Theme.px(420), parent.width - 20)
        // clear of the bar: on a board the bar is at the bottom, so the sidebar
        // starts at the top instead of below a bar that is not there
        readonly property bool bottomBar: FormFactor.barEdge(win.screen.name) === "bottom"
        // a phone: a shade up from the bottom, the whole width; everywhere else
        // one column in from the right, clear of the bar (docs/FORM-FACTORS.md)
        readonly property real insetTop: narrow ? Theme.px(10) : (bottomBar ? Theme.px(10) : Theme.barHeight + 18)
        y: narrow ? (Ui.controlCenter ? insetTop : parent.height) : insetTop
        height: Math.max(0, parent.height - Osk.heightOn(win.screen.name) - (narrow ? insetTop : y + (bottomBar ? Theme.barHeight + 18 : 10)))
        x: narrow ? 0 : (Ui.controlCenter ? parent.width - width - 10 : parent.width + 10)
        radius: Theme.radiusLarge
        Behavior on x {
            NumberAnimation {
                duration: Ui.controlCenter ? Theme.animEnter : Theme.animExit
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Ui.controlCenter ? Theme.emphasized : Theme.emphasizedExit
            }
        }
        Behavior on y {
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
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Home) { flick.contentY = 0; e.accepted = true; }
            else if (e.key === Qt.Key_End) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); e.accepted = true; }
        }
        // opened: the keyboard (or a controller) starts on the first control
        // focusFirst can scroll the first control into view and push the clock
        // header off the top; always open at the top of the panel
        Connections {
            target: Ui
            function onControlCenterChanged() {
                if (Ui.controlCenter) {
                    Ui.focusFirst(slide);
                    flick.contentY = 0;
                } else {
                    win.confirm = "";      // stale two-click power confirm must not survive a close
                }
            }
        }

        MouseArea { anchors.fill: parent; objectName: "nav:pointer" }   // swallow clicks so they don't close
        // A shade exits down; a desktop sidebar exits right. Keep vertical
        // dismissal on the shade's top handle so lists retain touch scrolling.
        Rectangle {
            visible: win.narrow
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.px(4)
            width: Theme.px(40)
            height: Theme.px(3)
            radius: height / 2
            color: Theme.dim
        }
        Item {
            visible: win.narrow
            width: parent.width
            height: Theme.px(16)
            DragHandler {
                target: null
                xAxis.enabled: false
                acceptedDevices: PointerDevice.TouchScreen
                onActiveChanged: if (!active && G.dismissed("down", translation.x, translation.y, Theme.px(80))) Ui.closeAll()
            }
        }
        DragHandler {
            enabled: !win.narrow
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            acceptedDevices: PointerDevice.TouchScreen
            onActiveChanged: if (!active && G.dismissed("right", translation.x, translation.y, Theme.px(80))) Ui.closeAll()
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

            ColumnLayout {
                id: col
                width: flick.width
                spacing: Theme.px(14)

                // ---- header ---------------------------------------------------
                SidebarHeader { objectName: "region:header"; Layout.fillWidth: true; sidebar: win; sidebarClock: clock }

                // ---- sliders --------------------------------------------------
                SidebarSliders { objectName: "region:sliders"; Layout.fillWidth: true; sidebar: win }

                // ---- tiles ----------------------------------------------------
                SidebarTiles { objectName: "region:tiles"; Layout.fillWidth: true; sidebar: win }

                // ---- detail lists -------------------------------------------
                SidebarDetails { objectName: "region:details"; Layout.fillWidth: true; sidebar: win; visible: Ui.expanded !== "" }

                // ---- quick notes ---------------------------------------------------
                SidebarNotes { objectName: "region:notes"; Layout.fillWidth: true }

                // a section with nothing to show takes no room (its own content's
                // condition, lifted here: QML's visible is the effective one, so a
                // section cannot ask its hidden children)
                // ---- screen time -------------------------------------------------
                SidebarScreenTime { objectName: "region:screentime"; Layout.fillWidth: true; visible: Settings.data.screenTime && ScreenTime.todayTotal >= 60 }

                // ---- shelf: the newest screenshots, recordings, downloads -------
                SidebarShelf { objectName: "region:shelf"; Layout.fillWidth: true; visible: Shelf.items.length > 0 }

                // ---- drives ------------------------------------------------------
                SidebarDrives { objectName: "region:drives"; Layout.fillWidth: true; visible: Drives.drives.length > 0 }

                // ---- calendar --------------------------------------------------
                SidebarCalendar { objectName: "region:calendar"; Layout.fillWidth: true; sidebarClock: clock }

                // ---- alarms & stopwatch ---------------------------------------
                SidebarClock { objectName: "region:clock"; Layout.fillWidth: true }

                // ---- now playing ------------------------------------------------
                SidebarNowPlaying { objectName: "region:nowplaying"; Layout.fillWidth: true; sidebar: win; visible: win.player !== null }

                // ---- notifications ------------------------------------------
                SidebarNotifications { objectName: "region:notifications"; Layout.fillWidth: true }

                Item { implicitHeight: Theme.px(4) }
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
