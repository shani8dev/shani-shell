// The launcher's built-in actions (from Launcher.qml): toggles, tools and
// settings pages, found by their words.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

QtObject {
    required property var launcher
    readonly property var list: [
        { title: Tr.t("Lock screen"), words: "lock away", icon: "system-lock-screen", run: () => Lock.lock() },
        { title: Tr.t("Do Not Disturb"), words: "dnd quiet notifications silence", icon: "notifications-disabled", run: () => Notifs.setDnd(!Notifs.dnd), state: () => Notifs.dnd },
        { title: Tr.t("Dark style"), words: "dark light theme mode", icon: "weather-clear-night", run: () => Appearance.toggle(), state: () => Appearance.dark },
        { title: Tr.t("Caffeine"), words: "awake sleep idle stay", icon: "preferences-desktop-screensaver", run: () => Idle.setCaffeine(!Idle.caffeine), state: () => Idle.caffeine },
        { title: Tr.t("Night light"), words: "night warm blue light", icon: "night-light", run: () => NightLight.toggle(), state: () => NightLight.active },
        { title: Tr.t("Wi-Fi"), words: "wifi wireless network internet", icon: "network-wireless-signal-excellent", run: () => Net.setWifi(!Net.wifiEnabled), state: () => Net.wifiEnabled },
        { title: Tr.t("Airplane mode"), words: "airplane flight radio", icon: "airplane-mode", run: () => Net.setAirplane(!Net.airplane), state: () => Net.airplane },
        { title: Tr.t("Screenshot"), words: "screenshot capture print", icon: "applets-screenshooter", run: () => Niri.action("screenshot") },
        { title: Tr.t("Screen record"), words: "record video capture", icon: "media-record", run: () => Recorder.toggle(), state: () => Recorder.recording },
        { title: Tr.t("Lens"), words: "lens ocr read text scan qr", icon: "system-search", run: () => Lens.capture() },
        { title: Tr.t("Color picker"), words: "color colour pick hex", icon: "color-select", run: () => Quickshell.execDetached(["sh", "-c", "c=$(niri msg pick-color | sed -n 's/^Hex: //p'); [ -n \"$c\" ] && printf %s \"$c\" | wl-copy"]) },
        ...(Displays.outputs.length > 1 ? [{ title: Tr.t("Swap monitors"), words: "swap monitors screens displays workspaces exchange", icon: "video-display",
            run: () => { const px = {}; for (const o of Displays.outputs) px[o.name] = o.width; Niri.swapMonitors(px); } }] : []),
        ...(Mirror.available ? [{ title: Tr.t("Mirror phone screen"), words: "phone android mirror scrcpy screen cast", icon: "phone",
            run: () => { Mirror.refresh(); Ui.closeAll(); Ui.toggleControlCenter("phone"); } }] : []),
        { title: Tr.t("Screen keyboard"), words: "keyboard osk touch", icon: "input-keyboard", run: () => Osk.toggle(), state: () => Osk.shown },
        { title: Tr.t("Clipboard history"), words: "clipboard paste history", icon: "edit-paste", run: () => Ui.toggleLauncher("c ") },
        { title: Tr.t("Shell settings"), words: "settings preferences control centre center", icon: "preferences-system", run: () => launcher.openSettings("") },
        // each settings category, by what people call what is in it
        { title: Tr.t("Personalisation"), words: "wallpaper background accent theme look blur dock bar tiles hot corners weather icons icon theme fonts font cursor pointer", icon: "preferences-desktop-wallpaper", run: () => launcher.openSettings("personal") },
        { title: Tr.t("Notification settings"), words: "notifications apps pop-ups popups quiet silent do not disturb per app", icon: "preferences-system-notifications", run: () => launcher.openSettings("notifications") },
        { title: Tr.t("Accessibility settings"), words: "accessibility screen reader orca large text contrast mono audio flash alerts captions read aloud speed", icon: "preferences-desktop-accessibility", run: () => launcher.openSettings("access") },
        { title: Tr.t("Keyboard & input"), words: "keyboard layout language input touchpad mouse tap scroll natural pointer speed repeat left-handed osk", icon: "input-keyboard", run: () => launcher.openSettings("input") },
        { title: Tr.t("Date & language"), words: "date time timezone time zone clock 24-hour ntp language locale region formats", icon: "preferences-system-time", run: () => launcher.openSettings("time") },
        { title: Tr.t("Default apps"), words: "default apps browser mail email files text pictures video music pdf open with terminal", icon: "view-app-grid", run: () => launcher.openSettings("apps") },
        { title: Tr.t("Your account"), words: "account user name password picture avatar photo face", icon: "system-users", run: () => launcher.openSettings("account") },
        { title: Tr.t("Clipboard as a QR code"), words: "qr code clipboard link phone share scan", icon: "view-barcode-qr", run: () => Qr.show("From the clipboard", Quickshell.clipboardText) },
        { title: Tr.t("Share Wi-Fi"), words: "wifi wi-fi share password qr code phone guest", icon: "network-wireless", run: () => Qr.shareWifi() },
        { title: Tr.t("Send a text message"), words: "sms text message send phone mobile sim", icon: "mail-send", run: () => { Ui.smsTo = ""; Ui.modemDialog = "sms"; } },
        { title: Tr.t("Tour"), words: "tour welcome help introduction tips what is new how", icon: "help-about", run: () => Ui.tour = true },
        { title: Tr.t("Take a photo"), words: "camera photo picture selfie snap webcam", icon: "camera-photo", run: () => Camera.photo() },
        { title: Tr.t("Record a video"), words: "camera video record webcam clip", icon: "camera-video", run: () => Camera.video(), state: () => Camera.phase === "recording" },
        { title: Tr.t("Camera"), words: "camera viewfinder webcam preview mirror qcam", icon: "camera-web", run: () => Camera.open() },
        { title: Tr.t("Privacy"), words: "privacy permissions camera microphone location recent files trash lock screen notifications previews", icon: "preferences-system-privacy", run: () => launcher.openSettings("privacy") },
        { title: Tr.t("Network settings"), words: "network proxy dns vpn wired ethernet ip", icon: "network-workgroup", run: () => launcher.openSettings("network") },
        { title: Tr.t("Windows"), words: "windows gaps focus ring column width animations focus follows mouse tiling", icon: "preferences-system-windows", run: () => launcher.openSettings("windows") },
        { title: Tr.t("Keyboard shortcuts"), words: "keyboard shortcuts keys hotkeys binds compose caps lock", icon: "preferences-desktop-keyboard-shortcuts", run: () => launcher.openSettings("input") },
        { title: Tr.t("Startup apps"), words: "startup apps autostart login start", icon: "system-run", run: () => launcher.openSettings("apps") },
        { title: Tr.t("Displays"), words: "displays display screens monitor monitors resolution refresh rate hz scale rotation rotate arrange arrangement external projector vrr freesync", icon: "video-display", run: () => launcher.openSettings("displays") },
        { title: Tr.t("Sound effects"), words: "sound effects equaliser equalizer eq bass boost crossfeed headphones autoeq impulse response convolver width jamesdsp viper", icon: "audio-speakers", run: () => launcher.openSettings("sound") },
        { title: Tr.t("Users"), words: "users add user new user account accounts remove user administrator admin automatic login autologin family", icon: "system-users", run: () => launcher.openSettings("users") },
        { title: Tr.t("Power settings"), words: "power battery saver idle lock suspend screen off sleep lid power button", icon: "preferences-system-power", run: () => launcher.openSettings("power") },
        { title: Tr.t("About this computer"), words: "about system computer name hostname rename version kernel memory disk cpu", icon: "help-about", run: () => launcher.openSettings("about") },
        { title: Tr.t("Live captions"), words: "captions subtitles live transcribe hearing", icon: "media-view-subtitles", run: () => Captions.toggle(), state: () => Captions.on && Captions.source === "speakers" },
        { title: Tr.t("Live transcribe"), words: "transcribe transcript meeting lecture microphone dictate", icon: "audio-input-microphone", run: () => Captions.transcribe(), state: () => Captions.on && Captions.source === "mic" },
        { title: Tr.t("Read aloud"), words: "read aloud speak tts selection voice", icon: "audio-speakers", run: () => Speak.speakSelection() },
        { title: Tr.t("Magnifier"), words: "magnifier zoom loupe enlarge", icon: "zoom-in", run: () => Ui.magnifier = true },
        { title: Tr.t("Record a call"), words: "call record recording meeting phone", icon: "call-start", run: () => CallRecorder.toggle(), state: () => CallRecorder.recording },
        { title: Tr.t("Cast screen"), words: "cast miracast tv display wireless project", icon: "video-display", run: () => Cast.open() },
        { title: Tr.t("Earlier versions of my files"), words: "restore deleted file earlier version undo backup snapshot time machine history recover", icon: "document-open-recent", run: () => Backup.open("home") },
        { title: Tr.t("Back up now"), words: "backup back up drive copy restic", icon: "drive-harddisk", run: () => Backup.backupNow() },
        { title: Tr.t("Paste as plain text"), words: "paste plain text formatting strip clean clipboard", icon: "edit-paste", run: () => Clipboard.pastePlain() },
        { title: Tr.t("Clear clipboard history"), words: "clipboard clear wipe history privacy", icon: "edit-clear-history", run: () => Clipboard.wipe() },
        { title: Tr.t("Notifications"), words: "notifications messages", icon: "preferences-system-notifications", run: () => Ui.toggleControlCenter("notifications") },
        { title: Tr.t("Switch windows"), words: "windows switch alt tab", icon: "focus-windows", run: () => Ui.switcherRequested(false) },
        { title: Tr.t("Suspend"), words: "suspend sleep", icon: "weather-clear-night", run: () => Power.suspend() },
        { title: Tr.t("Log out"), words: "logout log out sign out", icon: "system-log-out", run: () => Power.logout() },
        // irreversible: these open the sidebar's confirm row instead of acting
        { title: Tr.t("Restart…"), words: "reboot restart", icon: "system-reboot", run: () => Ui.toggleControlCenter("power") },
        { title: Tr.t("Restart into firmware setup…"), words: "uefi bios firmware setup boot menu restart", icon: "system-reboot", run: () => Ui.toggleControlCenter("power") },
        { title: Tr.t("Power off…"), words: "shutdown power off", icon: "system-shutdown", run: () => Ui.toggleControlCenter("power") }
    ]
}
