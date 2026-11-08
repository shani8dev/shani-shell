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
import qs.Modules.Ruler
import qs.Modules.Ring
import qs.Modules.Switcher
import qs.Modules.Background
import qs.Modules.Osk
import qs.Modules.WindowMenu
import qs.Modules.HotCorners
import qs.Modules.Processes
import qs.Modules.Captions
import qs.Modules.Magnifier
import qs.Modules.Annotate
import qs.Modules.Settings
import qs.Modules.Touch
import qs.Modules.Flash
import qs.Modules.Pair
import qs.Modules.LayoutSwitcher
import qs.Modules.DisplayConfirm
import qs.Modules.Tour
import qs.Modules.QrView
import qs.Modules.Viewer as ViewerMod
import qs.Modules.PdfReader
import qs.Modules.Camera
import qs.Modules.Player
import qs.Modules.Fonts
import qs.Modules.Characters
import qs.Modules.Modem
import qs.Modules.Share
import qs.Modules.Overview
import qs.Modules.ScreenSaver
import qs.Modules.Charging
import qs.Modules.Hints
import qs.Modules.FileActions
import qs.Modules.Calculator as CalcMod
import qs.Modules.Calendar as CalMod
import qs.Modules.Logs
import qs.Modules.VoiceRecorder

ShellRoot {
    Wallpaper {}
    ScreenCorners {}
    DesktopWidgets {}
    MoreWidgets {}
    DesktopIcons {}
    Bar {}
    Island {}
    Variants { model: Quickshell.screens; Dock {} }
    OverviewSearch {}
    // surfaces most sessions rarely open are made on first use and dropped after:
    // 56 MB of an idle desktop (tests: perf-*)
    LazyLoader { active: Niri.overviewOpen; OverviewStats {} }
    LazyLoader { active: ScreenSaver.active; Cover {} }
    ChargeFx {}
    StartHints {}
    FileActionsCard {}
    Sidebar {}
    Launcher {}
    Popups {}
    Osd {}
    Dim {}
    PolkitDialog {}
    LensPanel {}
    LazyLoader { active: Ruler.phase !== "idle"; RulerPanel {} }    Ring {}
    Switcher {}                     // always made: it opens itself on Ui.switcherRequested
    LazyLoader { active: Ui.layoutSwitcher; LayoutSwitcher {} }
    Keyboard {}
    OskButton {}
    LazyLoader { active: Ui.windowMenu; WindowMenu {} }
    HotCorners {}
    LazyLoader { active: Ui.processes; Processes {} }
    LazyLoader { active: Ui.logs; LogsPanel {} }
    LazyLoader { active: Captions.on; CaptionBar {} }
    LazyLoader { active: Ui.magnifier; Magnifier {} }
    LazyLoader { active: Ui.annotate; Annotate {} }
    LazyLoader { active: Ui.settingsOpen; SettingsWindow {} }
    LazyLoader { active: Settings.data.assistiveTouch; AssistiveTouch {} }
    FlashAlert {}
    PairDialog {}
    LazyLoader { active: Displays.pending; DisplayConfirm {} }
    LazyLoader { active: Ui.tour || (Settings.loaded && !Settings.data.tourSeen && !Quickshell.env("SHANI_NO_TOUR")); Tour {} }
    LazyLoader { active: Qr.shown; QrView {} }
    LazyLoader { active: Calculator.shown; CalcMod.Calculator {} }
    LazyLoader { active: Ui.calendar; CalMod.CalendarPanel {} }
    LazyLoader { active: Viewer.shown; ViewerMod.Viewer {} }
    LazyLoader { active: PdfViewer.shown; PdfReader {} }
    LazyLoader { active: Camera.open; CameraPanel {} }
    LazyLoader { active: Ui.player; Player {} }
    LazyLoader { active: Ui.fonts; FontsPanel {} }
    LazyLoader { active: Ui.voiceRecorder; VoiceRecorderPanel {} }
    LazyLoader { active: Ui.characters; CharactersPanel {} }
    ModemDialog {}
    LazyLoader { active: Share.file !== ""; ShareSheet {} }
    LockScreen { id: lockScreen }
    ChronoaSurface { id: chronoa }
    // the screen being worked on: the control centre opens there
    Binding { target: Ui; property: "screen"; value: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0] }

    // Services that hold no surface still have to be instantiated to run.
    readonly property var _services: [Idle, Polkit, NightLight, AutoRotate, Appearance, Privacy, Updates, Drives, Displays, Osk, Ime, Focus, ScreenTime, Shelf, Phone, Dictation, FocusTimer, QuickNotes, Weather, Screenshots, GameMode, Backup, Access, Smart, Cast, BtAgent, InputConfig, SoundFx, Camera, Housekeeping, SystemSounds, ObexReceive, Proxy, BtSend, Gpu, Printing, Thunderbolt, Agenda, Calculator, Modem, DynamicLock, Share, Automations, Reopen, LockKeys, Mirror, LauncherEntries, AppFilter, Scratchpads, Launch, WallpaperSync, FileActions, AmbientLight, WindowRules, WorldClock, Characters, Viewer, PdfViewer, Location, WebApps, ScreenSaver, KbdBacklight, Hooks, Plugged, GamepadNav, InputKinds, TabletMode, WhatsNew, VoiceRecorder]

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
        function closeAll() { Ui.closeAll(); Ui.settingsOpen = false; }
        // back to a resting desktop: closeAll() closes the panels Ui owns; the
        // overlays below live in their services, and a script photographing one
        // surface after another must not stack them (a render of Settings once
        // carried the ruler banner, the Lens, live captions and old notification
        // cards, all of them opened sections earlier)
        function dismissAll() {
            Ui.closeAll();
            Ui.settingsOpen = false;
            Ui.tour = false;
            Ui.modemDialog = "";
            Lens.close();
            Ruler.close();
            Qr.close();
            Calculator.close();
            Viewer.close();
            PdfViewer.close();
            Share.close();
            Chronoa.open = false;
            if (Captions.on) Captions.start(Captions.source);   // toggles it off
            Notifs.clearAll();
        }

        // Chronoa
        function openChronoa() { Chronoa.open = true; }
        function closeChronoa() { Chronoa.open = false; }
        function toggleChronoa() { Chronoa.open = !Chronoa.open; }
        function ask(text: string) { Chronoa.ask(text); }
        // Chronoa surfaces (wiring only, ask-fallback): see Services/Chronoa.openEditor/openDiff
        function openEditor(path: string) { Chronoa.openEditor(path); }
        function openDiff() { Chronoa.openDiff(); }
        function approve(decision: string) {
            if (Chronoa.approval)
                Chronoa.approve(Chronoa.approval.id, decision);
            else
                chronoa.approveLast(decision);
        }
        function action(name: string) { Chronoa.action(name); }

        // session
        function lock() { Lock.lock(); }
        function themeReload() { Matugen.reload(); }
        function volumeUp() { Audio.stepKey(true); }
        function volumeDown() { Audio.stepKey(false); }
        function volumeMute() { Audio.toggleMute(); }
        function micMute() { Audio.toggleMic(); }
        function brightnessUp() { Brightness.step(0.05); }
        function kbdBacklightUp() { KbdBacklight.step(1); }
        function kbdBacklightDown() { KbdBacklight.step(-1); }
        function kbdBacklightToggle() { KbdBacklight.toggle(); }
        function touchpad() { Settings.data.touchpadOff = !Settings.data.touchpadOff; }
        function airplane() { Net.setAirplane(!Net.airplane); }
        function brightnessDown() { Brightness.step(-0.05); }
        function dnd() { Notifs.setDnd(!Notifs.dnd); }
        function caffeine() { Idle.setCaffeine(!Idle.caffeine); }
        function record() { Recorder.toggle(); }
        function recordingToGif(path: string) { Recorder.toGif(path); }
        function recordingShrink(path: string) { Recorder.shrink(path); }
        function ring() { Ui.toggleRing(); }
        function layoutSwitcher() { Ui.toggleLayoutSwitcher(); }
        function switcher() { Ui.switcherRequested(false); }
        function switcherBack() { Ui.switcherRequested(true); }
        function inputMethod() { Ime.toggle(); }
        function osk() { Osk.toggle(); }
        function dictate() { Dictation.toggle(); }
        function timer(minutes: int) { minutes > 0 ? FocusTimer.start(minutes) : FocusTimer.stop(); }
        function processes() { const was = Ui.processes; Ui.closeAll(); Ui.processes = !was; }
        function toggleLogs() { const was = Ui.logs; Ui.closeAll(); Ui.logs = !was; }
        function togglePlayer() { const was = Ui.player; Ui.closeAll(); Ui.player = !was; }
        function toggleFonts() { const was = Ui.fonts; Ui.closeAll(); Ui.fonts = !was; }
        function toggleCharacters() { const was = Ui.characters; Ui.closeAll(); Ui.characters = !was; }
        function voiceRecorderOpen() { Ui.closeAll(); Ui.voiceRecorder = true; VoiceRecorder.refresh(); }
        function voiceRecorderClose() { Ui.voiceRecorder = false; }
        function voiceRecorderToggle() { const was = Ui.voiceRecorder; Ui.closeAll(); Ui.voiceRecorder = !was; if (Ui.voiceRecorder) VoiceRecorder.refresh(); }
        function voiceRecorderRecord() { VoiceRecorder.start(); }
        function voiceRecorderPause() { VoiceRecorder.togglePause(); }
        function voiceRecorderStop() { VoiceRecorder.stop(); }
        function voiceRecorderPlay(path: string) { VoiceRecorder.play(path); }
        function playerSeek(sec: string) { const p = Media.current; const v = parseFloat(sec); if (p && p.canSeek && isFinite(v)) p.position = Math.max(0, v); }
        function playerVolume(level: string) { const p = Media.current; const v = parseFloat(level); if (p && p.volumeSupported && p.canControl && isFinite(v)) p.volume = Math.max(0, Math.min(1, v)); }
        function playerShuffle() { const p = Media.current; if (p && p.shuffleSupported && p.canControl) p.shuffle = !p.shuffle; }
        function playerRepeat() {
            const p = Media.current;
            if (!p || !p.loopSupported || !p.canControl) return;
            if (p.loopState === MprisLoopState.None) p.loopState = MprisLoopState.Playlist;
            else if (p.loopState === MprisLoopState.Playlist) p.loopState = MprisLoopState.Track;
            else p.loopState = MprisLoopState.None;
        }
        function playerOpen(path: string) {
            const p = Media.current;
            if (!path) return;
            const uri = path.startsWith("file://") ? path : "file://" + encodeURI(path);
            if (p && p.openUri) p.openUri(uri);
            else Quickshell.execDetached(["xdg-open", path]);
        }
        function fontInstall(path: string) {
            if (!path) return;
            Quickshell.execDetached(["sh", "-c", 'dest="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"; mkdir -p "$dest" && cp -- "$1" "$dest/" && fc-cache -f >/dev/null 2>&1', "sh", path]);
        }
        function fontCopy(family: string) { if (family) Quickshell.clipboardText = family; }
        function weather(city: string) { Settings.data.weatherLat = 0; Settings.data.weatherLon = 0; Settings.data.weatherCity = city; }
        function weatherForecast(): string { return JSON.stringify({ city: Settings.data.weatherCity, forecast: Weather.forecast, hourly: Weather.hourly, summary: Weather.summary }); }
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
        function whatsNewCheck() { WhatsNew.check(); }
        function settings() { Ui.openSettings(""); }
        function settingsCategory(cat: string) { Ui.openSettings(cat); }
        // the keyboard into the dock or the bar (a key binds these; Escape gives it back)
        function focusDock() { Ui.closeAll(); Ui.dockFocus = true; }
        function focusBar() { Ui.closeAll(); Ui.barFocus = true; }
        function desktopMenu() { Ui.closeAll(); Ui.desktopMenu = true; }
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
        function cameraOpen() { Ui.closeAll(); Camera.openCamera(); }
        function cameraClose() { Camera.closeCamera(); }
        function cameraShutter() { Camera.shutter(); }
        function cameraViewfinder() { Camera.openViewfinder(); }
        function cameraRefresh() { Camera.refresh(); }
        function tour() { Ui.closeAll(); Ui.tour = true; }
        function agendaRefresh() { Agenda.refresh(); }
        function dynamicLockAway() { DynamicLock.away(); }
        function share(path: string) { Ui.closeAll(); Share.open(path); }
        function textMessage(to: string) { Ui.closeAll(); Ui.smsTo = to; Ui.modemDialog = "sms"; }
        function qr(title: string, text: string) { Ui.closeAll(); Qr.show(title, text); }
        function calculator() { Ui.closeAll(); Calculator.toggle(); }
        function calculatorOpen(expr: string) { Ui.closeAll(); if (expr) { Calculator.clear(); Calculator.display = expr; } Calculator.open(); }
        function calculatorPress(key: string) { Calculator.press(key); }
        function calculatorEquals() { Calculator.evaluate(); }
        function calculatorClear() { Calculator.clear(); }
        function calculatorCopy() { Calculator.copyResult(); }
        function calculatorConvert(value: string, from: string, to: string): string { const r = Calculator.convertUnit(value, from, to); return r ? r.text : ""; }
        function calculatorRecall(idx: int) { Calculator.recallHistory(idx); }
        function calculatorMemory(op: string) { if (op === "mc") Calculator.memoryClear(); else if (op === "mr") Calculator.memoryRecall(); else if (op === "mplus") Calculator.memoryAdd(); else Calculator.memorySubtract(); }
        function calculatorHistoryClear() { Calculator.clearHistory(); }
        function calendar() { const was = Ui.calendar; Ui.closeAll(); Ui.calendar = !was; }
        function calendarOpen() { Ui.closeAll(); Ui.calendar = true; }
        function calendarRefresh() { Agenda.refresh(); }
        function calendarSearch(query: string) { Ui.closeAll(); Ui.calendar = true; Agenda.search = query; }
        function calendarAdd(summary: string, startSec: int, endSec: int, location: string, allDay: string) { Agenda.addEvent({ summary: summary, start: startSec, end: endSec, location: location, allDay: (allDay === "true" || allDay === "1") }); }
        function calendarEdit(uid: string, summary: string, startSec: int, endSec: int, location: string, allDay: string) { Agenda.editEvent({ uid: uid, summary: summary, start: startSec, end: endSec, location: location, allDay: (allDay === "true" || allDay === "1") }); }
        function calendarDelete(uid: string) { Agenda.deleteEvent({ uid: uid }); }
        // image viewer (Loupe parity) + PDF reader (Papers/Evince parity)
        function openViewer(path: string) { Ui.closeAll(); Viewer.open(path); }
        function closeViewer() { Viewer.close(); }
        function viewerNext() { Viewer.next(); }
        function viewerPrev() { Viewer.prev(); }
        function viewerGoTo(index: int) { Viewer.goToIndex(index); }
        function viewerZoomIn() { Viewer.zoomIn(); }
        function viewerZoomOut() { Viewer.zoomOut(); }
        function viewerZoomReset() { Viewer.zoomReset(); }
        function viewerZoomFit() { Viewer.zoomFit(); }
        function viewerZoomActual() { Viewer.zoomActual(); }
        function viewerZoom200() { Viewer.zoom200(); }
        function viewerRotate() { Viewer.rotate(); }
        function viewerRotateCCW() { Viewer.rotateCCW(); }
        function viewerFlipH() { Viewer.toggleFlipH(); }
        function viewerFlipV() { Viewer.toggleFlipV(); }
        function viewerSlideshow() { Viewer.toggleSlideshow(); }
        function viewerGrid() { Viewer.toggleGrid(); }
        function viewerThumbs() { Viewer.toggleThumbs(); }
        function viewerCopy() { Viewer.copyPath(); }
        function viewerOpenWith(app: string) { Viewer.openWith(app); }
        function viewerTrash() { Viewer.trash(); }
        function openPdf(path: string) { Ui.closeAll(); PdfViewer.open(path); }
        function closePdf() { PdfViewer.close(); }
        function pdfNext() { PdfViewer.nextPage(); }
        function pdfPrev() { PdfViewer.prevPage(); }
        function pdfGoTo(page: int) { PdfViewer.jumpTo(page); }
        function pdfSearch(text: string) { PdfViewer.search(text); }
        function pdfFindNext() { PdfViewer.findNext(); }
        function pdfFindPrev() { PdfViewer.findPrev(); }
        function pdfClearSearch() { PdfViewer.clearSearch(); }
        function pdfRotate() { PdfViewer.rotate(); }
        function pdfRotateCCW() { PdfViewer.rotateCCW(); }
        function pdfFit(mode: string) { PdfViewer.setFit(mode); }
        function pdfContinuous() { PdfViewer.toggleContinuous(); }
        function pdfSidebar() { PdfViewer.toggleSidebar(); }
        function pdfPrint() { PdfViewer.printFile(); }
        function pdfOutlineGoTo(index: int) { PdfViewer.goToOutline(index); }
        // media keys: the player that is playing, else the first one
        function media(action: string) {
            const p = Media.current;
            if (!p) return;
            if (action === "play-pause") p.togglePlaying();
            else if (action === "next" && p.canGoNext) p.next();
            else if (action === "previous" && p.canGoPrevious) p.previous();
            else if (action === "stop") p.stop();
        }
        function nextPlayer() { Media.cycle(); }
        // the handwriting pad's reader, fed strokes directly (the tests have no pen)
        // a file, not the strokes: `qs ipc call` splits its arguments at commas,
        // so a JSON argument arrived as a dozen pieces and was refused
        function oskWrite(path: string) { Osk.recognizeFile(path); }
        function wallpaperSearch(q: string) { OnlineWalls.search(q); }
        function wallpaperFetch(i: int) { OnlineWalls.fetch(OnlineWalls.results[i]); }
        function renameWorkspace(idx: int, name: string) { Niri.renameWorkspaceAt(idx, name); }
        function video() { Camera.video(); }
        function displayRevert() { Displays.revert(); }
        function readAloud() { Speak.speakSelection(); }
        function speak(text: string) { Speak.speak(text); }
        function stopSpeaking() { Speak.stop(); }
        function magnifier() { Ui.closeAll(); Ui.magnifier = !Ui.magnifier; }
        function annotate() { const was = Ui.annotate; Ui.closeAll(); Ui.annotate = !was; }
        function callRecord() { CallRecorder.toggle(); }
        function cast() { Ui.closeAll(); Cast.open(); }
        function smartTouch() { Settings.data.assistiveTouch = !Settings.data.assistiveTouch; }
        function ringAt(x: int, y: int) { Ui.openRingAt(x, y); }
        function smartCopy(text: string) { Smart.suggestion = Smart.classify(text); }
        function smartRun() { if (Smart.suggestion) Smart.suggestion.run(); }
        function answerCall() { Notifs.answerCall(); }
        function minimise() { if (Niri.focusedWindow) Niri.minimise(Niri.focusedWindow.id); }
        function minimiseWindow(id: int) { Niri.minimise(id); }
        function restoreWindow(id: int) { Niri.restore(id); }
        function showDesktop() { Niri.showDesktop(); }
        function openFilesWith(app: string, file: string) { Ui.openFilesWith(app, [file]); }
        function pinWindow(id: int) { Niri.togglePinned(id); }
        // the tests: what the next sign-in would offer, offered now
        function reopenOffer() { Reopen.offer(Reopen.saved); }
        function mirrorPhone(serial: string) { Mirror.mirror(serial, false); }
        function appFilterRefresh() { AppFilter.refresh(); }
        // windows by a loose name (title or app id), for scripts and a phone over SSH:
        //   qs -c shani ipc call shani windowClose steam
        function windowList(): string {
            return JSON.stringify(Niri.mru().map(w => ({ id: w.id, title: w.title, app: w.app_id, workspace: Niri.workspaceLabel(w.workspace_id),
                                                         focused: w.id === Niri.focusedWindowId, minimised: Niri.isMinimised(w) })));
        }
        function windowFocus(match: string): string { const w = Niri.findWindows(match)[0]; if (!w) return "no window matches " + match; Niri.focusWin(w); return "focused " + w.title; }
        function windowClose(match: string): string { const w = Niri.findWindows(match)[0]; if (!w) return "no window matches " + match; Niri.action("close-window", "--id", w.id); return "closed " + w.title; }
        function windowFullscreen(match: string): string { const w = Niri.findWindows(match)[0]; if (!w) return "no window matches " + match; Niri.action("focus-window", "--id", w.id); Niri.action("fullscreen-window", "--id", w.id); return "fullscreen " + w.title; }
        function windowMove(match: string, to: string): string { const w = Niri.findWindows(match)[0]; if (!w) return "no window matches " + match; Niri.moveWindowTo(w, to); return "moved " + w.title + " to " + to; }
        function swapMonitors(): string {
            const px = {};
            for (const o of Displays.outputs) px[o.name] = o.width;
            return Niri.swapMonitors(px) ? "swapped" : "needs two monitors";
        }
        // a drop-down app (Mod+` for the terminal): shown, put away, or started
        function shelfPark(path: string) { Shelf.park([path]); }
        function shelfUnpark(path: string) { Shelf.unpark(path); }
        function scratchpad(name: string) { Scratchpads.toggle(name); }
        function screenSaverPreview() { ScreenSaver.preview = true; }
        function chargingPreview() { Ui.chargingPreview = true; }
        // the tests (and scripts): the card for a file, and one of its actions
        function fileActions(path: string) { FileActions.offer([path]); }
        function fileAction(id: string) { FileActions.run(id); }
        function fileFit(maxKb: int, minKb: int, w: int, h: int) { FileActions.fit({ max: maxKb, min: minKb, w: w, h: h }); }
        function dockMenu(app: string) { Ui.dockMenu = ""; Ui.dockMenu = app; }
        // the tests: type a reply into the notification with this summary
        // the tests: press a notification's action (its identifier) as a click would
        function notificationAct(summary: string, action: string) {
            const n = Notifs.list.find(x => x.summary === summary);
            const a = n ? Array.from(n.actions).find(x => x.identifier === action) : null;
            if (a) a.invoke();
        }
        function notificationReply(summary: string, text: string) {
            const n = Notifs.list.find(x => x.summary === summary);
            if (n && n.hasInlineReply) n.sendInlineReply(text);
        }
        function declineCall() { Notifs.declineCall(); }
        // the tests: as if this long at the screen (seconds), and today's total so far
        function wellbeingNow(streak: int, today: int) {
            const d = Object.assign({}, ScreenTime.days);
            d[ScreenTime.today] = Object.assign({}, d[ScreenTime.today] || {}, { "test": today });
            ScreenTime.days = d;
            ScreenTime.streak = streak;
            ScreenTime.wellbeing();
        }
        function playerSink(id: int, sinkName: string) {
            const node = Array.from(Audio.players || []).find(p => p.id == id);
            const sink = Array.from(Audio.sinks || []).find(s => s.name === sinkName || s.id == sinkName);
            if (node && sink && Audio.moveStream) Audio.moveStream(node, sink);
        }
        function storageScan() { if (Drives.scanStorage) Drives.scanStorage(); }
        function locationRefresh() { if (Location.refresh) Location.refresh(); }
        function closeWindow(q: string) { if (Niri.closeWindow) Niri.closeWindow(q); }
        function fullscreenWindow(q: string) { if (Niri.fullscreenWindow) Niri.fullscreenWindow(q); }
        function minimiseWindowByTitle(q: string) { if (Niri.minimiseWindowByTitle) Niri.minimiseWindowByTitle(q); }
        function focusWindowByTitle(q: string) { if (Niri.focusWindowByTitle) Niri.focusWindowByTitle(q); }
        function lens() { Ui.closeAll(); Lens.capture(); }
        function lensRegion(geometry: string) { Ui.closeAll(); Lens.capture(geometry); }
        function ruler() { Ui.closeAll(); Ruler.capture(); }

        function state(): string {
            return JSON.stringify({
                launcher: Ui.launcher,
                controlCenter: Ui.controlCenter,
                expanded: Ui.expanded,
                ring: Ui.ring,
                switcher: Ui.switcher,
                windowMenu: Ui.windowMenu,
                processes: TopProcesses.list.length,
                logs: Ui.logs,
                timerLeft: FocusTimer.left,
                weather: Weather.summary,
                notes: QuickNotes.loaded, notesCount: QuickNotes.notes.length, notesCurrent: QuickNotes.current, notesLinks: QuickNotes.links(),
                alarms: WorldClock.alarms.length, stopwatch: WorldClock.swDisplay,
                characters: Ui.characters, characterLast: Characters.last,
                forecast: Weather.forecast, hourly: Weather.hourly,
                accent: String(Theme.accent),
                bg: String(Theme.bg),
                darkFade: Theme.darkT,
                wallpaperNow: Theme.wallpaper,
                quiet: Notifs.quiet,
                fullscreen: GameMode.fullscreen,
                clipImages: Clipboard.entries.filter(e => e.image).length,
                lastScreenshot: Screenshots.last,
                snoozed: Notifs.snoozed.length,
                tilesShown: Ui.tilesShown, hiddenTiles: Settings.data.hiddenTiles,
                islandActivity: Ui.islandActivity,
                launcherSections: Ui.launcherSections,
                micVolume: Math.round(Audio.micVolume * 100),
                ambientSensor: AmbientLight.available,
                ambientEnabled: AmbientLight.enabled,
                ambientLux: Math.round(AmbientLight.lux),
                ambientTarget: Math.round(AmbientLight.targetBrightness * 100),
                appRules: Array.from(Settings.data.windowRules || []).map(r => r.app),
                worldClocks: WorldClock.clocks,
                locationAvailable: Location.available,
                locationLat: Location.lat,
                locationLon: Location.lon,
                locationAccuracy: Location.accuracy,
                locationError: Location.error,
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
                whatsNewVersion: WhatsNew.currentVersion, whatsNewShown: WhatsNew.shownVersion,
                drives: Drives.drives.length,
                outputs: Displays.outputs.length,
                displays: Displays.outputs.map(o => o.name + ":" + o.scale + "@" + o.x + "," + o.y).join(" "),
                displayPending: Displays.pending,
                mediaPlaying: Mpris.players.values.some(x => x.isPlaying),
                notifSounds: Notifs.sounds,
                trashEmptied: Housekeeping.emptied,
                systemSoundsPlayed: SystemSounds.played,
                bluetoothReceived: ObexReceive.received,
                qrShown: Qr.shown, qrImage: Qr.image,
                calculatorShown: Calculator.shown, calculatorDisplay: Calculator.display, calculatorResult: Calculator.result, calculatorPreview: Calculator.preview,
                calculatorHistory: Calculator.history.map(h => h.expr + "=" + h.value), calculatorMemory: Calculator.memory,
                calendarShown: Ui.calendar, calendarEvents: Agenda.events.length, calendarSearch: Agenda.search,
                viewerShown: Viewer.shown, viewer: Ui.viewer, viewerFile: Viewer.file, viewerZoom: Viewer.zoom, viewerRotation: Viewer.rotation,
                viewerSlideshow: Viewer.slideshow, viewerGrid: Viewer.gridMode, viewerThumbs: Viewer.showThumbs, viewerCopied: Viewer.lastCopied,
                viewerAction: Viewer.lastAction, viewerTrash: Viewer.trashLast, exifOrientation: Viewer.exifOrientation,
                pdfShown: PdfViewer.shown, pdfReader: Ui.pdfReader, pdfFile: PdfViewer.file, pdfPage: PdfViewer.page, pdfPages: PdfViewer.pageCount,
                pdfFit: PdfViewer.fitMode, pdfContinuous: PdfViewer.continuous, pdfSidebar: PdfViewer.showSidebar, pdfSearch: PdfViewer.searchText,
                pdfSearchMatches: PdfViewer.searchMatches.length, pdfOutline: PdfViewer.outline.length, pdfPrint: PdfViewer.printState,
                converted: Recorder.converted, converting: Recorder.converting,
                cpuTemp: SysStats.temp,
                gpus: Gpu.gpus.length,
                agenda: Agenda.events.map(e => e.summary),
                modem: Modem.modem ? Modem.modem.state + "/" + (Modem.modem.locked || "unlocked") + "/" + Modem.modem.operator : "",
                modemCall: Modem.call ? Modem.call.state + ":" + Modem.call.number : "",
                modemDialog: Ui.modemDialog,
                dynamicLocks: DynamicLock.locks, dynamicLockDevice: DynamicLock.address,
                automationsFired: Automations.fired,
                language: Tr.lang, sampleWord: Tr.t("Notifications"),
                minimised: Niri.minimised.map(w => w.id), visibleWorkspaces: Niri.workspacesOn(Niri.focusedOutput).length,
                backupSummary: Ui.backupSummary, printersSeen: Ui.printersSeen,
                annotate: Ui.annotate, annotateStrokes: Ui.annotateStrokes,
                shareTargets: Share.targets.map(t => t.label), shareDone: Share.done,
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
                keptAwakeBy: Idle.keptAwakeBy, idleStagesOn: !Idle.awake,
                niriConfigUndone: NiriConfig.undone, niriConfigPending: Object.keys(NiriConfig.pending).length,
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
                focusedTitle: Niri.focusedWindow ? Niri.focusedTitle : null,
                layout: Niri.layout,
                chronoa: Chronoa.state, chronoaOpen: Chronoa.open,
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
                flashes: Ui.flashes, lastFlash: Ui.lastFlash,
                settingsCat: Ui.settingsCat, settingsOpen: Ui.settingsOpen,
                pinned: Niri.pinned, badges: Notifs.perApp,
                capsLock: LockKeys.caps, numLock: LockKeys.num,
                screenSaver: ScreenSaver.active,
                desktopIconsShown: Settings.data.desktopIcons,
                mediaPlayer: Media.current ? Media.current.identity : '', notifEarlier: Notifs.earlier.length, dndUntil: Settings.data.dndUntil, oskWritten: Osk.lastWritten, shortcutsListed: Ui.shortcutsListed, plugGreeted: Plugged.greeted, navFocus: Ui.navFocus, osdLabel: Ui.osdLabel, presenting: Plugged.presenting ? Plugged.presenting.output : '', screenReader: Settings.data.screenReader, iphoneNoteDone: Settings.data.iphoneNoteDone, promptKeyboard: Ui.promptKeyboard, hasKeyboard: InputKinds.keyboard, tabletMode: TabletMode.on, gamepadNavRunning: GamepadNav.running, gamepadLast: GamepadNav.lastAction, dockFocus: Ui.dockFocus, barFocus: Ui.barFocus, controllersListed: Ui.controllersListed, padTestRunning: Ui.padTestRunning, padTestLast: Ui.padTestLast, u2fRegistered: Ui.u2fRegistered, plugLast: Plugged.last, tabletOutput: Settings.data.tabletOutput, sleepVerb: Power.sleepVerb, compassHeading: Compass.heading, onlineWalls: OnlineWalls.results.length, onlineWallSaved: OnlineWalls.lastSaved, lyricsLines: Lyrics.lines.length, trashCount: Ui.trashCount, shotCountdown: Screenshots.countdown, shelfParked: Shelf.parked, shelfItems: Shelf.items.map(x => x.name),
                layoutSwitcher: Ui.layoutSwitcher, layoutTrying: Ui.layoutTrying, layoutPreset: Settings.data.layoutPreset, dockOn: Settings.data.dock, dockHides: Settings.data.dockVisibility === "hide", dockMode: Settings.data.dockVisibility, barMode: Settings.data.barVisibility, dockShown: Hiding.dockShown[Niri.focusedOutput] !== false, barShown: Hiding.barShown[Niri.focusedOutput] !== false, dockHintSeen: Settings.data.dockHintSeen, desktopIconsOn: Settings.data.desktopIcons, winWidth: Settings.data.winDefaultWidth, widgets: Array.from(Settings.data.desktopWidgets),
                fileActions: FileActions.actions.map(x => x.id), fileActionLast: FileActions.last,
                notifLastSound: Notifs.lastSound,
                scratchpad: Scratchpads.last,
                overviewSearch: Niri.overviewOpen && !Ui.launcher, launcherQuery: Ui.launcherQuery,
                lockPhotos: lockScreen.lockPhotos.length,
                appsBlocked: AppFilter.blocked, appCount: AppFilter.blocked.length >= 0 ? DesktopEntries.applications.values.filter(a => !a.noDisplay && AppFilter.allowed(a.id)).length : 0,
                launcherEntries: LauncherEntries.entries, launcherEntryReady: LauncherEntries.ready,
                mirrorDevices: Mirror.devices.map(d => d.name), mirrored: Mirror.last,
                reopenSaved: Reopen.saved, reopenOffered: Reopen.offered, reopenSession: Reopen.session,
                tour: Ui.tour || (Settings.loaded && !Settings.data.tourSeen && !Quickshell.env("SHANI_NO_TOUR")),
                btAsk: BtAgent.ask ? BtAgent.ask.ask + ":" + BtAgent.ask.device : "",
                btShow: BtAgent.show ? BtAgent.show.device : "",
                speaking: Speak.speaking,
                spoken: Speak.last,
                magnifier: Ui.magnifier,
                player: Ui.player,
                fonts: Ui.fonts,
                playerVolume: Media.current && Media.current.volumeSupported ? Math.round(Media.current.volume * 100) : -1,
                playerShuffle: Media.current ? Media.current.shuffle : false,
                playerLoop: Media.current ? Media.current.loopState : -1,
                playerPosition: Media.current ? Math.round(Media.current.position) : -1,
                playerLength: Media.current ? Math.round(Media.current.length) : -1,
                playerSeekable: Media.current ? Media.current.canSeek : false,
                callRecording: CallRecorder.recording,
                callFile: CallRecorder.file,
                voiceRecorder: Ui.voiceRecorder, voiceRecording: VoiceRecorder.recording, voicePaused: VoiceRecorder.paused, voiceElapsed: VoiceRecorder.elapsed, voiceFiles: VoiceRecorder.recordings.length, voiceFile: VoiceRecorder.file, voiceLast: VoiceRecorder.last, voiceLevel: Math.round(VoiceRecorder.level * 100),
                smart: Smart.suggestion ? Smart.suggestion.text : "",
                assistiveTouch: Settings.data.assistiveTouch,
                castAvailable: Cast.available,
                lensText: Lens.text,
                lensCodes: Lens.codes,
                settingsLoaded: Settings.loaded,
                cpu: Math.round(SysStats.cpu * 100),
                rx: Math.round(SysStats.rxRate),
                balance: Audio.balance,
                reduceTransparency: Settings.data.reduceTransparency,
                sinks: Array.from(Audio.sinks || []).map(s => s.name),
                streams: Array.from(Audio.players || []).map(p => ({ name: p.name || p.properties?.["application.name"] || "", node: p.id, sink: Audio.streamSink ? (Audio.streamSink(p) ? Audio.streamSink(p).name : "") : "" })),
                storageSizes: Drives.storage || []
            });
        }
        function webappAdd(name: string, url: string, icon: string) { WebApps.addApp(name || url, url, icon || ""); }
        function webappRemove(name: string) { WebApps.removeApp(name); }
    }
}
