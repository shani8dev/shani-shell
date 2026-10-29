// Settings, as a window of its own: the categories down the left (with a
// search), the chosen one on the right - room for Displays' arrangement,
// Sound's equaliser and Automations, which the control centre's narrow column
// never had. The pages themselves are SettingsPage's, made when opened.
// Ui.openSettings(cat) opens it; Escape or the window's close closes it.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.ControlCenter

FloatingWindow {
    id: win
    title: Tr.t("Settings")
    visible: Ui.settingsOpen
    implicitWidth: 1040
    implicitHeight: 760
    // glass, as the rest of the shell: translucent over a blur of what is behind
    color: Settings.data.blur ? Theme.alpha(Theme.bg, 0.82) : Theme.bg
    BackgroundEffect.blurRegion: Settings.data.blur ? whole : null
    Region { id: whole; item: winRoot }
    // closed by the compositor (Super+Q, its close button): Settings knows
    onVisibleChanged: if (!visible) Ui.settingsOpen = false

    Item {
        id: winRoot
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.settingsOpen = false

        // ---- the categories -------------------------------------------------------
        Rectangle {
            id: side
            width: 260
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            color: Settings.data.blur ? Theme.alpha(Theme.surface1, 0.55) : Theme.surface1
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                Text {
                    text: Tr.t("Settings")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 20 * Theme.fontScale
                    font.weight: Font.DemiBold
                    Layout.leftMargin: 6
                    Layout.topMargin: 6
                }
                TextField {
                    id: search
                    Layout.fillWidth: true
                    placeholder: Tr.t("Search settings")
                    onAccepted: if (list.count) Ui.settingsCat = page.shownCats[0].id
                    // typing starts a search, as in GNOME's and Windows' Settings
                    Component.onCompleted: search.input.forceActiveFocus()
                    Connections { target: search.input; function onTextChanged() { page.query = search.text; } }
                }
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: page.shownCats
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool current: Ui.settingsCat === modelData.id
                        width: ListView.view.width
                        height: 40
                        radius: Theme.radiusSmall
                        color: current ? Theme.accentSoft : (rowArea.containsMouse ? Theme.surface2 : "transparent")
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.label
                        Accessible.onPressAction: Ui.settingsCat = modelData.id
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12
                            Icon { name: row.modelData.icon; size: 18; color: row.current ? Theme.accent : Theme.dim }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                elide: Text.ElideRight
                                color: row.current ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 13 * Theme.fontScale
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                            }
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Ui.settingsCat = row.modelData.id }
                    }
                }
            }
        }

        // ---- the chosen one ---------------------------------------------------------
        Flickable {
            id: content
            anchors { top: parent.top; bottom: parent.bottom; left: side.right; right: parent.right }
            anchors.margins: 28
            contentHeight: body.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: body
                width: Math.min(content.width, 720)
                spacing: 16
                Text {
                    text: page.catTitle
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 24 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                SettingsPage {
                    id: page
                    Layout.fillWidth: true
                    inWindow: true
                }
            }
            // a new category starts at its top
            Connections { target: Ui; function onSettingsCatChanged() { content.contentY = 0; } }
        }
    }
}
