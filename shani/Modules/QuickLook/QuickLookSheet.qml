// Quick Look's card (Services/QuickLook): the file, big, over a dimmed desktop.
// Space or Escape closes it, Left and Right walk the files beside it, Return
// opens it in its app. Loaded the first time something is looked at.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import qs.Common
import qs.Services
import "../../Common/Highlight.js" as Highlight
import "../../Common/FileIcons.js" as FileIcons
import "../../Common/Time.js" as Time

PanelWindow {
    id: win
    visible: QuickLook.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-quicklook"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }

    function fileUrl(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }
    // Open takes the same route as a double click in Files (the shell's viewer,
    // editor, player …), and Show in Files reveals the file in its folder, as
    // the other apps' reveal buttons do.
    function openIt() {
        const p = QuickLook.path;
        const folder = QuickLook.kind === "folder";
        QuickLook.close();
        if (folder) Files.show(p);
        else Files.openEntry(p);
    }
    function showInFiles(p) {
        const at = String(p || "").lastIndexOf("/");
        if (at < 0) return;
        Files.show(at === 0 ? "/" : p.substring(0, at));
        Files.select(p, "single");
        QuickLook.close();
    }
    readonly property string url: QuickLook.path ? fileUrl(QuickLook.path) : ""
    readonly property var tints: Theme.dark
        ? ({ comment: "#8a93a0", string: "#8fd18a", number: "#f2a65a", keyword: "#6cb6ff", heading: "#ffd166", added: "#8fd18a", removed: "#ff8f8f" })
        : ({ comment: "#6a737d", string: "#1b7f3b", number: "#b35900", keyword: "#0550ae", heading: "#8a4b00", added: "#1b7f3b", removed: "#b3261e" })

    onVisibleChanged: {
        if (!visible) { player.stop(); win.metaShown = false; }
        else win.loadMeta();
    }
    // "More info" reads the same bridge the rest of the shell uses; the path is
    // checked again on the way back so a fast Left/Right cannot show the
    // previous file's details under the new file's name.
    property bool metaShown: false
    function loadMeta() {
        const path = QuickLook.path;
        if (path) FileMeta.get(path);
    }
    Connections { target: QuickLook; function onPathChanged() { win.metaShown = false; win.loadMeta(); } }

    // the clipboard is the word channel to the Dictionary (it seeds its box on
    // open); Ui.dictionary is the shell's flag, so no the Ui singleton source file change is needed.
    function defineSelection() {
        const word = String(listing.selectedText || "").trim();
        if (word === "") return;
        Quickshell.clipboardText = word;
        Ui.dictionary = false;   // re-open so Dictionary re-reads the clipboard
        Ui.dictionary = true;
        QuickLook.close();
    }

    MouseArea { anchors.fill: parent; onClicked: QuickLook.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: QuickLook.close()
        Keys.onSpacePressed: QuickLook.close()
        Keys.onLeftPressed: QuickLook.step(-1)
        Keys.onRightPressed: QuickLook.step(1)
        Keys.onReturnPressed: win.openIt()
        // Home/End jump to the ends of the sibling list the header counts
        function jumpTo(i) {
            const cur = QuickLook.list.indexOf(QuickLook.path);
            if (cur >= 0) QuickLook.step(i - cur);
        }
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Home) { if (QuickLook.list.length) jumpTo(0); e.accepted = true; return }
            if (e.key === Qt.Key_End) { if (QuickLook.list.length) jumpTo(QuickLook.list.length - 1); e.accepted = true; return }
            if (QuickLook.kind !== "text") return;
            const d = Theme.px(40), maxY = Math.max(0, listingFlick.contentHeight - listingFlick.height);
            if (e.key === Qt.Key_Up) listingFlick.contentY = Math.max(0, listingFlick.contentY - d)
            else if (e.key === Qt.Key_Down) listingFlick.contentY = Math.min(maxY, listingFlick.contentY + d)
            else if (e.key === Qt.Key_PageUp) listingFlick.contentY = Math.max(0, listingFlick.contentY - listingFlick.height)
            else if (e.key === Qt.Key_PageDown) listingFlick.contentY = Math.min(maxY, listingFlick.contentY + listingFlick.height)
            else return;
            e.accepted = true;
        }
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1100)
        height: Math.min(parent.height - 120, 760)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }      // a click inside does not close it

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(12)

            // the file: what it is, how big, when; and where it can go
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)
                Icon { name: QuickLook.icon(); size: Theme.px(28) }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: QuickLook.name
                        color: Theme.text
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: Theme.px(15) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: [QuickLook.humanSize(QuickLook.size), QuickLook.modified,
                               QuickLook.list.length > 1 ? (QuickLook.list.indexOf(QuickLook.path) + 1) + " / " + QuickLook.list.length : ""].filter(x => x).join("  ·  ")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                IconButton { visible: QuickLook.list.length > 1; icon: "go-previous"; tip: Tr.t("Previous") + " (←)"; onClicked: QuickLook.step(-1) }
                IconButton { visible: QuickLook.list.length > 1; icon: "go-next"; tip: Tr.t("Next") + " (→)"; onClicked: QuickLook.step(1) }
                IconButton { icon: "folder-open"; tip: Tr.t("Show in Files"); onClicked: win.showInFiles(QuickLook.path) }
                Button {
                    visible: QuickLook.kind === "text"
                    flat: true
                    enabled: listing.selectedText.trim() !== ""
                    text: Tr.t("Define selection")
                    Accessible.name: text
                    onClicked: win.defineSelection()
                }
                Button { kind: "primary"; text: Tr.t("Open"); onClicked: win.openIt() }
                IconButton { icon: "window-close"; tip: Tr.t("Close") + " (Space)"; onClicked: QuickLook.close() }
            }

            // More info: the file's own facts, in label/value rows
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    flat: true
                    checked: win.metaShown
                    text: win.metaShown ? Tr.t("Less info") : Tr.t("More info")
                    Accessible.name: text
                    onClicked: { win.metaShown = !win.metaShown; if (win.metaShown) win.loadMeta(); }
                }
                BusyNote {
                    visible: win.metaShown && FileMeta.loading
                    note: Tr.t("Reading…")
                }
                Item { Layout.fillWidth: true }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(Theme.px(110), Math.min(metaFlick.contentHeight + Theme.px(16), Theme.px(170)))
                visible: win.metaShown
                radius: Theme.radiusSmall
                color: Theme.alpha(Theme.surface1, 0.6)
                border.width: 1
                border.color: Theme.border
                clip: true
                Flickable {
                    id: metaFlick
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    visible: FileMeta.rows.length > 0
                    contentHeight: metaCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: metaCol
                        width: parent.width
                        spacing: Theme.px(4)
                        Repeater {
                            model: FileMeta.rows
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.px(8)
                                Text {
                                    Layout.preferredWidth: Theme.px(96)
                                    text: modelData.label
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    color: Theme.text
                                    wrapMode: Text.WrapAnywhere
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
                            }
                        }
                    }
                }
                BusyNote {
                    anchors.centerIn: parent
                    visible: win.metaShown && FileMeta.loading
                    note: Tr.t("Reading file details…")
                }
                EmptyState {
                    anchors.centerIn: parent
                    width: parent.width - Theme.px(32)
                    visible: win.metaShown && !FileMeta.loading && FileMeta.rows.length === 0
                    icon: "document-properties"
                    title: FileMeta.error || Tr.t("No details for this file")
                    subtitle: FileMeta.error ? "" : Tr.t("Nothing more to show about this file")
                }
            }

            // what it holds
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: QuickLook.kind === "video" ? "black" : Theme.alpha(Theme.surface1, 0.6)
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    visible: QuickLook.kind === "image" || (QuickLook.kind === "pdf" && QuickLook.page !== "")
                    source: !visible ? "" : QuickLook.kind === "pdf" ? fileUrl(QuickLook.page) : win.url
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    sourceSize: Qt.size(2000, 2000)
                }

                MediaPlayer {
                    id: player
                    source: win.visible && (QuickLook.kind === "video" || QuickLook.kind === "audio") ? win.url : ""
                    videoOutput: video
                    audioOutput: AudioOutput { volume: 0.6 }
                    onSourceChanged: if (source != "") play()
                }
                VideoOutput {
                    id: video
                    anchors.fill: parent
                    visible: QuickLook.kind === "video"
                    fillMode: VideoOutput.PreserveAspectFit
                    MouseArea {
                        anchors.fill: parent
                        onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("Play or pause")
                        Accessible.onPressAction: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                        KeyFocus { name: Tr.t("Play or pause"); onActivated: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
                    }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: QuickLook.kind === "audio"
                    spacing: Theme.px(10)
                    Icon { Layout.alignment: Qt.AlignHCenter; name: "audio-x-generic"; size: Theme.px(96) }
                    // play / pause: a round accent button, as the Media Player's
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Theme.px(64)
                        implicitHeight: Theme.px(64)
                        radius: Theme.px(32)
                        color: playArea.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                        Icon {
                            anchors.centerIn: parent
                            name: player.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                            size: Theme.px(28)
                            color: Theme.accentInk
                        }
                        MouseArea {
                            id: playArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("Play or pause")
                        Accessible.onPressAction: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                        KeyFocus { name: Tr.t("Play or pause"); onActivated: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: player.duration > 0 ? Time.clock(player.position / 1000)
                              + " / " + Time.clock(player.duration / 1000) : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        Accessible.name: Tr.t("Position %1").arg(text)
                    }
                }

                // a text file in the editor's colours; an archive's or folder's list
                ListView {
                    reuseItems: true
                    cacheBuffer: 400
                    anchors.fill: parent
                    anchors.margins: Theme.px(12)
                    visible: (QuickLook.kind === "archive" || QuickLook.kind === "folder") && QuickLook.text !== ""
                    clip: true
                    spacing: 2
                    model: visible ? QuickLook.text.split("\n").filter(l => l !== "") : []
                    delegate: RowLayout {
                        required property string modelData
                        width: ListView.view.width
                        spacing: Theme.px(8)
                        readonly property bool dir: modelData.endsWith("/")
                        readonly property string base: (dir ? modelData.slice(0, -1) : modelData)
                        Icon {
                            name: FileIcons.iconFor({ isDir: parent.dir, ext: parent.base.indexOf(".") > 0 ? "." + parent.base.split(".").pop().toLowerCase() : "" })
                            size: Theme.px(18)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: parent.base
                            color: Theme.text
                            elide: Text.ElideMiddle
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                        }
                    }
                }
                Flickable {
                    id: listingFlick
                    anchors.fill: parent
                    anchors.margins: Theme.px(12)
                    visible: QuickLook.kind === "text" && QuickLook.text !== ""
                    contentHeight: listing.implicitHeight
                    clip: true
                    TextEdit {
                        id: listing
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        selectByKeyboard: true
                        textFormat: TextEdit.RichText
                        text: QuickLook.kind !== "text" ? "" : '<pre style="margin:0; white-space:pre-wrap;">' + Highlight.html(QuickLook.text, Highlight.langFor(QuickLook.path, QuickLook.text.split("\n")[0]), win.tints) + "</pre>"
                        color: Theme.text
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: QuickLook.kind === "other" || QuickLook.error !== "" || QuickLook.kind === ""
                        || (["text", "archive", "folder"].indexOf(QuickLook.kind) >= 0 && QuickLook.text === "")
                        || (QuickLook.kind === "pdf" && QuickLook.page === "")
                    icon: QuickLook.kind === "" ? "content-loading" : QuickLook.icon()
                    title: QuickLook.error || (QuickLook.kind === "" ? Tr.t("Looking…")
                        : QuickLook.kind === "other" ? Tr.t("No preview for this kind of file")
                        : QuickLook.kind === "folder" ? Tr.t("An empty folder") : Tr.t("Reading…"))
                    subtitle: QuickLook.kind === "other" ? Tr.t("Open shows it in its app") : ""
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Space or Esc closes · ← → the files beside it · Enter opens")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
