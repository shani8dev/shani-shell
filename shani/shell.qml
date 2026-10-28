// The icon theme is not a pragma here: shani-shell.service sets QS_ICON_THEME
// to the person's (Settings > Personalisation), Adwaita when none is set.
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
import Quickshell.Services.Mpris
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
import qs.Modules.WindowMenu
import qs.Modules.HotCorners
import qs.Modules.Processes
import qs.Modules.Captions
import qs.Modules.Magnifier
import qs.Modules.Touch
import qs.Modules.Flash
import qs.Modules.Pair
import qs.Modules.DisplayConfirm

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
    WindowMenu {}
    HotCorners {}
    Processes {}
    CaptionBar {}
    Magnifier {}
    AssistiveTouch {}
    FlashAlert {}
    PairDialog {}
    DisplayConfirm {}
    LockScreen {}
    ChronoaSurface { id: chronoa }

    // Services that hold no surface still have to be instantiated to run.
    readonly property var _services: [Idle, Polkit, NightLight, AutoRotate, Appearance, Privacy, Updates, Drives, Displays, Osk, Ime, Focus, ScreenTime, Shelf, Phone, Dictation, FocusTimer, QuickNotes, Weather, Screenshots, GameMode, Backup, Access, Smart, Cast, BtAgent, InputConfig, SoundFx, Camera, Housekeeping, SystemSounds, ObexReceive]

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
        function dictate() { Dictation.toggle(); }
        function timer(minutes: int) { minutes > 0 ? FocusTimer.start(minutes) : FocusTimer.stop(); }
        function processes() { const was = Ui.processes; Ui.closeAll(); Ui.processes = !was; }
        function weather(city: string) { Settings.data.weatherLat = 0; Settings.data.weatherLon = 0; Settings.data.weatherCity = city; }
        function setting(key: string, value: string) { Settings.data[key] = value === "true" ? true : value === "false" ? false : value; }
        function snoozeLatest(minutes: int) { if (Notifs.list.length) Notifs.snooze(Notifs.list[0], minutes); }
        function summarize() { Notifs.summarize(); }
        function focus(name: string) { Settings.data.focusMode = name; }
        function hotCorner(action: string) { HotCornerActions.run(action); }
        function windowMenu() { Ui.closeAll(); Ui.windowMenu = true; }
        function windowMenuAction(id: string) { Ui.windowMenuActionRequested(id); }
        // the same path a tap takes (tests drive the keyboard with it)
        function oskPress(key: string) { Osk.press(key); }
        function oskLanguage() { Osk.nextLanguage(); }
        function settings() { Ui.closeAll(); Ui.controlCenter = true; Ui.expanded = "settings"; }
        function settingsCategory(cat: string) { settings(); Ui.settingsCat = cat; }
        function askIsland() { Ui.askIsland(); }
        function captions() { Captions.toggle(); }
        function transcribe() { Captions.transcribe(); }
        function btAnswer(ok: bool, value: string) { BtAgent.answer(ok, value); }
        // set one screen's setting: key = mode | scale | transform | x | y | vrr | off
        function display(name: string, key: string, value: string) {
            const v = key === "scale" || key === "x" || key === "y" ? parseFloat(value) : key === "vrr" || key === "off" ? value === "true" : value;
            const patch = {};
            patch[key] = v;
            Displays.apply(name, patch);
        }
        function displayKeep() { Displays.keep(); }
        function photo() { Camera.photo(); }
        // media keys: the player that is playing, else the first one
        function media(action: string) {
            const ps = Mpris.players.values;
            const p = ps.find(x => x.isPlaying) || ps[0];
            if (!p) return;
            if (action === "play-pause") p.togglePlaying();
            else if (action === "next" && p.canGoNext) p.next();
            else if (action === "previous" && p.canGoPrevious) p.previous();
            else if (action === "stop") p.stop();
        }
        function video() { Camera.video(); }
        function displayRevert() { Displays.revert(); }
        function readAloud() { Speak.speakSelection(); }
        function speak(text: string) { Speak.speak(text); }
        function stopSpeaking() { Speak.stop(); }
        function magnifier() { Ui.closeAll(); Ui.magnifier = !Ui.magnifier; }
        function callRecord() { CallRecorder.toggle(); }
        function cast() { Ui.closeAll(); Cast.open(); }
        function smartTouch() { Settings.data.assistiveTouch = !Settings.data.assistiveTouch; }
        function ringAt(x: int, y: int) { Ui.openRingAt(x, y); }
        function smartCopy(text: string) { Smart.suggestion = Smart.classify(text); }
        function lens() { Ui.closeAll(); Lens.capture(); }
        function lensRegion(geometry: string) { Ui.closeAll(); Lens.capture(geometry); }

        function state(): string {
            return JSON.stringify({
                launcher: Ui.launcher,
                controlCenter: Ui.controlCenter,
                expanded: Ui.expanded,
                ring: Ui.ring,
                switcher: Ui.switcher,
                windowMenu: Ui.windowMenu,
                processes: TopProcesses.list.length,
                timerLeft: FocusTimer.left,
                weather: Weather.summary,
                notes: QuickNotes.loaded,
                accent: String(Theme.accent),
                bg: String(Theme.bg),
                wallpaperNow: Theme.wallpaper,
                quiet: Notifs.quiet,
                fullscreen: GameMode.fullscreen,
                clipImages: Clipboard.entries.filter(e => e.image).length,
                lastScreenshot: Screenshots.last,
                snoozed: Notifs.snoozed.length,
                tilesShown: Ui.tilesShown,
                islandActivity: Ui.islandActivity,
                launcherSections: Ui.launcherSections,
                micVolume: Math.round(Audio.micVolume * 100),
                fontScale: Theme.fontScale,
                contrast: Theme.contrast,
                sinkName: Audio.sink ? Audio.sink.name : "",
                focus: Focus.active,
                focusScheduled: Focus.scheduled,
                nightLightRunning: NightLight.active || Focus.nightLight,
                nightLightMode: NightLight.mode,
                iconsNeedRestart: Appearance.iconsNeedRestart,
                fx: SoundFx.on, fxRunning: SoundFx.running, fxTarget: SoundFx.target, fxError: SoundFx.error,
                micNoise: SoundFx.micOn, micRunning: SoundFx.micRunning, micError: SoundFx.micError,
                sourceName: Audio.source ? Audio.source.name : "",
                nightLightCommand: NightLight.command.join(" "),
                hotCorner: HotCornerActions.last,
                overview: Niri.overviewOpen,
                screenTimeTotal: ScreenTime.todayTotal,
                screenTimeTop: ScreenTime.top.length ? ScreenTime.top[0].app : "",
                shelf: Shelf.items.length,
                powerProfile: Power.profileName,
                wallpaper: Settings.data.wallpaper,
                dark: Settings.data.darkMode,
                players: Audio.players.length,
                screenShared: Audio.screenShared,
                updates: Updates.summary,
                drives: Drives.drives.length,
                outputs: Displays.outputs.length,
                displays: Displays.outputs.map(o => o.name + ":" + o.scale + "@" + o.x + "," + o.y).join(" "),
                displayPending: Displays.pending,
                mediaPlaying: Mpris.players.values.some(x => x.isPlaying),
                notifSounds: Notifs.sounds,
                trashEmptied: Housekeeping.emptied,
                systemSoundsPlayed: SystemSounds.played,
                bluetoothReceived: ObexReceive.received,
                cameras: Camera.cameras.length, cameraPhase: Camera.phase, cameraLast: Camera.last,
                inputMethod: Ime.current,
                osk: Osk.shown,
                dictation: Dictation.phase,
                dictated: Dictation.last,
                oskLang: Osk.lang,
                oskTyped: Osk.typed,
                ringDepth: Ui.ringDepth,
                topResult: Ui.topResult,
                locked: Lock.locked,
                lockSecure: Lock.secure,
                dnd: Notifs.dnd,
                notifications: Notifs.count,
                notificationSummaries: Notifs.list.map(n => n.summary),
                popupSummaries: Notifs.popups.map(n => n.summary),
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
                captions: Captions.on,
                captionText: Captions.text,
                captionSource: Captions.source,
                transcript: Captions.transcript,
                flashes: Ui.flashes,
                settingsCat: Ui.settingsCat,
                btAsk: BtAgent.ask ? BtAgent.ask.ask + ":" + BtAgent.ask.device : "",
                btShow: BtAgent.show ? BtAgent.show.device : "",
                speaking: Speak.speaking,
                spoken: Speak.last,
                magnifier: Ui.magnifier,
                callRecording: CallRecorder.recording,
                callFile: CallRecorder.file,
                smart: Smart.suggestion ? Smart.suggestion.text : "",
                assistiveTouch: Settings.data.assistiveTouch,
                castAvailable: Cast.available,
                lensText: Lens.text,
                lensCodes: Lens.codes,
                settingsLoaded: Settings.loaded,
                cpu: Math.round(SysStats.cpu * 100),
                rx: Math.round(SysStats.rxRate)
            });
        }
    }
}
