// Software > Explore's home, the way an app store opens (Google Play, GNOME
// Software): a large Featured banner that turns every few seconds, then shelves
// - Editor's picks, Creativity, Productivity, Games, Utilities, and the Snap
// Store's - each a row of big icons that scrolls sideways, with See all. A
// search or a category leaves the home for the full grid (SoftwareWindow).
// Every shelf is one `category` ask of the same bridge, nothing new.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common

Flickable {
    id: home
    property var store: null                 // the Software window: ask(), openApp(), showCategory()...
    property bool active: false
    clip: true
    contentHeight: col.implicitHeight + Theme.px(16)
    boundsBehavior: Flickable.StopAtBounds

    // [title, categories] - fetched once per open; the picks come from `featured`
    readonly property var shelfSpec: [
        [Tr.t("Creativity"), ["Graphics", "AudioVideo"]],
        [Tr.t("Productivity"), ["Office", "Development"]],
        [Tr.t("Games"), ["Game"]],
        [Tr.t("Utilities"), ["Utility", "System"]]
    ]
    property var shelves: ({})               // title -> [apps]
    property var snaps: []
    property bool loaded: false
    function load() {
        if (!store || loaded) return;
        loaded = true;
        for (const spec of shelfSpec) {
            const title = spec[0];
            let merged = [], left = spec[1].length;
            for (const c of spec[1]) {
                store.ask(["category", c], r => {
                    for (const a of (Array.isArray(r) ? r : []))
                        if (!merged.some(x => x.id === a.id)) merged.push(a);
                    if (--left === 0) {
                        // the ones with an icon first: a shelf is a row of pictures
                        merged.sort((a, b) => (!!b.icon - !!a.icon));
                        const s = Object.assign({}, home.shelves); s[title] = merged.slice(0, 16); home.shelves = s;
                    }
                });
            }
        }
        store.ask(["snap-search", ""], r => {
            home.snaps = (Array.isArray(r) ? r : []).slice(0, 16).map(x => ({ id: "snap:" + x.name, snap: x.name, source: "snap", name: x.name,
                summary: x.summary, publisher: x.publisher, classic: x.classic, icon: "", installed: (home.store.snaps || []).some(i => i.snap === x.name) }));
        });
    }
    onActiveChanged: if (active) load()
    Component.onCompleted: if (active) load()

    // the banner: the picks, one at a time
    readonly property var hero: (store && store.featured ? store.featured : []).filter(a => a.icon).slice(0, 6)
    property int heroAt: 0
    Timer { interval: 6000; repeat: true; running: home.visible && home.hero.length > 1 && !heroArea.containsMouse
            onTriggered: home.heroAt = (home.heroAt + 1) % home.hero.length }

    function open(a) {
        if (a.source === "snap") store.snapJob(a.installed ? "remove" : "install", a);
        else store.openApp(a.id);
    }

    ColumnLayout {
        id: col
        width: home.width
        spacing: Theme.px(18)

        // ---- Featured ----
        Rectangle {
            id: banner
            visible: home.hero.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(200)
            radius: Theme.radiusLarge
            clip: true
            readonly property var a: home.hero.length ? home.hero[Math.min(home.heroAt, home.hero.length - 1)] : ({})
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.alpha(Theme.accent, 0.55) }
                GradientStop { position: 1.0; color: Theme.alpha(Theme.accent, 0.08) }
            }
            // the app's own icon, large and soft behind, as a store's artwork
            Image {
                anchors { right: parent.right; rightMargin: -Theme.px(30); verticalCenter: parent.verticalCenter }
                width: Theme.px(260); height: width
                source: banner.a.icon ? "file://" + banner.a.icon : ""
                sourceSize: Qt.size(256, 256)
                opacity: 0.18
                fillMode: Image.PreserveAspectFit
            }
            MouseArea { id: heroArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: home.open(banner.a) }
            RowLayout {
                anchors { fill: parent; margins: Theme.px(24) }
                spacing: Theme.px(20)
                Rectangle {
                    Layout.preferredWidth: Theme.px(112); Layout.preferredHeight: Theme.px(112)
                    radius: Theme.px(26)
                    color: Theme.alpha(Theme.bg, 0.55)
                    Image { anchors.centerIn: parent; width: Theme.px(88); height: width; source: banner.a.icon ? "file://" + banner.a.icon : ""; sourceSize: Qt.size(176, 176); fillMode: Image.PreserveAspectFit }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Text { text: Tr.t("Featured"); color: Theme.text; opacity: 0.75; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap; text: banner.a.name || ""; color: Theme.text; font.family: Theme.font
                           font.pixelSize: Theme.px((banner.a.name || "").length > 22 ? 22 : 28) * Theme.fontScale; font.weight: Font.Bold }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap; text: banner.a.summary || ""; color: Theme.text; opacity: 0.85; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale }
                    Item { Layout.preferredHeight: Theme.px(6) }
                    Button { text: banner.a.installed ? Tr.t("Open") : Tr.t("Get it"); kind: "primary"; onClicked: home.open(banner.a) }
                }
            }
            // which one of the picks this is; a dot goes straight to one
            Row {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.px(10) }
                spacing: Theme.px(6)
                Repeater {
                    model: home.hero.length
                    Rectangle {
                        required property int index
                        width: index === home.heroAt ? Theme.px(18) : Theme.px(6); height: Theme.px(6); radius: height / 2
                        color: index === home.heroAt ? Theme.text : Theme.alpha(Theme.text, 0.35)
                        Behavior on width { NumberAnimation { duration: Theme.anim } }
                        MouseArea { anchors.fill: parent; anchors.margins: -Theme.px(4); onClicked: home.heroAt = parent.index }
                    }
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: Tr.t("Featured: %1", banner.a.name || "")
            Accessible.onPressAction: home.open(banner.a)
        }

        Shelf { title: Tr.t("Editor's picks"); apps: home.store ? home.store.featured : []; seeAllVisible: false }
        Repeater {
            model: home.shelfSpec
            Shelf {
                required property var modelData
                title: modelData[0]
                apps: home.shelves[modelData[0]] || []
                onSeeAll: home.store.showCollection(modelData[0], modelData[1])
            }
        }
        Shelf { title: Tr.t("From the Snap Store"); apps: home.snaps; seeAllVisible: false }
    }

    // a titled row of big icons, scrolling sideways
    component Shelf: ColumnLayout {
        id: shelf
        property string title
        property var apps: []
        property bool seeAllVisible: true
        signal seeAll()
        visible: apps.length > 0
        Layout.fillWidth: true
        spacing: Theme.px(8)
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: shelf.title; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(17) * Theme.fontScale; font.weight: Font.DemiBold; Accessible.role: Accessible.Heading; Accessible.name: text }
            Button { visible: shelf.seeAllVisible; flat: true; text: Tr.t("See all ›"); onClicked: shelf.seeAll() }
        }
        ListView {
            id: row
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(176)
            orientation: ListView.Horizontal
            spacing: Theme.px(12)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: shelf.apps
            delegate: Item {
                id: tile
                required property var modelData
                width: Theme.px(124); height: row.height
                readonly property bool isSnap: modelData.source === "snap"
                Rectangle {
                    id: art
                    width: parent.width; height: width
                    radius: Theme.px(28)
                    color: tileArea.containsMouse ? Theme.hover : Theme.card
                    border.width: 1
                    border.color: Theme.stroke
                    scale: tileArea.pressed ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.anim / 2 } }
                    Image { visible: !tile.isSnap; anchors.centerIn: parent; width: parent.width * 0.62; height: width; source: tile.modelData.icon ? "file://" + tile.modelData.icon : ""; sourceSize: Qt.size(160, 160); fillMode: Image.PreserveAspectFit; asynchronous: true }
                    // no picture (a snap, an app without one): its initial on a colour, as stores show those
                    AppIcon { visible: tile.isSnap || !tile.modelData.icon; anchors.centerIn: parent; implicitSize: parent.width * 0.62; icon: ""; name: tile.modelData.name || "" }
                    Rectangle {
                        visible: tile.modelData.installed
                        anchors { right: parent.right; bottom: parent.bottom; margins: Theme.px(8) }
                        width: Theme.px(22); height: width; radius: width / 2; color: Theme.accent
                        Icon { anchors.centerIn: parent; name: "object-select-symbolic"; size: Theme.px(14); color: Theme.accentInk }
                    }
                }
                Text { id: tName; anchors { top: art.bottom; topMargin: Theme.px(8); left: parent.left; right: parent.right }
                       text: tile.modelData.name; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.Medium }
                Text { anchors { top: tName.bottom; topMargin: Theme.px(2); left: parent.left; right: parent.right }
                       text: tile.isSnap ? Tr.t("Snap") + (tile.modelData.publisher ? " · " + tile.modelData.publisher : "") : (tile.modelData.summary || "")
                       elide: Text.ElideRight; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                MouseArea { id: tileArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: home.open(tile.modelData) }
                KeyFocus { onActivated: home.open(tile.modelData) }
                Accessible.role: Accessible.Button
                Accessible.name: tile.modelData.name + (tile.isSnap ? ", " + Tr.t("Snap") : "") + (tile.modelData.installed ? ", " + Tr.t("installed") : "")
                Accessible.onPressAction: home.open(tile.modelData)
            }
        }
    }
}
