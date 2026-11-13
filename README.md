<div align="center">

# Shani Shell

**The desktop of Shani OS — Chronoa, and everything else a desktop needs.**

Sign in without typing, find anything from one launcher, 39 apps of its own, your phone built in,
a desktop you can drive by keyboard, touch or game controller — and an assistant that asks before it acts.
Built on [niri](https://github.com/YaLTeR/niri) and [Quickshell](https://quickshell.org).

![The Shani desktop: Maps with a route across Pune, the Island in the bar, the dock](docs/showcase-desktop.jpg)

[Tour](#a-tour) · [More](#more-of-it) · [Apps](#apps-of-its-own) · [Keys](#the-keys-worth-knowing) · [Not yet](#what-it-does-not-do-yet) · [Try it](#try-it) · [Every feature](FEATURES.md)

</div>

## A tour

Everything here was recorded or photographed in a real session of the shell — the test suite's own
nested niri, the same one that runs the 700+ checks.

<table>
<tr>
<td width="50%" valign="top">

**Sign in without typing.** Look at the camera, touch the fingerprint reader or a security key; your
name and picture are already chosen. The password always works too.

<img src="docs/shots/greeter.jpg" alt="The sign-in screen: your name already picked">
</td>
<td width="50%" valign="top">

**Find anything.** <kbd>Space</kbd> on a file in Files shows it without opening an app — a video, a
PDF, a picture — and the arrows walk to the next.

<img src="docs/demos/quicklook.gif" alt="Quick Look in Files">
</td>
</tr>
<tr>
<td valign="top">

**The Ring.** <kbd>Super</kbd>+<kbd>X</kbd>: Chronoa, Lens, media, windows and apps, around the pointer.

<img src="docs/demos/ring.gif" alt="The Ring, a pie menu at the pointer">
</td>
<td valign="top">

**Lens.** <kbd>Super</kbd>+<kbd>S</kbd>, select part of the screen: its words read on this computer —
copy, search, translate, scan a QR code.

<img src="docs/demos/lens.gif" alt="Lens reads part of the screen">
</td>
</tr>
<tr>
<td valign="top">

**Your language.** The screen keyboard in Marathi (a vowel after a consonant becomes its sign), any of
xkb's 598 layouts, handwriting in English, Hindi and Marathi.

<img src="docs/demos/osk.gif" alt="Typing Marathi on the screen keyboard">
</td>
<td valign="top">

**Voice typing.** The screen keyboard's microphone: speak, and the words are heard on this computer
(Chronoa's speech engine) and typed where you were.

<img src="docs/demos/dictation.gif" alt="Voice typing: the keyboard's microphone, words typed into the editor">
</td>
</tr>
<tr>
<td valign="top">

**First setup in six languages**, with the screen keyboard and accessibility from its first screen.

<img src="docs/shots/setup-marathi.jpg" alt="First setup in Marathi">
</td>
<td valign="top">

**Windows that open beautifully** — Glide, Pop or Dissolve (the window gathers in grains), with the
corners, shadow and frosted glass picked in Settings › Windows.

<img src="docs/demos/effects.gif" alt="Windows opening with the Dissolve and Pop effects">
</td>

</tr>
<tr>
<td valign="top">

**Your phone, built in** (Shani Link): calls from the phone, a landline or the modem ring once, on the
Island; texts, one address book, your phone's screen in a window.

<img src="docs/shots/call.jpg" alt="A call ringing on the Island">
</td>
<td valign="top">

**Quick Settings** — volume, brightness and about 40 tiles, each only where it can work; Wi-Fi,
Bluetooth, audio and drives lists; notifications with inline reply.

<img src="docs/shots/quick-settings.jpg" alt="Quick Settings">
</td>
</tr>
</table>

### And an assistant that asks before it acts

Optional: with [Chronoa](https://github.com/shani8dev/shani-chronoa) installed, a model runs on your
own computer, lives in the middle of the bar and asks before it changes anything.

<table>
<tr>
<td width="50%" valign="top">

**It asks first** — in the bar, without opening anything.

<img src="docs/demos/island.gif" alt="Chronoa asks for approval in the bar">
</td>
<td width="50%" valign="top">

**Writing tools in any app** — select text, <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>W</kbd>, and Replace puts it back.

<img src="docs/demos/writing.gif" alt="Writing tools: select text, Super+Shift+W, Proofread, Replace">
</td>
</tr>
<tr>
<td valign="top">

**Ask from the launcher** — <kbd>Ctrl</kbd>+<kbd>Enter</kbd> on a question.

<img src="docs/demos/ask.gif" alt="Asking Chronoa from the launcher">
</td>
<td valign="top">

**Replies already written** on message notifications; **Tidy** sorts Downloads, shown first and undone in one click.

<img src="docs/demos/replies.gif" alt="Suggested replies on a notification">
</td>
</tr>
</table>

## More of it

Each of these is a real screen of the shell — the gaps the clips above leave.

<table>
<tr>
<td align="center" width="33%"><img src="docs/more/overview.jpg" alt="The overview"><br><b>Overview</b> — every workspace and window, live</td>
<td align="center" width="33%"><img src="docs/more/switcher.jpg" alt="Alt+Tab"><br><b>Alt+Tab</b> — the last window preselected</td>
<td align="center" width="33%"><img src="docs/more/app-menus.jpg" alt="The window menu with the app's menus"><br><b>The app's own menus</b> — from the bar, read from its accessibility tree</td>
</tr>
<tr>
<td align="center"><img src="docs/more/launcher-answer.jpg" alt="The launcher answering a conversion"><br><b>Answers in the launcher</b> — sums, units, money, Chronoa one key away</td>
<td align="center"><img src="docs/more/notifications.jpg" alt="Notification pop-ups"><br><b>Notifications</b> — reply, snooze, rules, quiet while you present</td>
<td align="center"><img src="docs/more/lock.jpg" alt="The lock screen with music"><br><b>Lock screen</b> — what is playing, a camera button, power</td>
</tr>
<tr>
<td align="center"><img src="docs/more/widgets.jpg" alt="Desktop widgets"><br><b>Desktop widgets</b> — clock, weather, now playing, battery</td>
<td align="center"><img src="docs/more/light.jpg" alt="The light style"><br><b>Light and dark</b> — following the time of day, colours from the wallpaper</td>
<td align="center"><img src="docs/more/accessibility.jpg" alt="Accessibility settings"><br><b>Accessibility</b> — screen reader, larger text, contrast, captions</td>
</tr>
<tr>
<td align="center"><img src="docs/more/battery.jpg" alt="Battery health"><br><b>Battery health</b> — wear, charge history, what drains it</td>
<td align="center"><img src="docs/more/controllers.jpg" alt="Game controller settings"><br><b>Game controllers</b> — what a pad plays as; the guide button opens Quick Settings over a game (InputPlumber)</td>
<td align="center"><img src="docs/more/ups.jpg" alt="A UPS in Settings"><br><b>A UPS</b> — a power cut said the moment it happens</td>
</tr>
</table>

## What makes it different

- **A complete desktop, not a bar.** Sign-in and lock screens, first setup, Quick Settings, notifications,
  a launcher, a file manager, 39 apps and Settings — one look, one set of keys.
- **Click, don't type.** Settings are picked from choices — your city, a DNS that blocks ads, a
  shortcut you press — never values you would have to know.
- **For everyone.** A screen reader names every control (checked through AT-SPI); large text, high
  contrast, a magnifier, live captions; 45 Indian keyboard layouts; the whole desktop by keyboard or
  game controller; a screen keyboard wherever a keyboard is needed.
- **Your devices and phone.** Plug something in and it says what it can do; calls, texts and contacts
  from your phone; the screen locks when your phone walks away.
- **Light.** At rest it draws nothing and starts at most a few programs a minute — measured by its tests.
- **Tested by running it.** Over 700 checks drive the real shell in a nested session and read back what
  it did; filming this page found four bugs, each now a check.

## Apps of its own

<table>
<tr>
<td align="center" width="33%"><img src="docs/apps/files.jpg" alt="Files"><br><b>Files</b> — places and drives, Tidy, Quick Look, the trash</td>
<td align="center" width="33%"><img src="docs/apps/document-viewer.jpg" alt="Document Viewer"><br><b>Document Viewer</b> — PDF, e-books, comics, DjVu, forms</td>
<td align="center" width="33%"><img src="docs/apps/media-player.jpg" alt="Media Player"><br><b>Media Player</b> — resumes where you left off, subtitles, mini player</td>
</tr>
<tr>
<td align="center" width="33%"><img src="docs/apps/maps.jpg" alt="Maps"><br><b>Maps</b> — search, and directions by car, bike or foot</td>
<td align="center" width="33%"><img src="docs/apps/weather.jpg" alt="Weather"><br><b>Weather</b> — now, the hours and the week</td>
<td align="center" width="33%"><img src="docs/apps/photos.jpg" alt="Photos"><br><b>Photos</b> — every picture, by month</td>
</tr>
<tr>
<td align="center" width="33%"><img src="docs/apps/image-viewer.jpg" alt="Image Viewer"><br><b>Image Viewer</b> — a picture, and the rest of its folder</td>
<td align="center" width="33%"><img src="docs/apps/archive-manager.jpg" alt="Archive Manager"><br><b>Archive Manager</b> — look inside, take one file out, passwords</td>
<td align="center" width="33%"><img src="docs/apps/clocks.jpg" alt="Clocks"><br><b>Clocks</b> — world clocks, alarms, a stopwatch, a timer</td>
</tr>
<tr>
<td align="center" width="33%"><img src="docs/apps/system-monitor.jpg" alt="System Monitor"><br><b>System Monitor</b> — what is running, and what it uses</td>
<td align="center" width="33%"><img src="docs/apps/calculator.jpg" alt="Calculator"><br><b>Calculator</b> — sums, units, money and number bases</td>
<td align="center" width="33%"><img src="docs/apps/settings.jpg" alt="Settings"><br><b>Settings</b> — everything a desktop's settings app has</td>
</tr>
</table>

Also: Text Editor, Calendar, Notes, Tasks, Translate, Kundali, Camera, Voice Recorder, Screenshot,
Screen Recorder, Color Picker, Magnifier, Live Captions, Characters, Fonts, Disk Usage, Logs, Document
Scanner, Password Generator, Authenticator, PDF Signer, Video Trimmer, Converter, Nearby Share,
Screen Ruler and a Tour. `shani app` lists them; each opens from the launcher like any app.

## The keys worth knowing

| Keys | | Keys | |
|---|---|---|---|
| <kbd>Super</kbd>+<kbd>Space</kbd> | Launcher — apps, files, actions, answers | <kbd>Super</kbd>+<kbd>A</kbd> | Chronoa |
| <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>W</kbd> | Writing tools on the selection | <kbd>Super</kbd>+<kbd>S</kbd> | Lens |
| <kbd>Super</kbd>+<kbd>X</kbd> | The Ring | <kbd>Super</kbd>+<kbd>E</kbd> | Files |
| <kbd>Super</kbd>+<kbd>V</kbd> | Clipboard history (pinned texts on top) | <kbd>Super</kbd>+<kbd>.</kbd> | Emoji |
| <kbd>Super</kbd>+<kbd>,</kbd> | Sidebar — quick settings | <kbd>Super</kbd>+<kbd>N</kbd> | Notifications |
| <kbd>Alt</kbd>+<kbd>Tab</kbd> | Switch windows | <kbd>Super</kbd>+<kbd>L</kbd> | Lock |
| <kbd>Super</kbd>+<kbd>Alt</kbd>+<kbd>C</kbd> | Live captions | <kbd>Super</kbd>+<kbd>Alt</kbd>+<kbd>Z</kbd> | Magnifier |

The Tour app shows every shortcut.

## What it does not do yet

- **Proven in a nested session, not yet on an installed image.** Features that need real hardware —
  Wi-Fi edge cases, Bluetooth pairing, two screens, face and fingerprint sign-in, the camera, modem
  calls — are tested against stand-ins only; two (casting to a TV, drives) have no
  check yet. [docs/GAPS.md](docs/GAPS.md) lists every one.
- **Translations are partial**: Marathi and Hindi are translated for the shell's main surfaces
  (1527 of 2347 strings; the newer app windows and settings still show in English); German, Spanish
  and French cover first setup only.
- **What niri cannot give yet**: remote desktop through the portal, colour management, always on top,
  sticky/slow keys in the compositor.
- **Not built**: online accounts, a session chooser at sign-in; a browser and an office suite stay Flatpaks.

## Try it

- **On ShaniOS** it is the desktop of the niri edition — nothing to install.
- **On Arch:** add the `[shani]` repository (`https://repo.shani.dev/$arch`, with `shani-keyring` —
  see [shani-repo](https://github.com/shani8dev/shani-repo)), then `pacman -S shani-shell shani-desktop-niri`. Chronoa (`shani-chronoa`) is optional: the desktop works without it, and the bar shows it offline.
- **Without installing anything:** `sh dev/check.sh demo` records every clip above in a container, and
  `sh dev/check.sh render=shell` draws every surface to a picture.

<details>
<summary><b>Every surface, in one table</b></summary>

| Surface | What it does |
|---|---|
| **Island** | Chronoa's mascot (its own art, over `org.shani.Chronoa.Mascot`) in the bar; grows to show the tool step in progress; opens into an **Approve / Deny card** when Chronoa asks; click the line to ask a question; right-click for Lens |
| **Bar** | launcher, niri workspaces, focused window, now playing, ↓/↑ net speed, cpu/mem, recording + mic/camera/**screen-sharing** privacy dots, tray, status cluster with the input method, notifications, clock with an update dot |
| **Sidebar** | Raven-style: power row, volume/brightness, ~20 quick tiles (Wi-Fi, Bluetooth, airplane, hotspot, VPN, DND, caffeine, power mode, night light, dark style, mic, camera kill switch, screen record, screenshot, color picker, Lens, auto-rotate, flashlight, keyboard, clipboard, Chronoa) — each only where it can work — with Wi-Fi/Bluetooth/VPN/audio lists, calendar, media card, notification history grouped by app with inline reply and **Ask Chronoa**, per-app volume mixer, display scale + mirroring, removable drives (mount / eject), ShaniOS update status (shani-deploy) |
| **Dock** | Latte-style: parabolic zoom, launch bounce, window indicators, pins |
| **Launcher** | full screen. Empty: frequent apps, recent files, the app grid with category chips. Typing: one ranked list — apps (with their actions), open **windows**, **actions** (a command palette: dark style, DND, lock, Lens, wifi …), **files** (recent + home search via fd/find), calculator, emoji, clipboard, web — with **Chronoa** on the right, one keystroke away (Ctrl+Enter, about the selected file too). Prefixes `= : c > ?` still work |
| **Files** | the file manager, in the shell: the places on the left (Home, Documents, Downloads, Pictures, Videos, plugged-in drives), the folder as a grid of tiles or a list of rows, a search box, a preview of what is chosen. Click to choose, Ctrl-click for more, Shift-click for a range, Enter to open, F2 to rename, Delete to the **trash** (the desktop trash, so it can be put back). The folder is watched (inotify), so a file made or removed elsewhere shows up at once. The **chooser** it offers replaces the portal's native dialog — that one held the whole shell while D-Bus waited |
| **Lens** | select part of the screen: its text (Tesseract, offline), QR/barcodes (zbar), copy/search/translate — or ask Chronoa, which *sees* it through its `look_at_image` skill |
| **Ring** | a pie menu at the pointer (Mod+X): Chronoa, Lens, screenshot, media, window, workspaces, apps, power; sub-rings on dwell |
| **Alt+Tab** | every window, most recent first, the previous one preselected; releasing Alt switches |
| **Screen keyboard** | the shell's own, typing through niri's virtual-keyboard protocol: hand-made English and **मराठी** (smart matras: क + आ = का), plus **any of xkb's 598 layouts** (45 Indian — Marathi, Hindi, Tamil, Telugu, Bengali, Gujarati, Kannada, Malayalam, Odia, Gurmukhi, Sanskrit …; Cyrillic, Arabic, Greek, Hebrew, Thai …) generated from the system's own xkb data by `bridge/osk-layout.py`, chosen in settings; never steals focus, never fights the input method |
| **Input methods** | fcitx5 (English + Hindi phonetic by default, 179 m17n tables); the active one in the bar (हि), switched from the sidebar |
| **Window menu** | click the focused window's title: the app's own menus (File, Edit … read from its accessibility tree, as a screen reader does — GTK 3, Qt and XWayland apps; others get their desktop actions), then close, fullscreen, float, maximize, center, move to a workspace, ask Chronoa about it |
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

</details>

## For developers

### Layout
```
shani/              Quickshell config (`qs -c shani`)
  shell.qml         root: modules + `ipc call shani <fn>` (incl. `state` as JSON)
  Common/           Theme tokens, Settings (live JSON), Ui state, small widgets
  Services/         one singleton per system: Niri (event stream), Audio, Net,
                    Power, Notifs, Lock, Idle, Polkit, Lens, Recorder, Chronoa, …
  Modules/          Bar, Island, Sidebar (ControlCenter), Settings (window + pages), Dock, Launcher, Lens,
                    Ring, Notifications, Osd, Lock, Polkit, Chronoa, Idle, Files (the file manager),
                    FilePicker (the chooser)
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
                    CROSS-REF; demos/ and apps/: the README's clips and stills
out/                what test runs write: logs, screenshots, renders (not in git)
```
Settings: `~/.config/shani-shell/settings.json` — any subset of the keys in
`shani/Common/Settings.qml`; edits apply live, toggles write back.

### Packaging
`shani-pkgbuilds/shani-shell` (this repo) and `shani-pkgbuilds/shani-desktop-niri`
(the session: niri config with keybinds, greetd + this greeter, portals, the
tools every tile uses). Development: link the checkout over the packaged config:
`ln -s ~/Documents/shani/shani-shell/shani ~/.config/quickshell/shani`

### Settings and Cassini: one place for each thing
The shell's Settings has what a desktop's settings app has; Cassini (the system
manager) has what goes beyond it, and neither repeats the other. The list is in
shani-cassini's AGENTS.md ("Cassini and shani-shell"). The shell opens Cassini on
a page with `shani-cassini --section=<id>` (update badge, firmware, a failing
disk, Settings > About's "More in Cassini"); inside the shell Cassini's Chronoa,
Printers and fingerprint enrolment point back here
(`qs -c shani ipc call shani settingsCategory <id>`).

### From a script, or a phone over SSH
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

### Tests — everything is run, not read
One runner for every suite, on the host (it builds `shani-shell-dev` when missing):
```
sh dev/check.sh                    # everything: unit shell greeter setup polkit admin setup-polkit
sh dev/check.sh unit shell         # just these
sh dev/check.sh idle               # the idle cost alone; a11y: idle + accessibility lint
sh dev/check.sh render=all         # every surface to PNG (shell|greeter|setup|all) in out/renders
sh dev/check.sh demo               # the README's clips and app stills, in out/demos
CHRONOA=real sh dev/check.sh demo=writing,ask,replies   # the AI clips, with the real model
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
