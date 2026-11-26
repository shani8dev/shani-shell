// Live captions: two lines above the dock, for as long as captions are on.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    visible: Captions.on && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors.bottom: true
    margins.bottom: 100
    implicitWidth: Math.min(1100, (screen ? screen.width : 1920) - 120)
    implicitHeight: Theme.px(84)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-captions"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}                       // never in the way of a click

    Glass {
        id: blurCard
        anchors.fill: parent
        strong: true
        radius: Theme.radiusLarge
        color: Theme.alpha("#000000", 0.78)
        Row {
            x: 18
            y: 12
            spacing: Theme.px(8)
            Rectangle { width: Theme.px(8); height: Theme.px(8); radius: Theme.px(4); color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
            Text {
                // keep a long stderr line inside the card; pulseaudio warns on
                // stderr routinely, so an error only outranks the status before
                // a caption has actually arrived (the service clears it on start)
                width: blurCard.width - 36
                text: (Captions.error && !Captions.text) ? Captions.error : (Captions.source === "mic" ? "Live transcribe · saved to Documents/Transcripts" : "Live captions")
                color: (Captions.error && !Captions.text) ? Theme.red : Theme.dim
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.font
                font.pixelSize: Theme.type("caption")
            }
        }
        Text {
            anchors.fill: parent
            anchors.leftMargin: Theme.px(18)
            anchors.rightMargin: Theme.px(18)
            anchors.topMargin: Theme.px(30)
            anchors.bottomMargin: Theme.px(10)
            // the service buffers three chunks but this card shows two lines;
            // ElideLeft is ignored with wrapped text, so extra lines were clipped
            // from the bottom (the newest caption) - bind only the two newest
            text: (Captions.lines.length ? Captions.lines.slice(-2).join(" ") : "") || (Captions.source === "mic" ? "Listening to the room…" : "Listening to what is playing…")
            color: Captions.text ? Theme.text : Theme.dim
            wrapMode: Text.Wrap
            maximumLineCount: 2
            verticalAlignment: Text.AlignBottom
            font.family: Theme.font
            font.pixelSize: Theme.type("subtitle")
        }
    }
}
