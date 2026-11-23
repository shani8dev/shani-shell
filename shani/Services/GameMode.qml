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
    readonly property bool fullscreen: Boolean(Settings.data.quietWhileFullscreen) && !!top && Boolean(top.fullscreen)
    readonly property bool game: {
        if (!fullscreen)
            return false;
        const e = DesktopEntries.heuristicLookup(top.appId || "");
        return e !== null && [].concat(e.categories || []).indexOf("Game") >= 0;
    }
    // battery saver outranks a game (Power.qml has the whole order): while it
    // holds, a game starting leaves power saver alone
    property int savedProfile: -1
    readonly property bool active: savedProfile >= 0
    signal modeChanged(bool active)
    property bool toldUnavailable: false

    // critical is the only urgency fullscreen quiet lets through, and -t keeps
    // the toast transient instead of sitting over the game
    function tell(title, body) {
        Quickshell.execDetached(["notify-send", "-a", Tr.t("Game mode"), "-i", "games",
            "-u", "critical", "-t", "1800", title, body]);
    }
    function evaluate() {
        if (!game) toldUnavailable = false;
        if (game && PowerProfiles.hasPerformanceProfile && Power.savedProfile < 0) {
            if (savedProfile >= 0)
                return;
            savedProfile = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.Performance;
            if (PowerProfiles.profile !== PowerProfile.Performance) {
                // the daemon refused it: don't promise a restore we never made
                savedProfile = -1;
                if (!toldUnavailable) {
                    tell(Tr.t("Performance unavailable"), Tr.t("Game mode could not set the performance profile."));
                    toldUnavailable = true;
                }
            } else
                tell(Tr.t("Performance mode on"), Tr.t("The game is fullscreen; the previous profile returns when it ends."));
            modeChanged(active);
        } else if (!game && savedProfile >= 0) {
            // back: what the charger rule wants now (it may have been plugged in or
            // out meanwhile), or else what was there before
            PowerProfiles.profile = Power.chargerWanted >= 0 ? Power.chargerWanted : savedProfile;
            savedProfile = -1;
            tell(Tr.t("Performance mode off"), Tr.t("Game mode: %1 restored.", Power.profileName));
            modeChanged(active);
        }
    }
    onGameChanged: root.evaluate()
    // the saver can end, or PPD can appear after startup, while `game` stays the
    // same: neither change reached onGameChanged before, so performance never came on
    Connections { target: Power; function onSavedProfileChanged() { root.evaluate(); } }
    Connections { target: PowerProfiles; function onHasPerformanceProfileChanged() { root.evaluate(); } }
}
