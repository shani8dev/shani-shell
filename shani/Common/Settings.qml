pragma Singleton
// User settings: ~/.config/shani-shell/settings.json, created on first change.
// Defaults live in the adapter below, so a missing or partial file is fine.
// The file is watched: editing it by hand applies without restarting the shell,
// and the shell's own toggles (DND, caffeine, …) write back through it.
// SHANI_SHELL_SETTINGS overrides the path (tests point it at a scratch file).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string path: Quickshell.env("SHANI_SHELL_SETTINGS")
        || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/shani-shell/settings.json")

    property alias data: adapter

    // blur behind the chrome: the toggle, minus the battery rule — a solid
    // background costs no pixels, and on battery every blurred surface is watts
    readonly property bool blurWanted: data.blur && !(data.reduceTransparencyOnBattery && PowerState.onBattery)
    property bool loaded: false
    // Our own write is not news: reloading it could undo a change made since
    // (measured: a quick on-then-off came back on). Not a time window — a late
    // notice outlived one under load — but the content: a change to the file is
    // applied only when the file differs from what we last wrote.
    property string lastWritten: ""
    // The defaults, as declared below, taken before the file is read. A key
    // missing from the file means its default: JsonAdapter on its own leaves a
    // missing key at whatever it was (measured: a file reset to {} changed
    // nothing), so an outside edit is applied as defaults + file.
    property var defaults: ({})
    Component.onCompleted: {
        const d = {};
        for (const k in adapter) {
            const v = adapter[k];
            if (typeof v === "function" || k === "objectName" || k.startsWith("__"))
                continue;
            d[k] = JSON.parse(JSON.stringify(v === undefined ? null : v));
        }
        defaults = d;
    }
    function applyOutside(text) {
        let file = {};
        try {
            file = JSON.parse(text);
        } catch (e) {
            return;            // a half-saved or broken file: keep what we have
        }
        // before visibility had three ways: an auto-hidden dock stays hidden
        if (file.dockVisibility === undefined && file.dockAutoHide === true)
            file.dockVisibility = "hide";
        for (const k of Object.keys(defaults)) {
            const v = file[k] !== undefined ? file[k] : defaults[k];
            if (JSON.stringify(adapter[k]) !== JSON.stringify(v))
                adapter[k] = v;
        }
    }

    // Write after a burst of changes settles, not once per slider tick.
    function save() {
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", root.path.substring(0, root.path.lastIndexOf("/"))]);
            view.writeAdapter();
        }
    }

    // reads the file as it is on disk, to tell our write from someone else's
    FileView {
        id: probe
        path: root.path
        printErrors: false
        onLoaded: {
            if (root.loaded && text() !== root.lastWritten)
                root.applyOutside(text());
        }
    }

    FileView {
        id: view
        path: root.path
        watchChanges: true
        atomicWrites: true                  // a crash mid-write leaves the old file, never half of one
        printErrors: false
        onSaved: root.lastWritten = text()
        onFileChanged: Qt.callLater(function() { probe.reload(); })
        // A file that does not parse (hand-edited, a disk that filled) would be
        // overwritten by the defaults at the next save, and every setting lost:
        // it is kept beside it first, and the person told where.
        onLoaded: {
            const t = text();
            try {
                if (t.trim() !== "")
                    JSON.parse(t);
            } catch (e) {
                const kept = root.path + ".unreadable-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
                Quickshell.execDetached(["sh", "-c", 'cp -- "$1" "$2" && notify-send -a Settings -i dialog-warning "Settings could not be read" "The defaults are in use. Your file was kept as $2"', "sh", root.path, kept]);
            }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true    // no file yet: defaults apply
        onAdapterUpdated: root.save()

        JsonAdapter {
            id: adapter

            property bool doNotDisturb: false
            property real dndUntil: 0         // ms since the epoch it turns itself off; 0 = until turned off
            property string dndSchedule: "manual"   // manual | custom (quiet hours)
            property string dndFrom: "22:00"
            property string dndTo: "07:00"
            property bool caffeine: false
            property string caffeineBoot: ""   // the boot it was turned on in: it doesn't outlive a restart
            property bool use24h: true
            property list<string> worldClocks: []   // other cities on the calendar: zoneinfo zones, as chosen
            property list<string> recentColors: []  // colours picked with the Color picker, newest first
            property bool blur: true
            property bool showSeconds: false
            property bool showSysStats: false             // a system monitor in the bar: one switch away, not the first thing seen
            property bool showNetSpeed: false
            property bool darkMode: true
            property bool nightLight: false
            property int nightLightTemp: 4000
            property string nightLightSchedule: "manual"   // manual | sunset (by location) | custom
            property string nightLightFrom: "21:00"
            property string nightLightTo: "07:00"
            property string weatherUnits: "celsius"       // celsius | fahrenheit (Open-Meteo)
            property string weekStartsOn: "monday"        // monday | sunday (the calendar)
            property bool weekNumbers: false
            property bool lyrics: false                   // synced lyrics on the media card, from LRCLIB (online)
            // buttons of your own in the bar: what a command prints (its last line),
            // run again every `every` seconds (0 = once); a click runs `click`
            property var barCommands: []                  // [{ command, every, click }]
            property bool screenCorners: true             // rounded screen corners (not over fullscreen windows)
            property bool batteryRefresh60: true          // the laptop's panel at 60 Hz on battery
            property bool dockTrash: true                 // the trash at the dock's end
            property string preferredPlayer: ""           // the media player followed, by its name; "" = the one playing              // ISO week numbers down the calendar's side
            property bool bluetoothOnBoot: true          // power the adapter at sign-in
            property string hotspotName: ""              // "" = <hostname>-hotspot
            property string hotspotBand: "auto"          // auto | bg | a (nmcli device wifi hotspot)
            property bool wifiMacRandom: false           // random MAC for saved Wi-Fi networks (cloned-mac-address)
            property bool wakeOnLan: false               // 802-3-ethernet.wake-on-lan=magic on saved wired networks
            property string obexDir: ""                  // "" = the XDG downloads dir
            property bool adaptiveBrightness: false
            property bool autoRotate: false
            // ShaniOS's pair (the Saturn brand art, re-encoded — see assets/make-wallpapers.py)
            property string wallpaper: "/usr/share/backgrounds/shani/shani-dark.jpg"
            property string terminal: "foot"
            property bool dock: true
            // always | smart (in view, steps aside only for a window over it - Plank's
            // and Dash-to-Dock's default) | hide (until the pointer asks)
            property string dockVisibility: "smart"
            property string barVisibility: "always"
            property bool dockHintSeen: false            // the one-time note on where a smart dock went
            property string layoutPreset: "default"
            property int dockIconSize: 48            // Plank's and the macOS dock's size; the zoom peaks at about 1.6×
            // desktop-entry ids, in order; ones not installed are skipped
            // what the image ships: Files, Vivaldi (Flatpak), the terminal, Cassini, Chronoa, Text Editor (Flatpak)
            property string reopenApps: "ask"           // at sign-in, the apps open at the last one: ask | always | never
            property list<string> dockPinned: ["org.gnome.Nautilus", "com.vivaldi.Vivaldi", "foot", "dev.shani.cassini", "shani-chronoa", "org.gnome.TextEditor"]
            property string recordingsDir: ""   // "" -> $XDG_VIDEOS_DIR or ~/Videos/Recordings

            // idle stages, seconds; 0 turns a stage off. *Battery applies on battery.
            property int dimAfter: 240
            property int dimAfterBattery: 120         // dim sooner on battery
            property int lockAfter: 300
            property int screenOffAfter: 360
            property int suspendAfter: 0
            property int lockAfterBattery: 180
            property int screenOffAfterBattery: 240
            property int suspendAfterBattery: 600
            property bool lockBeforeSuspend: true
            property bool reduceMotion: false
            property real animationSpeed: 1.0
            property bool accentFromWallpaper: true       // the accent is the wallpaper's most vivid colour, pushed to a lightness that reads on this palette — on by default: the shipped dusk wall yields an amber that is the brand's own
            // adaptive palette (matugen): a full Material You palette derived
            // from the wallpaper feeds the shell's own tones and app templates
            // (GTK, kitty, rofi…); off keeps the hue-tinted material above
            property bool adaptivePalette: false
            // matugen scheme options (wayle-inspired)
            property string matugenScheme: "tonal-spot"       // tonal-spot, vibrant, expressive, fidelity, content, monochrome, neutral, fruit-salad, rainbow
            property real matugenContrast: 0.0               // -1.0 to 1.0
            property int matugenSourceColor: 0                // 0-3
            // which apps receive the palette (only GTK is shipped in ShaniOS niri)
            property var matugenApps: []
            // hooks: user scripts on shell events (noctalia-inspired)
            property var hooks: ({ enabled: false, wallpaperChange: "", darkModeChange: "", screenLock: "", screenUnlock: "", startup: "", colorGeneration: "", notificationRules: [] })
            // notification rules: filter/mute/block notifications (noctalia-inspired)
            property var notifRules: []
            // apps' look, through org.gnome.desktop.interface (Appearance); the
            // shell uses the fonts itself, and the icon theme from its next start
            property string iconTheme: "Papirus"     // follows the style: Papirus-Dark / Papirus-Light
            property string cursorTheme: "Adwaita"
            property int cursorSize: 24
            property string uiFont: "Inter"
            property int uiFontSize: 11
            property string monoFont: "JetBrains Mono"
            // GNOME's accent names (libadwaita apps follow it too): blue teal green
            // yellow orange red pink purple slate — default is the brand amber (orange)
            property string accentName: "orange"
            property int monoFontSize: 11
            // accessibility
            property bool screenReader: false
            property bool largeText: false
            property bool highContrast: false
            property bool monoAudio: false
            // sound effects (SoundFx): a 10-band EQ in dB, bass boost, AutoEq text,
            // an impulse response, stereo width (1 = as recorded) and crossfeed
            property bool fxEnabled: false
            property bool fxSpatial: false        // matrix spatialiser (stereo widening) for headphones
            property var fxEq: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            property string fxPreset: "Flat"
            property real fxBass: 0
            property string fxAutoEq: ""
            property string fxIr: ""
            property real fxWidth: 1
            property bool fxCrossfeed: false
            property bool fxLoudness: false          // hold loudness near -16 LUFS
            property bool micNoise: false            // RNNoise on the microphone
            property string captionLanguage: "en"
            property bool flashAlerts: false
            property bool speakNotifications: false
            property string speechRate: "normal"   // slow | normal | fast, for read aloud
            property int popupSeconds: 6           // when the app does not say
            property int snoozeMinutes: 60         // how long "Snooze" holds a notification off (5/10/30/60)
            property bool dndWhileLocked: false    // hold popups while the screen is locked (critical still show)
            property bool notifHideContent: false  // privacy: hide message text; the app name is all that shows
            // per app (after Android): every app that has notified, those whose
            // pop-ups are off (they still go to the sidebar), and those that come
            // through Do Not Disturb
            property bool notifSound: true            // the freedesktop theme's message sound
            property list<string> notifApps: []
            property list<string> silentApps: []
            property list<string> dndAllowedApps: []
            property bool assistiveTouch: false
            // missing Noctalia adapter entries with existing QML bindings (subagent finding #1)
            property bool showCalendarEvents: true     // SidebarCalendar.qml line 40
            property bool bluetoothAutoConnect: true  // BtAgent.qml reconnects audio/input devices
            property string screenshotAnnotationTool: ""  // "satty" (default) | "swappy"
            // Keyboard & input: written to ~/.config/niri/shani-input.kdl (InputConfig)
            property bool tapToClick: true
            property bool typingGuard: true          // touchpad off while typing (dwt)
            property bool naturalScroll: true        // touchpad
            property real touchpadSpeed: 0
            property bool mouseNaturalScroll: false
            property real mouseSpeed: 0
            property int doubleClickSpeed: 400    // GTK double-click time, in ms
            property bool leftHanded: false
            property string tpAccel: "adaptive"       // adaptive | flat
            property real tpScroll: 0.8               // niri scroll-factor
            property string tpClick: "clickfinger"    // clickfinger | button-areas
            property string tpScrollMethod: "two-finger"   // two-finger | edge
            property bool tpOffWithMouse: false
            property bool tpMiddleEmulation: false   // both buttons together → middle click
            property bool tpDragLock: false          // keep dragging after the finger lifts
            property string tpTapButtonMap: "left-right-middle"    // left-right-middle | left-middle-right
            property bool dndEdgeViewScroll: true     // dragging a window to an edge scrolls the view
            property bool dndEdgeWorkspaceSwitch: true // dragging a window to an edge switches workspaces
            property string mouseAccel: "adaptive"
            property real mouseScroll: 1.0
            property bool numlock: true
            property bool middlePaste: true           // paste the selection with the middle button
            property int keyRepeatDelay: 400
            property int keyRepeatRate: 30
            // screens, by connector: { mode, scale, transform, x, y, vrr, off } (Displays)
            property var displays: ({})
            property string kbCompose: ""            // xkb: "" | ralt | rwin | menu | caps
            property string kbCaps: ""               // xkb: "" | ctrl:nocaps | caps:escape | caps:backspace
            // your own shortcuts: [{ key: "Mod+Alt+T", title, command }]
            property var customBinds: []
            // windows (niri layout)
            property int winGaps: 12
            property int winFocusRing: 2
            property real winDefaultWidth: 0.5
            property bool winFocusFollowsMouse: false   // click to focus, as on every other desktop (the Tiling layout turns it on)
            property bool winAnimations: true
            property var windowRules: []           // [{ app, float, workspace, width }] — per-app, niri window-rules
            property string screenshotDir: "~/Pictures/Screenshots"
            // screenshot output format/quality (subagent finding #2 — missing adapter entries)
            property string screenshotFormat: "png"        // niri's format: png | jpeg; webp also affects the drawing tool
            property int screenshotQuality: 95             // 1-100 percent (jpeg/webp only)
            property bool screenshotCopyImage: true        // copy the captured picture to the clipboard automatically
            property string clipboardOutputFormat: "png"  // clipboard copy format: "" = the file's format; png | jpeg | webp
            property bool rememberRecent: true
            property bool lockPreviews: false         // notification titles on the lock screen
            property bool lockScreenClock: true       // the clock on the lock screen
            property bool lockScreenDate: true        // the date under the clock
            property bool lockScreenBlur: true        // blur the wallpaper on the lock screen
            property bool lockScreenMedia: true       // the now-playing controls on the lock screen
            property bool lockScreenBattery: true     // battery percentage on the lock screen
            property list<string> clipPins: []          // pinned clipboard texts
            property string tabletOutput: ""              // the screen a drawing tablet maps to ("" all)
            property bool tabletLeftHanded: false
            property string touchOutput: ""               // the screen a touchscreen maps to
            property string fxCompress: "off"             // "off" | "gentle" | "night" (SoundFx, swh-plugins SC4)
            property int breakEveryMinutes: 0             // a break reminder after this long at the screen (0 off)
            property int screenLimitMinutes: 0            // a daily screen-time reminder (0 off)
            property bool machineTranslate: false         // the shell's missing words by the local model (Common/Tr); opt-in
            property var automations: []                // [{ when, is, then, arg, on }] (Services/Automations)
            property string dynamicLockDevice: ""     // a paired device's address: lock when it goes (DynamicLock)
            property string proxyMode: "none"         // none | manual | auto
            property string proxyHttp: ""             // host:port
            property string proxyHttps: ""
            property string proxySocks: ""
            property string proxyPac: ""
            property int batteryLimit: 100            // last chosen charge limit; compared with the battery's at startup
            property bool systemSounds: true
            property bool soundVolumeChange: true
            property bool soundScreenshot: true
            property bool soundNotification: true
            property bool barBatteryPercent: true
            property string popupPosition: "top-right"  // top-right | top-center | bottom-right
            property bool islandActivities: true       // timers, music, recordings in the Island
            property string slideshowDir: ""           // "" = no slideshow
            property int slideshowMinutes: 30
            property bool slideshowShuffle: false      // shuffle order (wayle-inspired)
            property string themingMonitor: ""         // which monitor's wallpaper drives color extraction; "" = first available
            property bool wallpaperPerMonitor: false    // per-monitor wallpapers (wayle-inspired)
            property var wallpapersByMonitor: ({})      // monitor name -> wallpaper path (wayle-inspired)
            // desktop widgets (Background/DesktopWidgets): which cards float on the
            // wallpaper — clock, media, weather, stats — and where each was dragged
            property bool desktopIcons: false           // the Desktop folder's files on the desktop (nothing while it is empty)
            property var deskIconPos: ({})             // { key: { x, y } } where each was put
            property bool deskStacks: false            // pile the desktop's files by kind (macOS's stacks)
            property list<string> desktopWidgets: ["clock"]
            property var deskPos: ({})
            property bool overAmplify: false          // volume up to 150 %
            property int audioBalance: 0               // left/right, −100 … 100 (Audio)
            property bool reduceTransparency: false    // the chrome opaque (Accessibility)
            property bool reduceTransparencyOnBattery: false  // …and make it opaque while on battery (glass is pixel-heavy)
            // the launcher (Settings > Search)
            property bool searchFiles: true           // file names
            property bool searchInside: true          // inside documents
            property bool searchProviders: true       // apps' own results
            property bool searchCalc: true            // sums, units, currency
            property list<string> searchFolders: ["~"]
            // launcher interaction and display options (borrow from Noctalia)
            property bool launcherIgnoreMouse: false     // ignore pointer hover/input in launcher
            property bool launcherHideNavLabels: false   // hide navigation label hints
            property bool hideVolumeGlyph: false       // hide volume widget glyph
            property bool hideBrightnessGlyph: false  // hide brightness widget glyph
            property bool barClickThrough: true      // click through unused bar space
            property string webSearch: "duckduckgo"   // duckduckgo | google | startpage | bing | ecosia
            property int volumeStep: 5                // per key press, in %
            property bool barDate: true
            property bool showScrollbars: false        // false: overlay scrollbars that appear on use
            property string darkSchedule: "manual"     // manual | sunset | custom
            property string darkFrom: "19:00"
            property string darkTo: "07:00"
            property bool tourSeen: false             // the first-login tour (Tour)
            property var appLaunch: ({})               // per-app launch options: { id: { gpu, env, args } } (Services/Launch)
            property int launcherOpens: 0              // how often the launcher was opened (the start hints retire at 5)
            property bool startHintsDone: false        // the empty-workspace hints, dismissed
            property string recordArea: "screen"     // screen | region
            property string recordSound: "none"      // none | desktop | mic          // volume click, screenshot shutter
            property int recordFps: 0                // 0 = what the compositor does; 30 | 60 locks wf-recorder's -r
            property string recordCodec: ""          // "" = wf-recorder's default (libx264); h264 | hevc | vp9 | av1
            property int trashDays: 0                 // empty trash older than this; 0 = never
            property list<string> kbLayouts: []      // xkb "layout" or "layout+variant"; [] = the system's (localectl)
            property string kbSwitch: "grp:alt_shift_toggle"   // Super+Space is the launcher
            property string kbdBacklight: "auto"       // auto | on | off (keyboard backlight)
            property int kbdBacklightLevel: 0          // 0 = full; 1/2/3 = dimmer (when "on")
            property real touchX: 24
            property real touchY: 420
            // day/night wallpaper: used with the light / dark style when set
            property string wallpaperLight: "/usr/share/backgrounds/shani/shani-light.jpg"
            property string wallpaperDark: "/usr/share/backgrounds/shani/shani-dark.jpg"
            // hold notifications while the screen is shared, and while
            // something is fullscreen (a game also gets the performance profile)
            property bool quietWhileSharing: true
            // the sidebar's tiles: their order, and the ones put away
            property list<string> tileOrder: []
            // a calm default: the everyday tiles; "All tiles" in the control centre shows the rest
            // the first page keeps what people reach for daily (Wi-Fi, Bluetooth, Do Not Disturb,
            // night light, dark style, power, screenshots, focus); the tools wait under "All tiles"
            property list<string> hiddenTiles: ["ruler", "snippets", "compress", "qrgen", "vpn", "hotspot", "phone", "timer", "camera", "photo", "lens", "colorpicker", "rotate", "flashlight", "display", "osk", "keyboard", "clipboard", "backup", "access", "captions", "transcribe", "speak", "magnifier", "callrecord", "cast", "touch", "chronoa", "kbdbacklight"]
            property bool quietWhileFullscreen: true
            // weather: off unless a city is set — it asks open-meteo.com, which sees the location
            property string weatherCity: ""
            property real weatherLat: 0
            property real weatherLon: 0
            property bool useLocation: false   // ask GeoClue2 where the computer is
            // hot corners: overview | launcher | sidebar | chronoa | lock | none
            property string hotCornerTopLeft: "overview"
            property string hotCornerTopRight: "none"
            property string hotCornerBottomLeft: "none"
            property string hotCornerBottomRight: "none"
            property bool hotCornersInFullscreen: false  // corners also over a fullscreen window
            // focus modes: notifications held back except from `allow` (app
            // names), optional caffeine / night light, optional schedule
            // (days: 0 = Sunday … 6; from/to "HH:MM", to may pass midnight)
            property var focusModes: [
                { name: "Work", icon: "x-office-document", allow: [], caffeine: false, nightLight: false,
                  schedule: { days: [1, 2, 3, 4, 5], from: "09:30", to: "18:00", on: false } },
                { name: "Sleep", icon: "weather-clear-night", allow: [], caffeine: false, nightLight: true,
                  schedule: { days: [0, 1, 2, 3, 4, 5, 6], from: "22:30", to: "07:00", on: false } },
                { name: "Personal", icon: "face-smile-big", allow: [], caffeine: false, nightLight: false,
                  schedule: { days: [], from: "", to: "", on: false } }
            ]
            property string focusMode: ""       // chosen by hand; "" = schedules decide
            property bool autoPowerSaver: true  // power saver at (powerSaverAt) % on battery
            property int powerSaverAt: 20       // battery saver kicks in at this charge level
            property bool autoLockOnLowBattery: true  // lock the screen when the battery is critically low
            property bool screenTime: true
            // screen keyboard languages, in the order the globe key cycles them
            property list<string> oskLanguages: ["en", "mr"]
            // scratchpads: quick hide/show apps
            // drop-down apps, one key away (Services/Scratchpads; Mod+` toggles "terminal")
            property var scratchPads: [{ name: "terminal", command: "foot --app-id=shani-pad-terminal", appId: "shani-pad-terminal" }]
            // screen saver settings (Android TV style)
            property int screenSaverMinutes: 3          // a clock after this much idle, before the dim (4) and the lock (5)
            property bool screenSaverEnabled: false
            property string screenSaverStyle: "clock"    // clock | photos (the Pictures folder)
            // web apps: [{ name, url, icon, title }]
            // web apps: [{ name, url, icon, title }]
            property var webApps: []
            // UI
            property int cornerRadius: 16
            property int cornerRadiusSmall: 10
        }
    }
}
