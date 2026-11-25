// Podcasts: the window over Services/Podcasts. The service owns the subscriptions,
// the polling cache, the enclosures and where a last-played episode was left;
// this is only its view — every action goes back into the service.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Podcasts"
    visible: Ui.podcasts
    onGone: Ui.podcasts = false
    implicitWidth: Theme.px(760)
    implicitHeight: Theme.px(620)

    property string filter: "all"   // all | favourites | downloaded
    Component.onCompleted: Podcasts.restore()

    function shownEpisodes() {
        if (win.filter === "favourites")
            return Podcasts.episodes.filter(r => Podcasts.favourites.indexOf(r.url + "|" + r.id) >= 0);
        if (win.filter === "downloaded")
            return Podcasts.episodes.filter(r => r.enclosure
                && Podcasts.downloads.some(d => d.url === r.enclosure.url && d.state === "done"));
        return Podcasts.episodes;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.px(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: feedField
                Layout.fillWidth: true
                placeholder: Tr.t("Feed address")
                Accessible.name: Tr.t("Add a podcast feed")
                onAccepted: { Podcasts.addFeed(feedField.text); feedField.text = ""; }
            }
            Button {
                text: Tr.t("Add")
                kind: "primary"
                onClicked: { Podcasts.addFeed(feedField.text); feedField.text = ""; }
            }
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholder: Tr.t("Search podcasts")
                Accessible.name: Tr.t("Search podcasts")
                onAccepted: Podcasts.searchFeeds(searchField.text)
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Choice {
                text: Tr.t("All")
                selected: win.filter === "all"
                onClicked: win.filter = "all"
            }
            Choice {
                text: Tr.t("Favourites")
                selected: win.filter === "favourites"
                onClicked: win.filter = "favourites"
            }
            Choice {
                text: Tr.t("Downloaded")
                selected: win.filter === "downloaded"
                onClicked: win.filter = "downloaded"
            }
        }

        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: Podcasts.error || Podcasts.note
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        ListView {
            id: episodes
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: win.shownEpisodes()
            spacing: 2
            delegate: ListRow {
                required property var modelData
                width: episodes.width
                icon: "audio-x-generic"
                title: modelData.title || modelData.url
                subtitle: modelData.date || ""
                selected: Podcasts.currentEpisode === modelData.url + "|" + modelData.id
                onClicked: Podcasts.play(modelData.url, modelData.id)
                IconButton {
                    size: Theme.px(26)
                    icon: Podcasts.favourites.indexOf(modelData.url + "|" + modelData.id) >= 0
                        ? "starred-symbolic" : "star-symbolic"
                    tip: Tr.t("Favourite episode")
                    onClicked: Podcasts.toggleFavourite(modelData.url, modelData.id)
                }
                IconButton {
                    size: Theme.px(26)
                    icon: "go-down"
                    tip: Tr.t("Download episode")
                    onClicked: Podcasts.download(modelData.enclosure && modelData.enclosure.url, modelData.title)
                }
                // the service already hands the enclosure to PlayQueue; this
                // button makes that handoff an explicit action on the episode
                Button {
                    text: Tr.t("Open in Media Player")
                    flat: true
                    onClicked: Podcasts.play(modelData.url, modelData.id)
                }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: win.shownEpisodes().length === 0
                icon: "audio-x-generic"
                title: win.filter === "favourites" ? Tr.t("No favourite episodes")
                    : win.filter === "downloaded" ? Tr.t("No downloaded episodes")
                    : Tr.t("No podcast episodes")
                subtitle: Tr.t("Add a feed to see its episodes here")
                actionText: Tr.t("Add a feed")
                onAction: feedField.forceActiveFocus()
            }
        }
    }
}
