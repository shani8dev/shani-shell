pragma Singleton
// The desktop's own small sounds (freedesktop sound theme, pw-play): a click
// when the volume changes, so the new level is heard, a shutter for each
// screenshot, the charger going in and out, a drive arriving and leaving.
// Off with Settings > Sound > System sounds. Nothing sounds for the state the
// shell starts in: only changes after it is up.
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
        if (name === "audio-volume-change" && Settings.data.soundVolumeChange === false)
            return;
        if (name === "camera-shutter" && Settings.data.soundScreenshot === false)
            return;
        played++;
        Quickshell.execDetached(["sh", "-c", '[ -f "$1" ] && exec pw-play "$1"', "sh", dir + name + ".oga"]);
    }
    property bool armed: false
    Timer { interval: 4000; running: true; onTriggered: root.armed = true }
    property string last: ""              // the last sound played (the tests)
    function event(name) { if (armed) { last = name; play(name); } }
    // the charger
    Connections {
        target: Power
        function onOnBatteryChanged() { if (Power.hasBattery) root.event(Power.onBattery ? "power-unplug" : "power-plug"); }
    }
    // a removable drive: in, out
    property int driveCount: Drives.drives.length
    onDriveCountChanged: {
        if (driveCount > lastDrives && lastDrives >= 0) event("device-added");
        else if (driveCount < lastDrives) event("device-removed");
        lastDrives = driveCount;
    }
    property int lastDrives: -1
    Component.onCompleted: lastDrives = Drives.drives.length
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
