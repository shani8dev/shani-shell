// The character browser: symbols, math, arrows, Indic scripts and emoji by
// keyword, after the launcher's ":" (which used to know only emoji).
// Type "arrow", "devanagari", "rupee" or "checkmark"; click a cell to
// copy the character, Enter copies it too, Esc closes.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Characters"
    tools: [ IconButton { size: 30; icon: "view-refresh"; tip: Tr.t("Refresh"); onClicked: Characters.browse() } ]
    visible: Ui.characters
    onGone: Ui.characters = false
    margins: 0
    implicitWidth: 640
    implicitHeight: 580

    onVisibleChanged: if (visible) Characters.browse()
    Component.onCompleted: if (visible) Characters.browse()

    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.characters = false }

    Item {
        id: card
        anchors.fill: parent


        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholder: Tr.t("Search symbols, arrows, math, scripts — “arrow”, “devanagari”, “rupee”…")
                label: Tr.t("Search characters")
                onTextChanged: Characters.search(text)
            }

            // quick categories, one tap each
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: ["Symbols", "Arrows", "Math", "Devanagari", "Greek", "Emoji"]
                    Choice {
                        required property string modelData
                        text: modelData
                        selected: searchField.text.toLowerCase() === modelData.toLowerCase()
                        onClicked: {
                            searchField.text = modelData;
                            Characters.search(modelData);
                        }
                    }
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 92
                cellHeight: 76
                model: Characters.results
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    radius: 10
                    color: cellArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: cell.modelData.name
                    Accessible.onPressAction: Characters.copy(cell.modelData)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.ch
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 22 * Theme.fontScale
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.name
                            color: Theme.faint
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 9 * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: "U+" + cell.modelData.cp.toString(16).toUpperCase().padStart(4, "0")
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.mono
                            font.pixelSize: 9 * Theme.fontScale
                        }
                    }
                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Characters.copy(cell.modelData)
                    }
                    KeyFocus {
                        name: cell.modelData.name
                        onActivated: Characters.copy(cell.modelData)
                    }
                }
            }

            EmptyState {
                Layout.fillWidth: true
                visible: Characters.loaded && Characters.results.length === 0
                icon: "preferences-desktop-font"
                title: Tr.t("No characters match")
                subtitle: Tr.t("Try a word like arrow, star, rupee, devanagari or math")
            }

            Item { Layout.fillWidth: true }
            Text {
                Layout.fillWidth: true
                text: Characters.results.length ? Tr.t("Click a character to copy it · Esc closes") : Tr.t("Searching Unicode…")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
