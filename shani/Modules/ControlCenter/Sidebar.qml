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
        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        focus: Ui.controlCenter
        Keys.onEscapePressed: Ui.closeAll()

        MouseArea { anchors.fill: parent }   // swallow clicks so they don't close

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            visible: Ui.expanded === "settings"
            contentHeight: settingsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: settingsCol
                width: parent.width
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    // back: out of a category, then out of settings
                    IconButton { icon: "go-previous"; Accessible.name: Tr.t("Back"); onClicked: Ui.settingsCat !== "" ? Ui.settingsCat = "" : Ui.expanded = "" }
                    Text { text: settingsPage.catTitle; color: Theme.text; font.family: Theme.font; font.pixelSize: 16 * Theme.fontScale; font.weight: Font.DemiBold; Layout.fillWidth: true }
                }
                SettingsPage {
                    id: settingsPage
                    Layout.fillWidth: true
                    visible: Ui.expanded === "settings"
                    onVisibleChanged: if (!visible) Ui.settingsCat = ""
                }
            }
        }

        Flickable {
            id: flick
            visible: Ui.expanded !== "settings"
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
                SidebarDetails { Layout.fillWidth: true; sidebar: win }

                // ---- quick notes ---------------------------------------------------
                SidebarNotes { Layout.fillWidth: true }

                // ---- screen time -------------------------------------------------
                SidebarScreenTime { Layout.fillWidth: true }

                // ---- shelf: the newest screenshots, recordings, downloads -------
                SidebarShelf { Layout.fillWidth: true }

                // ---- drives ------------------------------------------------------
                SidebarDrives { Layout.fillWidth: true }

                // ---- calendar --------------------------------------------------
                SidebarCalendar { Layout.fillWidth: true; sidebarClock: clock }

                // ---- now playing ------------------------------------------------
                SidebarNowPlaying { Layout.fillWidth: true; sidebar: win }

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
