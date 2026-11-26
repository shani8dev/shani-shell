// Settings > search: find a *setting*, not just a category. Every entry names
// the key in ~/.config/shani-shell/settings.json, the category it lives in,
// what a person might type to find it, and a one-line hint. The sidebar's
// reset-this-section counts the same keys (scalar values only — arrays and
// objects stay untouched, so a customised setup is never destroyed).
.import "../../Common/Tools.js" as Tools
.pragma library

// Tools.list owns these nine rows' label, op (the deep link) and order. Only the
// settings-side key, category and hint stay here; the words are the catalog's
// search words without the launcher's leading "tool" operator.
var toolMeta = {
    dictionary: { key: "appDictionary", cat: "apps", hint: "look a word up offline; dictionary and thesaurus" },
    podcasts: { key: "appPodcasts", cat: "sound", hint: "subscribe to podcasts and listen" },
    teleprompter: { key: "appTeleprompter", cat: "apps", hint: "scroll a script while you speak" },
    netTools: { key: "appNetTools", cat: "network", hint: "ping, DNS, whois and a LAN scan" },
    databaseBrowser: { key: "appDatabaseBrowser", cat: "apps", hint: "browse and query SQLite files" },
    nearby: { key: "appNearby", cat: "sharing", hint: "send files to devices nearby; copy a device's address or show it as a QR" },
    pasteHistory: { key: "appPasteHistory", cat: "apps", hint: "clipboard slots, favourites and search" },
    // startupManager and scheduled are Settings pages (rows: startupApps, automations)
};

var entries = [
    // ---- Personalisation (wallpaper, look, bar & dock, tiles, hot corners, weather)
    { key: "wallpaper", label: "Wallpaper", cat: "personal", hint: "the picture behind everything", words: "wallpaper background desktop picture image lock screen photo" },
    { key: "wallpaperLight", label: "Light wallpaper", cat: "personal", hint: "used in light mode", words: "wallpaper light day" },
    { key: "wallpaperDark", label: "Dark wallpaper", cat: "personal", hint: "used in dark mode", words: "wallpaper dark night" },
    { key: "accentFromWallpaper", label: "Accent from wallpaper", cat: "personal", hint: "the wallpaper's most vivid colour becomes the accent", words: "accent colour color wallpaper dynamic" },
    { key: "accentName", label: "Accent colour", cat: "personal", hint: "the tint used across the desktop", words: "accent colour color orange teal blue green purple red pink slate yellow" },
    { key: "darkMode", label: "Dark mode", cat: "personal", hint: "the whole desktop in dark", words: "dark light mode theme style" },
    { key: "darkSchedule", label: "Dark style schedule", cat: "personal", hint: "switch light/dark on a time", words: "dark light schedule automatic sunset sunrise night" },
    { key: "darkFrom", label: "Dark style from", cat: "personal", hint: "start of the dark period", words: "dark schedule from start time" },
    { key: "darkTo", label: "Dark style until", cat: "personal", hint: "end of the dark period", words: "dark schedule until end time" },
    { key: "blur", label: "Blur behind panels", cat: "personal", hint: "translucency; the glass look", words: "blur translucency transparency glass background" },
    { key: "iconTheme", label: "Icons", cat: "personal", hint: "the icon theme apps use", words: "icon theme papirus yaru adwaita" },
    { key: "cursorTheme", label: "Cursor", cat: "personal", hint: "the mouse pointer set", words: "cursor pointer mouse theme" },
    { key: "cursorSize", label: "Cursor size", cat: "personal", hint: "bigger pointer for the far screen", words: "cursor pointer mouse size large" },
    { key: "uiFont", label: "Interface font", cat: "personal", hint: "the font the desktop uses", words: "font interface ui text" },
    { key: "uiFontSize", label: "Interface font size", cat: "personal", hint: "all labels, menus and buttons", words: "font size interface text" },
    { key: "monoFont", label: "Monospace font", cat: "personal", hint: "the font for code and the terminal", words: "font mono monospace code terminal" },
    { key: "monoFontSize", label: "Monospace font size", cat: "personal", hint: "code, snippets and the terminal", words: "font size mono code" },
    { key: "cornerRadius", label: "Corner radius", cat: "personal", hint: "how round every corner is", words: "corner radius round edges rounded" },
    { key: "cornerRadiusSmall", label: "Small corners", cat: "personal", hint: "radius for small controls", words: "corner radius small buttons" },
    { key: "showScrollbars", label: "Always show scrollbars", cat: "personal", hint: "on: scrollbars always visible", words: "scrollbar scroll visible hide overlay" },
    { key: "reduceMotion", label: "Reduce motion", cat: "personal", hint: "no sliding or zooming animations", words: "motion animation reduce accessibility" },
    { key: "animationSpeed", label: "Interface animation speed", cat: "access", hint: "0.5 slower, 2 fastest", words: "animation speed motion interface faster slower" },
    { key: "dock", label: "Show the dock", cat: "personal", hint: "the icons along the bottom", words: "dock icons bottom bar" },
    { key: "dockVisibility", label: "When the dock shows", cat: "personal", hint: "always, out of a window's way, or only at the edge", words: "dock hide auto hidden reveal intelligent intellihide smart dodge windows" },
    { key: "barVisibility", label: "When the bar shows", cat: "personal", hint: "always, out of a window's way, or only at the edge", words: "bar panel top hide auto hidden reveal intelligent smart" },
    { key: "leftRail", label: "Left workspace rail", cat: "personal", hint: "your workspaces down the left edge; off puts them in the dock", words: "left rail workspace strip edge sidebar" },
    { key: "barApps", label: "Your apps in the bar", cat: "personal", hint: "a taskbar: after the apps button or in the middle", words: "taskbar apps bar windows 7 10 11 start middle center pinned running" },
    { key: "barSearch", label: "A box to ask or search in the bar", cat: "personal", hint: "it opens search, which asks Chronoa what it cannot find", words: "search box cortana ask taskbar bar" },
    { key: "railContent", label: "The left rail shows", cat: "personal", hint: "your workspaces, or your apps as a launcher", words: "rail launcher unity left apps workspaces" },
    { key: "navButtons", label: "Back and keyboard buttons", cat: "personal", hint: "in the dock on a touch screen, which has no keys", words: "navigation bar buttons back home recents keyboard touch tablet phone board nav" },
    { key: "edgeSwipes", label: "Edge swipes", cat: "personal", hint: "swipe a screen's edges on a touch device", words: "edge swipe gesture touch tablet phone launcher overview back" },
    { key: "dockIconSize", label: "Dock icon size", cat: "personal", hint: "the icons in the dock", words: "dock icon size icons" },
    { key: "dockPinned", label: "Dock pins", cat: "personal", hint: "which apps live in the dock", words: "dock pin apps favourites" },
    { key: "layoutPreset", label: "Layout preset", cat: "personal", hint: "a whole arrangement in one choice", words: "layout preset arrangement" },
    { key: "tileOrder", label: "Quick tile order", cat: "personal", hint: "the order of the control centre tiles", words: "tile order quick rearrange" },
    { key: "hiddenTiles", label: "Hidden quick tiles", cat: "personal", hint: "tiles kept out of the control centre", words: "tile hidden quick hide" },
    { key: "desktopWidgets", label: "Desktop widgets", cat: "personal", hint: "clock, media and weather on the wallpaper", words: "widget desktop clock weather stats media" },
    { key: "slideshowDir", label: "Wallpaper slideshow folder", cat: "personal", hint: "a folder of pictures to cycle", words: "slideshow wallpaper folder directory rotate" },
    { key: "slideshowMinutes", label: "Slideshow interval", cat: "personal", hint: "minutes between pictures", words: "slideshow interval minutes every" },
    { key: "showSysStats", label: "System monitor in the bar", cat: "personal", hint: "CPU and memory in one glance", words: "sys stats monitor cpu memory bar" },
    { key: "showNetSpeed", label: "Network speed in the bar", cat: "personal", hint: "download/upload rate in the bar", words: "network speed net traffic mbps bar" },
    { key: "barBatteryPercent", label: "Battery percentage in the bar", cat: "personal", hint: "the number next to the battery icon", words: "battery percent percentage bar" },
    { key: "barDate", label: "Date in the bar", cat: "personal", hint: "the date next to the clock", words: "date bar calendar" },
    { key: "hideVolumeGlyph", label: "Hide volume icon", cat: "personal", hint: "the speaker in the bar", words: "volume icon glyph hide bar mute" },
    { key: "hideBrightnessGlyph", label: "Hide brightness icon", cat: "personal", hint: "the sun in the bar", words: "brightness icon glyph hide bar" },
    { key: "barClickThrough", label: "Click through the bar", cat: "personal", hint: "clicks land on the window, not the bar", words: "bar click through click-through pointer" },
    { key: "hotCornerTopLeft", label: "Top-left hot corner", cat: "personal", hint: "what the top-left corner does", words: "hot corner top left overview" },
    { key: "hotCornerTopRight", label: "Top-right hot corner", cat: "personal", hint: "what the top-right corner does", words: "hot corner top right" },
    { key: "hotCornerBottomLeft", label: "Bottom-left hot corner", cat: "personal", hint: "what the bottom-left corner does", words: "hot corner bottom left" },
    { key: "hotCornerBottomRight", label: "Bottom-right hot corner", cat: "personal", hint: "what the bottom-right corner does", words: "hot corner bottom right" },
    { key: "hotCornersInFullscreen", label: "Hot corners in fullscreen", cat: "personal", hint: "also active over a fullscreen window", words: "hot corner fullscreen game" },
    { key: "weatherCity", label: "Weather city", cat: "personal", hint: "where the forecast comes from", words: "weather city forecast location" },
    { key: "weatherLat", label: "Weather latitude", cat: "personal", hint: "exact position, from location or typed", words: "weather latitude location geography" },
    { key: "weatherLon", label: "Weather longitude", cat: "personal", hint: "exact position, from location or typed", words: "weather longitude location geography" },
    { key: "useLocation", label: "Use my location for weather", cat: "personal", hint: "GeoClue2; no city has to be typed", words: "weather location geoclue location automatic" },
    { key: "weatherUnits", label: "Temperature units", cat: "personal", hint: "celsius or fahrenheit", words: "weather temperature units celsius fahrenheit degrees" },

    // ---- Notifications
    { key: "doNotDisturb", label: "Do not disturb", cat: "notifications", hint: "nothing pops up; critical still does", words: "do not disturb dnd quiet focus silence" },
    { key: "dndSchedule", label: "Do not disturb schedule", cat: "notifications", hint: "quiet hours, chosen times", words: "do not disturb schedule quiet hours from to" },
    { key: "dndFrom", label: "Quiet hours from", cat: "notifications", hint: "when quiet hours begin", words: "do not disturb from schedule start" },
    { key: "dndTo", label: "Quiet hours until", cat: "notifications", hint: "when quiet hours end", words: "do not disturb until schedule end" },
    { key: "dndWhileLocked", label: "Quiet while locked", cat: "notifications", hint: "no popups on the lock screen", words: "do not disturb locked screen lock quiet" },
    { key: "smartReplies", label: "Suggested replies", cat: "notifications", hint: "Chronoa writes three answers for a message", words: "smart replies suggested reply quick answer message chronoa notification" },
    { key: "notifHideContent", label: "Hide message content", cat: "notifications", hint: "the app is named; the message is not", words: "notification privacy hide content preview private" },
    { key: "notifSound", label: "Notification sounds", cat: "notifications", hint: "a chime for each pop-up", words: "notification sound chime ping alert" },
    { key: "popupSeconds", label: "Pop-up duration", cat: "notifications", hint: "how long a banner stays up", words: "notification popup duration seconds timeout banner" },
    { key: "popupPosition", label: "Pop-up position", cat: "notifications", hint: "where banners appear", words: "notification popup position corner banner" },
    { key: "silentApps", label: "Silent apps", cat: "notifications", hint: "these go to the sidebar without popping", words: "notification silent mute app" },
    { key: "dndAllowedApps", label: "Allowed during Do not disturb", cat: "notifications", hint: "these come through anyway", words: "notification allow dnd through app" },
    { key: "notifApps", label: "Notifying apps", cat: "notifications", hint: "apps that have notified", words: "notification apps list" },
    { key: "quietWhileSharing", label: "Quiet while sharing the screen", cat: "notifications", hint: "nothing leaks into a call", words: "notification quiet screen share presenting call" },
    { key: "quietWhileFullscreen", label: "Quiet in fullscreen", cat: "notifications", hint: "a game never gets banners", words: "notification quiet fullscreen game" },
    { key: "focusModes", label: "Focus modes", cat: "notifications", hint: "Work, Sleep, Personal — with schedules", words: "focus modes work sleep personal" },
    { key: "focusMode", label: "Focus mode", cat: "notifications", hint: "which mode is on by hand", words: "focus mode work sleep personal" },

    // ---- Network
    { key: "hotspotName", label: "Hotspot name", cat: "network", hint: "what the hotspot calls itself", words: "hotspot name wifi ssid ap tethering" },
    { key: "hotspotBand", label: "Hotspot band", cat: "network", hint: "automatic, 2.4 or 5 GHz", words: "hotspot band 2.4 ghz 5 wifi tethering" },
    { key: "wifiMacRandom", label: "Random MAC on Wi-Fi", cat: "network", hint: "a different address for each saved network", words: "wifi mac address random privacy cloned track" },
    { key: "wakeOnLan", label: "Wake on LAN", cat: "network", hint: "magic packets wake a wired computer", words: "wake on lan wol magic packet wired" },
    { key: "bluetoothOnBoot", label: "Bluetooth at sign-in", cat: "network", hint: "power the adapter when you log in", words: "bluetooth sign in boot on startup" },
    { key: "obexDir", label: "Bluetooth files folder", cat: "network", hint: "where received files go (default: Downloads)", words: "bluetooth files received folder obex downloads" },
    { key: "proxyMode", label: "Proxy", cat: "network", hint: "none, manual or auto", words: "proxy http https socks pac auto manual internet" },
    { key: "proxyHttp", label: "HTTP proxy", cat: "network", hint: "host:port for web traffic", words: "proxy http host port network" },
    { key: "proxyHttps", label: "HTTPS proxy", cat: "network", hint: "host:port for secure web traffic", words: "proxy https host port network" },
    { key: "proxySocks", label: "SOCKS proxy", cat: "network", hint: "a SOCKS5 endpoint", words: "proxy socks host port network" },
    { key: "proxyPac", label: "PAC file", cat: "network", hint: "scripted proxy rules", words: "proxy pac file script network" },
    { key: "bluetoothAutoConnect", label: "Bluetooth auto-connect", cat: "network", hint: "headphones and keyboards reconnect", words: "bluetooth auto connect device paired headphones" },

    // ---- Displays
    { key: "autoRotate", label: "Auto-rotate the screen", cat: "displays", hint: "following the accelerometer", words: "rotate rotation auto orient tablet convertible" },
    { key: "displays", label: "Displays", cat: "displays", hint: "the screens, their layout and resolution", words: "displays screens monitor resolution arrange layout vrr scale form factor kind of screen tablet mode phone tv handheld laptop shell size" },
    // These six live in Personalisation's own page (SettingsPage), not in
    // SettingsDisplays: search must land where the control actually is.
    { key: "adaptiveBrightness", label: "Adaptive brightness", cat: "personal", hint: "the ambient sensor drives the backlight", words: "brightness adaptive ambient sensor auto" },
    { key: "nightLight", label: "Night light", cat: "personal", hint: "warm colour after dusk", words: "night light warm filter blue eye strain" },
    { key: "nightLightTemp", label: "Night light temperature", cat: "personal", hint: "how warm, in kelvin", words: "night light temperature kelvin warmth" },
    { key: "nightLightFrom", label: "Night light from", cat: "personal", hint: "start of the warm period", words: "night light from schedule start" },
    { key: "nightLightTo", label: "Night light until", cat: "personal", hint: "end of the warm period", words: "night light until schedule end" },
    { key: "nightLightSchedule", label: "Night light schedule", cat: "personal", hint: "by sunset, or by the clock", words: "night light schedule sunset hours custom" },

    // ---- Windows
    { key: "winGaps", label: "Window gaps", cat: "windows", hint: "the space between tiles", words: "gap gaps windows tiling layout" },
    { key: "winFocusRing", label: "Focus ring", cat: "windows", hint: "the outline of the focused window", words: "focus ring outline window" },
    { key: "winDefaultWidth", label: "Default window width", cat: "windows", hint: "how wide a new window opens", words: "window width default column" },
    { key: "winFocusFollowsMouse", label: "Focus follows the mouse", cat: "windows", hint: "the window under the pointer takes focus", words: "focus follows mouse pointer hover" },
    { key: "winAnimations", label: "Window animations", cat: "windows", hint: "sliding and resizing", words: "window animations animation motion" },
    { key: "winMotion", label: "Windows open and close", cat: "windows", hint: "Glide, Pop, Dissolve or Plain", words: "window open close animation effect glide pop dissolve shader motion" },
    { key: "winSpeed", label: "Animation speed", cat: "windows", hint: "brisk, normal or relaxed", words: "animation speed fast slow slowdown motion" },
    { key: "winShadow", label: "Window shadow", cat: "windows", hint: "none, soft or deep", words: "shadow depth window drop shadow" },
    { key: "winCorners", label: "Window corners", cat: "windows", hint: "square to round", words: "corners rounded radius round square window" },
    { key: "blurStrength", label: "Frosted glass", cat: "windows", hint: "how strong the blur behind the panels is", words: "blur frosted glass transparency translucent effect" },
    { key: "windowRules", label: "Per-app rules", cat: "windows", hint: "open an app floating or on a workspace", words: "window rules per app floating workspace" },

    // ---- Sound
    { key: "fxEnabled", label: "Sound effects", cat: "sound", hint: "the equaliser and friends", words: "sound effects eq equalizer audio" },
    { key: "fxPreset", label: "EQ preset", cat: "sound", hint: "a curve to start from", words: "equalizer preset eq bass" },
    { key: "fxBass", label: "Bass boost", cat: "sound", hint: "low end, pushed", words: "bass boost sound equalizer" },
    { key: "fxSpatial", label: "Stereo widening", cat: "sound", hint: "a wider stage for headphones", words: "spatial stereo widening headphones soundstage" },
    { key: "fxWidth", label: "Stereo width", cat: "sound", hint: "1 is as recorded", words: "stereo width soundstage sound" },
    { key: "fxCrossfeed", label: "Crossfeed", cat: "sound", hint: "headphones that sound like speakers", words: "crossfeed headphones speaker" },
    { key: "fxLoudness", label: "Loudness", cat: "sound", hint: "keep volume near -16 LUFS", words: "loudness levelling volume sound" },
    { key: "fxCompress", label: "Compressor", cat: "sound", hint: "gentle, or night mode", words: "compressor night gentle sound level" },
    { key: "fxAutoEq", label: "Headphone correction", cat: "sound", hint: "AutoEq for your headphones", words: "autoeq headphone correction sound" },
    { key: "fxIr", label: "Room/impulse response", cat: "sound", hint: "the sound of a measured space", words: "impulse response room ir convolver" },
    { key: "fxEq", label: "Equaliser", cat: "sound", hint: "ten bands, dB each", words: "equalizer eq bands sound" },
    { key: "micNoise", label: "Noise suppression", cat: "sound", hint: "RNNoise on the microphone", words: "noise suppression microphone rnnoise mic call" },
    { key: "overAmplify", label: "Volume up to 150 %", cat: "sound", hint: "beyond 100, for quiet apps", words: "volume overamplify 150 amplify sound" },
    { key: "audioBalance", label: "Audio balance", cat: "sound", hint: "left into right, or the middle", words: "audio balance left right sound" },
    { key: "systemSounds", label: "System sounds", cat: "sound", hint: "the chimes and clicks", words: "system sounds chime click audio" },
    { key: "soundVolumeChange", label: "Volume change sound", cat: "sound", hint: "a click when the volume changes", words: "volume sound click change" },
    { key: "soundScreenshot", label: "Screenshot shutter", cat: "sound", hint: "a shutter for every screenshot", words: "screenshot shutter sound camera" },
    { key: "soundNotification", label: "Notification chime", cat: "sound", hint: "the freedesktop message sound", words: "notification chime sound message" },
    { key: "volumeStep", label: "Volume step", cat: "sound", hint: "how much each key press changes it", words: "volume step key press sound" },

    // ---- Accessibility
    { key: "screenReader", label: "Screen reader", cat: "access", hint: "Orca, for reading the screen", words: "screen reader orca accessibility voice" },
    { key: "largeText", label: "Large text", cat: "access", hint: "every label, bigger", words: "large text big font accessibility" },
    { key: "highContrast", label: "High contrast", cat: "access", hint: "strong colours, harder edges", words: "high contrast accessibility" },
    { key: "monoAudio", label: "Mono audio", cat: "access", hint: "both ears get the same mix", words: "mono audio accessibility hearing" },
    { key: "flashAlerts", label: "Flash for alerts", cat: "access", hint: "the screen edge flashes on a notification", words: "flash alerts screen edge notification accessibility" },
    { key: "speakNotifications", label: "Speak notifications", cat: "access", hint: "the app and title, read aloud", words: "speak notifications read aloud voice accessibility" },
    { key: "speechRate", label: "Speech rate", cat: "access", hint: "slow, normal, fast", words: "speech rate speed voice reading accessibility" },
    { key: "captionLanguage", label: "Captions language", cat: "access", hint: "the language of live captions", words: "captions transcribe language accessibility" },
    { key: "sttBackend", label: "Voice typing engine", cat: "access", hint: "Chronoa, or whisper on its own", words: "voice typing dictation engine whisper chronoa speech input" },
    { key: "whisperModel", label: "Whisper model", cat: "access", hint: "the local model used when Whisper does the typing", words: "whisper model ggml voice typing dictation speech stt" },
    { key: "compassEnabled", label: "Compass", cat: "access", hint: "the heading tile, where a magnetometer is", words: "compass heading north direction magnetometer tile" },
    { key: "tourEnabled", label: "First-login tour", cat: "access", hint: "the walkthrough shown at first sign-in", words: "tour walkthrough onboarding first login" },
    { key: "assistiveTouch", label: "Smart touch", cat: "access", hint: "a floating bubble that opens the Ring", words: "smart touch assistive touch bubble ring accessibility touchscreen" },
    { key: "touchX", label: "Smart touch position X", cat: "access", hint: "how far across the screen the bubble sits", words: "smart touch bubble position x horizontal accessibility" },
    { key: "touchY", label: "Smart touch position Y", cat: "access", hint: "how far down the screen the bubble sits", words: "smart touch bubble position y vertical accessibility" },
    { key: "reduceTransparency", label: "Reduce transparency", cat: "access", hint: "opaque panels, no glass", words: "reduce transparency opaque accessibility" },
    { key: "reduceTransparencyOnBattery", label: "Opaque panels on battery", cat: "access", hint: "glass is pixels; on battery, none", words: "battery opaque reduce transparency blur accessibility" },

    // ---- Keyboard & input
    { key: "kbLayouts", label: "Keyboard layouts", cat: "input", hint: "the layouts Switch (Ctrl+Space) cycles", words: "keyboard layout language input" },
    { key: "kbSwitch", label: "Layout switch shortcut", cat: "input", hint: "the key that switches layouts", words: "keyboard layout switch shortcut ctrl space" },
    { key: "customBinds", label: "Your own shortcuts", cat: "input", hint: "shortcuts you made for yourself", words: "custom shortcuts keys binds keybindings keyboard own" },
    { key: "kbCompose", label: "Compose key", cat: "input", hint: "a key for accents and symbols", words: "compose key keyboard accents" },
    { key: "kbCaps", label: "Caps Lock behaviour", cat: "input", hint: "no caps, escape, or backspace", words: "caps lock keyboard escape backspace" },
    { key: "numlock", label: "Num lock on start", cat: "input", hint: "numbers always on", words: "numlock num lock keyboard" },
    { key: "doubleClickSpeed", label: "Double-click speed", cat: "input", hint: "slow, normal, fast, fastest", words: "double click speed mouse gtk" },
    { key: "keyRepeatDelay", label: "Key repeat delay", cat: "input", hint: "how long before a held key repeats", words: "key repeat delay keyboard hold" },
    { key: "keyRepeatRate", label: "Key repeat rate", cat: "input", hint: "how fast it repeats", words: "key repeat rate keyboard speed" },
    { key: "oskButton", label: "Keyboard button when hidden", cat: "input", hint: "brings the screen keyboard back on a touchscreen", words: "screen keyboard osk button hidden touch tablet floating" },
    { key: "oskLanguages", label: "Screen keyboard languages", cat: "input", hint: "the languages the globe key cycles", words: "osk languages screen keyboard dictation layout globe input" },
    { key: "middlePaste", label: "Middle-click pastes", cat: "input", hint: "the text last selected, with the middle button", words: "middle click paste selection primary clipboard x11" },
    { key: "oskWithTabletMode", label: "Screen keyboard in tablet mode", cat: "input", hint: "folded: it comes up; unfolded: it goes", words: "tablet mode convertible fold screen keyboard osk" },
    { key: "gamepadNav", label: "Move around with a controller", cat: "input", hint: "the d-pad moves, A selects, B goes back", words: "game controller gamepad joystick navigate desktop" },
    { key: "plugGreetings", label: "Greet plugged-in devices", cat: "notifications", hint: "what it is and the next step", words: "plug plugged device usb monitor tablet controller security key scanner greeting" },
    { key: "tapToClick", label: "Tap to click", cat: "input", hint: "the touchpad clicks like a button", words: "tap click touchpad" },
    { key: "typingGuard", label: "Touchpad off while typing", cat: "input", hint: "no palm jumps while you write", words: "touchpad typing dwt palm disable" },
    { key: "naturalScroll", label: "Natural scroll", cat: "input", hint: "content follows the finger", words: "natural scroll touchpad two finger" },
    { key: "touchpadSpeed", label: "Touchpad speed", cat: "input", hint: "how far the pointer flies", words: "touchpad speed pointer velocity" },
    { key: "tpAccel", label: "Touchpad acceleration", cat: "input", hint: "adaptive or flat", words: "touchpad acceleration pointer" },
    { key: "tpScroll", label: "Touchpad scroll speed", cat: "input", hint: "the scroll factor", words: "touchpad scroll speed factor" },
    { key: "tpClick", label: "Touchpad click method", cat: "input", hint: "light finger or corners", words: "touchpad click corners clickfinger" },
    { key: "tpScrollMethod", label: "Scroll method", cat: "input", hint: "two fingers or the edge", words: "touchpad scroll method edge two-finger" },
    { key: "tpOffWithMouse", label: "Touchpad off with a mouse", cat: "input", hint: "the touchpad sleeps when a mouse is in", words: "touchpad mouse disable external" },
    { key: "mouseNaturalScroll", label: "Mouse natural scroll", cat: "input", hint: "for wheel mice too", words: "mouse natural scroll wheel" },
    { key: "mouseSpeed", label: "Mouse speed", cat: "input", hint: "pointer velocity", words: "mouse speed pointer velocity" },
    { key: "mouseAccel", label: "Mouse acceleration", cat: "input", hint: "adaptive or flat", words: "mouse acceleration pointer" },
    { key: "mouseScroll", label: "Mouse scroll speed", cat: "input", hint: "lines or pixels", words: "mouse scroll speed wheel" },
    { key: "leftHanded", label: "Left-handed mouse", cat: "input", hint: "the buttons swap", words: "left handed mouse buttons swap" },
    { key: "tabletOutput", label: "Tablet screen", cat: "input", hint: "one screen, every screen, or the one in use", words: "tablet screen display output drawing pen wacom focused" },
    { key: "tabletLeftHanded", label: "Tablet left-handed", cat: "input", hint: "the tablet's buttons swap", words: "tablet left handed drawing" },
    { key: "touchOutput", label: "Touchscreen maps to", cat: "input", hint: "which display the touch maps to", words: "touchscreen map display output" },
    { key: "tpMiddleEmulation", label: "Middle click with both buttons", cat: "input", hint: "press left and right together", words: "touchpad middle click both buttons" },
    { key: "tpDragLock", label: "Drag lock", cat: "input", hint: "keep dragging after the finger lifts", words: "touchpad drag lock lift finger" },
    { key: "tpTapButtonMap", label: "Tap button order", cat: "input", hint: "left/right/middle or left/middle/right", words: "touchpad tap button order map lrm lmr" },
    { key: "dndEdgeViewScroll", label: "Drag to edge scrolls the view", cat: "input", hint: "a window dragged to an edge scrolls the columns", words: "touchpad drag edge scroll view gesture" },
    { key: "dndEdgeWorkspaceSwitch", label: "Drag to edge switches workspaces", cat: "input", hint: "a window dragged to an edge moves to the next workspace", words: "touchpad drag edge workspace switch gesture" },
    { key: "kbdBacklight", label: "Keyboard backlight mode", cat: "input", hint: "auto, always on, or off", words: "keyboard backlight light kbd led" },
    { key: "kbdBacklightLevel", label: "Keyboard backlight level", cat: "input", hint: "dim, medium, bright or full", words: "keyboard backlight level brightness dim" },

    // ---- Date & language
    { key: "use24h", label: "24-hour clock", cat: "time", hint: "13:00, not 1 PM", words: "24 hour clock 12 am pm time format" },
    { key: "showSeconds", label: "Seconds in the bar", cat: "personal", hint: "a ticking clock in the bar", words: "seconds clock bar time" },
    { key: "worldClocks", label: "World clocks", cat: "time", hint: "other cities under the calendar", words: "world clock time zone city" },
    { key: "showCalendarEvents", label: "Calendar events", cat: "time", hint: "what is coming, under the clock", words: "calendar events appointments agenda" },
    { key: "machineTranslate", label: "Translate missing strings", cat: "time", hint: "the local model fills in untranslated labels", words: "translate machine language missing strings" },
    { key: "weekStartsOn", label: "Week starts on", cat: "time", hint: "Monday or Sunday in the calendar", words: "week start monday sunday calendar first day" },

    // ---- Apps & files
    { key: "terminal", label: "Terminal", cat: "apps", hint: "the one Mod+Return and every app opens", words: "terminal shell foot footclient ghostty kitty xterm console default" },
    { key: "terminalThemed", label: "Foot in the desktop's colours", cat: "apps", hint: "background, text, accent, titlebar", words: "terminal foot colours colors theme dark light accent titlebar" },
    { key: "startupApps", label: "Startup apps", cat: "apps", hint: "which apps start at login; add any app or .desktop file", words: "startup autostart login apps desktop file manager" },
    { key: "reopenApps", label: "Reopen apps at login", cat: "apps", hint: "bring back what you had open", words: "reopen apps session restore login startup" },
    { key: "recordingsDir", label: "Recordings folder", cat: "apps", hint: "where screen recordings go", words: "recordings folder screen record videos directory" },
    { key: "screenshotDir", label: "Screenshots folder", cat: "apps", hint: "where screenshots go", words: "screenshots folder pictures directory screenshot" },
    { key: "screenshotFormat", label: "Drawing tool format", cat: "apps", hint: "the format drawings are saved as", words: "screenshot format png jpeg webp drawing" },
    { key: "screenshotQuality", label: "Drawing quality", cat: "apps", hint: "1-100 for JPEG/WebP drawings", words: "screenshot quality jpeg webp drawing" },
    { key: "clipboardOutputFormat", label: "Clipboard format", cat: "apps", hint: "what screenshots are copied as", words: "clipboard format png jpeg webp screenshot paste" },
    { key: "screenshotAnnotationTool", label: "Annotate with", cat: "apps", hint: "Satty (default) or Swappy", words: "annotate satty swappy screenshot draw" },
    { key: "recordArea", label: "What to record", cat: "apps", hint: "the screen or a chosen region", words: "record area screen region recording" },
    { key: "recordSound", label: "Record sound", cat: "apps", hint: "none, the computer, or the microphone", words: "record sound audio desktop mic none recording" },
    { key: "recordFps", label: "Recording framerate", cat: "apps", hint: "auto, 30 or 60 frames per second", words: "record fps framerate recording 30 60" },
    { key: "screenSaverEnabled", label: "Screen saver", cat: "apps", hint: "wallpaper art after idle", words: "screen saver wallpaper idle screensaver" },
    { key: "screenSaverMinutes", label: "Screen saver after", cat: "apps", hint: "minutes of idleness before it starts", words: "screen saver idle minutes timer" },
    { key: "webApps", label: "Web apps", cat: "apps", hint: "sites that behave like apps", words: "web app pwa website install chrome" },

    // ---- Search
    { key: "searchFiles", label: "Search file names", cat: "search", hint: "find files by name", words: "search files find name" },
    { key: "searchInside", label: "Search inside documents", cat: "search", hint: "words inside files", words: "search inside documents content full text" },
    { key: "searchProviders", label: "Apps' own results", cat: "search", hint: "what apps find themselves", words: "search providers apps results" },
    { key: "searchCalc", label: "Sums and conversions", cat: "search", hint: "12*12, 5 km in miles", words: "search calculator sums conversions math" },
    { key: "searchFolders", label: "Search these folders", cat: "search", hint: "the folders search looks in", words: "search folders directories paths" },
    { key: "webSearch", label: "Web search engine", cat: "search", hint: "where web searches go", words: "web search engine duckduckgo google startpage bing ecosia" },
    { key: "launcherIgnoreMouse", label: "Launcher ignores pointer", cat: "search", hint: "keyboard only, no hover", words: "launcher mouse pointer ignore hover" },
    { key: "launcherHideNavLabels", label: "Hide launcher hints", cat: "search", hint: "the arrows and Enter hints", words: "launcher hints navigation labels hide" },

    // ---- Privacy
    { key: "dimAfterBattery", label: "Dim the screen (battery)", cat: "power", hint: "dim sooner on battery", words: "dim screen battery idle power" },
    { key: "lockPreviews", label: "Show notification titles", cat: "privacy", hint: "off: only how many came in", words: "notification preview titles lock screen hide private privacy" },
    { key: "lockScreenClock", label: "Show the clock", cat: "privacy", hint: "the time on the lock screen", words: "clock time lock screen" },
    { key: "lockScreenDate", label: "Date on lock screen", cat: "privacy", hint: "the day under the clock", words: "date lock screen" },
    { key: "lockScreenBattery", label: "Battery on lock screen", cat: "privacy", hint: "the charge percentage", words: "battery lock screen charge" },
    { key: "lockScreenBlur", label: "Blur on lock screen", cat: "privacy", hint: "the desktop, softened behind the lock", words: "blur lock screen wallpaper" },
    { key: "lockScreenMedia", label: "Show media controls", cat: "privacy", hint: "play, pause and skip on the lock screen", words: "media music player controls lock screen now playing" },
    { key: "rememberRecent", label: "Recent files", cat: "privacy", hint: "the launcher's recent files list", words: "recent files privacy launcher" },
    { key: "trashDays", label: "Empty trash automatically", cat: "privacy", hint: "after this many days", words: "trash empty auto delete days" },
    { key: "dynamicLockDevice", label: "Lock when my phone leaves", cat: "privacy", hint: "the desktop locks when the paired phone goes", words: "dynamic lock phone proximity lock device" },
    { key: "dynamicLockGrace", label: "Lock delay when the phone leaves", cat: "privacy", hint: "how long it must stay gone before the lock", words: "dynamic lock delay grace phone leaves bluetooth seconds" },
    { key: "clipPins", label: "Pinned clipboard", cat: "privacy", hint: "texts kept above the clipboard history", words: "clipboard pin pinned texts privacy" },

    // ---- Chronoa
    { key: "islandActivities", label: "The Island on the bar", cat: "chronoa", hint: "timers, music and recordings in the Island", words: "island chronoa bar activities pomodoro timer" },

    // ---- Power
    { key: "autoLockOnLowBattery", label: "Lock when critically low", cat: "power", hint: "lock the screen at 7 % battery", words: "lock battery low critical auto" },
    { key: "profileFollowsCharger", label: "Power mode follows the charger", cat: "power", hint: "one power mode on battery, another plugged in", words: "power mode profile charger battery plugged performance balanced saver" },
    { key: "autoPowerSaver", label: "Battery saver", cat: "power", hint: "power saver at the charge below, back when charging", words: "battery saver power automatic threshold charge" },
    { key: "profileOnBattery", label: "On battery use", cat: "power", hint: "the power mode when the charger is unplugged", words: "battery power profile mode saver balanced unplugged" },
    { key: "profilePluggedIn", label: "Plugged in use", cat: "power", hint: "the power mode while charging", words: "plugged charger power profile mode balanced performance" },
    { key: "powerSaverAt", label: "Battery saver turns on at", cat: "power", hint: "10, 15, 20 or 30 percent", words: "battery saver percentage threshold power" },
    { key: "screenTime", label: "Screen time", cat: "screentime", hint: "per-app time, kept on this machine", words: "screen time wellbeing usage break" },
    { key: "breakEveryMinutes", label: "Break reminder", cat: "screentime", hint: "a nudge to look away", words: "break reminder every minutes wellbeing" },
    { key: "screenLimitMinutes", label: "Daily screen time reminder", cat: "screentime", hint: "a nudge at the daily limit", words: "screen time daily limit reminder wellbeing" },
    { key: "dimAfter", label: "Dim the screen after", cat: "power", hint: "on idle, before it locks", words: "dim screen idle brightness power" },
    { key: "lockAfter", label: "Lock after", cat: "power", hint: "lock the screen on idle", words: "lock screen idle power" },
    { key: "screenOffAfter", label: "Screen off after", cat: "power", hint: "turn the display off on idle", words: "screen off display idle power" },
    { key: "suspendAfter", label: "Suspend after", cat: "power", hint: "sleep the machine on idle", words: "suspend sleep idle power" },
    { key: "lockAfterBattery", label: "Lock after (battery)", cat: "power", hint: "shorter on battery", words: "lock screen idle battery power" },
    { key: "screenOffAfterBattery", label: "Screen off after (battery)", cat: "power", hint: "shorter on battery", words: "screen off idle battery power" },
    { key: "suspendAfterBattery", label: "Suspend after (battery)", cat: "power", hint: "shorter on battery", words: "suspend sleep idle battery power" },
    { key: "lockBeforeSuspend", label: "Lock before suspend", cat: "power", hint: "always lock, then sleep", words: "lock before suspend sleep power" },
    { key: "batteryLimit", label: "Battery charge limit", cat: "power", hint: "stop charging here (needs EC support)", words: "battery charge limit charging threshold" },

    // ---- Automations
    { key: "automations", label: "Automations", cat: "automations", hint: "when this happens, do that", words: "automation rule when then routine trigger wifi plugged headphones" },

    // ---- Apps reachable as deep links (entry.link is the shell's IPC function;
    // consumers open the app instead of jumping to entry.cat — the words carry the
    // desktop categories so a search by "Office", "AudioVideo", "Network" finds them)
    // (a tool that is a Settings page - Startup apps, Automations - has its own
    // row above, so it is not listed twice)
    ...Tools.list.filter(t => !t.settings).map(t => {
        const m = toolMeta[t.flag];
        return { key: m.key, label: t.label, cat: m.cat, hint: m.hint,
                 words: t.words.replace(/^tool /, ""), link: t.op };
    }),

    // ---- About (read-only machine info)
    // "Updates" is the one label for this destination (SettingsAbout, SidebarHeader,
    // SettingsPage, this index); "System restore" is the rollback panel inside it.
    { key: "updates", label: "Updates", cat: "updates", hint: "the system update, its channel and firmware", words: "updates update upgrade channel stable latest rollback firmware restart reboot" },
    { key: "systemRestore", label: "System restore", cat: "updates", hint: "blue-green slot rollback with shani-deploy", words: "system restore rollback slot blue green deploy update recovery" },
    // VPN has no app flag/IPC: no link, so a search lands on the Network category
    { key: "vpn", label: "VPN", cat: "network", hint: "wireguard and openvpn connections, import and status", words: "vpn wireguard openvpn tunnel connections network" },
    { key: "cloudSync", label: "Cloud sync", cat: "network", hint: "background rclone sync with progress", words: "cloud sync rclone remote backup upload download", link: "cloudSyncOpen" },
    { key: "irc", label: "IRC", cat: "network", hint: "chat on IRC networks", words: "irc chat server channel nick message", link: "ircOpen" },
    { key: "health", label: "Health", cat: "personal", hint: "steps, sleep and workouts stored locally", words: "health fitness steps sleep workouts heart rate", link: "healthOpen" },
    { key: "phoneLines", label: "Phone lines", cat: "phone", hint: "the mobile modem, the landline and SIP accounts", words: "phone lines calls dial sim mobile modem landline sip account" },
    { key: "sipAccounts", label: "Internet calling accounts", cat: "phone", hint: "add, edit or remove an internet calling account", words: "internet calling sip account username server password transport" },
    { key: "landlineSetup", label: "Landline", cat: "phone", hint: "set up the landline on your network", words: "landline phone setup code network line" },
    { key: "devicesApp", label: "Devices", cat: "devices", hint: "paired phones, gadgets and your screen on a phone", words: "devices phone gadget android bluetooth pair screen windows", link: "devicesOpen" },
    { key: "fmRadio", label: "FM radio", cat: "devices", hint: "listen to local radio through the aerial", words: "fm radio frequency station aerial gadget" },
    { key: "nfcReader", label: "NFC reader", cat: "devices", hint: "read and write nearby tags", words: "nfc tag read write nearby gadget" },
    { key: "about", label: "About", cat: "about", hint: "this machine — model, CPU, GPU, memory, kernel, compositor", words: "about machine info system kernel cpu memory gpu" },

    // ---- Backup: every flow is a shell page now, not the GTK app ----------------
    { key: "backup", label: "Backup", cat: "backup", hint: "back up your home, restore a backup, snapshots of your files", words: "backup backups restore snapshot snapshots drive other disk copy home", link: "backupOpen" },
    { key: "dailyBackup", label: "Daily backup", cat: "backup", hint: "turn the daily copy on or off and choose its time", words: "daily backup schedule every day time on off automatic timer" },
    { key: "homeSnapshots", label: "Earlier versions of my files", cat: "backup", hint: "snapshots of your home, and restoring a file or folder from one", words: "earlier versions restore deleted file folder snapshot time machine history recover" },

    // ---- System pages folded in from the old system manager -------------------
    { key: "firmware", label: "Firmware updates", cat: "firmware", hint: "the machine's firmware devices, what can be updated, and applying it", words: "firmware updates devices fwupd lvfs capsule bios uefi apply restart" },
    { key: "systemHealth", label: "System health", cat: "health", hint: "run the checks and see every result in plain words", words: "health checks verify diagnose problems report system" },
    { key: "maintenance", label: "Maintenance", cat: "maintenance", hint: "clean system space, save a report, or factory reset", words: "maintenance clean cleanup system space old updates backup report diagnostics reset factory" },
    { key: "graphics", label: "Graphics & drivers", cat: "graphics", hint: "each graphics card, its driver and its render node", words: "graphics gpu driver render node pci mesa vulkan monitor black unbound" },
    { key: "appVersions", label: "App versions", cat: "appversions", hint: "which version of each installed app is really there", words: "app versions installed flatpak snap os deployment package" },
    { key: "etcChanges", label: "System changes", cat: "etcchanges", hint: "what this computer changed in its system settings, and putting a file back", words: "system changes etc overlay diff restore file back config" },
    { key: "persistence", label: "Persistence", cat: "persistence", hint: "what survives a switch between system slots", words: "persistence survives slot update switch data var bind mount state" },
    { key: "virtualization", label: "Virtualization", cat: "virtualization", hint: "KVM readiness and what the virtual machine tools hold", words: "virtualization kvm virtual machines libvirt lxc lxd nspawn readiness manage containers" },
    { key: "disksFilesystems", label: "Disks & filesystems", cat: "disksfs", hint: "RAID, logical volumes, subvolumes, compression and disk health", words: "disks filesystems raid mdadm lvm btrfs subvolume scrub compression smart disk health" },
    { key: "backgroundServices", label: "Background services", cat: "background", hint: "scheduled work, process priority, interrupts and the audit log", words: "background services cron schedule system jobs priority interrupts irq audit log mail" },
    { key: "dnsResolver", label: "DNS", cat: "dns", hint: "which name resolver actually answers, and setting one", words: "dns resolver nameserver which answers set systemd resolved" },
    { key: "networkServices", label: "Network services", cat: "netservices", hint: "what can reach this machine and what it announces", words: "network services inbound open ports sshd tunnels mdns announcements web server mail relay" },
    { key: "signInAccess", label: "Sign-in & access", cat: "adminaccess", hint: "who may sign in, and what they may do once they do", words: "access sign in directory sssd kerberos smartcard privileges sudo ssh keys codes security modules" },
];

// every key, grouped by category: for “N customised” and “Reset this section”
// (scalars only — arrays and objects in a section survive a reset)
var groups = {
    personal: ["blur", "darkMode", "darkSchedule", "darkFrom", "darkTo", "wallpaper", "wallpaperLight", "wallpaperDark", "accentFromWallpaper", "accentName", "iconTheme", "cursorTheme", "cursorSize", "uiFont", "uiFontSize", "monoFont", "monoFontSize", "cornerRadius", "cornerRadiusSmall", "showScrollbars", "reduceMotion", "dock", "dockVisibility", "barVisibility", "dockIconSize", "layoutPreset", "tileOrder", "hiddenTiles", "desktopWidgets", "slideshowDir", "slideshowMinutes", "showSysStats", "showNetSpeed", "barBatteryPercent", "barDate", "hideVolumeGlyph", "hideBrightnessGlyph", "barClickThrough", "hotCornerTopLeft", "hotCornerTopRight", "hotCornerBottomLeft", "hotCornerBottomRight", "hotCornersInFullscreen", "weatherCity", "weatherLat", "weatherLon", "useLocation", "weatherUnits", "adaptiveBrightness", "nightLight", "nightLightTemp", "nightLightSchedule", "nightLightFrom", "nightLightTo", "showSeconds", "leftRail", "railContent", "barApps", "barSearch", "navButtons", "edgeSwipes", ],
    notifications: ["smartReplies", "doNotDisturb", "plugGreetings", "dndSchedule", "dndFrom", "dndTo", "dndWhileLocked", "notifHideContent", "notifSound", "popupSeconds", "popupPosition", "silentApps", "dndAllowedApps", "notifApps", "quietWhileSharing", "quietWhileFullscreen", "focusModes", "focusMode"],
    network: ["proxyMode", "proxyHttp", "proxyHttps", "proxySocks", "proxyPac", "bluetoothAutoConnect", "bluetoothOnBoot", "hotspotName", "hotspotBand", "wifiMacRandom", "wakeOnLan", "obexDir"],
    displays: ["displays", "autoRotate"],
    windows: ["winGaps", "winFocusRing", "winDefaultWidth", "winFocusFollowsMouse", "winAnimations", "winMotion", "winSpeed", "winShadow", "winCorners", "blurStrength", "windowRules"],
    sound: ["fxEnabled", "fxSpatial", "fxEq", "fxPreset", "fxBass", "fxAutoEq", "fxIr", "fxWidth", "fxCrossfeed", "fxLoudness", "micNoise", "fxCompress", "overAmplify", "audioBalance", "systemSounds", "soundVolumeChange", "soundScreenshot", "soundNotification", "volumeStep"],
    access: ["screenReader", "largeText", "highContrast", "monoAudio", "flashAlerts", "speakNotifications", "speechRate", "captionLanguage", "sttBackend", "whisperModel", "compassEnabled", "tourEnabled", "assistiveTouch", "touchX", "touchY", "reduceTransparency", "reduceTransparencyOnBattery", "animationSpeed"],
    input: ["tapToClick", "typingGuard", "naturalScroll", "touchpadSpeed", "mouseNaturalScroll", "mouseSpeed", "leftHanded", "tpAccel", "tpScroll", "tpClick", "tpScrollMethod", "tpOffWithMouse", "mouseAccel", "mouseScroll", "numlock", "middlePaste", "doubleClickSpeed", "keyRepeatDelay", "keyRepeatRate", "kbCompose", "kbCaps", "kbLayouts", "kbSwitch", "oskLanguages", "tabletOutput", "tabletLeftHanded", "touchOutput", "customBinds", "kbdBacklight", "kbdBacklightLevel", "tpMiddleEmulation", "tpDragLock", "tpTapButtonMap", "dndEdgeViewScroll", "dndEdgeWorkspaceSwitch", "gamepadNav", "oskButton", "oskWithTabletMode"],
    time: ["use24h", "worldClocks", "showCalendarEvents", "machineTranslate", "weekStartsOn"],
    apps: ["terminal", "terminalThemed", "reopenApps", "recordingsDir", "screenshotDir", "screenshotFormat", "screenshotQuality", "clipboardOutputFormat", "screenshotAnnotationTool", "recordArea", "recordSound", "recordFps", "screenSaverMinutes", "screenSaverEnabled", "webApps"],
    search: ["searchFiles", "searchInside", "searchProviders", "searchCalc", "searchFolders", "webSearch", "launcherIgnoreMouse", "launcherHideNavLabels"],
    backup: [],
    sharing: [],
    phone: [],
    devices: [],
    printers: [],
    firewall: [],
    boot: [],
    updates: [],
    security: [],
    journal: [],
    storage: [],
    modules: [],
    automations: ["automations"],
    privacy: ["clipPins", "lockPreviews", "lockScreenClock", "lockScreenDate", "lockScreenBattery", "lockScreenBlur", "lockScreenMedia", "rememberRecent", "trashDays", "dynamicLockDevice", "dynamicLockGrace"],
    chronoa: ["islandActivities"],
    account: [],
    users: [],
    screentime: ["screenTime", "breakEveryMinutes", "screenLimitMinutes"],
    power: ["dimAfter", "dimAfterBattery", "lockAfter", "screenOffAfter", "suspendAfter", "lockAfterBattery", "screenOffAfterBattery", "suspendAfterBattery", "lockBeforeSuspend", "autoPowerSaver", "powerSaverAt", "profileFollowsCharger", "profileOnBattery", "profilePluggedIn", "autoLockOnLowBattery", "batteryLimit"],
    about: [],
    // read-first system pages: no shell setting keys to reset
    firmware: [],
    health: [],
    maintenance: [],
    graphics: [],
    appversions: [],
    etcchanges: [],
    persistence: [],
    virtualization: [],
    disksfs: [],
    background: [],
    dns: [],
    netservices: [],
    adminaccess: []
};

// is a value a scalar we may compare and reset?
// a setting's name as the search shows it ("" for a key that is not a setting a person picks)
var _labels = null;
function labelOf(key) {
    if (!_labels) {
        _labels = {};
        for (var i = 0; i < entries.length; i++)
            _labels[entries[i].key] = entries[i].label;
    }
    return _labels[key] || "";
}

function isScalar(v) {
    return v === null || typeof v === "string" || typeof v === "number" || typeof v === "boolean";
}

// how many entries differ from the shipped default (scalars only)
function modifiedCount(d, defaults, cat) {
    var keys = groups[cat] || [], n = 0;
    for (var i = 0; i < keys.length; i++) {
        var k = keys[i];
        if (k in d && isScalar(d[k]) && JSON.stringify(d[k]) !== JSON.stringify(defaults[k]))
            n++;
    }
    return n;
}

// reset exactly the scalar keys of one category
function resetSection(d, defaults, cat) {
    var keys = groups[cat] || [];
    for (var i = 0; i < keys.length; i++) {
        var k = keys[i];
        if (k in d && isScalar(d[k]))
            d[k] = JSON.parse(JSON.stringify(defaults[k]));
    }
}

// a token matches a list when it prefixes one of the words
function _startsWith(words, token) {
    for (var i = 0; i < words.length; i++)
        if (words[i].indexOf(token) === 0)
            return true;
    return false;
}

function _words(text) {
    return String(text || "").toLowerCase().split(/[\s&,-]+/).filter(function (w) { return w.length > 0; });
}

// fewest one-character edits between a token and any prefix of a word (99 = far).
// The first letter must agree: typos rarely hit it, and it keeps this cheap.
function _editNear(token, word) {
    if (!word || token.charAt(0) !== word.charAt(0))
        return 99;
    var m = token.length, n = word.length;
    var prev = new Array(n + 1), cur = new Array(n + 1), i, j;
    for (j = 0; j <= n; j++) prev[j] = j;
    for (i = 1; i <= m; i++) {
        cur[0] = i;
        for (j = 1; j <= n; j++) {
            cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1,
                prev[j - 1] + (token.charAt(i - 1) === word.charAt(j - 1) ? 0 : 1));
        }
        var swap = prev; prev = cur; cur = swap;
    }
    var best = 99;
    for (j = 1; j <= n; j++) best = Math.min(best, prev[j]);
    return best;
}

// typo fallback: "wallpapr" finds "wallpaper". No typos for <4 letters, one up
// to 6, two beyond - so short tokens do not match half the dictionary.
function _fuzzy(words, token) {
    var allowed = token.length < 4 ? 0 : token.length < 7 ? 1 : 2;
    if (!allowed)
        return false;
    for (var i = 0; i < words.length; i++)
        if (_editNear(token, words[i]) <= allowed)
            return true;
    return false;
}

// lower-cased search fields, built once (matches() runs on every keystroke)
var _fields = null;
function _prepare() {
    if (_fields)
        return;
    _fields = entries.map(function (e) {
        var label = _words(e.label);
        var keywords = _words(e.words);
        var hints = _words(e.hint);
        return { label: (e.label || "").toLowerCase(), labelWords: label,
                 kw: keywords, hint: hints, all: label.concat(keywords).concat(hints) };
    });
}

// typed words → matching entries, best first (limit 8).
// label prefix (3) > keyword (2) > hint (1) > typo (0). Every token must match;
// an entry ranks by its weakest token, and ties keep declaration order.
function matches(query) {
    var q = (query || "").trim().toLowerCase();
    if (!q)
        return [];
    _prepare();
    var tokens = q.split(/\s+/).filter(function (t) { return t.length > 0; });
    var scored = [];
    for (var i = 0; i < entries.length; i++) {
        var f = _fields[i];
        var worst = 3, ok = true;
        for (var j = 0; j < tokens.length; j++) {
            var t = tokens[j], s;
            if (f.label.indexOf(t) === 0)
                s = 3;
            else if (_startsWith(f.labelWords, t) || _startsWith(f.kw, t))
                s = 2;
            else if (_startsWith(f.hint, t))
                s = 1;
            else if (_fuzzy(f.all, t))
                s = 0;              // below every exact hit
            else { ok = false; break; }
            if (s < worst) worst = s;
        }
        if (ok)
            scored.push({ entry: entries[i], score: worst, order: i });
    }
    scored.sort(function (a, b) { return b.score - a.score || a.order - b.order; });
    var out = [];
    for (var k = 0; k < scored.length && k < 8; k++)
        out.push(scored[k].entry);
    return out;
}

// a short, honest summary of the current value for a result row
function valueSummary(d, key) {
    var v = d[key];
    if (v === undefined)
        return "";
    if (typeof v === "boolean")
        return v ? "On" : "Off";
    if (typeof v === "number")
        return String(v);
    var s = String(v);
    return s.length > 22 ? "Custom" : s;
}
