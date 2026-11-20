// The Media Player's Radio page (Shortwave parity): your favourite stations, the
// most played, the ones near you, a genre, or a search - a click plays one, the
// star keeps it. The stations are radio-browser.info's (Services/Radio).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: view
    spacing: Theme.px(8)

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Theme.px(10)
        spacing: Theme.px(8)
        TextField {
            id: find
            Layout.fillWidth: true
            placeholderText: Tr.t("Find a station")
            onAccepted: if (text.trim()) Radio.show("search:" + text.trim())
        }
        Button { text: Tr.t("Find"); enabled: find.text.trim() !== ""; onClicked: Radio.show("search:" + find.text.trim()) }
    }
    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.px(10)
        Layout.rightMargin: Theme.px(10)
        spacing: Theme.px(6)
        Repeater {
            model: [["favourites", Tr.t("Favourites")], ["popular", Tr.t("Popular")], ["near", Tr.t("Near you")],
                    ["genre:news", Tr.t("News")], ["genre:pop", Tr.t("Pop")], ["genre:rock", Tr.t("Rock")], ["genre:jazz", Tr.t("Jazz")],
                    ["genre:classical", Tr.t("Classical")], ["genre:bollywood", Tr.t("Bollywood")], ["genre:devotional", Tr.t("Devotional")],
                    ["genre:talk", Tr.t("Talk")], ["genre:electronic", Tr.t("Electronic")]]
            Choice { required property var modelData; text: modelData[1]; selected: Radio.showing === modelData[0]; onClicked: Radio.show(modelData[0]) }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.px(10)
        visible: Radio.loading || Radio.error !== "" || (!Radio.loading && Radio.stations.length === 0)
        wrapMode: Text.WordWrap
        text: Radio.loading ? Tr.t("Looking…") : Radio.error !== "" ? Radio.error
            : Radio.showing === "favourites" ? Tr.t("No favourites yet: the star on a station keeps it here.") : Tr.t("No stations found")
        color: Radio.error !== "" ? Theme.danger : Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: Radio.stations
        delegate: Rectangle {
            id: row
            required property var modelData
            width: list.width
            height: Theme.px(52)
            radius: Theme.px(8)
            readonly property bool playing: PlayQueue.current === modelData.url
            color: playing ? Theme.accentSoft : (area.containsMouse ? Theme.hover : "transparent")
            MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Radio.play(row.modelData) }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.px(10)
                anchors.rightMargin: Theme.px(6)
                spacing: Theme.px(10)
                Item {
                    Layout.preferredWidth: Theme.px(36); Layout.preferredHeight: Theme.px(36)
                    Image {
                        id: logo
                        anchors.fill: parent
                        source: row.modelData.favicon || ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize: Qt.size(Theme.px(72), Theme.px(72))
                        visible: status === Image.Ready
                    }
                    Icon { anchors.centerIn: parent; visible: logo.status !== Image.Ready; name: "audio-x-generic"; size: Theme.px(22); color: Theme.dim }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: row.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: row.playing ? Font.DemiBold : Font.Normal }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: [row.modelData.tags, row.modelData.country, row.modelData.bitrate ? row.modelData.bitrate + " kbps" : ""].filter(x => x).join("  ·  ")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                IconButton {
                    icon: Radio.isFavourite(row.modelData) ? "starred" : "non-starred"
                    on: Radio.isFavourite(row.modelData)
                    size: Theme.px(28)
                    tip: Radio.isFavourite(row.modelData) ? Tr.t("Forget %1", row.modelData.name) : Tr.t("Keep %1 in Favourites", row.modelData.name)
                    onClicked: Radio.toggleFavourite(row.modelData)
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: row.modelData.name
            Accessible.onPressAction: Radio.play(row.modelData)
        }
    }
}
