// Feeds: an RSS/Atom reader. Three panes — what you subscribe to, what is in
// the feed you picked, and the article — with the unread count beside each feed.
// bridge/feeds.py does the fetching, so the window is only a view.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Feeds"
    visible: Ui.feeds
    onGone: Ui.feeds = false
    implicitWidth: Theme.px(1000)
    implicitHeight: Theme.px(660)

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(10)
        spacing: Theme.px(10)

        // ---- what you subscribe to ------------------------------------------
        Rectangle {
            Layout.preferredWidth: Theme.px(240)
            Layout.fillHeight: true
            radius: Theme.radius
            color: Theme.alpha(Theme.text, 0.035)
            border.width: 1
            border.color: Theme.stroke

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(10)
                spacing: Theme.px(8)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Text { text: Tr.t("Feeds"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    IconButton { icon: "view-refresh"; tip: Tr.t("Refresh"); size: Theme.px(26); on: Feeds.busy; onClicked: Feeds.update() }
                }

                ListView {
                    id: feedList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: Feeds.feeds
                    delegate: ListRow {
                        required property var modelData
                        width: ListView.view.width
                        icon: "mail-unread"
                        title: modelData.title
                        subtitle: modelData.unread > 0 ? Tr.t("%1 unread", modelData.unread) : ""
                        selected: Feeds.current === modelData.url
                        onClicked: Feeds.open(modelData.url)
                    }
                }

                TextField {
                    id: addField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Feed address…")
                    onAccepted: { if (text.trim() !== "") { Feeds.add(text.trim()); text = "" } }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Button {
                        text: Tr.t("Add")
                        enabled: addField.text.trim() !== ""
                        onClicked: { Feeds.add(addField.text.trim()); addField.text = "" }
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: Tr.t("Remove")
                        flat: true
                        enabled: Feeds.current !== ""
                        onClicked: Feeds.remove(Feeds.current)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: Feeds.feeds.length === 0 && !Feeds.busy
                    text: Tr.t("No feeds yet — add one above")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }

        // ---- what is in the feed --------------------------------------------
        ColumnLayout {
            Layout.preferredWidth: Theme.px(300)
            Layout.fillHeight: true
            spacing: Theme.px(4)

            Text {
                Layout.fillWidth: true
                text: (Feeds.feeds.filter(f => f.url === Feeds.current)[0] || {}).title || Tr.t("Articles")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            ListView {
                id: itemList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: Feeds.items
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: ListRow {
                    required property var modelData
                    width: ListView.view.width
                    icon: modelData.read ? "mail-read" : "mail-unread"
                    title: modelData.title
                    subtitle: Feeds.when(modelData.date)
                    selected: Feeds.articleTitle === modelData.title
                    onClicked: { Feeds.show(Feeds.current, modelData.id) }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: Feeds.items.length === 0
                text: Tr.t("Nothing in this feed yet")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }

        // ---- the article -----------------------------------------------------
        Flickable {
            id: reader
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: body.height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: body
                width: reader.width
                spacing: Theme.px(10)

                Text {
                    Layout.fillWidth: true
                    visible: Feeds.article === ""
                    text: Tr.t("Pick an article")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
                Text {
                    Layout.fillWidth: true
                    visible: Feeds.article !== ""
                    text: Feeds.articleTitle
                    color: Theme.text
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(20) * Theme.fontScale
                    font.weight: Font.DemiBold
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: Feeds.article !== ""
                    text: Feeds.article
                    color: Theme.text
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                }
                Button {
                    visible: Feeds.articleLink !== ""
                    text: Tr.t("Open in a browser")
                    kind: "outline"
                    onClicked: Qt.openUrlExternally(Feeds.articleLink)
                }
                Item { Layout.preferredHeight: 20 }
            }
        }
    }
}