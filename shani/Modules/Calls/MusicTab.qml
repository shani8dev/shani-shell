// What the linked phone is playing, with the four things a person can do.
// The bridge owns the player; this tab only asks it to act and shows the answer.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: root
    spacing: Theme.px(10)

    readonly property bool playing: String(PhoneTools.music.title || PhoneTools.music.summary || "") !== ""
    readonly property string title: String(PhoneTools.music.title || PhoneTools.music.summary || Tr.t("Nothing is playing"))
    readonly property string detail: [PhoneTools.music.artist, PhoneTools.music.player]
        .filter(x => String(x || "") !== "").join(" · ")

    BusyNote {
        visible: PhoneTools.busy
        Layout.fillWidth: true
        note: Tr.t("Working…")
    }
    Text {
        visible: root.playing
        Layout.fillWidth: true
        text: root.title
        Accessible.name: root.title
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.type("subtitle")
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
    }
    Text {
        visible: root.detail !== ""
        Layout.fillWidth: true
        text: root.detail
        Accessible.name: root.detail
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.type("body")
        wrapMode: Text.Wrap
    }
    EmptyState {
        visible: !root.playing
        icon: "media-playback-start"
        title: Tr.t("Nothing is playing")
        subtitle: Tr.t("Music from the phone shows up here")
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(8)
        Button {
            Layout.fillWidth: true
            text: Tr.t("Previous")
            enabled: root.playing
            onClicked: PhoneTools.musicAction("previous")
        }
        Button {
            Layout.fillWidth: true
            text: Tr.t("Play or pause")
            enabled: root.playing
            kind: "primary"
            onClicked: PhoneTools.musicAction("toggle")
        }
        Button {
            Layout.fillWidth: true
            text: Tr.t("Next")
            enabled: root.playing
            onClicked: PhoneTools.musicAction("next")
        }
        Button {
            text: Tr.t("Look again")
            flat: true
            onClicked: PhoneTools.musicAction("status")
        }
    }
    Text {
        Layout.fillWidth: true
        visible: PhoneTools.note !== ""
        text: PhoneTools.note
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.type("small")
        wrapMode: Text.Wrap
    }
    Item { Layout.fillHeight: true }
}
