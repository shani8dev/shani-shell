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
import qs.Modules.Maps
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
import qs.Modules.Notes
import qs.Modules.TextEditor
import qs.Modules.Scanner
import qs.Modules.PasswordGenerator
import qs.Modules.Kundali
import qs.Modules.PdfSigner
import qs.Modules.DiskUsage
import qs.Modules.Files
import qs.Modules.FilePicker
import qs.Modules.VideoTrimmer
// registers the folder as a module for the Media Player window, which a `source:`
// loader reads (an import loads nothing by itself)
import qs.Modules.MediaPlayer

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
    // The surfaces below that say `source:` are the shell's apps and other
    // rarely opened panels: read and compiled when first opened, not at sign-in
    // (measured: 527 -> 512 MB idle). A mistake in one therefore shows when it
    // is opened, not at load - dev/shell-parts/apps.sh opens every one of them.
    LazyLoader { active: Ui.layoutSwitcher; source: "Modules/LayoutSwitcher/LayoutSwitcher.qml" }
    Keyboard {}
    OskButton {}
    LazyLoader { active: Ui.windowMenu; source: "Modules/WindowMenu/WindowMenu.qml" }
    HotCorners {}
    LazyLoader { active: Ui.processes; source: "Modules/Processes/Processes.qml" }
    LazyLoader { active: Ui.logs; source: "Modules/Logs/LogsPanel.qml" }
    LazyLoader { active: Captions.on; CaptionBar {} }
    LazyLoader { active: Ui.magnifier; source: "Modules/Magnifier/Magnifier.qml" }
    LazyLoader { active: Ui.annotate; Annotate {} }
    LazyLoader { active: Ui.settingsOpen; SettingsWindow {} }
    LazyLoader { active: Settings.data.assistiveTouch; AssistiveTouch {} }
    FlashAlert {}
    PairDialog {}
    LazyLoader { active: Displays.pending; DisplayConfirm {} }
    LazyLoader { active: Ui.tour || (Settings.loaded && !Settings.data.tourSeen && !Quickshell.env("SHANI_NO_TOUR")); Tour {} }
    LazyLoader { active: Qr.shown; source: "Modules/QrView/QrView.qml" }
    LazyLoader { active: Calculator.shown; source: "Modules/Calculator/Calculator.qml" }
    LazyLoader { active: Ui.calendar; source: "Modules/Calendar/CalendarPanel.qml" }
    LazyLoader { active: Viewer.shown; source: "Modules/Viewer/Viewer.qml" }
    LazyLoader { active: PdfViewer.shown; source: "Modules/PdfReader/PdfReader.qml" }
    LazyLoader { active: Camera.open; source: "Modules/Camera/CameraPanel.qml" }
    LazyLoader { active: Ui.maps; source: "Modules/Maps/MapsPanel.qml" }
    LazyLoader { active: Ui.player; source: "Modules/Player/Player.qml" }
    LazyLoader { active: Ui.fonts; source: "Modules/Fonts/FontsPanel.qml" }
    LazyLoader { active: Ui.voiceRecorder; source: "Modules/VoiceRecorder/VoiceRecorderPanel.qml" }
    LazyLoader { active: Ui.notes; source: "Modules/Notes/NotesPanel.qml" }
    LazyLoader { active: Ui.textEditor; source: "Modules/TextEditor/TextEditorPanel.qml" }
    LazyLoader { active: PlayQueue.shown; source: "Modules/MediaPlayer/MediaPlayerWindow.qml" }
    LazyLoader { active: Ui.clocks; source: "Modules/Clocks/ClocksWindow.qml" }
    LazyLoader { active: Ui.authenticator; source: "Modules/Authenticator/AuthenticatorWindow.qml" }
    LazyLoader { active: Ui.nearby; source: "Modules/Nearby/NearbyWindow.qml" }
    LazyLoader { active: Ui.converter; source: "Modules/Converter/ConverterWindow.qml" }
    LazyLoader { active: Ui.tasks; source: "Modules/Tasks/TasksWindow.qml" }
    LazyLoader { active: QuickLook.shown; source: "Modules/QuickLook/QuickLookSheet.qml" }
    LazyLoader { active: WritingTools.shown; source: "Modules/WritingTools/WritingToolsSheet.qml" }
    LazyLoader { active: Ui.photos; source: "Modules/Photos/PhotosWindow.qml" }
    LazyLoader { active: Ui.translate; source: "Modules/Translate/TranslateWindow.qml" }
    LazyLoader { active: Ui.weather; source: "Modules/Weather/WeatherWindow.qml" }
    LazyLoader { active: Archive.shown; source: "Modules/Archives/ArchivesWindow.qml" }
    LazyLoader { active: Ui.scanner; source: "Modules/Scanner/ScannerPanel.qml" }
    LazyLoader { active: Ui.passwordGenerator; source: "Modules/PasswordGenerator/PasswordGeneratorPanel.qml" }
    LazyLoader { active: Ui.kundali; source: "Modules/Kundali/KundaliPanel.qml" }
    LazyLoader { active: Ui.pdfSigner; source: "Modules/PdfSigner/PdfSignerPanel.qml" }
    LazyLoader { active: Ui.diskUsage; source: "Modules/DiskUsage/DiskUsagePanel.qml" }
    LazyLoader { active: Ui.files; source: "Modules/Files/FilesPanel.qml" }
    LazyLoader { active: FilePicker.shown; source: "Modules/FilePicker/FilePickerPanel.qml" }
    LazyLoader { active: Ui.videoTrimmer; source: "Modules/VideoTrimmer/VideoTrimmerPanel.qml" }
    LazyLoader { active: Ui.characters; source: "Modules/Characters/CharactersPanel.qml" }
    ModemDialog {}
    LazyLoader { active: Share.file !== ""; source: "Modules/Share/ShareSheet.qml" }
    LockScreen { id: lockScreen }
    ChronoaSurface { id: chronoa }
    // the screen being worked on: the control centre opens there
    Binding { target: Ui; property: "screen"; value: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0] }
    // the file chooser, for the widgets in Common that ask for a file
    Component.onCompleted: { Ui.filePicker = FilePicker; Ui.minimiser = () => { if (Niri.focusedWindow) Niri.minimise(Niri.focusedWindow.id); }; }

    // closeApps() (the IPC's closeAll, a script's "empty desktop"): the apps
    // shown by their services, not by a Ui flag, close with the others
    // "raise" from a media client (the bar's now playing, playerctl): the player's window forward
    Connections {
        target: PlayQueue
        function onRaiseRequested() { Niri.raiseApp("dev.shani.MediaPlayer"); }
    }
    Connections {
        target: Ui
        function onClosedApps() {
            if (Calculator.shown) Calculator.close();
            if (Viewer.shown) Viewer.close();
            if (PdfViewer.shown) PdfViewer.close();
            if (Camera.open) Camera.closeCamera();
            if (PlayQueue.shown) PlayQueue.close();
            if (Archive.shown) Archive.close();
        }
    }

    // Services that hold no surface still have to be instantiated to run.
    readonly property var _services: [Idle, InputPlumber, Ups, Polkit, NightLight, AutoRotate, Appearance, Privacy, Updates, Drives, Displays, Osk, Ime, Focus, ScreenTime, Shelf, Phone, Dictation, FocusTimer, QuickNotes, Weather, Screenshots, GameMode, Backup, Access, Smart, Cast, BtAgent, InputConfig, SoundFx, Camera, Housekeeping, SystemSounds, ObexReceive, Proxy, BtSend, Gpu, Printing, Thunderbolt, Agenda, Calculator, Modem, DynamicLock, Share, Automations, Reopen, LockKeys, Mirror, LauncherEntries, AppFilter, Scratchpads, Launch, WallpaperSync, FileActions, AmbientLight, WindowRules, WindowLook, Terminal, SmartReplies, WorldClock, Characters, Viewer, PdfViewer, Location, WebApps, ScreenSaver, KbdBacklight, Hooks, Plugged, GamepadNav, InputKinds, TabletMode, WhatsNew, VoiceRecorder, PdfSigner, DiskUsage, WallpaperStyle, VideoTrimmer]

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
        function closeAll() { Ui.closeAll(); Ui.closeApps(); Ui.settingsOpen = false; }
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
            PdfSigner.close();
            DiskUsage.close();
            FilePicker.cancel();
            VideoTrimmer.close();
            Share.close();
            WallpaperStyle.close();
            Chronoa.open = false;
            if (Captions.on) Captions.start(Captions.source);   // toggles it off
            Notifs.clearAll();
        }

        // Chronoa
        function openChronoa() { Chronoa.open = true; }
        function closeChronoa() { Chronoa.open = false; }
        function toggleChronoa() { Chronoa.open = !Chronoa.open; }
        function ask(text: string) { Chronoa.ask(text); }
        // Quick Look: a file seen without opening its app (Space in Files)
        function quickLook(path: string) { QuickLook.open(path, []); }
        function quickLookClose() { QuickLook.close(); }
        // writing tools on the selected text (Mod+Shift+W); Chronoa's Agent.Write
        function writingTools() { Ui.closeAll(); WritingTools.open(); }
        function writingToolsChoose(i: string) { WritingTools.choose(Number(i)); }
        function writingToolsTranslate(lang: string) { WritingTools.translate(lang); }
        function writingToolsReplace() { WritingTools.replace(); }
        function writingToolsClose() { WritingTools.close(); }
        function quickLookStep(d: string) { QuickLook.step(Number(d)); }
        // a terminal's output (foot: Ctrl+Shift+A = the last command's, Ctrl+Shift+E = the
        // selection): the panel opens with the question and the end of the text
        function chronoaExplain(text: string) {
            const t = text.replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "").trim();
            if (!t)
                return;
            Chronoa.open = true;
            Chronoa.ask(Tr.t("What does this terminal output mean? If something went wrong, what should I do?") + "\n\n```\n" + (t.length > 6000 ? "…" + t.slice(-6000) : t) + "\n```");
        }
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
        // WallpaperStyle (Settings > Personalisation): theme extraction + application over Matugen
        function themeFromImage(path: string) { Ui.closeAll(); WallpaperStyle.open(path || ""); }
        function wallpaperStyleOpen(path: string) { Ui.closeAll(); WallpaperStyle.open(path || ""); }
        function wallpaperStyleClose() { WallpaperStyle.close(); }
        function wallpaperStyleExtract() { WallpaperStyle.extract(); }
        function wallpaperStyleApply() { WallpaperStyle.apply(); }
        function wallpaperStyleSaveTheme(name: string) { WallpaperStyle.saveTheme(name); }
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
        // one of the shell's app windows, forward (`shani app` asks after opening it)
        function appRaise(id: string) { Niri.raiseApp(id); }
        // opening, not toggling: what a desktop entry (`shani app …`) and a dock pin ask for
        function processesOpen() { Ui.closeAll(); Ui.processes = true; }
        function logsOpen() { Ui.closeAll(); Ui.logs = true; }
        function fontsOpen() { Ui.closeAll(); Ui.fonts = true; }
        function charactersOpen() { Ui.closeAll(); Ui.characters = true; }
        function processes() { const was = Ui.processes; Ui.closeAll(); Ui.processes = !was; }
        function toggleLogs() { const was = Ui.logs; Ui.closeAll(); Ui.logs = !was; }
        function togglePlayer() { const was = Ui.player; Ui.closeAll(); Ui.player = !was; }
        function toggleFonts() { const was = Ui.fonts; Ui.closeAll(); Ui.fonts = !was; }
        function toggleCharacters() { const was = Ui.characters; Ui.closeAll(); Ui.characters = !was; }
        function voiceRecorderOpen() { Ui.closeAll(); Ui.voiceRecorder = true; VoiceRecorder.refresh(); }
        function voiceRecorderClose() { Ui.voiceRecorder = false; }
        function voiceRecorderToggle() { const was = Ui.voiceRecorder; Ui.closeAll(); Ui.voiceRecorder = !was; if (Ui.voiceRecorder) VoiceRecorder.refresh(); }
        function notesOpen() { Ui.closeAll(); Ui.notes = true; QuickNotes.refresh(); if (QuickNotes.current === "") { if (QuickNotes.notes.length > 0) QuickNotes.open(QuickNotes.notes[0].name, QuickNotes.notes[0].notebook); else QuickNotes.create("Untitled", ""); } }
        function notesClose() { Ui.notes = false; }
        function notesRefresh() { QuickNotes.refresh(); }
        function notesToggle() { const was = Ui.notes; Ui.closeAll(); Ui.notes = !was; if (Ui.notes) { QuickNotes.refresh(); if (QuickNotes.current === "") { if (QuickNotes.notes.length > 0) QuickNotes.open(QuickNotes.notes[0].name, QuickNotes.notes[0].notebook); else QuickNotes.create("Untitled", ""); } } }
        function textEditorClose() { Ui.textEditor = false; }
        function textEditorToggle() { const was = Ui.textEditor; Ui.closeAll(); Ui.textEditor = !was; }
        function tasksOpen() { Ui.closeAll(); Ui.tasks = true; Tasks.refresh(); }
        function tasksAdd(summary: string, due: string) { Tasks.add(summary, parseFloat(due) || 0); }
        function photosOpen() { Ui.closeAll(); Ui.photos = true; }
        function translateOpen() { Ui.closeAll(); Ui.translate = true; }
        // Converter: files, if any, then the window
        function converterOpen(path: string) { Ui.closeAll(); if (path) Ui.converterFiles = [path]; Ui.converter = true; }
        // Nearby (LocalSend): files to send, if any, then the window
        function nearbyOpen(path: string) { Ui.closeAll(); if (path) Nearby.pending = [path]; Ui.nearby = true; }
        function nearbyVisible(on: string) { Nearby.setVisible(on === "true"); }
        function nearbyAnswer(accept: string) { if (Nearby.offers.length) Nearby.answer(Nearby.offers[0].session, accept === "true"); }
        function nearbySendTo(alias: string) { const d = Nearby.devices.find(x => x.alias === alias); if (d) Nearby.sendTo(d.fingerprint); }
        function authenticatorOpen() { Ui.closeAll(); Ui.authenticator = true; }
        function cleanUpOpen() { Ui.openSettings("storage"); }
        function weatherOpen() { Ui.closeAll(); Ui.weather = true; }
        function screenTimeOpen() { Ui.openSettings("screentime"); }
        // the tools that are an action, not a window (their desktop entries start these)
        function screenshotTool() { Ui.closeAll(); Niri.action("screenshot"); }
        function colorPicker() { Ui.closeAll(); Quickshell.execDetached(["sh", "-c", "c=$(niri msg pick-color | sed -n 's/^Hex: //p'); [ -n \"$c\" ] && printf %s \"$c\" | wl-copy && notify-send -a 'Color picker' -i color-select \"$c\" 'Copied'"]); }
        // Clocks (Modules/Clocks): a tab - world | alarms | stopwatch | timer - or "" for the last one
        function clocksOpen(tab: string) { Ui.closeAll(); if (tab) Ui.clocksTab = tab; Ui.clocks = true; }
        function clocksClose() { Ui.clocks = false; }
        // Archives (Modules/Archives, Services/Archive): look inside, extract beside it or into a folder
        function archiveOpen(path: string) { Ui.closeAll(); Archive.open(path); }
        function archiveClose() { Archive.close(); }
        function archiveExtract(where: string) { Archive.extract(where || ""); }
        function archiveExtractOne(entry: string) { Archive.extractOne(entry); }
        function archiveUnlock(password: string) { Archive.unlock(password); }
        // paths one per line (qs ipc turns a JSON list argument into several arguments)
        function archiveCompress(paths: string, ext: string) { const p = paths.split("\n").filter(x => x); Archive.createAsk(p); Archive.create(p, ext || "zip", ""); }
        // Media Player (Modules/MediaPlayer, Services/PlayQueue): videos and music
        // the Library: an album by its title, from its first song
        function mediaLibraryVideos() { MusicLibrary.scanVideos(); }
        function mediaPage(page: string) { if (page === "library" || page === "playing") PlayQueue.page = page; }
        function mediaPlayAlbum(title: string) { const a = MusicLibrary.albums.find(x => x.title === title); if (a) MusicLibrary.play(a.songs, 0); }
        function mediaOpen(path: string) { Ui.closeAll(); PlayQueue.open(path); }
        function mediaClose() { PlayQueue.close(); }
        function mediaMini(on: string) { PlayQueue.miniRequested(on === "true"); }
        function mediaPlayPause() { PlayQueue.toggleRequested(); }
        function mediaPlay() { PlayQueue.playRequested(); }
        function mediaPause() { PlayQueue.pauseRequested(); }
        function mediaSeek(seconds: string) { const v = parseFloat(seconds); if (isFinite(v)) PlayQueue.seekRequested(v); }
        function mediaNext() { PlayQueue.next(); }
        function mediaPrevious() { PlayQueue.previous(); }
        function mediaVolume(level: string) { const v = parseFloat(level); if (isFinite(v)) { PlayQueue.muted = false; PlayQueue.volume = Math.max(0, Math.min(1, v)); } }
        function mediaRate(rate: string) { const v = parseFloat(rate); if (isFinite(v) && v >= 0.25 && v <= 4) PlayQueue.rate = v; }
        function scannerOpen() { Ui.closeAll(); Ui.scanner = true; }
        function scannerClose() { Ui.scanner = false; }
        function scannerToggle() { const was = Ui.scanner; Ui.closeAll(); Ui.scanner = !was; }
        function passwordGeneratorOpen() { Ui.closeAll(); Ui.passwordGenerator = true; }
        function passwordGeneratorClose() { Ui.passwordGenerator = false; }
        function passwordGeneratorToggle() { const was = Ui.passwordGenerator; Ui.closeAll(); Ui.passwordGenerator = !was; }
        function kundaliOpen() { Ui.closeAll(); Ui.kundali = true; }
        function kundaliClose() { Ui.kundali = false; }
        function kundaliToggle() { const was = Ui.kundali; Ui.closeAll(); Ui.kundali = !was; }
        function voiceRecorderRecord() { VoiceRecorder.start(); }
        function voiceRecorderPause() { VoiceRecorder.togglePause(); }
        function voiceRecorderStop() { VoiceRecorder.stop(); }
        function voiceRecorderPlay(path: string) { VoiceRecorder.play(path); }
        // Signed: sign / fill a PDF (arg or a folder's last PDF)
        function pdfSignerOpen(path: string) { PdfSigner.open(path); }
        function pdfSignerClose() { PdfSigner.close(); }
        function pdfSignerToggle(path: string) { PdfSigner.toggle(path); }
        function pdfSignerSave() { PdfSigner.save(); }
        function pdfSignerSignature(path: string) { PdfSigner.setSignature(path); }
        function pdfSignerPosition(x: string, y: string) { PdfSigner.setPosition(x, y); }
        function pdfSignerScale(scale: string) { PdfSigner.setScale(scale); }
        function pdfSignerText(text: string) { PdfSigner.setFillText(text); }
        function pdfSignerTextPosition(x: string, y: string) { PdfSigner.setTextPosition(x, y); }
        // DiskUsage: disk treemap (default home), walk in, mark, trash
        function diskUsageOpen(path: string) { DiskUsage.open(path); }
        function diskUsageClose() { DiskUsage.close(); }
        function diskUsageToggle() { DiskUsage.toggle(); }
        function diskUsageScan(path: string) { if (path) DiskUsage.scan(path); else DiskUsage.refresh(); }
        function diskUsageEnter(path: string) { DiskUsage.enter(path); }
        function diskUsageBack() { DiskUsage.back(); }
        function diskUsageMark(path: string) { DiskUsage.toggleMark(path); }
        function diskUsageClearMarks() { DiskUsage.clearMarks(); }
        function diskUsageTrashMarked() { DiskUsage.trashMarked(); }
        // Files: the file manager
        function filesOpen(path: string) { Files.show(path); }
        // Tidy and name (Files): sort a folder by kind, undo it; a name from Chronoa
        function filesTidy(path: string) { Files.show(path); Tidy.plan(path); }
        function filesTidyApply() { Tidy.apply(); }
        function filesTidyUndo() { Tidy.undo(); }
        function filesSuggestName(path: string) { Tidy.suggestName(path); }
        function filesHome() { Files.show(""); }
        function filesClose() { Files.hide(); }
        function filesToggle(path: string) { Files.toggle(path); }
        function filesGo(path: string) { Files.open(path); }
        function filesBack() { Files.back(); }
        function filesUp() { Files.up(); }
        function filesSelect(path: string) { Files.select(path, "single"); }
        function filesTrash() { Files.trashEntries([]); }
        function filesMakeFolder(name: string) { Files.makeFolder(name); }
        function filesRename(path: string, name: string) { Files.renameEntry(path, name); }
        // the file chooser: open | save | folder
        function filePickerOpen(mode: string, path: string) { FilePicker.open({ "mode": mode || "open", "startPath": path || "" }); }
        function filePickerHome() { FilePicker.open({ "mode": "open" }); }
        function filePickerClose() { FilePicker.cancel(); }
        function filePickerGo(path: string) { FilePicker.go(path); }
        function filePickerSelect(path: string) { FilePicker.select(path, "single"); }
        function filePickerAccept() { FilePicker.accept(); }
        function voiceRecorderTrim(path: string, start: string, end: string) {
            const s = parseFloat(start), e = parseFloat(end);
            if (!path || !isFinite(s) || !isFinite(e))
                return;
            VoiceRecorder.openTrim(path);
            VoiceRecorder.setTrimStart(s);
            VoiceRecorder.setTrimEnd(e);
            VideoTrimmer.trimAudio(path, s, e);
        }
        // Video Trimmer: a file, or a folder's last video
        function videoTrimmerOpen(path: string) { Ui.closeAll(); VideoTrimmer.open(path); }
        function videoTrimmerClose() { VideoTrimmer.close(); }
        function videoTrimmerToggle() { const was = Ui.videoTrimmer; Ui.closeAll(); Ui.videoTrimmer = !was; if (Ui.videoTrimmer) VideoTrimmer.open(""); }
        function videoTrimmerCut() { VideoTrimmer.cut(); }
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
        // Text Editor: the documents are Services/TextDocs's, so they outlive the panel.
        // A file handed over while it is open joins the tabs (nothing else is closed).
        function textEditorOpen(path: string) { Ui.closeAll(); Ui.textEditor = true; TextDocs.open(path); }
        function textEditorNew() { Ui.closeAll(); Ui.textEditor = true; TextDocs.newDoc(); }
        function textEditorSetText(text: string) { TextDocs.setText(text); TextDocs.revision++; }
        function textEditorSave(): string { return TextDocs.save() ? "ok" : "no name yet: use save-as"; }
        function textEditorSaveAs(path: string) { TextDocs.saveAs(path); }
        function textEditorCloseTab() { TextDocs.close(TextDocs.active); }
        function setting(key: string, value: string) { Settings.data[key] = value === "true" ? true : value === "false" ? false : value; }
        function snoozeLatest(minutes: int) { if (Notifs.list.length) Notifs.snooze(Notifs.list[0], minutes); }
        function summarize() { Notifs.summarize(); }
        function focus(name: string) { Settings.data.focusMode = name; }
        function hotCorner(action: string) { HotCornerActions.run(action); }
        function windowMenu() { Ui.closeAll(); Ui.windowMenu = true; }
        function windowMenuAction(id: string) { Ui.windowMenuActionRequested(id); }
        // the app's own menus in the window menu (Services/AppMenu): open one, press an item
        function windowMenuOpenApp(index: string) { Ui.windowMenuAppRequested(Number(index)); }
        function appMenuActivate(path: string) { AppMenu.activate(path); }
        // InputPlumber (Settings > Game controllers): what a controller plays as, every controller
        function inputPlumberPlaysAs(path: string, id: string) {
            const d = InputPlumber.devices.find(x => x.path === path);
            InputPlumber.setTargets(path, [id].concat(((d && d.targets) || []).filter(t => ["keyboard", "mouse", "touchpad", "touchscreen"].indexOf(t) >= 0)));
        }
        function inputPlumberManageAll(on: bool) { InputPlumber.setManageAll(on); }
        function upsRefresh() { Ups.refresh(); }
        // the same path a tap takes (tests drive the keyboard with it)
        function oskPress(key: string) { Osk.press(key); }
        function oskTapMod(name: string) { if (name === "ctrl" || name === "alt") Osk.tapMod(name); }
        function oskLanguage() { Osk.nextLanguage(); }
        function whatsNewCheck() { WhatsNew.check(); }
        function settings() { Ui.openSettings(""); }
        function settingsCategory(cat: string) { Ui.openSettings(cat); }
        function settingsAt(cat: string, section: string) { Ui.openSettings(cat, section); }
        // settings undo: revert one or all changed settings
        function settingsChangedKeys(): string { return JSON.stringify(Settings.changedKeys); }
        function settingsUndo(key: string) { Settings.undo(key); }
        function settingsUndoAll() { Settings.undoAll(); }
        // Files split view: two panes side by side
        function filesSplit() { Files.toggleSplit(); }
        function filesSplitPath(p: string) { Files.openInSplit(p); }
        function filesSplitCopy() { Files.copyToSplit(); }
        // copy / cut / paste, undo, the trash, Properties, batch rename, bookmarks, deep search
        function filesCopy(paths: string) { Files.toClipboard("copy", paths ? paths.split("\n") : []); }
        function filesCut(paths: string) { Files.toClipboard("cut", paths ? paths.split("\n") : []); }
        function filesPaste(dest: string) { Files.pasteHere(dest); }
        function filesUndo() { Files.undo(); }
        function filesPutBack(paths: string) { Files.putBack(paths ? paths.split("\n") : []); }
        function filesEmptyTrash() { Files.emptyTrash(); }
        function filesProps(paths: string) { Files.showProps(paths ? paths.split("\n") : []); }
        function filesBatchRename(pattern: string, paths: string) { Files.batchRename(pattern, paths.split("\n")); }
        function filesBookmark(path: string, on: bool) { Files.setBookmark(path, on); }
        function filesSearchDeep(on: bool) { Files.setSearchDeep(on); }
        function filesSearch(words: string) { Files.searchText = words; }
        function filesSplitMove() { Files.moveToSplit(); }
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
        function maps() { Ui.closeAll(); Ui.maps = true; }
        function mapsRefresh() { Location.refresh(); }
        function mapsSearch(query: string) { Ui.closeAll(); Ui.maps = true; Ui.mapsQuery = query; }
        function mapsPan(dxdy: string) { Ui.mapsAsked("pan", dxdy); }
        function mapsZoomBy(d: string) { Ui.mapsAsked("zoom", d); }
        function mapsDirections(profile: string) { Ui.mapsAsked("directions", profile); }
        function mapsFrom(place: string) { Ui.mapsAsked("from", place); }
        function cameraClose() { Camera.closeCamera(); }
        function cameraShutter() { Camera.shutter(); }
        function cameraViewfinder() { Camera.openViewfinder(); }
        function cameraRefresh() { Camera.refresh(); }
        function tour() { Ui.closeAll(); Ui.tour = true; }
        function agendaRefresh() { Agenda.refresh(); }
        // which calendars show (the Calendar's chips): a name, and "true" or "false"
        function calendarShow(name: string, on: string) { Agenda.setShown(name, on !== "false"); }
        function dynamicLockAway() { DynamicLock.away(); }
        function share(path: string) { Ui.closeAll(); Share.open(path); }
        function textMessage(to: string) { Ui.closeAll(); Ui.smsTo = to; Ui.modemDialog = "sms"; }
        // Shani Link Phone / Messages (Services/Phone, the external app).
        // `phoneOpen` / `messagesOpen` take an optional number - called with
        // none, the pad/composer opens empty; called with one, it is prefilled
        // and nothing is dialled or sent until the person presses Call / Send.
        function phoneOpen(number: string) {
            Ui.closeAll();
            Ui.phonePage = "phone";
            Ui.phoneNumber = (number || "").trim();
            Phone.openDial(Ui.phoneNumber);
        }
        function messagesOpen(number: string) {
            Ui.closeAll();
            Ui.phonePage = "messages";
            Ui.phoneNumber = (number || "").trim();
            Phone.openMessages(Ui.phoneNumber);
        }
        function recentCalls() {
            Ui.closeAll();
            Ui.phonePage = "recent";
            Ui.phoneNumber = "";
            Phone.openRecentCalls();
        }
        function qr(title: string, text: string) { Ui.closeAll(); Qr.show(title, text); }
        function calculator() { const was = Calculator.shown; Ui.closeAll(); if (!was) Calculator.open(); }
        function calculatorOpen(expr: string) { Ui.closeAll(); if (expr) { Calculator.clear(); Calculator.display = expr; } Calculator.open(); }
        function calculatorPress(key: string) { Calculator.press(key); }
        function calculatorEquals() { Calculator.evaluate(); }
        function calculatorClear() { Calculator.clear(); }
        function calculatorCopy() { Calculator.copyResult(); }
        function calculatorConvert(value: string, from: string, to: string): string { const r = Calculator.convertUnit(value, from, to); return r ? r.text : ""; }
        function calculatorFinancial(op: string, a: string, b: string, c: string, d: string): string { const v = Calculator.financial(op, a, b, c, d); return v === null || v === undefined ? "" : String(v); }
        function calculatorProgramming(op: string, a: string, b: string): string { const o = String(op || "").toLowerCase(); if (o === "fromchar" || o === "charfromcode" || o === "codechar") return Calculator.codeToChar(a); if (o === "tobase") return Calculator.toBase(a, b); if (o === "frombase") { const v = Calculator.fromBase(a, b); return v === null ? "" : String(v); } if (o === "twos" || o === "twoscomplement" || o === "twos-complement") { const v = Calculator.twosComplement(a, b); return v === null ? "" : String(v); } if (o === "charcode" || o === "char" || o === "charcodeof") { const v = Calculator.charCode(a); return v === null ? "" : String(v); } const v = Calculator.programming(op, a, b); return v === null || v === undefined ? "" : String(v); }
        function calculatorRecall(idx: int) { Calculator.recallHistory(idx); }
        function calculatorMemory(op: string) { if (op === "mc") Calculator.memoryClear(); else if (op === "mr") Calculator.memoryRecall(); else if (op === "mplus") Calculator.memoryAdd(); else Calculator.memorySubtract(); }
        function calculatorHistoryClear() { Calculator.clearHistory(); }
        function notesCreateNotebook(name: string) { QuickNotes.createNotebook(name); }
        function notesRenameNotebook(oldName: string, newName: string) { QuickNotes.renameNotebook(oldName, newName); }
        function notesCreate(name: string, notebook: string) { QuickNotes.create(name, notebook); }
        function notesOpenNote(name: string, notebook: string) { QuickNotes.open(name, notebook); }
        function notesExportHtml(): string { return QuickNotes.exportHtml(); }
        function notesPrint(): string { return QuickNotes.printNote(); }
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
        // a form: show it, set a field (text, or "true"/"false" for a box), save a filled copy
        function pdfFormShow() { PdfViewer.formShown = true; }
        function pdfFormSet(name: string, value: string) { PdfViewer.setField(name, value === "true" ? true : value === "false" ? false : value); }
        function pdfFormSave() { PdfViewer.saveForm(); }
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
        // one of the suggested replies (SmartReplies), by its place on the card
        function notificationSuggestedReply(summary: string, index: int) {
            const n = Notifs.list.find(x => x.summary === summary);
            const s = n ? SmartReplies.forId(n.id) : [];
            if (n && n.hasInlineReply && s[index]) n.sendInlineReply(s[index]);
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
                windowMenu: Ui.windowMenu, appMenus: AppMenu.menus.map(m => m.label), appMenuItems: AppMenu.menus.map(m => (m.items || []).filter(i => !i.separator).map(i => i.label + (i.shortcut ? " " + i.shortcut : "") + (i.items ? " >" : ""))), appMenuLoading: AppMenu.loading, appMenuWhy: AppMenu.why, appMenuDid: AppMenu.did, windowMenuLabels: Ui.windowMenuLabels, windowPid: Niri.focusedWindow ? (Niri.focusedWindow.pid || 0) : 0,
                processes: TopProcesses.list.length,
                logs: Ui.logs,
                timerLeft: FocusTimer.left,
                weather: Weather.summary,
                notesLoaded: QuickNotes.loaded, notesCount: QuickNotes.notes.length, notesCurrent: QuickNotes.current, notesLinks: QuickNotes.links(), notesNotebooks: QuickNotes.notebooks.join(" "), notesNotebook: QuickNotes.currentNotebook, notesExported: QuickNotes.lastExported, notesPrinted: QuickNotes.lastPrinted, notesSync: QuickNotes.syncState,
                alarms: WorldClock.alarms.length, stopwatch: WorldClock.swDisplay,
                characters: Ui.characters, characterLast: Characters.last,
                forecast: Weather.forecast, hourly: Weather.hourly,
                accent: String(Theme.accent),
                bg: String(Theme.bg),
                darkFade: Theme.darkT, darkSteps: Theme.darkSteps,
                wallpaperNow: Theme.wallpaper,
                quiet: Notifs.quiet,
                fullscreen: GameMode.fullscreen,
                clipImages: Clipboard.entries.filter(e => e.image).length, smartReplies: Notifs.list.filter(n => SmartReplies.forId(n.id).length).map(n => n.summary + ': ' + SmartReplies.forId(n.id).join(' | ')), clipFromPhone: Clipboard.entries.filter(e => !e.image && Clipboard.originOf(e.text)).map(e => Clipboard.originOf(e.text) + ": " + e.text.slice(0, 40)),
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
                players: Audio.players.length, mprisPlayers: Media.players.map(p => p.identity), mprisCurrent: Media.current ? Media.current.identity : "",
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
                calculatorBase: Calculator.base, calculatorWidth: Calculator.width, calculatorFin: Calculator.finResult, calculatorProg: Calculator.progResult, calculatorBin: Calculator.progBin, calculatorOct: Calculator.progOct, calculatorDec: Calculator.progDec, calculatorHex: Calculator.progHex, calculatorTwos: Calculator.twosResult, calculatorChar: Calculator.charResult,
                calendarShown: Ui.calendar, calendarEvents: Agenda.events.length, calendarSearch: Agenda.search,
                viewerShown: Viewer.shown, viewer: Ui.viewer, viewerFile: Viewer.file, viewerZoom: Viewer.zoom, viewerRotation: Viewer.rotation,
                viewerSlideshow: Viewer.slideshow, viewerGrid: Viewer.gridMode, viewerThumbs: Viewer.showThumbs, viewerCopied: Viewer.lastCopied,
                viewerAction: Viewer.lastAction, viewerTrash: Viewer.trashLast, exifOrientation: Viewer.exifOrientation,
                pdfShown: PdfViewer.shown, pdfReader: Ui.pdfReader, pdfFile: PdfViewer.file, pdfPage: PdfViewer.page, pdfPages: PdfViewer.pageCount,
                pdfFit: PdfViewer.fitMode, pdfContinuous: PdfViewer.continuous, pdfSidebar: PdfViewer.showSidebar, pdfSearch: PdfViewer.searchText,
                pdfSearchMatches: PdfViewer.searchMatches.length, pdfOutline: PdfViewer.outline.length, pdfError: PdfViewer.error, pdfCopy: PdfViewer.pdf, pdfFormFields: PdfViewer.formFields.length, pdfFormSaved: PdfViewer.formSaved, pdfFormError: PdfViewer.formError, pdfPrint: PdfViewer.printState,
                converted: Recorder.converted, converting: Recorder.converting,
                cpuTemp: SysStats.temp,
                gpus: Gpu.gpus.length,
                agenda: Agenda.events.map(e => e.summary), calendars: Agenda.calendarNames, calendarsHidden: Agenda.hidden,
                modem: Modem.modem ? Modem.modem.state + "/" + (Modem.modem.locked || "unlocked") + "/" + Modem.modem.operator : "",
                modemCall: Modem.call ? Modem.call.state + ":" + Modem.call.number : "",
                modemDialog: Ui.modemDialog, phonePage: Ui.phonePage, phoneNumber: Ui.phoneNumber,
                dynamicLocks: DynamicLock.locks, dynamicLockDevice: DynamicLock.address,
                automationsFired: Automations.fired,
                language: Tr.lang, sampleWord: Tr.t("Notifications"),
                minimised: Niri.minimised.map(w => w.id), visibleWorkspaces: Niri.workspacesOn(Niri.focusedOutput).length,
                backupSummary: Ui.backupSummary, printersSeen: Ui.printersSeen,
                annotate: Ui.annotate, annotateStrokes: Ui.annotateStrokes,
                shareTargets: Share.targets.map(t => t.label), shareDone: Share.done,
                cameras: Camera.cameras.length, cameraPhase: Camera.phase, cameraLast: Camera.last,
                mapsShown: Ui.maps, mapsView: Ui.mapsView, mapsLat: Location.lat, mapsLon: Location.lon,
                wallpaperStyleShown: Ui.settingsOpen && Ui.settingsCat === "personal", terminalList: Terminal.listState, terminalFoot: Terminal.footState, wallpaperStyleImage: WallpaperStyle.image, wallpaperStyleNote: WallpaperStyle.note,
                wallpaperStylePalette: Object.keys(Matugen.previewPalette || {}).length,
                wallpaperStyleThemes: (Settings.data.wallpaperStyleThemes || []).length, wallpaperStyleSaved: WallpaperStyle.lastSaved,
                inputMethod: Ime.current,
                osk: Osk.shown,
                dictation: Dictation.phase,
                dictated: Dictation.last,
                oskLang: Osk.lang,
                oskTyped: Osk.typed,
                ringDepth: Ui.ringDepth,
                topResult: Ui.topResult, liveWallpaperWhy: LiveWallpaper.why, liveWallpaperPlaying: Ui.liveWallpaperPlaying, launcherFiles: Ui.launcherFiles, launcherMeaning: Ui.launcherMeaning,
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
                chronoa: Chronoa.state, chronoaOpen: Chronoa.open, quickLookShown: QuickLook.shown, tidyPlanned: Tidy.planned.length, tidyGroups: Tidy.groups.map(g => g.group + ' ' + g.count), tidyMoved: Tidy.moved, tidyNote: Tidy.note, tidyCanUndo: Tidy.canUndo, nameSuggestion: Tidy.suggestion, nameError: Tidy.namingError, naming: Tidy.naming, writingShown: WritingTools.shown, writingSource: WritingTools.source, writingFrom: WritingTools.from, writingResult: WritingTools.result, writingError: WritingTools.error, writingBusy: WritingTools.busy, quickLookKind: QuickLook.kind, quickLookText: QuickLook.text.length, quickLookPage: QuickLook.page, quickLookError: QuickLook.error, filesCurrent: Files.current, chronoaAsked: Chronoa.lastAsked.slice(0, 400), chronoaReply: Chronoa.lastReply.slice(-600),
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
                mediaPlayer: Media.current ? Media.current.identity : '', notifEarlier: Notifs.earlier.length, dndUntil: Settings.data.dndUntil, oskWritten: Osk.lastWritten, shortcutsListed: Ui.shortcutsListed, plugGreeted: Plugged.greeted, navFocus: Ui.navFocus, osdLabel: Ui.osdLabel, presenting: Plugged.presenting ? Plugged.presenting.output : '', screenReader: Settings.data.screenReader, iphoneNoteDone: Settings.data.iphoneNoteDone, promptKeyboard: Ui.promptKeyboard, hasKeyboard: InputKinds.keyboard, tabletMode: TabletMode.on, gamepadNavRunning: GamepadNav.running, gamepadLast: GamepadNav.lastAction, dockFocus: Ui.dockFocus, ipRunning: InputPlumber.running, ipManageAll: InputPlumber.manageAll, ipDevices: InputPlumber.devices.map(d => d.name + " " + InputPlumber.playsAs(d) + " " + d.intercept), ipBorrowed: InputPlumber.borrowed !== "", ipLastEvent: InputPlumber.lastEvent, oskCtrl: Osk.ctrl, oskAlt: Osk.alt, upsPresent: Ups.present, upsOnBattery: Ups.onBattery, upsLow: Ups.low, upsCharge: Ups.info.charge === undefined ? -1 : Ups.info.charge, barFocus: Ui.barFocus, controllersListed: Ui.controllersListed, padTestRunning: Ui.padTestRunning, padTestLast: Ui.padTestLast, u2fRegistered: Ui.u2fRegistered, plugLast: Plugged.last, tabletOutput: Settings.data.tabletOutput, sleepVerb: Power.sleepVerb, compassHeading: Compass.heading, onlineWalls: OnlineWalls.results.length, onlineWallSaved: OnlineWalls.lastSaved, lyricsLines: Lyrics.lines.length, trashCount: Ui.trashCount, shotCountdown: Screenshots.countdown, shelfParked: Shelf.parked, shelfItems: Shelf.items.map(x => x.name),
                layoutSwitcher: Ui.layoutSwitcher, layoutTrying: Ui.layoutTrying, layoutPreset: Settings.data.layoutPreset, dockOn: Settings.data.dock, dockHides: Settings.data.dockVisibility === "hide", dockMode: Settings.data.dockVisibility, barMode: Settings.data.barVisibility, dockShown: Hiding.dockShown[Niri.focusedOutput] !== false, dockFits: Hiding.dockFits[Niri.focusedOutput] !== false, barShown: Hiding.barShown[Niri.focusedOutput] !== false, dockHintSeen: Settings.data.dockHintSeen, desktopIconsOn: Settings.data.desktopIcons, winWidth: Settings.data.winDefaultWidth, widgets: Array.from(Settings.data.desktopWidgets),
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
                contacts: Ui.contacts,
                playerVolume: Media.current && Media.current.volumeSupported ? Math.round(Media.current.volume * 100) : -1,
                playerShuffle: Media.current ? Media.current.shuffle : false,
                playerLoop: Media.current ? Media.current.loopState : -1,
                playerPosition: Media.current ? Math.round(Media.current.position) : -1,
                playerLength: Media.current ? Math.round(Media.current.length) : -1,
                playerSeekable: Media.current ? Media.current.canSeek : false,
                callRecording: CallRecorder.recording,
                callFile: CallRecorder.file,
                cameraShown: Camera.open, notes: Ui.notes, textEditor: Ui.textEditor,
                textEditorFile: TextDocs.current ? TextDocs.current.path : "", textEditorDocs: TextDocs.docs.length, textEditorUnsaved: TextDocs.unsaved, textEditorChars: TextDocs.current ? TextDocs.current.text.length : 0, textEditorSaved: TextDocs.lastSaved, textEditorError: TextDocs.error, textEditorReadOnly: TextDocs.current ? TextDocs.current.readOnly : false,
                tasksShown: Ui.tasks, tasksOpen: Tasks.open.map(t => t.summary), tasksDone: Tasks.done.map(t => t.summary), tasksAvailable: Tasks.available, photosShown: Ui.photos, translateShown: Ui.translate, weatherShown: Ui.weather, cleanUpShown: Ui.settingsOpen && Ui.settingsCat === "storage", authenticatorShown: Ui.authenticator, converterShown: Ui.converter, nearbyShown: Ui.nearby, nearbyVisible: Nearby.visible_, nearbyDevices: Nearby.devices.map(d => d.alias), nearbyOffers: Nearby.offers.length, nearbyTransfers: Object.values(Nearby.transfers).map(t => t.direction + ":" + t.state), nearbyNote: Nearby.note, screenTimeShown: Ui.settingsOpen && Ui.settingsCat === "screentime", clocksShown: Ui.clocks, clocksTab: Ui.clocksTab,
                archiveShown: Archive.shown, archiveFile: Archive.file, archiveEntries: Archive.entries.length, archiveSize: Archive.totalSize, archiveExtractedTo: Archive.extractedTo, archiveError: Archive.error, archiveReading: Archive.reading, archiveExtracting: Archive.extracting, archivePassword: Archive.needsPassword, archiveMade: Archive.made, archiveCreating: Archive.creating,
                librarySongs: MusicLibrary.songs.length, libraryVideos: MusicLibrary.videos.length, libraryAlbums: MusicLibrary.albums.map(a => a.title), libraryScanning: MusicLibrary.scanning, mediaPage: PlayQueue.page, mediaShown: PlayQueue.shown, mediaFile: PlayQueue.current, mediaPlayerPlaying: PlayQueue.playing, mediaMini: PlayQueue.mini, mediaResumedFrom: PlayQueue.resumedFrom, mediaSubtitleFile: PlayQueue.subtitleFile, mediaCue: PlayQueue.cue, mediaAudioTracks: PlayQueue.audioTrackCount, mediaTagLine: PlayQueue.tagLine, mediaCover: PlayQueue.coverShown, mediaPinned: Niri.pinned.length, mediaPosition: Math.round(PlayQueue.position * 10) / 10, mediaDuration: Math.round(PlayQueue.duration * 10) / 10, mediaHasVideo: PlayQueue.hasVideo, mediaQueue: PlayQueue.queue.length, mediaIndex: PlayQueue.index, mediaError: PlayQueue.error, mediaVolume: PlayQueue.volume, mediaRate: PlayQueue.rate,
                scanner: Ui.scanner, passwordGenerator: Ui.passwordGenerator, kundali: Ui.kundali,
                pdfSigner: Ui.pdfSigner, pdfSignerFile: PdfSigner.file, pdfSignerName: PdfSigner.name, pdfSignerSignature: PdfSigner.signature, pdfSignerX: PdfSigner.x, pdfSignerY: PdfSigner.y, pdfSignerScale: PdfSigner.scale, pdfSignerText: PdfSigner.fillText, pdfSignerTextX: PdfSigner.textX, pdfSignerTextY: PdfSigner.textY, pdfSignerSaved: PdfSigner.pdfSignerFile, pdfSignerLastSaved: PdfSigner.lastSaved, pdfSignerSaving: PdfSigner.saving,
                disktree: Ui.diskUsage, diskUsageRoot: DiskUsage.scanRoot, diskUsageCurrent: DiskUsage.current, diskUsageEntries: DiskUsage.entries.length, diskUsageMarked: DiskUsage.markedCount, diskUsageTotal: DiskUsage.totalSize, diskUsageScanning: DiskUsage.scanning, diskUsageLast: DiskUsage.last,
                filesShown: Ui.files, filesPath: Files.path, filesSelected: Files.selected.length, filesView: Files.viewMode, filesError: Files.error, filesPlaces: Files.places.length, filesEntries: Files.entryCount, filesNote: Files.note, filesUndo: Files.undoLabel, filesProps: Files.props ? JSON.stringify(Files.props) : "", filesTrashNames: Object.keys(Files.trashItems), filesBookmarks: Files.places.filter(p => p.bookmark).map(p => p.path), filesNames: Files._paths.map(p => p.split("/").pop()),
                pickerShown: FilePicker.shown, pickerPath: FilePicker.path, pickerPicked: FilePicker.lastPicked.join(" "),
                voiceRecorder: Ui.voiceRecorder, voiceRecording: VoiceRecorder.recording, voicePaused: VoiceRecorder.paused, voiceElapsed: VoiceRecorder.elapsed, voiceFiles: VoiceRecorder.recordings.length, voiceFile: VoiceRecorder.file, voiceLast: VoiceRecorder.last, voiceLevel: Math.round(VoiceRecorder.level * 100), voiceTrimFile: VoiceRecorder.trimFile, voiceTrimStart: VoiceRecorder.trimStart, voiceTrimEnd: VoiceRecorder.trimEnd, voiceTrimmed: VoiceRecorder.trimmedLast,
                videoTrimmer: Ui.videoTrimmer, videoTrimmerInput: VideoTrimmer.input, videoTrimmerStart: VideoTrimmer.start, videoTrimmerEnd: VideoTrimmer.end, videoTrimmerDuration: VideoTrimmer.inputDuration, videoTrimmerResult: VideoTrimmer.result, videoTrimmerCutting: VideoTrimmer.cutting, videoTrimmerError: VideoTrimmer.error, videoTrimmerAvailable: VideoTrimmer.available, videoTrimmerResultDuration: VideoTrimmer.resultDuration,
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
