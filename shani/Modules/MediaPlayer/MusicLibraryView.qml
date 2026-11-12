// The Media Player's Library: the music in ~/Music by album (with its
// cover), by artist, and every song; the videos in ~/Videos by folder, each
// with a frame of it - and a search over them. A click
// plays: an album from its first song (or the one clicked), a song with the
// rest of the list after it. Services/MusicLibrary holds the songs.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Rectangle {
    id: lib
    color: Theme.bg
    property string tab: "albums"          // albums | artists | songs | videos
    onTabChanged: if (tab === "videos") MusicLibrary.scanVideos()
    property var album: null               // an album opened, or null
    property string artist: ""             // an artist chosen, or ""
    property string query: ""
    readonly property string q: query.trim().toLowerCase()
    function hit(s) { return q === "" || (s.title + " " + s.artist + " " + s.album).toLowerCase().indexOf(q) >= 0; }
    readonly property var albumsShown: MusicLibrary.albums.filter(a => (artist === "" || a.artist === artist)
        && (q === "" || (a.title + " " + a.artist).toLowerCase().indexOf(q) >= 0 || a.songs.some(hit)))
    readonly property var songsShown: MusicLibrary.songs.filter(hit)
    function fileUrl(p) { return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : ""; }

    // looked at again each time it opens: songs added since are there, and a
    // second look reads only what changed (the scanner keeps the rest)
    Component.onCompleted: MusicLibrary.scan()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            IconButton { visible: lib.album !== null || lib.artist !== ""; size: 30; icon: "go-previous"; tip: Tr.t("Back"); onClicked: { if (lib.album) lib.album = null; else lib.artist = ""; } }
            Repeater {
                model: [["albums", Tr.t("Albums")], ["artists", Tr.t("Artists")], ["songs", Tr.t("Songs")], ["videos", Tr.t("Videos")]]
                Choice {
                    required property var modelData
                    visible: lib.album === null
                    text: modelData[1]
                    selected: lib.tab === modelData[0] && lib.artist === ""
                    onClicked: { lib.tab = modelData[0]; lib.artist = ""; }
                }
            }
            TextField {
                Layout.fillWidth: true
                visible: lib.album === null
                placeholder: Tr.t("Search the music")
                label: Tr.t("Search the music")
                onTextChanged: lib.query = text
            }
            Item { Layout.fillWidth: true; visible: lib.album !== null }
            Text {
                text: MusicLibrary.scanning ? Tr.t("Looking…") : lib.tab === "videos" ? MusicLibrary.videos.length + " " + Tr.t("videos") : MusicLibrary.songs.length + " " + Tr.t("songs")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
            IconButton { size: 30; icon: "view-refresh"; tip: Tr.t("Look again"); onClicked: lib.tab === "videos" ? MusicLibrary.scanVideos() : MusicLibrary.scan() }
        }

        // ---- albums (all, or an artist's) ----
        GridView {
            id: albumGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: lib.album === null && (lib.tab === "albums" || lib.artist !== "")
            clip: true
            cellWidth: Math.max(150, width / Math.max(1, Math.floor(width / 170)))
            cellHeight: cellWidth + 46
            boundsBehavior: Flickable.StopAtBounds
            model: lib.albumsShown
            delegate: Item {
                id: cell
                required property var modelData
                width: albumGrid.cellWidth
                height: albumGrid.cellHeight
                Rectangle {
                    id: art
                    x: 6; y: 6
                    width: parent.width - 12
                    height: width
                    radius: Theme.radiusSmall
                    color: Theme.surface2
                    clip: true
                    Icon { anchors.centerIn: parent; visible: cover.status !== Image.Ready; name: "media-optical"; size: parent.width * 0.35; color: Theme.faint }
                    Image { id: cover; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(320, 320); source: lib.fileUrl(cell.modelData.cover) }
                    Rectangle { anchors.fill: parent; color: "transparent"; radius: parent.radius; border.width: cellArea.containsMouse ? 2 : 0; border.color: Theme.accent }
                }
                Text { anchors { left: art.left; right: art.right; top: art.bottom; topMargin: 6 } text: cell.modelData.title; color: Theme.text; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.weight: Font.DemiBold }
                Text { anchors { left: art.left; right: art.right; top: art.bottom; topMargin: 24 } text: cell.modelData.artist; color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                Accessible.role: Accessible.Button
                Accessible.name: cell.modelData.title + ", " + cell.modelData.artist
                Accessible.onPressAction: lib.album = cell.modelData
                MouseArea { id: cellArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lib.album = cell.modelData; onDoubleClicked: MusicLibrary.play(cell.modelData.songs, 0) }
                KeyFocus { name: cell.modelData.title; onActivated: lib.album = cell.modelData }
            }
        }

        // ---- artists ----
        ListView {
            id: artistList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: lib.album === null && lib.tab === "artists" && lib.artist === ""
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: MusicLibrary.artists.filter(a => lib.q === "" || a.name.toLowerCase().indexOf(lib.q) >= 0)
            delegate: ListRow {
                required property var modelData
                width: artistList.width
                icon: "avatar-default"
                title: modelData.name
                subtitle: modelData.albums + " " + (modelData.albums === 1 ? Tr.t("album") : Tr.t("albums")) + "  ·  " + modelData.songs + " " + Tr.t("songs")
                onClicked: lib.artist = modelData.name
            }
        }

        // ---- an album: its cover, its songs ----
        RowLayout {
            Layout.fillWidth: true
            visible: lib.album !== null
            spacing: 16
            Rectangle {
                Layout.preferredWidth: 140
                Layout.preferredHeight: 140
                radius: Theme.radiusSmall
                color: Theme.surface2
                clip: true
                Icon { anchors.centerIn: parent; name: "media-optical"; size: 52; color: Theme.faint; visible: bigCover.status !== Image.Ready }
                Image { id: bigCover; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(320, 320); source: lib.album ? lib.fileUrl(lib.album.cover) : "" }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text { Layout.fillWidth: true; text: lib.album ? lib.album.title : ""; color: Theme.text; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: 20 * Theme.fontScale; font.weight: Font.DemiBold }
                Text { text: lib.album ? lib.album.artist + (lib.album.year ? "  ·  " + lib.album.year : "") + "  ·  " + lib.album.songs.length + " " + Tr.t("songs") : ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                RowLayout {
                    spacing: 8
                    Button { kind: "primary"; text: Tr.t("Play"); onClicked: MusicLibrary.play(lib.album.songs, 0) }
                    Button { text: Tr.t("Shuffle"); onClicked: { PlayQueue.shuffle = true; MusicLibrary.play(lib.album.songs, Math.floor(Math.random() * lib.album.songs.length)); } }
                }
            }
        }

        // ---- songs: an album's, or every one ----
        ListView {
            id: songList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: lib.album !== null || (lib.tab === "songs" && lib.artist === "")
            clip: true
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds
            model: lib.album !== null ? lib.album.songs : lib.songsShown
            delegate: Rectangle {
                id: songRow
                required property var modelData
                required property int index
                readonly property bool now: PlayQueue.current === modelData.path
                width: songList.width
                height: 38
                radius: Theme.radiusSmall
                color: now ? Theme.accentSoft : songArea.containsMouse ? Theme.hover : "transparent"
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 12
                    Text { Layout.preferredWidth: 26; horizontalAlignment: Text.AlignRight; text: songRow.now ? "▶" : (lib.album !== null && songRow.modelData.track ? songRow.modelData.track : ""); color: songRow.now ? Theme.accent : Theme.faint; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.features: { "tnum": 1 } }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; text: songRow.modelData.title; color: Theme.text; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
                        Text { Layout.fillWidth: true; visible: lib.album === null; text: songRow.modelData.artist + "  ·  " + songRow.modelData.album; color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                    }
                    Text { text: PlayQueue.clock(songRow.modelData.duration); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.features: { "tnum": 1 } }
                }
                Accessible.role: Accessible.ListItem
                Accessible.name: songRow.modelData.title + ", " + songRow.modelData.artist
                Accessible.onPressAction: MusicLibrary.play(songList.model, songRow.index)
                MouseArea { id: songArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: MusicLibrary.play(songList.model, songRow.index) }
                KeyFocus { name: songRow.modelData.title; onActivated: MusicLibrary.play(songList.model, songRow.index) }
            }
        }

        // ---- videos: by folder (a series' episodes together), each with a frame of it ----
        ListView {
            id: videoList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: lib.album === null && lib.tab === "videos"
            clip: true
            spacing: 14
            boundsBehavior: Flickable.StopAtBounds
            model: MusicLibrary.videoFolders.map(f => ({ name: f.name, videos: f.videos.filter(v => lib.q === "" || (v.title + " " + f.name).toLowerCase().indexOf(lib.q) >= 0) })).filter(f => f.videos.length)
            delegate: Column {
                id: folderCol
                required property var modelData
                width: videoList.width
                spacing: 8
                readonly property int cols: Math.max(1, Math.floor(width / 230))
                readonly property real cell: width / cols
                Text {
                    visible: folderCol.modelData.name !== ""
                    text: folderCol.modelData.name + "  ·  " + folderCol.modelData.videos.length
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Grid {
                    columns: folderCol.cols
                    Repeater {
                        model: folderCol.modelData.videos
                        Item {
                            id: vcell
                            required property var modelData
                            required property int index
                            width: folderCol.cell
                            height: folderCol.cell * 9 / 16 + 44
                            function play() { PlayQueue.playList(folderCol.modelData.videos.map(v => v.path), vcell.index); }
                            Rectangle {
                                id: frame
                                x: 5; y: 5
                                width: parent.width - 10
                                height: width * 9 / 16
                                radius: Theme.radiusSmall
                                color: "black"
                                clip: true
                                Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(480, 270); source: lib.fileUrl(vcell.modelData.thumb) }
                                Rectangle {
                                    anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                                    width: dur.implicitWidth + 10; height: 20; radius: 4
                                    color: "#b0000000"
                                    Text { id: dur; anchors.centerIn: parent; text: PlayQueue.clock(vcell.modelData.duration); color: "white"; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale; font.features: { "tnum": 1 } }
                                }
                                Rectangle { anchors.fill: parent; color: "transparent"; radius: parent.radius; border.width: vArea.containsMouse ? 2 : 0; border.color: Theme.accent }
                            }
                            Text { anchors { left: frame.left; right: frame.right; top: frame.bottom; topMargin: 6 } text: vcell.modelData.title; color: Theme.text; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                            Accessible.role: Accessible.Button
                            Accessible.name: vcell.modelData.title
                            Accessible.onPressAction: vcell.play()
                            MouseArea { id: vArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: vcell.play() }
                            KeyFocus { name: vcell.modelData.title; onActivated: vcell.play() }
                        }
                    }
                }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: !MusicLibrary.scanning && MusicLibrary.videosScanned && MusicLibrary.videos.length === 0
                icon: "folder-videos"
                title: Tr.t("No videos yet")
                subtitle: Tr.t("Videos in your Videos folder show here, a folder's together")
            }
        }

        EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: lib.tab !== "videos" && !MusicLibrary.scanning && MusicLibrary.songs.length === 0
            icon: "folder-music"
            title: Tr.t("No music yet")
            subtitle: Tr.t("Songs in your Music folder show here, by album and artist")
        }
    }
}
