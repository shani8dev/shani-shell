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
    tools: [ IconButton { size: Theme.px(30); icon: "view-refresh"; tip: Tr.t("Refresh"); onClicked: Characters.browse() } ]
    visible: Ui.characters
    onGone: Ui.characters = false
    margins: 0
    implicitWidth: Theme.px(640)
    implicitHeight: Theme.px(580)

    property string copiedLabel: ""

    function copyChar(entry) {
        if (!entry || !entry.ch)
            return;
        Characters.copy(entry);
        win.copiedLabel = entry.ch + "  " + (entry.name || "");
        copiedTimer.restart();
    }

    onVisibleChanged: if (visible) { Characters.browse(); searchField.forceActiveFocus() }
    Component.onCompleted: if (visible) { Characters.browse(); searchField.forceActiveFocus() }

    Timer { id: copiedTimer; interval: 1800; onTriggered: win.copiedLabel = "" }

    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.characters = false }

    Item {
        id: card
        anchors.fill: parent


        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(12)

            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholder: Tr.t("Search symbols, arrows, math, scripts — “arrow”, “devanagari”, “rupee”…")
                label: Tr.t("Search characters")
                onTextChanged: Characters.search(text)
                onAccepted: if (Characters.results.length > 0) win.copyChar(Characters.results[0])
            }

            // quick categories, one tap each — the Unicode blocks the bridge
            // indexes (bridge/characters.py RANGES), not just the first six
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: ["Symbols", "Arrows", "Math", "Currency", "Latin", "Greek", "Cyrillic", "Hebrew", "Arabic", "Devanagari", "Bengali", "Tamil", "Telugu", "Malayalam", "Emoji"]
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
                Accessible.role: Accessible.List
                Accessible.name: Tr.t("Character results")

                Connections {
                    target: Characters
                    function onResultsChanged() { grid.contentY = 0 }
                }

                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    radius: Theme.px(10)
                    color: cellArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: cell.modelData.name
                    Accessible.onPressAction: win.copyChar(cell.modelData)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(4)
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.ch
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(22) * Theme.fontScale
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.name
                            color: Theme.dim
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.type("caption")
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: "U+" + cell.modelData.cp.toString(16).toUpperCase().padStart(4, "0")
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.mono
                            font.pixelSize: Theme.type("caption")
                        }
                    }
                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.copyChar(cell.modelData)
                    }
                    KeyFocus {
                        name: cell.modelData.name
                        onActivated: win.copyChar(cell.modelData)
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
                text: win.copiedLabel !== "" ? Tr.t("Copied %1 · Esc closes", win.copiedLabel)
                    : Characters.results.length ? Tr.t("Click a character to copy it · Enter copies first · Esc closes")
                    : (Characters.loaded ? Tr.t("No results") : Tr.t("Searching Unicode…"))
                color: win.copiedLabel !== "" ? Theme.accent : Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: Theme.type("caption")
            }
        }
    }
}
