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

PanelWindow {
    id: win
    visible: QuickLook.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-quicklook"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }

    readonly property string url: QuickLook.path ? "file://" + QuickLook.path.split("/").map(encodeURIComponent).join("/") : ""
    readonly property var tints: Theme.dark
        ? ({ comment: "#8a93a0", string: "#8fd18a", number: "#f2a65a", keyword: "#6cb6ff", heading: "#ffd166", added: "#8fd18a", removed: "#ff8f8f" })
        : ({ comment: "#6a737d", string: "#1b7f3b", number: "#b35900", keyword: "#0550ae", heading: "#8a4b00", added: "#1b7f3b", removed: "#b3261e" })

    onVisibleChanged: if (!visible) player.stop()

    MouseArea { anchors.fill: parent; onClicked: QuickLook.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: QuickLook.close()
        Keys.onSpacePressed: QuickLook.close()
        Keys.onLeftPressed: QuickLook.step(-1)
        Keys.onRightPressed: QuickLook.step(1)
        Keys.onReturnPressed: QuickLook.openIt()
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
            anchors.margins: 16
            spacing: 12

            // the file: what it is, how big, when; and where it can go
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Icon { name: QuickLook.icon(); size: 28 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: QuickLook.name
                        color: Theme.text
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: 15 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: [QuickLook.humanSize(QuickLook.size), QuickLook.modified,
                               QuickLook.list.length > 1 ? (QuickLook.list.indexOf(QuickLook.path) + 1) + " / " + QuickLook.list.length : ""].filter(x => x).join("  ·  ")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                }
                IconButton { visible: QuickLook.list.length > 1; icon: "go-previous"; tip: Tr.t("Previous") + " (←)"; onClicked: QuickLook.step(-1) }
                IconButton { visible: QuickLook.list.length > 1; icon: "go-next"; tip: Tr.t("Next") + " (→)"; onClicked: QuickLook.step(1) }
                IconButton { icon: "folder-open"; tip: Tr.t("Show in Files"); onClicked: { Files.show(QuickLook.path); QuickLook.close(); } }
                Button { kind: "primary"; text: Tr.t("Open"); onClicked: QuickLook.openIt() }
                IconButton { icon: "window-close"; tip: Tr.t("Close") + " (Space)"; onClicked: QuickLook.close() }
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
                    anchors.margins: 8
                    visible: QuickLook.kind === "image" || (QuickLook.kind === "pdf" && QuickLook.page !== "")
                    source: !visible ? "" : QuickLook.kind === "pdf" ? "file://" + QuickLook.page : win.url
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
                    MouseArea { anchors.fill: parent; onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: QuickLook.kind === "audio"
                    spacing: 10
                    Icon { Layout.alignment: Qt.AlignHCenter; name: "audio-x-generic"; size: 96 }
                    // play / pause: a round accent button, as the Media Player's
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 64
                        implicitHeight: 64
                        radius: 32
                        color: playArea.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                        Icon {
                            anchors.centerIn: parent
                            name: player.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                            size: 28
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
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: player.duration > 0 ? Math.floor(player.position / 60000) + ":" + String(Math.floor(player.position / 1000) % 60).padStart(2, "0")
                              + " / " + Math.floor(player.duration / 60000) + ":" + String(Math.floor(player.duration / 1000) % 60).padStart(2, "0") : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                    }
                }

                // a text file in the editor's colours; an archive's or folder's list
                ListView {
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: (QuickLook.kind === "archive" || QuickLook.kind === "folder") && QuickLook.text !== ""
                    clip: true
                    spacing: 2
                    model: visible ? QuickLook.text.split("\n").filter(l => l !== "") : []
                    delegate: RowLayout {
                        required property string modelData
                        width: ListView.view.width
                        spacing: 8
                        readonly property bool dir: modelData.endsWith("/")
                        readonly property string base: (dir ? modelData.slice(0, -1) : modelData)
                        Icon {
                            name: FileIcons.iconFor({ isDir: parent.dir, ext: parent.base.indexOf(".") > 0 ? "." + parent.base.split(".").pop().toLowerCase() : "" })
                            size: 18
                        }
                        Text {
                            Layout.fillWidth: true
                            text: parent.base
                            color: Theme.text
                            elide: Text.ElideMiddle
                            font.family: Theme.font
                            font.pixelSize: 13 * Theme.fontScale
                        }
                    }
                }
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: QuickLook.kind === "text" && QuickLook.text !== ""
                    contentHeight: listing.implicitHeight
                    clip: true
                    Text {
                        id: listing
                        width: parent.width
                        textFormat: Text.RichText
                        text: QuickLook.kind !== "text" ? "" : '<pre style="margin:0; white-space:pre-wrap;">' + Highlight.html(QuickLook.text, Highlight.langFor(QuickLook.path, QuickLook.text.split("\n")[0]), win.tints) + "</pre>"
                        color: Theme.text
                        wrapMode: Text.WrapAnywhere
                        font.family: Theme.mono
                        font.pixelSize: 13 * Theme.fontScale
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
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
