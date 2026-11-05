// The search results for Settings: the matching settings (not just
// categories), each with its current value and an amber dot when it differs
// from the shipped default. Activating one jumps to its category and flashes
// the control — see SettingsIndex.js and Ui.flashSetting.
import QtQuick
import QtQuick.Layouts
import qs.Common
import "SettingsIndex.js" as SettingsIndex

ColumnLayout {
    id: root
    spacing: 2
    property var matches: []
    property var icons: ({})          // category id → icon name (the page's cats)
    property string needle: ""          // the current search query, for highlighting
    readonly property var d: Settings.data
    readonly property var defaults: Settings.defaults
    signal activated(var entry)

    Text {
        text: Tr.t("Settings")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
        Layout.leftMargin: 2
    }
    Repeater {
        model: root.matches
        Rectangle {
            id: matchRow
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Theme.radiusSmall
            color: matchArea.containsMouse ? Theme.surface3 : "transparent"
            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
            Accessible.onPressAction: root.activated(modelData)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 10
                spacing: 10
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: 8
                    color: Theme.accentSoft
                    Icon {
                        anchors.centerIn: parent
                        name: root.icons[matchRow.modelData.cat] || "system-search"
                        size: 15
                        color: Theme.accent
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    HighlightText {
                        Layout.fillWidth: true
                        sourceText: matchRow.modelData.label
                        needle: root.needle
                        color: Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: matchRow.modelData.hint || ""
                        visible: text !== ""
                        color: Theme.faint
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: SettingsIndex.valueSummary(root.d, matchRow.modelData.key)
                    color: root.modifiedKey(matchRow.modelData.key) ? Theme.accent : Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 10 * Theme.fontScale
                }
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.modifiedKey(matchRow.modelData.key)
                    implicitWidth: 7
                    implicitHeight: 7
                    radius: 3.5
                    color: Theme.accent
                }
            }
            MouseArea {
                id: matchArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated(matchRow.modelData)
            }
            KeyFocus { onActivated: root.activated(matchRow.modelData) }
        }
    }
    function modifiedKey(key) {
        const v = root.d[key];
        if (!SettingsIndex.isScalar(v))
            return true;
        return JSON.stringify(v) !== JSON.stringify(root.defaults[key]);
    }
}
