pragma Singleton
// A live wallpaper (Settings > Personalisation): a video, muted and looping,
// drawn over the still picture on the background layer (Modules/Background).
// It plays only while somebody can see it and it costs little: paused under
// windows (anything tiled on the screen's workspace, or one full-screen), while
// locked, dimmed or idle, and on battery unless that is allowed. Paused, its
// last frame stays; the still picture is underneath for the moments before the
// first frame.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string video: Settings.loaded ? (Settings.data.wallpaperVideo || "") : ""
    readonly property bool enabled: video !== ""
    readonly property bool batteryOk: !Power.onBattery || Settings.data.wallpaperVideoOnBattery === true

    // why it is paused on this screen now ("" while it plays) - the tests read it too
    function pausedWhy(output) {
        if (!enabled) return "off";
        if (Lock.locked) return "locked";
        if (Idle.dimmed) return "idle";
        if (!batteryOk) return "battery";
        const ws = Niri.workspaces.find(w => w.output === output && w.is_active);
        if (ws) {
            const here = Object.values(Niri.windows).filter(w => w.workspace_id === ws.id && !Niri.isMinimised(w));
            if (here.some(w => !w.is_floating || w.is_fullscreen)) return "covered";
        }
        return "";
    }
    readonly property var why: {
        const out = {};
        for (const s of Quickshell.screens) out[s.name] = pausedWhy(s.name);
        return out;
    }
}
