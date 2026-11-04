pragma Singleton
// The media player the bar, sidebar, lock screen, Ring and desktop widget all
// follow: the one picked by hand on the media card (remembered by name, after
// noctalia's preferred player), else the one playing, else the first.
import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var players: Mpris.players.values
    readonly property var preferred: Settings.loaded && Settings.data.preferredPlayer
        ? players.find(p => p.identity === Settings.data.preferredPlayer) || null : null
    readonly property var current: preferred || players.find(p => p.isPlaying) || players[0] || null
    // the next one along, chosen as the one to follow
    function cycle() {
        if (players.length < 2)
            return;
        const next = players[(players.indexOf(current) + 1) % players.length];
        Settings.data.preferredPlayer = next.identity;
    }
}
