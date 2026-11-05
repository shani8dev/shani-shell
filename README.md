# shani-shell — the ShaniOS AI desktop shell (Quickshell + Chronoa)

An AI desktop on **niri + Quickshell 0.3.2**. Chronoa is not an app in a corner:
its companion lives in the middle of the bar, answers approvals in place, and
can be asked from anywhere — the Island, the launcher, a notification, a
selection of the screen (Lens), or the pie menu.

![desktop](docs/showcase-desktop.png)

**[All features, in plain words → FEATURES.md](FEATURES.md)**

| Surface | What it does |
|---|---|
| **Island** | Chronoa's mascot (its own art, over `org.shani.Chronoa.Mascot`) in the bar; grows to show the tool step in progress; opens into an **Approve / Deny card** when Chronoa asks; click the line to ask a question; right-click for Lens |
| **Bar** | launcher, niri workspaces, focused window, now playing, ↓/↑ net speed, cpu/mem, recording + mic/camera/**screen-sharing** privacy dots, tray, status cluster with the input method, notifications, clock with an update dot |
| **Sidebar** | Raven-style: power row, volume/brightness, ~20 quick tiles (Wi-Fi, Bluetooth, airplane, hotspot, VPN, DND, caffeine, power mode, night light, dark style, mic, camera kill switch, screen record, screenshot, color picker, Lens, auto-rotate, flashlight, keyboard, clipboard, Chronoa) — each only where it can work — with Wi-Fi/Bluetooth/VPN/audio lists, calendar, media card, notification history grouped by app with inline reply and **Ask Chronoa**, per-app volume mixer, display scale + mirroring, removable drives (mount / eject), ShaniOS update status (shani-deploy) |
| **Dock** | Latte-style: parabolic zoom, launch bounce, window indicators, pins |
| **Launcher** | full screen. Empty: frequent apps, recent files, the app grid with category chips. Typing: one ranked list — apps (with their actions), open **windows**, **actions** (a command palette: dark style, DND, lock, Lens, wifi …), **files** (recent + home search via fd/find), calculator, emoji, clipboard, web — with **Chronoa** on the right, one keystroke away (Ctrl+Enter, about the selected file too). Prefixes `= : c > ?` still work |
| **Lens** | select part of the screen: its text (Tesseract, offline), QR/barcodes (zbar), copy/search/translate — or ask Chronoa, which *sees* it through its `look_at_image` skill |
| **Ring** | a pie menu at the pointer (Mod+X): Chronoa, Lens, screenshot, media, window, workspaces, apps, power; sub-rings on dwell |
| **Alt+Tab** | every window, most recent first, the previous one preselected; releasing Alt switches |
| **Screen keyboard** | the shell's own, typing through niri's virtual-keyboard protocol: hand-made English and **मराठी** (smart matras: क + आ = का), plus **any of xkb's 598 layouts** (45 Indian — Marathi, Hindi, Tamil, Telugu, Bengali, Gujarati, Kannada, Malayalam, Odia, Gurmukhi, Sanskrit …; Cyrillic, Arabic, Greek, Hebrew, Thai …) generated from the system's own xkb data by `bridge/osk-layout.py`, chosen in settings; never steals focus, never fights the input method |
| **Input methods** | fcitx5 (English + Hindi phonetic by default, 179 m17n tables); the active one in the bar (हि), switched from the sidebar |
| **Window menu** | click the focused window's title: close, fullscreen, float, maximize, center, move to a workspace, ask Chronoa about it (no global menus: niri has no appmenu protocol and GTK 4 apps export none) |
| **Focus modes** | Work / Sleep / Personal (after macOS, Android): hold back notifications except allowed apps, warm or keep awake, on a schedule or by hand |
| **Also borrowed** | hot corners (GNOME), battery saver at 20 % (Android), screen time (Digital Wellbeing), the shelf of recent screenshots/recordings/downloads (ChromeOS), Quick Look of the selected file in the launcher (macOS), the phone through KDE Connect |
| **Accessibility** | screen reader (Orca; every shell control has an accessible role and name — verified through AT-SPI), large text (shell + apps), high contrast, reduce motion, mono audio, screen keyboard, voice typing |
| **Look** | light and dark palettes that follow Dark style, accent from the wallpaper (optional), soft shadows, opening motion, Inter with tabular figures, a blurred lock screen with media controls and your avatar, day/night wallpapers |
| **Live Activities** | the Island carries what is in progress when Chronoa is idle: recording, voice typing, the focus timer, screen sharing, a backup, now playing — a click acts on it |
| **Notifications, more** | snooze 1 h, summaries by Chronoa, quiet while presenting or fullscreen (a game also gets the performance profile), screenshots offered for annotation (satty) or Chronoa |
| **Voice typing** | the screen keyboard's mic: record, transcribe with Chronoa's own speech engine in the keyboard's language, type it where the keys would |
| **Search providers** | the launcher asks apps' own search (GNOME SearchProvider2): Calculator, Files, Characters, Settings … |
| **Settings** | a page in the sidebar: wallpaper picker, bar and dock items, blur, reduce motion, night-light temperature, idle timings |
| **Lock / idle** | ext-session-lock + PAM (`/etc/pam.d/shani-lock`); dim → lock → screen off → suspend; `loginctl lock-session`; locks **before** sleep (logind delay inhibitor) |
| **Plugged in** | a device that arrives during the session is greeted once with its next step: a monitor (extend / mirror / only this screen / Presenting - mirrored, quiet, awake, undone when unplugged), a drawing tablet (use it on this screen), a game controller (name, battery, test the buttons), a security key (sign in with it - pam-u2f on the lock and sign-in screens), a scanner (Simple Scan), a camera or a phone or an iPhone (its files), a presentation clicker, a capture card (Camera), a MIDI device, a serial board (its port), a card reader, a braille display (the screen reader on, with Undo), an external GPU; the sound moving to new headphones is said on the OSD; a charger too slow to keep up is said once — one `udevadm monitor`, no polling; Settings also has a gaming mouse's DPI, polling rate and buttons (libratbag) and the game controllers |
| **Keyboard and controller** | every surface answers the keys: arrows in reading order (the tiles in 2-D), Enter / Space press, the Menu key right-clicks, Tab jumps between regions, Escape goes back, an accent ring shows where you are (Common/KeyFocus); Super+T the dock, Super+B the bar, Super+F10 the desktop menu. A game controller drives the same (d-pad/stick arrows, A Enter, B back, X menu, Y launcher, Start Quick Settings, Select overview, LB/RB workspaces) while no game is fullscreen; read, never grabbed |
| **Never locked out** | the lock screen, the sign-in screen, setup and the administrator prompt each have a screen keyboard a tap away; with no working keyboard (none in udev, or only a touchscreen) it opens by itself; the desktop's keyboard hides with ⌄ and a floating button brings it back on touch; a convertible folded into a tablet shows it |
| **Polkit agent**, **OSD**, **notifications** (DND lets critical through), **greeter** (greetd, same theme, remembers the user) | |

![sidebar](docs/showcase-sidebar.png)

## Layout
```
shani/              Quickshell config (`qs -c shani`)
  shell.qml         root: modules + `ipc call shani <fn>` (incl. `state` as JSON)
  Common/           Theme tokens, Settings (live JSON), Ui state, small widgets
  Services/         one singleton per system: Niri (event stream), Audio, Net,
                    Power, Notifs, Lock, Idle, Polkit, Lens, Recorder, Chronoa, …
  Modules/          Bar, Island, Sidebar (ControlCenter), Settings (window + pages), Dock, Launcher, Lens,
                    Ring, Notifications, Osd, Lock, Polkit, Chronoa, Idle
greeter/            greetd greeter (`qs -c shani-greeter`); Common -> ../shani/Common
setup/              first-boot wizard (`qs -c shani-setup`); Common -> ../shani/Common
bridge/             helpers the shell runs: shani-chronoa-bridge (D-Bus <-> the
                    shell's socket), launch-app, appfilter, agenda, location, …
bin/                shani-doctor (installed as /usr/bin/shani-doctor)
data/               systemd user units, pam.d/shani-lock
assets/             wallpapers and their masters (assets/make-wallpapers.py)
tools/              i18n catalogs, the world map's land outlines
tests/              pytest: bridges, launch-app, QML patterns
dev/                the test harness: dev/check.sh runs every suite (below);
                    the dev session, mock Chronoa, fakes for greetd/MPRIS/…
docs/               FINDINGS (measurements, bugs the tests caught), GAPS,
                    CROSS-REF, the two README showcase images
out/                what test runs write: logs, screenshots, renders (not in git)
```
Settings: `~/.config/shani-shell/settings.json` — any subset of the keys in
`shani/Common/Settings.qml`; edits apply live, toggles write back.

## Packaging
`shani-pkgbuilds/shani-shell` (this repo) and `shani-pkgbuilds/shani-desktop-niri`
(the session: niri config with keybinds, greetd + this greeter, portals, the
tools every tile uses). Development: link the checkout over the packaged config:
`ln -s ~/Documents/shani/shani-shell/shani ~/.config/quickshell/shani`

## Settings and Cassini: one place for each thing
The shell's Settings has what a desktop's settings app has; Cassini (the system
manager) has what goes beyond it, and neither repeats the other. The list is in
shani-cassini's AGENTS.md ("Cassini and shani-shell"). The shell opens Cassini on
a page with `shani-cassini --section=<id>` (update badge, firmware, a failing
disk, Settings > About's "More in Cassini"); inside the shell Cassini's Chronoa,
Printers and fingerprint enrolment point back here
(`qs -c shani ipc call shani settingsCategory <id>`).

## From a script, or a phone over SSH
The shell answers `qs -c shani ipc call shani <fn>`; it holds niri's socket
itself, so this works from an SSH session too (no `NIRI_SOCKET` to find).
Windows are named loosely — a piece of the title or the app id, the one in front
first (after niri-remote and the niri-ipc agent skill):
```
qs -c shani ipc call shani windowList                 # JSON: id, title, app, workspace
qs -c shani ipc call shani windowFocus firefox
qs -c shani ipc call shani windowMove "Terminal" 2    # a workspace number or name, or a monitor
qs -c shani ipc call shani windowClose steam
qs -c shani ipc call shani swapMonitors               # the two screens trade workspaces, widths kept
qs -c shani ipc call shani showDesktop                # also: lock, launcher "…", state
```

## Tests — everything is run, not read
One runner for every suite, on the host (it builds `shani-shell-dev` when missing):
```
sh dev/check.sh                    # everything: unit shell greeter setup polkit admin setup-polkit
sh dev/check.sh unit shell         # just these
sh dev/check.sh idle               # the idle cost alone; a11y: idle + accessibility lint
sh dev/check.sh render=all         # every surface to PNG (shell|greeter|setup|all) in out/renders
sh dev/check.sh --build shell      # rebuild the image first
```
Everything a run writes goes to `out/` (git-ignored): logs in `out/logs`
(`check-summary.txt` lists pass/fail counts and every failing check),
screenshots in `out/shots`, renders in `out/renders`. `admin` and `setup-polkit` need
`../shani-pkgbuilds/shani-desktop-niri` (or `$SHANI_DESKTOP_NIRI`).
Three checks guard the whole shell, not one feature:
- **idle-cost** — 30 s with nothing happening: the programs the shell starts
  (strace on its execve calls, hence SYS_PTRACE; budget 12/min, today 2–4), its
  CPU (budget 15 ms/s) and memory. A new always-on poller fails here, by name.
- **a11y-\*** — shani-testbed's AT-SPI client (mounted at /testbed) lints the
  bar, control centre, launcher, every Settings category and Chronoa: every
  control has a name a screen reader can say.
- **i18n-\*** — the shell restarted in Marathi, its catalog loaded and the bar
  read back in Marathi through AT-SPI. `tools/i18n.py check` lists each
  catalog's gaps; strings a catalog lacks can be translated on the machine by
  Chronoa's local model (opt-in: Settings > Date & language).

`shell-test.sh` brings up a nested niri with a system bus and the real daemons
(NetworkManager, UPower, power-profiles-daemon, BlueZ), PipeWire with null
sinks, the bridge and mock Chronoa, then drives each feature for real (wpctl,
notify-send, niri actions, wtype keystrokes, gdbus into the bridge, the
settings file) and asserts on the shell's own `state`.

**Not verifiable nested** (no GPU / no gamma in a nested niri), so checked on
real outputs in shani-testbed: a real screen recording (wf-recorder gets a 0×0
frame nested; the test checks the failure is reported), night light (needs
wlr-gamma-control), auto-rotate (needs an accelerometer).

See `docs/FINDINGS.md` for the measurements and the bugs these tests caught.
