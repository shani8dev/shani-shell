pragma Singleton
// The desktop's own small sounds (freedesktop sound theme, pw-play): a click
// when the volume changes, so the new level is heard, and a shutter for each
// screenshot. Off with Settings > Sound > System sounds.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string dir: "/usr/share/sounds/freedesktop/stereo/"
    property int played: 0                // for the tests
    function play(name) {
        if (!Settings.data.systemSounds)
            return;
        played++;
        Quickshell.execDetached(["sh", "-c", '[ -f "$1" ] && exec pw-play "$1"', "sh", dir + name + ".oga"]);
    }
    // the volume: once it settles, so a held key is one click, not twenty
    property real lastVolume: -1
    readonly property real volume: Audio.volume
    onVolumeChanged: {
        if (lastVolume >= 0 && Audio.ready && !Audio.muted)
            settle.restart();
        lastVolume = volume;
    }
    Timer { id: settle; interval: 180; onTriggered: root.play("audio-volume-change") }
    Connections {
        target: Niri
        function onScreenshotSaved(path) { root.play("camera-shutter"); }
    }
}
