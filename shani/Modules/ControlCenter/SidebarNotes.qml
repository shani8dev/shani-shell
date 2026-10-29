// The control centre's quick notes (one section of Sidebar.qml).
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
    // a section whose parts are all hidden takes no room (no double gap)
    visible: Array.from(children).some(c => c.visible)

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Notes") }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.max(64, notes.contentHeight + 20)
        radius: Theme.radiusSmall
        color: Theme.hover
        border.width: notes.activeFocus ? 1 : 0
        border.color: Theme.accentLine
        TextEdit {
            id: notes
            Accessible.role: Accessible.EditableText
            Accessible.name: Tr.t("Quick notes")
            anchors.fill: parent
            anchors.margins: 10
            text: QuickNotes.text
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.accentInk
            wrapMode: TextEdit.Wrap
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
            onTextChanged: if (activeFocus) QuickNotes.set(text)
            Text {
                visible: notes.text === ""
                text: Tr.t("Jot something down — saved to Documents/Notes/quick.md")
                color: Theme.faint
                font: notes.font
            }
        }
    }
}
