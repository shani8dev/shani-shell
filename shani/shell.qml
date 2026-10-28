//@ pragma IconTheme Adwaita
// ShaniOS shell — an AI desktop on niri + Quickshell. Chronoa lives in the
// middle of the bar (the Island); the sidebar holds the quick settings and
// notifications; a Latte-style dock sits at the bottom.
//
//   Common/    theme tokens, settings (live-reloaded JSON), small widgets
//   Services/  one singleton per system: niri, audio, network, power, lock …
//   Modules/   the surfaces, which only bind to services
//
// `qs -c shani ipc call shani <fn>` drives all of it (niri keybinds use it);
// `state` answers with the live state as JSON, for tests and scripts.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Bar
import qs.Modules.Island
import qs.Modules.ControlCenter
import qs.Modules.Launcher
import qs.Modules.Notifications
import qs.Modules.Osd
import qs.Modules.Lock
import qs.Modules.Polkit
import qs.Modules.Chronoa
import qs.Modules.Dock
import qs.Modules.Idle
import qs.Modules.Lens
import qs.Modules.Ring
import qs.Modules.Switcher
import qs.Modules.Background
import qs.Modules.Osk

ShellRoot {
    Wallpaper {}
    Bar {}
    Island {}
    Dock {}
    Sidebar {}
    Launcher {}
    Popups {}
    Osd {}
    Dim {}
    PolkitDialog {}
    LensPanel {}
    Ring {}
    Switcher {}
    Keyboard {}
    LockScreen {}
    ChronoaSurface { id: chronoa }

    // Services that hold no surface still have to be instantiated to run.
    readonly property var _services: [Idle, Polkit, NightLight, AutoRotate, Appearance, Privacy, Updates, Drives, Displays, Osk, Ime]

    IpcHandler {
        target: "shani"

        // surfaces
        function toggleLauncher() { Ui.toggleLauncher(); }
        function openLauncher() { if (!Ui.launcher) Ui.toggleLauncher(); }
        function closeLauncher() { Ui.closeAll(); }
        function launcher(query: string) { Ui.closeAll(); Ui.toggleLauncher(query); }
        function toggleControlCenter() { Ui.toggleControlCenter(); }
        function controlCenter(section: string) { Ui.closeAll(); Ui.toggleControlCenter(section); }
        function toggleNotifications() { Ui.toggleControlCenter("notifications"); }
        function closeAll() { Ui.closeAll(); }

        // Chronoa
        function openChronoa() { Chronoa.open = true; }
        function closeChronoa() { Chronoa.open = false; }
        function toggleChronoa() { Chronoa.open = !Chronoa.open; }
        function ask(text: string) { Chronoa.ask(text); }
        function approve(decision: string) {
            if (Chronoa.approval)
                Chronoa.approve(Chronoa.approval.id, decision);
            else
                chronoa.approveLast(decision);
        }
        function action(name: string) { Chronoa.action(name); }

        // session
        function lock() { Lock.lock(); }
        function volumeUp() { Audio.step(0.05); }
        function volumeDown() { Audio.step(-0.05); }
        function volumeMute() { Audio.toggleMute(); }
        function micMute() { Audio.toggleMic(); }
        function brightnessUp() { Brightness.step(0.05); }
        function brightnessDown() { Brightness.step(-0.05); }
        function dnd() { Notifs.setDnd(!Notifs.dnd); }
        function caffeine() { Idle.setCaffeine(!Idle.caffeine); }
        function record() { Recorder.toggle(); }
        function ring() { Ui.toggleRing(); }
        function switcher() { Ui.switcherRequested(false); }
        function switcherBack() { Ui.switcherRequested(true); }
        function inputMethod() { Ime.toggle(); }
        function osk() { Osk.toggle(); }
        // the same path a tap takes (tests drive the keyboard with it)
        function oskPress(key: string) { Osk.press(key); }
        function oskLanguage() { Osk.nextLanguage(); }
        function settings() { Ui.closeAll(); Ui.controlCenter = true; Ui.expanded = "settings"; }
        function askIsland() { Ui.askIsland(); }
        function lens() { Ui.closeAll(); Lens.capture(); }
        function lensRegion(geometry: string) { Ui.closeAll(); Lens.capture(geometry); }

        function state(): string {
            return JSON.stringify({
                launcher: Ui.launcher,
                controlCenter: Ui.controlCenter,
                expanded: Ui.expanded,
                ring: Ui.ring,
                switcher: Ui.switcher,
                wallpaper: Settings.data.wallpaper,
                dark: Settings.data.darkMode,
                players: Audio.players.length,
                screenShared: Audio.screenShared,
                updates: Updates.summary,
                drives: Drives.drives.length,
                outputs: Displays.outputs.length,
                inputMethod: Ime.current,
                osk: Osk.shown,
                oskLang: Osk.lang,
                oskTyped: Osk.typed,
                ringDepth: Ui.ringDepth,
                topResult: Ui.topResult,
                locked: Lock.locked,
                lockSecure: Lock.secure,
                dnd: Notifs.dnd,
                notifications: Notifs.count,
                popups: Notifs.popups.length,
                caffeine: Idle.caffeine,
                dimmed: Idle.dimmed,
                idleLock: Idle.lockIdle,
                lockAfter: Idle.lockAfter,
                volume: Math.round(Audio.volume * 100),
                muted: Audio.muted,
                audioReady: Audio.ready,
                micInUse: Audio.micInUse,
                workspaces: Niri.workspaces.length,
                focusedWorkspace: (Niri.workspaces.find(w => w.is_focused) || {}).idx,
                windows: Object.keys(Niri.windows).length,
                focusedTitle: Niri.focusedWindow ? Niri.focusedWindow.title : null,
                layout: Niri.layout,
                chronoa: Chronoa.state,
                bridge: Bridge.connected,
                approval: Chronoa.approval ? Chronoa.approval.text : null,
                art: Chronoa.art,
                polkit: Polkit.active,
                polkitRegistered: Polkit.agent.isRegistered,
                recording: Recorder.recording,
                lens: Lens.phase,
                lensText: Lens.text,
                lensCodes: Lens.codes,
                settingsLoaded: Settings.loaded,
                cpu: Math.round(SysStats.cpu * 100),
                rx: Math.round(SysStats.rxRate)
            });
        }
    }
}
