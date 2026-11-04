pragma Singleton
// User-configurable hooks: run a shell command on shell events (wallpaper
// change, dark-mode change, screen lock/unlock, startup). Ported from
// noctalia-shell's HooksService. Settings > Automations stores the commands;
// each is a free-form shell string with $1/$2/$3 placeholders.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    // pending wallpaper hook (wait for color generation to finish)
    property var pendingWallpaperHook: null

    // ---- settings keys (stored in Settings.data.hooks) -------------------------
    // Settings.data.hooks = { enabled, wallpaperChange, darkModeChange,
    //   screenLock, screenUnlock, startup, colorGeneration }

    function _enabled() { return Settings.data.hooks && Settings.data.hooks.enabled; }
    function _script(key) { return (Settings.data.hooks && Settings.data.hooks[key]) || ""; }

    // ---- execute helpers -------------------------------------------------------
    function _exec(cmd) {
        if (!_enabled() || !cmd) return;
        try { Quickshell.execDetached(["sh", "-lc", cmd]); }
        catch (e) { console.warn("Hooks: failed to run", cmd, e); }
    }

    function executeWallpaperHook(wallpaperPath, screenName) {
        const script = _script("wallpaperChange");
        if (!script) return;
        let cmd = script.replace(/\$1/g, wallpaperPath || "");
        cmd = cmd.replace(/\$2/g, screenName || "");
        cmd = cmd.replace(/\$3/g, Settings.data.darkMode ? "dark" : "light");
        _exec(cmd);
    }

    function executeDarkModeHook(isDarkMode) {
        const script = _script("darkModeChange");
        if (!script) return;
        const cmd = script.replace(/\$1/g, isDarkMode ? "true" : "false");
        _exec(cmd);
    }

    function executeLockHook() {
        const script = _script("screenLock");
        if (!script) return;
        _exec(script);
    }

    function executeUnlockHook() {
        const script = _script("screenUnlock");
        if (!script) return;
        _exec(script);
    }

    function executeColorGenerationHook() {
        const script = _script("colorGeneration");
        if (!script) return;
        const cmd = script.replace(/\$1/g, Settings.data.darkMode ? "dark" : "light");
        _exec(cmd);
    }

    function executeStartupHook() {
        const script = _script("startup");
        if (!script) return;
        _exec(script);
    }

    // ---- react to events -------------------------------------------------------
    // dark mode change
    Connections {
        target: Settings.data
        function onDarkModeChanged() {
            executeDarkModeHook(Settings.data.darkMode);
        }
    }

    // wallpaper change (via Theme.wallpaper)
    Connections {
        target: Theme
        function onWallpaperChanged() {
            executeWallpaperHook(Theme.wallpaper, "");
        }
    }

    // matugen color generation complete
    Connections {
        target: Matugen
        function onReadyChanged() {
            if (Matugen.ready) executeColorGenerationHook();
        }
    }

    // the screen locked and unlocked
    Connections {
        target: Lock
        function onLockedChanged() {
            if (Lock.locked) executeLockHook(); else executeUnlockHook();
        }
    }

    // startup
    Component.onCompleted: Qt.callLater(executeStartupHook)
}
