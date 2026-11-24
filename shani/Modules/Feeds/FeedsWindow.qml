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

    property string tagFilter: ""   // the category the feed list is narrowed to
    property bool savedShown: false // show the saved pile instead of a feed

    // a feed or the saved pile must win over an old search: otherwise the list
    // keeps showing search results and the click looks inert
    function leaveSearch() {
        articleSearch.text = "";
        Feeds.search("");
    }

    // single keypresses must not eat letters typed into the three fields
    function isEditing() {
        const f = win.activeFocusItem;
        return !!f && (f.objectName === "feedEdit" || f.objectName === "articleSearch" || f.objectName === "tagEdit");
    }

    // the keyboard walks what is on screen, not the cache: a search or the
    // saved pile has its own feed column, which is why rows carry `url`
    function visibleArticles() {
        if (Feeds.query !== "") return Feeds.sorted(Feeds.searchResults);
        if (win.savedShown) return Feeds.sorted(Feeds.saved);
        return Feeds.sorted(Feeds.items.filter(i => Feeds.showRead || !i.read));
    }
    function step(delta) {
        const rows = win.visibleArticles();
        if (!rows.length) return;
        let idx = -1;
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].id === Feeds.openId && (rows[i].url || Feeds.current) === (Feeds.articleUrl || Feeds.current)) { idx = i; break; }
        }
        idx = idx < 0 ? (delta > 0 ? 0 : rows.length - 1) : (idx + delta + rows.length) % rows.length;
        const row = rows[idx];
        if (Feeds.query !== "" || win.savedShown) Feeds.openArticleAt(row.url || Feeds.current, row.id);
        else Feeds.show(Feeds.current, row.id);
    }
    function toggleRead() {
        if (!Feeds.openId) return;
        const row = win.visibleArticles().filter(a => a.id === Feeds.openId)[0];
        const url = Feeds.articleUrl || Feeds.current;
        if (row && row.read) Feeds.markUnread(url, Feeds.openId);
        else Feeds.markRead(url, Feeds.openId);
    }
    function feedCount(tag) {
        return Feeds.feeds.filter(f => tag === "" || (f.tags || []).indexOf(tag) >= 0).length;
    }

    // a newly opened feed (including the auto-opened first one) gets its own
    // tags in the field, so editing them is one keystroke away, not a fresh type
    Connections {
        target: Feeds
        function onCurrentChanged() {
            if (tagField && Feeds.current !== "") tagField.text = Feeds.tagsFor(Feeds.current);
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F) {
                articleSearch.forceActiveFocus();
                e.accepted = true;
                return;
            }
            if (win.isEditing()) return;
            let handled = true;
            if (e.key === Qt.Key_J || e.key === Qt.Key_N) win.step(1);
            else if (e.key === Qt.Key_K || e.key === Qt.Key_P) win.step(-1);
            else if (e.key === Qt.Key_R) win.toggleRead();
            else if (e.key === Qt.Key_F) Feeds.toggleSave(Feeds.articleUrl || Feeds.current, Feeds.openId);
            else if (e.key === Qt.Key_Escape) {
                if (Feeds.query !== "") win.leaveSearch();
                else if (win.savedShown) win.savedShown = false;
                else handled = false;
            } else handled = false;
            if (handled) e.accepted = true;
        }

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
                    Text {
                        text: Tr.t("%1 unread", Feeds.unreadTotal())
                        color: Feeds.unreadTotal() > 0 ? Theme.accent : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        Accessible.name: text
                    }
                    Item { Layout.fillWidth: true }
                    IconButton { icon: "go-next"; tip: Tr.t("Next unread"); accessibleName: Tr.t("Next unread article"); size: Theme.px(26); enabled: Feeds.feeds.some(f => f.unread > 0); onClicked: Feeds.nextUnread() }
                    IconButton { icon: "mail-mark-read"; tip: Tr.t("Mark all read"); accessibleName: Tr.t("Mark this feed read"); size: Theme.px(26); enabled: Feeds.current !== "" && !win.savedShown && Feeds.query === ""; onClicked: Feeds.markAll(Feeds.current) }
                    IconButton { icon: "view-refresh"; tip: Tr.t("Refresh"); accessibleName: Tr.t("Refresh feeds"); size: Theme.px(26); on: Feeds.busy; onClicked: Feeds.update() }
                }

                // tags double as categories: pick one to narrow the list
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    visible: Feeds.tags.length > 0
                    Choice {
                        text: Tr.t("All") + "  " + win.feedCount("")
                        selected: win.tagFilter === ""
                        onClicked: win.tagFilter = ""
                    }
                    Repeater {
                        model: Feeds.tags
                        Choice {
                            required property var modelData
                            text: modelData + "  " + win.feedCount(modelData)
                            selected: win.tagFilter === modelData
                            onClicked: win.tagFilter = modelData
                        }
                    }
                }

                ListView {
                    id: feedList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    Accessible.role: Accessible.List
                    Accessible.name: Tr.t("Feeds")
                    model: Feeds.feeds.filter(f => win.tagFilter === "" || (f.tags || []).indexOf(win.tagFilter) >= 0)
                    delegate: ListRow {
                        required property var modelData
                        width: ListView.view.width
                        icon: "mail-unread"
                        title: modelData.title
                        subtitle: (modelData.tags && modelData.tags.length ? modelData.tags.join(", ") + "  ·  " : "")
                                  + (modelData.unread > 0 ? Tr.t("%1 unread", modelData.unread) : "")
                        trailing: modelData.unread > 0 ? String(modelData.unread) : ""
                        selected: Feeds.current === modelData.url
                        // a feed wins over the saved pile too: otherwise the
                        // click looks inert while the list stays on Saved
                        onClicked: { win.leaveSearch(); win.savedShown = false; Feeds.open(modelData.url) }
                    }
                }

                TextField {
                    id: addField
                    objectName: "feedEdit"
                    label: Tr.t("Feed address")
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
                    Button {
                        text: Tr.t("Discover")
                        flat: true
                        enabled: addField.text.trim() !== ""
                        onClicked: { Feeds.discover(addField.text.trim()); addField.text = "" }
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: Tr.t("Remove")
                        flat: true
                        enabled: Feeds.current !== ""
                        // the service auto-opens another feed only when current is empty
                        onClicked: { Feeds.remove(Feeds.current); Feeds.current = "" }
                    }
                }
                TextField {
                    id: tagField
                    objectName: "tagEdit"
                    label: Tr.t("Tags for this feed")
                    Layout.fillWidth: true
                    placeholder: Tr.t("Tags for this feed…")
                    enabled: Feeds.current !== ""
                    onAccepted: { if (Feeds.current) Feeds.setTags(Feeds.current, text); text = "" }
                }
                // the subscription list in and out (OPML), and how often it
                // fetches on its own
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Button { text: Tr.t("Import…"); flat: true; onClicked: Feeds.importDialog() }
                    Button { text: Tr.t("Export…"); flat: true; enabled: Feeds.feeds.length > 0; onClicked: Feeds.exportDialog() }
                    Button {
                        text: Tr.t("Saved") + "  " + Feeds.saved.length
                        flat: true
                        checked: win.savedShown
                        onClicked: { win.leaveSearch(); win.savedShown = !win.savedShown; if (win.savedShown) Feeds.savedArticles() }
                    }
                }
                Text { text: Tr.t("Refresh"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: [0, 15, 30, 60, 360, 1440]
                        Choice {
                            required property int modelData
                            text: modelData === 0 ? Tr.t("Never")
                                : modelData === 60 ? Tr.t("Hourly")
                                : modelData === 360 ? Tr.t("Every 6 hours")
                                : modelData === 1440 ? Tr.t("Daily")
                                : Tr.t("Every %1 min", modelData)
                            selected: Feeds.refreshMinutes === modelData
                            onClicked: Feeds.setInterval(modelData)
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: Feeds.note !== ""
                    text: Feeds.note
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                Text {
                    Layout.fillWidth: true
                    visible: !Net.online
                    text: Tr.t("Offline — showing cached articles")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Text {
                    Layout.fillWidth: true
                    visible: feedList.count === 0 && !Feeds.busy
                    text: Feeds.feeds.length === 0 ? Tr.t("No feeds yet — add one above") : Tr.t("Nothing matches")
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
                // While a search is in flight the old results are still in the
                // model: say so instead of claiming the results have arrived.
                text: Feeds.query !== "" ? (Feeds.busy ? Tr.t("Searching…") : Tr.t("Search results"))
                    : win.savedShown ? Tr.t("Saved articles")
                    : (Feeds.feeds.filter(f => f.url === Feeds.current)[0] || {}).title || Tr.t("Articles")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            TextField {
                id: articleSearch
                objectName: "articleSearch"
                label: Tr.t("Search all articles")
                Layout.fillWidth: true
                placeholder: Tr.t("Search all articles…")
                onAccepted: Feeds.search(text.trim())
                onTextChanged: if (text.trim() === "" && Feeds.query !== "") Feeds.search("")
            }
            Text {
                Layout.fillWidth: true
                visible: Feeds.query !== "" && !Feeds.busy
                text: Tr.t("%1 results", itemList.count)
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.name: text
            }
            Choice {
                text: Tr.t("Show read")
                selected: Feeds.showRead
                onClicked: Feeds.showRead = !Feeds.showRead
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [
                        [Tr.t("Newest"), "newest"],
                        [Tr.t("Oldest"), "oldest"],
                        [Tr.t("Title"), "title"]
                    ]
                    Choice {
                        required property var modelData
                        text: modelData[0]
                        selected: Feeds.sortOrder === modelData[1]
                        onClicked: Feeds.setSort(modelData[1])
                    }
                }
            }
            ListView {
                id: itemList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: Feeds.query !== "" ? Feeds.sorted(Feeds.searchResults)
                    : win.savedShown ? Feeds.sorted(Feeds.saved)
                    : Feeds.sorted(Feeds.items.filter(i => Feeds.showRead || !i.read))
                Accessible.role: Accessible.List
                Accessible.name: Tr.t("Articles")
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: ListRow {
                    required property var modelData
                    width: ListView.view.width
                    icon: modelData.saved ? "user-bookmarks" : (modelData.read ? "mail-read" : "mail-unread")
                    title: modelData.title
                    subtitle: (modelData.feed ? modelData.feed + "  ·  " : "")
                              + Feeds.when(modelData.date) + (modelData.summary ? "  ·  " + modelData.summary : "")
                    selected: Feeds.articleTitle === modelData.title
                    onClicked: {
                        if (Feeds.query !== "" || win.savedShown) Feeds.openArticleAt(modelData.url, modelData.id);
                        else Feeds.show(Feeds.current, modelData.id);
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: itemList.count === 0 && !Feeds.busy
                text: Feeds.query !== "" ? Tr.t("No articles match that search")
                    : win.savedShown ? Tr.t("Nothing saved yet")
                    : Tr.t("Nothing in this feed yet")
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }

        // ---- the article -----------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(4)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    text: Tr.t("Reader")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Choice {
                    text: Tr.t("Compact")
                    selected: Feeds.readerMode === "compact"
                    onClicked: Feeds.setReaderMode("compact")
                }
                Choice {
                    text: Tr.t("Full")
                    selected: Feeds.readerMode === "full"
                    onClicked: Feeds.setReaderMode("full")
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: !Net.online
                    text: Tr.t("Offline")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Text {
                    text: Tr.t("j/k move · r unread · f save")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                    Accessible.name: text
                }
            }

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
                    spacing: Theme.px(Feeds.readerMode === "compact" ? 6 : 10)

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
                        textFormat: Text.PlainText
                        font.family: Theme.font
                        font.pixelSize: Theme.px(Feeds.readerMode === "compact" ? 16 : 20) * Theme.fontScale
                        font.weight: Font.DemiBold
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        Accessible.role: Accessible.Heading
                        Accessible.name: Feeds.articleTitle
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: Feeds.article !== ""
                        text: Feeds.article
                        color: Theme.text
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font.family: Theme.font
                        font.pixelSize: Theme.px(Feeds.readerMode === "compact" ? 12 : 14) * Theme.fontScale
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        visible: Feeds.openId !== ""
                        Button {
                            visible: Feeds.articleLink !== ""
                            text: Tr.t("Open in a browser")
                            kind: "outline"
                            onClicked: Qt.openUrlExternally(Feeds.articleLink)
                        }
                        Button {
                            text: Feeds.articleSaved ? Tr.t("Saved") : Tr.t("Save for later")
                            flat: true
                            checked: Feeds.articleSaved
                            onClicked: Feeds.toggleSave(Feeds.articleUrl || Feeds.current, Feeds.openId)
                        }
                        Button {
                            text: Tr.t("Mark unread")
                            flat: true
                            onClicked: Feeds.markUnread(Feeds.articleUrl || Feeds.current, Feeds.openId)
                        }
                        Button {
                            visible: Feeds.articleEnclosure !== ""
                            text: Tr.t("Open episode")
                            kind: "outline"
                            onClicked: Qt.openUrlExternally(Feeds.articleEnclosure)
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Item { Layout.preferredHeight: 20 }
                }
            }
        }
    }
    }
}
