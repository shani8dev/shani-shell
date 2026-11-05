pragma Singleton
// Fullscreen and game mode: while the focused window is fullscreen,
// notifications wait (a film, a slide deck, a game); when it is a game (its
// desktop entry says Game), the performance power profile is used too, and the
// previous profile comes back afterwards.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var top: ToplevelManager.activeToplevel
    readonly property bool fullscreen: Boolean(Settings.data.quietWhileFullscreen) && top !== null && Boolean(top.fullscreen)
    readonly property bool game: {
        if (!fullscreen)
            return false;
        const e = DesktopEntries.heuristicLookup(top.appId || "");
        return e !== null && [].concat(e.categories || []).indexOf("Game") >= 0;
    }
    // battery saver outranks a game (Power.qml has the whole order): while it
    // holds, a game starting leaves power saver alone
    property int savedProfile: -1
    onGameChanged: {
        if (game && PowerProfiles.hasPerformanceProfile && Power.savedProfile < 0) {
            savedProfile = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.Performance;
        } else if (!game && savedProfile >= 0) {
            // back: what the charger rule wants now (it may have been plugged in or
            // out meanwhile), or else what was there before
            PowerProfiles.profile = Power.chargerWanted >= 0 ? Power.chargerWanted : savedProfile;
            savedProfile = -1;
        }
    }
}
