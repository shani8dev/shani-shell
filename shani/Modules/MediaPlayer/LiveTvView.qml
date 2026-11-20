// The Media Player's Live TV page (the Hypnotix idea): load an M3U playlist -
// your own URL or a local file - and the channels are listed by group. Clicking
// one plays it in the Media Player. No channels are bundled with the shell.
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
            id: source
            Layout.fillWidth: true
            text: LiveTv.source
            placeholderText: Tr.t("M3U playlist URL or file")
            Accessible.name: Tr.t("M3U playlist URL or file")
            onAccepted: if (text.trim()) LiveTv.load(text.trim())
        }
        Button {
            text: Tr.t("Browse…")
            onClicked: FilePicker.open({ mode: "open", title: Tr.t("An M3U playlist"),
                                         onPicked: paths => { if (paths.length) LiveTv.load(paths[0]); } })
        }
        Button {
            text: Tr.t("Load")
            enabled: source.text.trim() !== "" && !LiveTv.loading
            onClicked: LiveTv.load(source.text.trim())
        }
    }
    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.px(10)
        Layout.rightMargin: Theme.px(10)
        spacing: Theme.px(6)
        Choice { text: Tr.t("Free picks"); selected: LiveTv.builtIn; onClicked: LiveTv.loadDefaults() }
        Choice {
            text: Tr.t("Free TV (community)")
            selected: !LiveTv.builtIn && LiveTv.source === LiveTv.freeTvUrl
            onClicked: LiveTv.load(LiveTv.freeTvUrl)
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.px(10)
        Layout.rightMargin: Theme.px(10)
        visible: LiveTv.builtIn && LiveTv.channels.length > 0
        text: Tr.t("Free public channels. Add your own M3U above for more.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.px(10)
        Layout.rightMargin: Theme.px(10)
        spacing: Theme.px(8)
        TextField {
            id: find
            Layout.fillWidth: true
            placeholderText: Tr.t("Find a channel")
            Accessible.name: Tr.t("Find a channel")
            onTextChanged: LiveTv.search = text.trim()
        }
        Text {
            visible: LiveTv.channels.length > 0
            text: Tr.t("%1 channels", LiveTv.shown.length)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
    }
    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.px(10)
        Layout.rightMargin: Theme.px(10)
        spacing: Theme.px(6)
        visible: LiveTv.groups.length > 1
        Choice {
            text: Tr.t("All")
            selected: LiveTv.group === ""
            onClicked: LiveTv.group = ""
        }
        Repeater {
            model: LiveTv.groups
            Choice {
                required property string modelData
                text: modelData
                selected: LiveTv.group === modelData
                onClicked: LiveTv.group = modelData
            }
        }
    }
    EmptyState {
        Layout.fillWidth: true
        visible: LiveTv.loading || LiveTv.error !== "" || LiveTv.channels.length === 0
        icon: "tv"
        title: LiveTv.loading ? Tr.t("Reading the playlist…")
             : LiveTv.error !== "" ? Tr.t("Could not read the playlist")
             : Tr.t("No channels yet")
        subtitle: LiveTv.error !== "" ? LiveTv.error
                : Tr.t("Load an M3U playlist, or pick free channels to start watching")
        actionText: LiveTv.loading || LiveTv.error !== "" ? "" : Tr.t("Browse…")
        onAction: LiveTv.loadDefaults()
    }
    ListView {
        reuseItems: true
        cacheBuffer: 400
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: LiveTv.shown
        delegate: Rectangle {
            id: row
            required property var modelData
            width: list.width
            height: Theme.px(52)
            radius: Theme.px(8)
            readonly property bool playing: PlayQueue.current === modelData.url
            color: playing ? Theme.accentSoft : (area.containsMouse ? Theme.hover : "transparent")
            MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: LiveTv.play(row.modelData) }
            KeyFocus { onActivated: LiveTv.play(row.modelData) }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.px(10)
                anchors.rightMargin: Theme.px(6)
                spacing: Theme.px(10)
                Item {
                    Layout.preferredWidth: Theme.px(36)
                    Layout.preferredHeight: Theme.px(36)
                    Image {
                        id: logo
                        anchors.fill: parent
                        source: row.modelData.logo || ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize: Qt.size(Theme.px(72), Theme.px(72))
                        visible: status === Image.Ready
                    }
                    Icon { anchors.centerIn: parent; visible: logo.status !== Image.Ready; name: "video-x-generic"; size: Theme.px(22); color: Theme.dim }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.modelData.name
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                        font.weight: row.playing ? Font.DemiBold : Font.Normal
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.modelData.group || ""
                        visible: text !== ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: row.modelData.name
            Accessible.onPressAction: LiveTv.play(row.modelData)
        }
    }
}
