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
    implicitHeight: 84
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-captions"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.data.blur && visible ? blurArea : null
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
            spacing: 8
            Rectangle { width: 8; height: 8; radius: 4; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
            Text { text: Captions.source === "mic" ? "Live transcribe · saved to Documents/Transcripts" : "Live captions"; color: "#c8d0da"; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
        }
        Text {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 30
            anchors.bottomMargin: 10
            text: Captions.text || (Captions.source === "mic" ? "Listening to the room…" : "Listening to what is playing…")
            color: Captions.text ? "#ffffff" : "#8a94a3"
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideLeft
            verticalAlignment: Text.AlignBottom
            font.family: Theme.font
            font.pixelSize: 17 * Theme.fontScale
        }
    }
}
