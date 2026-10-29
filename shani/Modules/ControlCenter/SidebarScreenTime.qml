// The control centre's screen time (one section of Sidebar.qml).
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

ColumnLayout {
    spacing: 14

    ColumnLayout {
        visible: Settings.data.screenTime && ScreenTime.todayTotal >= 60
        Layout.fillWidth: true
        spacing: 6
        SectionTitle { text: "Screen time today · " + ScreenTime.label(ScreenTime.todayTotal) }
        Repeater {
            model: ScreenTime.top
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.preferredWidth: 110
                    text: modelData.app
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Theme.hover
                    Rectangle {
                        width: parent.width * modelData.seconds / Math.max(1, ScreenTime.top[0].seconds)
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                    }
                }
                Text {
                    Layout.preferredWidth: 70
                    horizontalAlignment: Text.AlignRight
                    text: ScreenTime.label(modelData.seconds)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                }
            }
        }
    }
}
