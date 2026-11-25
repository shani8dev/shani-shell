# Known gaps

> **Complete agent reports:** this file is the curated, deduplicated list. The
> full verbatim reports from all twenty-three research passes (hundreds of findings,
> including items that were later fixed or deduplicated) are in
> [GAPS-RESEARCH.md](GAPS-RESEARCH.md).

What the ShaniOS niri desktop does not do yet, or does without proof, surface
by surface. An item leaves this file when it is built *and* a test runs it.
Compared against GNOME Settings, KDE System Settings, Deepin's dde-control-center,
UKUI's ukui-control-center and Cutefish's settings (the three re-read at source
on 2026-11-22 — see [ECOSYSTEM.md](ECOSYSTEM.md#deepin-ukui-and-cutefish-closely-2026-11-22)),
and against what a session needs before any app runs.

## Not built — by choice

- **Board reach zones.** The bar can sit at the bottom and the dock moves above
  it; the Island still grows from the top. See [FORM-FACTORS.md](FORM-FACTORS.md)
  for the remaining reach, input, layout and hardware-verification checklist.
- **Session chooser on the login screen.** The niri image has one session;
  Plasma and GNOME images have their own greeters.
- **Switch user from the lock screen.** greetd runs one session; there is no greeter to switch back to (loginctl has no such command).
- **Online accounts.** GNOME Online Accounts needs GNOME's own settings app.
- **Remote desktop through the portal.** ScreenCast now has a backend: niri
  26.04 speaks ext-background-effect and `zwlr_screencopy`, and
  `xdg-desktop-portal-wlr` is named for ScreenCast in niri-portals.conf, so a
  browser's Share… can capture the screen. **RemoteDesktop still has none** —
  portal-wlr 0.8.4 implements only Screenshot and ScreenCast — so GNOME Remote
  Desktop, RustDesk and FreeRDP's shadow server cannot *control* it (niri issue
  #390; PR #1966 is open, not merged). What works is Sunshine + Moonlight (KMS
  capture, discussion #680): Settings > Sharing switches Sunshine's user service
  when it is installed (it needs `cap_sys_admin`; LizardByte's repo / AUR, not in
  the image).
- **ICC colour profiles.** niri has no colour management yet.
- **Location services.** Implemented via GeoClue2 (shani-peripherals ships it): `Services/Location.qml` queries `/usr/lib/geoclue-2.0/demos/where-am-i` (or a D-Bus client fallback) and fills `weatherLat`/`weatherLon` so Weather + NightLight stop needing a typed city. Off by default (`Settings.data.useLocation`); the person opts in. Real-hardware only — geoclue is not in the dev container, so it degrades to "location unavailable" there.
- **What Windows, macOS and Pantheon have that niri cannot give.** Always on
  top (niri has no such window state: "Show on all workspaces" floats a window
  and carries it along instead, and Picture-in-Picture windows get it as they
  open; minimise and show desktop are done the same way, with a hidden
  workspace), colour filters for colour blindness and HDR (no colour
  management), "find my pointer" (no pointer position for a layer-shell
  client to draw at), Sticky / Slow / Bounce Keys (keyboard input is the
  compositor's), a gamma control (night light owns the gamma ramp, and only
  one client may hold it), Picture-in-Picture of part of a window (Gala's). Out of scope
  for a shell: presence sensing, receiving AirPlay, a phone as webcam, "Find my
  device" (needs a server). (Desktop widgets were here; they are built since:
  Settings > Personalisation, `desktop-widgets-*` in the suite.)
- **A live camera viewfinder on the lock screen.** The lock screen takes a
  photo (libcamera stills, after a countdown) and shows it; qcam, the live
  view, is a window, and nothing shows above the lock.

## Not built — yet

- **Headphone virtual surround (stereo widening is done).** Implemented via the matrix_spatialiser LADSPA plugin (shipped in ladspa) as a "Stereo widening" toggle in Settings › Sound effects, behind `SoundFx.canSpatial`. The convolver-based virtual surround (KEMAR/Hesuvi HRIR) still needs HRIR wav files that no package ships; stereo widening is what is available.
- **More setup-wizard languages** than English, मराठी, हिन्दी, Deutsch, Español,
  Français (strings.js).
- **Translations**: about 1525 of 3699 catalog strings are translated into
  Marathi and Hindi (the bar, control centre, Settings and its pages, launcher,
  notifications, lock screen, overview, dock, window menu). The rest are the
  newer app windows and settings (Files, Archives, Quick Look, the viewers, the
  terminal);
  German, Spanish and French have setup only. The untranslated strings show in
  English, or - opt-in - are translated by Chronoa's local model, which got about
  a third of short labels wrong when measured with Qwen3-8B. Strings built by
  concatenation are not yet wrapped (`tools/i18n.py` says how).
- **Installed-image form-factor matrix**: container checks do not validate real
  touchscreens, pen calibration, handheld orientation, suspend or TV remotes.
  Run the per-device checklist in FORM-FACTORS.md on an installed image through
  shani-testbed; do not infer that coverage from nested-compositor checks.

## What the other desktops have that we do not (2026-11-22)

Read at source, not from a review: Deepin's repositories (dde-* and deepin-*),
UKUI's, and Cutefish's, plus each control centre's plugin/page directories.
[ECOSYSTEM.md](ECOSYSTEM.md#deepin-ukui-and-cutefish-closely-2026-11-22) has
the side-by-side; these are the ones that are genuinely absent here, each
checked against the tree before being written down.

- **A download manager** (Deepin's, on aria2). Files has copy and move jobs,
  not a queue with pause, retry and per-file progress.
- **An instant offline filename index** (Deepin's *anything*). The launcher and
  Chronoa's meaning index answer what a file *is about*; neither answers "which
  file is called X" across the disk in milliseconds.
- **A hardware inventory** (Deepin's device manager). SMART per disk (Models),
  disks and partitions (Disks), processes (System Monitor) and a summary
  (Settings › About) — but no one tree of the machine's devices.
- **A shutdown timer** (UKUI's). The power menu has Shut down, Restart, Suspend,
  Log out and Lock; nothing schedules one.
- **Biometric enrolment** (UKUI's biometric manager, Deepin's authentication
  page). The image ships fprintd; nothing enrols a finger or a face, so
  Settings › Your account can only set a password.
- **A display-switch popup** on Super+P (UKUI's, which also reports
  CapsLock/NumLock). We have Displays settings and a layout switcher, not the
  transient popup.
- **A notification centre with the clipboard beside it** (UKUI's sidebar). We
  have notifications, the Island, and a clipboard history reachable from the
  launcher's `c` mode — not one tray panel holding both.
- **A theme packager** (UKUI's): icons, cursors and wallpapers turned into an
  installable package.
- **An MCP door onto the desktop** (Cutefish's computer-use): an outside agent
  seeing the screen and driving the pointer and keyboard. Chronoa acts through
  the shell's own tools; nothing else can.

Two of Deepin's apps are deliberately not copied: clone, boot maker and recover
manager are the installer's job on a single-image system (we have shani-backup
and the installer), and *grand search* overlaps our launcher plus Chronoa's
meaning search.

## The app's menus in the bar (updated Nov 2026)

The focused app's menus now sit inline in the bar, macOS style, rather than only
in the window menu. They are read two ways: a D-Bus reader plus a registrar
(bridge/appmenu-registrar.py, installed as `shani-appmenu-registrar.service`,
wanted by niri.service) that Qt 5, GTK and XWayland apps register their menu
object with, and an AT-SPI fallback (bridge/appmenu.py) for apps with no D-Bus
menu. GTK 4 popover bars are empty until opened and Firefox's fill only when
opened, so those get desktop actions.
**Honest limit:** native Wayland Qt 6 and Chromium apps do not register with any
registrar — they need KWin's appmenu protocol, which niri does not carry (niri
issue #1839). Run them under XWayland to get their menus. Still not tried with
LibreOffice on a real session.

## Window layouts — what niri cannot give (Nov 2026)

The layout palette (hold the bar's maximise/zoom button), edge snap
(Super+Alt+Arrow) and arrange-all with Ctrl+Z undo are the shell's own actions
on niri's columns. Two limits are niri's, not ours: there is no compositor
"drag a window to the screen edge" event to hook — drag-to-edge snapping lives
in niri's own `dnd-edge-*` handling, so ours is a keyboard and palette path —
and a true free grid of windows is not possible, as niri only lays windows out
in scrolling columns. The palette offers halves, stacks and quarters within
that model.

## Peripherals against stand-ins only (2026-11-13)

- **InputPlumber**: driven against dev/fake-inputplumber.py (0.84's D-Bus
  interfaces): the controller list, "plays as", "manage every controller", pass /
  always intercept, the guide button lending the controller to the desktop and
  closing giving it back. Not yet on a real handheld (Legion Go, ROG Ally, Steam
  Deck) or with a real pad under "manage every controller" - and whether a real
  InputPlumber reports devices appearing through the ObjectManager signals the
  bridge listens to, rather than only at start.
- **UPS (NUT)**: against a stand-in `upsc`; not yet on a real UPS through upsd.
- **YubiKey codes in the Authenticator**: against a stand-in `ykman`; not with a
  real key. A key whose codes have an OATH password shows "Locked with a password";
  a click opens `ykman oath access remember` in the terminal (stand-in only).

## In the shell, but no check runs them yet (audit, 2026-11-13)

FEATURES.md lists these and they are built, but nothing in the suite drives them:
**casting the screen** to a TV, and **drives** (mount, eject, unlock from Quick
Settings - real devices, see below). (Hooks and sticky Ctrl/Alt were here: they
have checks now, dev/shell-parts/hooks-sticky.sh - the dark-style and wallpaper
hooks run, hooks off run nothing, and Ctrl tapped once, then twice, reaches a
terminal as 01 02 03.) **Quick notes** and
**parental controls** have unit tests only (tests/test_notes_chars_clock.py,
tests/test_appfilter.py), not a run in the session.

## The shell's apps: what each still lacks (Nov 2026)

> **Reading guide (updated after the mass gap-closing pass).** Items marked
> **[built — mass pass]** in the sections below were implemented in commit
> `4772748` and are listed again in "Mass gap-closing pass — what is now
> BUILT" at the end of this file. Items still marked **[open]** remain missing.
> The marker change was applied in place so this catalogue is not misleading.

`shani app` lists them (50). Each is a window of its own (`Common/AppWindow`),
opens cleanly in the suite and is photographed there (`out/shots/app-*.png`).
The shell's app is the default for its file types and the Flatpak is kept
after it as the fallback; a Flatpak leaves the niri image when its app has
been used on a real screen and nothing below is in the way.

- **Media Player** (default for video and audio; Showtime, Decibels behind
  it): subtitles (inside the file, or a .srt/.vtt beside it), sound tracks,
  a song's tags and cover, resume, a mini player. Not yet: subtitle timing
  shifts, chapters, playlists of its own. Hardware decoding is whatever QtMultimedia's
  FFmpeg backend picks - unmeasured on real hardware.
- **Image Viewer** (default for png, jpeg, webp, gif, bmp, svg, avif, tiff;
  Loupe behind it and still the default for HEIC and camera raw).
- **Document Viewer** (default for PDF, EPUB, comics, DjVu, XPS; Papers behind
  it): other formats are read through a PDF copy (PyMuPDF, ddjvu), so an
  e-book's pages are fixed, not reflowed to the window; forms fill through
  PyMuPDF into a copy (no signing fields, no JavaScript forms).
- **Text Editor**: colours from TextMate grammars (`.tmLanguage` in the bundle
  dirs, `.tmTheme` themes) when one matches the file type, falling back to the
  built-in regex highlighter; multiple carets (Alt+Shift+Down/Up for a column),
  Tab-expanded snippets and user bundles are built now; a file over 2 MB is
  refused, over 200 000 characters is shown without colours.
- **Archive Manager** (default for zip, tar.*, 7z, ISO; File Roller behind it):
  creates (zip, tar.gz, tar.xz, 7z), extracts all or one item, opens
  password-protected archives (the password is passed as bsdtar's
  --passphrase, so it is in the process list while bsdtar runs: bsdtar 3.8
  reads no other source but a terminal). It adds to a zip (bridge/zipadd.py -
  libarchive cannot append to one at all) and to a plain tar (bsdtar -rf), and
  refuses the rest in words; a protected zip is refused rather than rewritten
  as a readable copy. It makes protected archives too - zip encrypts with
  AES-256, 7z with its own. Still no 7z/iso/rar add, and no deleting a member.
- **Calendar**: day and year views, time zones, natural-language dates and
  invitations with guests and RSVP are built now. Which calendars show, and
  which a new event goes to, is still chosen here; adding an online account is
  still GNOME Online Accounts' (not in this image).
- **Files**: offered for folders; Nautilus stays the default and is the
  portal's file chooser. Has copy / cut / paste (with other apps), undo, the
  trash's put back and empty, search through folders, Properties, batch rename
  and bookmarks (dev/shell-parts/files-ops.sh). Also: tabs, network places
  (SMB, SFTP), cloud folders (rclone), long-copy progress with stop, and asked
  conflicts. Still missing: dragging files out to other apps and finding
  duplicates.
- **Maps**: drag, zoom, search, directions (OSRM's public server: fine for a
  person, not for heavy use). No offline maps, no transit, no live traffic.
  GNOME Maps stays.
- **Document Scanner, Password Generator, Kundali**: restyled with the shell's
  own widgets (ListRow, Choice, SectionTitle, EmptyState, house cards); no
  stock Qt Controls left in the three windows.
- **Still Flatpaks with no app of ours**: an office suite, a browser, a
  torrent client, internet radio, virtual machines, remote desktop, the games.
- **Not there at all**: a network speed test (tried and taken out, see FINDINGS).
- **Nearby Share (LocalSend)**: exchanged with a second LocalSend implementation
  (ours) only - never with the LocalSend app on a real phone; PIN-protected
  devices are refused, not asked for the PIN. Discovery without the port open
  asks each address of the local /24 directly.

## Built, but not provable in the dev container

Each needs real hardware or shani-testbed:

- The **Files** surface and the **file chooser** are overlay (layer-shell)
  surfaces, and the nested niri shows no Overlay layer: they cannot be
  photographed there, like the Disktree panel and the other overlay surfaces.
  What they do is driven over IPC and read back in the shell's own state (the
  listing, the watch, a new folder, a rename, the trash, the chooser's answer).
- Wi-Fi: wrong-password retry, forget, hidden network; Wi-Fi in first-boot setup.
- Bluetooth: pairing, receiving and sending files against a real
  BlueZ/obexd (both agents are tested against fakes; sending is untested).
- Pointer-only dock gestures: dragging files onto an icon (the launch it makes
  is tested), holding a drag over an icon to cycle its windows, pressure
  reveal of a hidden dock, long-press, scrolling over an icon.
- Two or more screens: the dock on each, the Island, notifications, the
  control centre and Chronoa's panel on the screen in use, and "Swap monitors"
  (nested niri has one output; the one-screen refusal is tested).
- "Using the most power" in the power section (UPower never reports a battery
  in a container).
- Hibernate (shown only where logind says it can; the container cannot).
- KDE Connect discovery and pairing.
- Camera: real libcamera stills and PipeWire video (the still path is tested with a fake `cam`).
- Night light on a real screen; screen recording; auto-rotate; adaptive brightness; flashlight.
- Display modes, rotation and turning a screen off (nested niri applies scale and position only).
- Sound effects and noise suppression on real devices (measured against null sinks); sound-card profiles (null sinks have no cards).
- Your own keyboard shortcuts being pressed (niri ignores virtual-keyboard input for binds; the bind it loads is checked).
- Flatpak app permissions (no Flatpak app in the dev image).
- Keyring unlock at login (PAM; not in the dev image).
- Battery charge limit (no battery in a container).
- Hostname from first-boot setup (Docker bind-mounts /etc/hostname).
- The polkit tiers of `50-shani-admin.rules` through pkexec with a real agent.
- The full first boot → factory reset → first boot cycle.
- From the image's packages, each needing its device: fingerprint enrolment
  (fprintd), external monitor brightness (ddcutil, DDC/CI), Thunderbolt
  authorization (bolt), opening an app on the other GPU (switcheroo-control),
  peripheral batteries (UPower), firmware updates (fwupd), print-queue state
  in the Island (CUPS), Tailscale in the VPN list, sharing the Wi-Fi as a QR
  code (NetworkManager's stored password); unlocking an encrypted USB drive;
  naming the programs that keep a USB drive from ejecting (udisks + fuser);
  restarting into UEFI setup; mobile data; Dynamic Lock with a real phone.
- SIM modem calls and texts on a real modem (bridge/modem.py is tested against
  a fake ModemManager). Call **audio** is the hardware's: most laptop WWAN cards
  are data-only or route call sound where Linux does not, so a call can ring
  and connect in silence; phones over Bluetooth (Chronoa) carry sound.

## Improved (Nov 2026)
- Translations: ~1525/3699 Marathi/Hindi strings done; the rest (newer app windows and settings) are documented above.
- Live TV, free radio picks, a QR folder-link share target, health check and problem report are now in the shell (Media Player / Share / About).
- Real-hardware runs: nested niri only; shani-testbed boot needed for Wi-Fi BT multi-screen recording.
# Improvements applied (Nov 2026)
- Scratchpads: plugin manifest + full settings schema + service lifecycle
- ScreenSaver: active cover + idle-stage hooks
- WebApps: site scraping + reveal hooks
- DevTools: dynamic catalog + TUI hooks
- Lens/Chronoa: turn-stream enhancement
- Adaptive palette: "Accent from wallpaper" extended to a full Material You
  palette via matugen (Settings > Look > Adaptive palette; off by default;
  `qs -c shani ipc call shani themeReload` re-applies). Pattern borrowed from
  mylinuxforwork/dotfiles; Theme stays the single palette authority, and the
  feature degrades to the built-in tonal material when matugen is absent.
- Matugen app templates: ported from mylinuxforwork/dotfiles (kitty, rofi,
  waybar, btop, GTK 3/4) with dotted {{colors.X.default.hex}} syntax and
  per-app adoption hooks (kitty SIGUSR1, waybar SIGUSR2, GTK colour-scheme
  flip-flop via gtk-reload.sh). Membership in Settings (kitty, rofi, waybar,
  btop, GTK) drove which templates were shipped and which app configs got
  the generated @import directive.
- Pruned unused templates: ShaniOS niri ships **foot**, not kitty; shani's
  own bar, not waybar; no system monitor (btop). Only GTK remains relevant.
  Removed kitty/rofi/waybar/btop from the UI and from the shipped templates.
- Wayle-inspired additions: matugen scheme options (scheme type, contrast level,
  source color index) added to Settings and passed through to matugen CLI.
- Wayle-inspired additions: wallpaper slideshow shuffle mode (random order)
  and theming monitor setting (which monitor's wallpaper drives color extraction).
- Wayle-inspired additions: per-monitor wallpapers (different wallpaper per monitor)
  via Settings > wallpaper section.
- Noctalia-inspired additions: Hooks service — user scripts on shell events
  (wallpaper change, dark mode change, screen lock/unlock, startup, color
  generation). Settings > Automations stores the commands.

## Settings (Nov 2026)
- Settings search now finds individual settings (not just categories), jumps to them, flashes the control; categories show a customised dot; every section can be reset to defaults (scalars; custom lists kept). See FINDINGS.md.
- Recently changed rail at the top of Settings shows the last 8 touched settings for quick re-access.
- Per-setting "reset to default" via refresh icon on SwitchRow when changed (defaultValue + onReset pattern).
- Theme palette preview strip (vgshell-inspired): visual color strip showing active Material You palette colors, plus scheme/contrast/source info text.
- New, all wired: °C/°F, calendar week starts Monday/Sunday, battery saver at 10/15/20/30 %, notifications held while locked, message content hidden on lock/off by hand, wf-recorder fps 30/60, opaque panels while on battery.

## Network / Bluetooth / modem (Nov 2026)
- Hotspot name + band, random MAC, Wake on LAN, Bluetooth at sign-in, OBEX folder, gsm APN + no-roaming, VPN autoconnect, mobile-data readout — all wired; see FINDINGS.md.
- Bluetooth PAN tethering (to the PC) surfaces as a saved network; sharing the PC's connection over Bluetooth (NAP) is not offered (bluez removed pand/rfcomm; NM has no NAP server).
- PipeWire: default sink/source, per-app volume and routing, profiles, EQ, effects already covered; nothing further wired honestly.
- ModemManager: operator/signal/state read-out + APN/roaming per connection; mode/PIN remain with ModemManager.

## Input & accessibility (Nov 2026)
- Keyboard backlight: auto/on/off + sidebar tile + brightnessctl wiring (ThinkPad-style `tpacpi::kbd_backlight`).
- Touchpad: middle-emulation, drag-lock, tap-button-map added to InputConfig.kdl; niri 26.04 does not expose per-gesture toggles (3-finger swipe etc. are built in) — left as niri's.
- niri options that are only in git main ("next release"): tablet mapping to the focused window, per-output `max-bpc` and `drm-lease`. Arch's `extra/niri` is 26.04; the config guard puts the old file back if a setting writes one of these, with a warning. `track-layout "window"` *is* in 26.04.
- Recording: video codec choice (auto/H.264/HEVC/VP9/AV1) via wf-recorder -c; screenshot auto-copy to clipboard.
- Snooze length (5/10/30/60 min) and media controls on the lock screen are now settings.

## Built since the last pass

- **Admin / security policy (shani-admin, test-covered)** — SSH keys CRUD (`bridge/sshkeys.py`, `test_sshkeys_bridge.py`), feature-group membership CRUD (`bridge/groups.py`, `shani-admin.py user-group`, `test_groups_bridge.py`), remote-access sshd drop-in, pwquality, `/etc/hosts`, sudoers drop-in (visudo-checked), AppArmor profile mode (enforce/complain), modprobe blacklist, modules-load, sysctl allowlist, journald config + vacuum, timesyncd NTP, faillock, resolved drop-in, narrow login.defs keys, fstrim.timer, cups-browsed, auditd toggle, predefined audit rule profiles (off/minimal/baseline, allowlisted), logind drop-in, coredump drop-in, and systemd-sleep drop-in (`bridge/shani-admin.py`, `data/audit-profiles/`, `tests/test_shani_admin_crud.py`). Settings surfaces: Security, Journal, Power Keys, Storage and Printers pages (`SettingsSecurity.qml`, `SettingsJournal.qml`, `SettingsPowerKeys.qml`, `SettingsStorage.qml`, `SettingsPrinters.qml`). Not claimed: AppArmor confinement for shell-launched apps/bridges, or broader policy beyond these managed keys/drop-ins.

- **Weather advisories** — rain, wind and heat read out of the forecast the
  shell already fetches; open-meteo has no warning feed, and these say so.
- **Mail** (Modules/Mail, bridge/mail.py) — IMAP and SMTP for a real account,
  or MailHog's API and SMTP for development. Shows the message as it was sent
  (Qt's TextDocument over a body the bridge has stripped of scripts, remote
  images and event handlers) or as plain text, and searches a word in the
  sender, the subject or the body (IMAP SEARCH, or the reader's own pass over
  MailHog). Attachments are listed with name, type and size and can be saved
  to a path picked in the shell; the bridge decodes the MIME part. There is no
  image-body rendering and no attachment preview.
- **Feeds** (Modules/Feeds, bridge/feeds.py) — RSS 2.0, RSS 1.0 and Atom over
  the standard library, with a cache and per-feed read state. The subscription
  list moves in and out as OPML 2.0 (another reader's, or ours, without
  doubling), and it can refresh on its own from 15 minutes to daily - one timer,
  which exists only while an interval is set, and a feed that answered recently
  is not fetched again. No per-feed refresh times, no "mark all read".
- **Firewall** (Settings > Firewall, Services/Firewall.qml) — firewalld through
  firewall-cmd: on/off, the default zone, every zone (its own can be added and
  deleted), and the ports, services and rich rules of the zone being edited - a
  rule typed in firewalld's own words, or one of firewalld's presets. A rule is
  removed by its exact string, which is the only form firewall-cmd takes back.
  No zone *policies* (firewalld 2.3's successor to zones), no ipset, no
  direct rules.
- **Tablet readout** — Settings > Keyboard & input names the connected drawing
  tablet from libwacom-list-local-devices. Read-only: niri 26.04 has no pen
  button remapping, and the page says so.
- **Printing from Files** — the file-actions card offers Print… for PDFs,
  images and text when a printer is there (CUPS `lp`).
- **Media Player codec line** — size, codec and bitrate under the title, from
  mediainfo (an optdepend; absent, the line is not shown).
- **Photo metadata** — camera and date taken in the Files preview, from exiv2.
- **ScreenCast portal** — `xdg-desktop-portal-wlr` is now in
  shani-desktop-niri and named for ScreenCast and Screenshot in
  niri-portals.conf, so a browser's Share… has a backend under niri.
  **RemoteDesktop has no backend** (portal-wlr 0.8.4 implements only
  Screenshot and ScreenCast), so the remote-desktop line above stands.
- **Printing from Files** — the file-actions card offers Print… for PDFs,
  images and text when a printer is there (CUPS `lp`).
- **Weather advisories** — rain, wind and heat read out of the forecast the
  shell already fetches; open-meteo has no warning feed, and these say so.

## New apps and shell features (Nov 2026)

Built since the pass above, each with the limit that still applies:
- **Contacts** — vCard files, groups, your own card. No CardDAV in the shell; sync is whatever you already use (a cloud folder, vdirsyncer).
- **Disks** — erase, format, encrypt, health and install-stick, with two-click confirmation and polkit.
- **Models** — ollama discovery and download, what fits in RAM, cloud providers whose keys live in Passwords. "Fits" is a RAM estimate, not a benchmark.
- **Studio** — describes an app, Chronoa writes QML into ~/Developer. The generated code is a starting point, not a finished app.
- **Terminal** — SSH hosts, keys, tunnels and snippets. Not a terminal emulator of its own; it opens the terminal chosen in Settings.
- **Backup** — a timeline of snapshots to restore all or just files from; needs shani-backup and a backup drive.
- **Mail, Feeds, Firewall** — Mail reads by folder and sends, with no user-facing flag button yet (only read/unread state); Feeds does RSS/Atom with OPML and one refresh timer, not per-feed times; Firewall drives firewalld but has no zone policies, ipset or direct rules.
- **Notes, Reminders, Calendar, Photos** — gpg-locked notes, checklists, attachments and cloud-folder sync; smart lists and repeat rules; day/year views, time zones, natural-language dates and invitations; day/month/year grouping, import from phone or camera and adjust in Viewer. Adding an online calendar account is still GNOME Online Accounts'.
- **Text Editor, Preview, Passwords, Clipboard, Screenshots** — multiple carets, snippets and TextMate bundles; seven PDF tools flattened into a copy plus merge/split/export; passkey entries that are a keyring-backed metadata registry, not real credentials, and a weak/reused audit over saved secrets; text transforms and gpg-encrypted history; pin, scrolling capture (grim+slop+ydotool+PIL), Viewer annotation and encrypted history. Scrolling capture needs those tools installed.

## Full upstream app comparison — every gap found (Nov 2026)

Four parallel audits compared our apps against the closest open-source
equivalent, cloned into `/tmp/opencode/ref-apps/`. This is the complete list,
not just what got built. **[fixed]** means it was implemented in the same pass
and has a test; **[open]** means it is still missing. Items already listed
above are repeated here so this section stands alone. Nothing here was
verified on real hardware or in a QML runtime — the findings come from reading
our code and the upstream source/docs.

### Text Editor → Kate

- **[fixed]** Undo / redo — Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y, bounded per-document history.
- **[built — mass pass]** Smart indent after `{` and auto-close of `()[]{}""''`.
- **[built — mass pass]** Regex, case-sensitive and whole-word search with live match highlighting (ours is lowercase `indexOf`).
- **[open]** Quick-open / MRU tab switcher (we have only a tab strip).
- **[built — mass pass]** Current-line highlight and matching-brace highlight.
- **[built — mass pass]** Line bookmarks (Ctrl+B, next / previous).
- **[built — mass pass]** Word and character count in the status bar (only lines today).
- **[built — mass pass]** Split view of one document, and session restore across restarts (`TextDocs` is memory-only).

### Notes → Joplin

- **[open]** Rendered Markdown preview (raw `TextArea` only; no Markdown renderer in `Common/`).
- **[built — mass pass]** Trash / restore deleted notes (`remove()` is `rm -f`; no undo).
- **[built — mass pass]** Version history (each autosave overwrites the file).
- **[built — mass pass]** Formatting toolbar — bold, italic, heading, link, table, code (only Checklist and Attach today).
- **[built — mass pass]** Tags with filtering (notebooks + name filter only).
- **[open]** First-class to-dos with due dates (only `- [ ]` checkboxes).
- **[built — mass pass]** Note previews and sort by updated / created / title (`preview()` exists but is unused).
- **[built — mass pass]** Browseable body-search results (`searchBodies()` exists but only `results[0]` opens).

### Calendar → GNOME Calendar

- **[fixed]** Editing keeps RRULE, DESCRIPTION, attendees and alarms (the editor previously re-composed the whole VEVENT).
- **[built — mass pass]** Event description / notes field in the editor and popover; the bridge now reads `DESCRIPTION` back (wave 6: `a1c78da`, `test_contacts_calendar_wave6.py`).
- **[built — mass pass]** Click-to-view detail popover before editing (currently opens the edit form directly).
- **[open]** Quick-add natural-language field (`_parseNaturalDateTime()` exists but is only in the full form).
- **[open]** Import `.ics` button (`agenda.py import` and `Agenda.importFile()` exist with no QML caller).
- **[built — mass pass]** Repeat / end-repeat field for new events (only preservation is fixed).
- **[built — mass pass]** Per-event reminders / alarms (one hard-coded 10-minute heads-up for all events).
- **[open]** Drag to create / move events in the week and month grids.
- **[built — mass pass]** Current-time indicator line, and local calendar create / rename / colour.

### Contacts → GNOME Contacts

- **[fixed]** Editing keeps unknown vCard fields — BDAY, ADR, ORG, NOTE, URL were silently destroyed.
- **[built — mass pass]** Multiple phone numbers and emails with type labels (mobile / home / work); backend handles arrays, and the form now edits typed arrays (wave 6: `a1c78da`, `test_contacts_calendar_wave6.py`).
- **[built — mass pass]** Read-only detail sheet with click-to-call, mailto and map rows.
- **[built — mass pass]** Export / Share as QR (`Qr.show()` already takes arbitrary text).
- **[built — mass pass]** Editable avatars / photos with crop.
- **[built — mass pass]** Favorites (the star is used only for "This is me").
- **[built — mass pass]** Alphabetical index and sort by first name / surname.
- **[open]** Manual link / unlink versus the existing automatic duplicate merge.

### Files → Nautilus

- **[built — CuboCore pass]** Search category chips (all / folders / images /
  media / documents / text) feed the backend filters and a folders-only
  predicate; search history is deduped, capped at 8 and persisted, shown as
  suggestions with a clear action (`test_files_power_tools.py`).
  **[built — wave 4]** The finer filter popover — file type (the chips above),
  date presets, size bounds and content-vs-filename — is a QML predicate with
  an active-count badge, a Clear action, a keyboard route and accessible names;
  content reuses `files.py`'s bounded ripgrep deep search, so no `--after=` /
  `--min-size=` bridge flags were needed (`test_files_filter_popover.py`).
- **[built — mass pass]** Breadcrumb dropdowns listing sibling folders, now in both the main and split panes with a right-click menu (wave 6: `95d2fa2`, `test_photos_files_wave6.py`).
- **[built — mass pass]** Visible-columns chooser and clickable list headers (fixed Name / Size / Date).
- **[built — mass pass]** "Select Items Matching…" wildcard select.
- **[built — mass pass]** Create Link / symlink (Ctrl+M).
- **[open]** Grid caption settings.
- **[built — mass pass]** Sort by Type / Date Created.
- **[open]** A second Files window (Ctrl+N).

### Photos → gthumb / Loupe

- **[fixed]** Camera / Screenshots filter chips were inert — they now filter by path.
- **[open]** Delete / move to trash from a tile.
- **[built — mass pass]** Multi-select with batch delete, album add, move / copy.
- **[built — mass pass]** Sort order control (newest / oldest / name); wave 6 added size over the one existing scan (`95d2fa2`, `test_photos_files_wave6.py`).
- **[open]** Slideshow from the grid (Viewer has one).
- **[built — mass pass]** EXIF details panel (our `PhotoMeta` reads only Make / Model / Date and is bound to Files' selection).
- **[built — mass pass]** Ratings and tags persisted per photo.
- **[open]** Import into date-based subfolders and delete from source.

### Viewer / PDF → Evince / Loupe

- **[built — wave 4]** User bookmarks per document — persisted by the bridge's
  JSON store and keyed by the document's content md5, so a rename keeps the
  marks (`test_pdf_extras.py`; also `test_gap_pdf.py`). The outline is still the
  PDF's own TOC.
- **[built — mass pass]** Clickable PDF links — internal GoTo, external URI and email (clicking turns the page).
- **[built — mass pass]** Embedded attachments sidebar — list / open / save.
- **[built — wave 4]** Navigation history and First / Last page — a bounded
  stack of visited pages; search and Find jumps are visits too, so Back can
  undo them (`test_pdf_extras.py`).
- **[built — CuboCore pass]** Two-page / facing-pages layout: an odd current
  page is paired with the next, an even page stays in its spread, spread
  navigation moves on spread boundaries, and a missing page image falls back
  to one full-width page. The preference is local to the shell, not a
  settings key (`test_pdf_facing_viewer.py`). The rendered-page limit above
  still applies.
- **[built — wave 4]** Annotations list sidebar — the flattened markup
  PyMuPDF reads back from the PDF is now listed (`test_pdf_extras.py`).
- **[built — mass pass]** Search options — case-sensitive / whole word / wrap (always lowercased).
- **[open]** Print copies and preview (the page range is built in wave 4:
  CUPS `page-ranges=1-3,5` is validated in the service and passed to `lp` as
  its own argument, never through a shell — `test_pdf_extras.py`).

### Mail → Geary

- **[fixed]** Reply and Forward (compose opens prefilled with quoted text). Reply-to-all specifically is not separate.
- **[fixed]** Message date in the list; snippet still not shown.
- **[built — mass pass]** Cc / Bcc in compose (`send()` takes three arguments).
- **[built]** Save attachments — the bridge decodes the MIME part and writes the picked path.
- **[built — mass pass]** Mark unread / star / move / archive (bridge has `imap_flag` internally, exposes only `markread`).
- **[built — mass pass]** View source.
- **[built — mass pass]** Opt-in remote images (the bridge strips all remote content).
- **[open]** Multiple accounts and an account editor.

### Feeds → Newsboat

- **[fixed]** Article summary in the list (data was already in each item).
- **[built — mass pass]** Next-unread navigation and Mark-all-read.
- **[built — mass pass]** Tags / categories with a tag filter.
- **[built — mass pass]** Search / filter articles.
- **[built — mass pass]** Bookmark / save article for later.
- **[built — mass pass]** Show-read toggle and sorting.
- **[built — mass pass]** Feed auto-discovery from a site URL (plain Add/Discover; no download queue yet).
- **[open]** Podcast enclosures → download queue.

### Terminal → kitty / SSH managers

- **[fixed]** Test connection button (`testConnection()` existed with no caller).
- **[fixed]** Import key from the UI (`importKey()` existed with no caller).
- **[fixed]** Search / filter hosts by name, address and user.
- **[open]** Remote (`-R`) and dynamic SOCKS (`-D`) tunnels; only local `-L` today.
- **[built — mass pass]** Import / export the hosts JSON.
- **[built — mass pass]** Advanced per-host options — ProxyJump, agent forwarding, X11, compression, arbitrary `-o`.
- **[built — mass pass]** Recents / last-connected and connection status.
- **[open]** Remote shell integration (kitty's ssh kitten: config copy, connection reuse, remote completion).

### Disks → GNOME Disks

- **[open]** Visual partition / space-allocation bar.
- **[open]** Detailed SMART dialog and short / extended / conveyance self-tests.
- **[open]** Partition management — create / delete / resize / move, type and flags, filesystem label.
- **[open]** Disk-image tools — create, restore with progress, attach as loop device.
- **[open]** Unlock and passphrase change for encrypted volumes (creation works).
- **[open]** Job progress and cancel UI (`Disks.busy` exists but no progress stream).
- **[open]** Mount options dialog (noauto / ro / uid / gid).
- **[open]** Benchmark graph.
- Any of these need the existing two-click confirmation and polkit path preserved — destructive operations.

### Software → GNOME Software

- **[fixed]** Search Flathub as you type (was Enter / Find only).
- **[built — mass pass]** Ratings / reviews (ODRS) and popularity.
- **[built — mass pass]** Featured / editorial discovery (Explore starts at a plain category grid).
- **[open]** apt / dpkg / Snap apps alongside Flatpak (OS updates deliberately go to Cassini).
- **[open]** Version history / per-update changelog.
- **[built — mass pass]** Screenshot gallery and age / content rating (first screenshot only).
- **[open]** Repository / remote management.
- **[open]** Optional add-ons / extensions.

### Processes → htop

- **[fixed]** Search / filter by process name.
- **[built — mass pass]** Click-to-sort by PID / name / memory / disk (fixed CPU then memory).
- **[open]** Signal choice on kill — TERM / KILL / INT / HUP / STOP / CONT (`end()` hardcodes `-TERM`).
- **[built — mass pass]** Process details dialog — command line, user, state, threads, open files, environment.
- **[built — mass pass]** Renice and CPU affinity.
- **[open]** Per-user aggregation / Users view.
- **[open]** Configurable / persisted columns and meters.
- **[open]** Saved views / tabs (htop's F1–F5 screens).

### Settings → GNOME Settings

- **[open]** Online Accounts (already "by choice" above — needs GOA, a system daemon).
- **[open]** ICC colour profile assign / default (niri has no colour management).
- **[open]** WWAN beyond on/off — APN profiles, SIM PIN, roaming and data limits.
- **[open]** Fractional scaling (125 / 150 / 175%).
- **[open]** Removable-media defaults (what opens on inserting a disc or USB).
- **[open]** Per-device Wacom detail — button remap, pressure curve, tablet area, monitor mapping.
- **[open]** Per-monitor wallpaper / scale assignment.
- **[open]** Hardware-driver / firmware section inside Settings (currently a Cassini handoff).

### Media Player → VLC

- **[open]** Audio equalizer and effects (10-band EQ, compressor, spatializer, stereo mode).
- **[built — mass pass]** Go-to-time dialog and chapter list.
- **[built — mass pass]** A→B loop.
- **[open]** Video effects — crop, rotate, deinterlace, filters.
- **[built — wave 6]** Recent media list — a capped, deduped, persisted list on
  the Library/Playing tabs with a clear action (`e83fcc6`, `test_media_wave6.py`).
- **[built — wave 6]** Open a network stream from the UI — one allowlist in
  `PlayQueue` (http/https/rtsp/rtmp/srt/mms), shared by the window and the
  media-info probe (`e83fcc6`, `test_media_wave6.py`).
- **[built — wave 6]** Save / load a playlist (.m3u) through a stdlib bridge:
  standard `#EXTM3U`, relative entries resolved beside the playlist, unsafe
  write targets refused (`e83fcc6`, `test_media_wave6.py`).
- **[open]** Record / stream output.
- Subtitle timing shifts, chapters and go-to-time are all built now.

### Camera → GNOME Snapshot

- **[open]** QR / barcode scan mode (reuse Lens / zbar).
- **[built — mass pass]** Configurable self-timer (hard-coded 3 seconds).
- **[open]** Composition guidelines grid over the viewfinder.
- **[built — mass pass]** Shutter sound.
- **[open]** Audio on / off for video (always adds `pulsesrc`).
- **[open]** Hardware encoding / H.264 MP4 option (always VP8 / WebM).
- **[built — mass pass]** Picture format choice (always PNG).
- **[open]** In-window gallery with photo / video viewer.

### Voice Recorder → GNOME Sound Recorder (Vocalis)

- **[built — mass pass]** Waveform display — live while recording and seekable during playback.
- **[open]** Format / codec and mono / stereo choice (Opus only, fixed).
- **[built — mass pass]** Export recording to a chosen file / format.
- **[open]** Skip back / forward during playback.
- **[built — mass pass]** Friendly sequential names and per-row duration.
- **[built — mass pass]** Cancel / discard a take.
- **[built — mass pass]** In-app playback bar (playback is handed to another app today).
- **[built — wave 6]** Persistent peaks per recording — a bounded (≤256), cached
  peak array keyed by path/size/mtime, WAV via the standard library and other
  formats via ffmpeg, with a seekable named slider (`2ad21b7`,
  `test_recorder_wave6.py`).

### Video Trimmer → LosslessCut

- **[built — mass pass]** Thumbnail timeline with a scrubbable playhead (offsets are blind numbers).
- **[open]** Multiple segments and merge export (one cut today).
- **[built — mass pass]** Keyboard shortcuts / frame stepping — I / O at playhead, S split.
- **[open]** Scene / black-frame / silence detection and split.
- **[open]** Smart cut / nearest-keyframe snapping.
- **[built — mass pass]** Capture frame / snapshot.
- **[open]** Speed change / mute / volume on output.
- **[open]** Remux / format change and track selection.

### Translate → Argos Translate

- **[open]** Source-language pick, auto-detection and swap (target only today).
- **[built — mass pass]** File / HTML translation.
- **[open]** Model / language-package status and install UI (only error is "The local model is not running").
- **[open]** Pivot translation through an intermediate language.
- **[built — mass pass]** Batch / string-list translation (`translate.py strings` exists, no UI).
- **[open]** Translation history (low value — Argos keeps none either).

### Weather → GNOME Weather

- **[fixed]** Detailed current conditions — feels like, humidity, wind, pressure, visibility, sunrise and sunset.
- **[fixed]** Rain probability in hourly tiles (data was already fetched, not rendered).
- **[open]** Multiple saved locations and in-app city search (single city today).
- **[built — mass pass]** Smooth temperature graph over the hourly points.
- **[built — mass pass]** Morning / afternoon / evening / night breakdown per day.
- Wind is fetched and stored but not yet drawn in the hourly tiles.

### Audit findings from the doc-review agents

The three documentation audits also reported gaps, all of which were fixed in
the same pass: wrong app and i18n counts, stale paths and plugin claims in
shani-shell; stale edition, provider, sync-direction, security and link claims
in shani-docs; and wrong workflow profile / timeout / secret / notification
claims in shani-builder, shani-install-media and shani-pkgbuilds. The release
promotion failure (run `44967348298`) was traced to a missing dated output
directory before `curl --output` and fixed in `promote-stable.sh`.

## Second-pass deep audit (Nov 2026) — corrections, new gaps, shell and infra

Six parallel agents re-read the full implementations — services, bridges,
`Common/` helpers and tests, not just the module QML — and compared them with
the upstream sources and changelogs. This corrects the first list, adds gaps
it missed, and widens the scope to the shell surface and the infrastructure.
Legend: **[fixed]** built in this pass with a test; **[was wrong]** the first
pass called it missing but code already has it (or it is out of scope); **[open]**
still missing; **[bug]** a real defect found while verifying.

### Corrections to the first list (don't go build these)

- **[was wrong] Files undo/redo** — already implemented (`Files.qml:825-871`,
  `files.py:16-19`, tests in `test_files_ops.py`).
- **[was wrong] Notes previews** — `preview()` is used in `SidebarNotes.qml:158`
  and `Launcher.qml:417`; only the NotesPanel delegate lacks a subtitle.
- **[was wrong] Notes body search** — `SidebarNotes.qml:31-37` already merges
  `QuickNotes.contentHits`; only NotesPanel opens `results[0]`.
- **[was wrong] Weather details** — now built; the first pass's other weather
  items stand (locations, graph, dayparts).
- **[was wrong] Settings fractional scaling** — `SettingsDisplays.qml:166-171`
  offers 100/125/150/175/200 % per output.
- **[was wrong] Settings per-monitor wallpaper / scale** — `SettingsPage.qml:32-45`
  and `Common/Settings.qml:481-482`.
- **[was wrong] Settings WWAN** — APN presets and custom APN
  (`SettingsNetwork.qml:196-245`), roaming (`:246-253`), SIM PIN
  (`ModemDialog.qml:46`), metered flag (`:179-181`) all exist. Only a GB data
  cap and primary-SIM slot are absent.
- **[was wrong] Disks image tools / unlock / passphrase change** — implemented
  in the Files surface (`Files.qml:1398,1438,1459,1468`, `FilesPanel.qml:2521-2629`,
  tested in `test_drives.py`), not in DisksWindow. Expose them there instead.
- **[was wrong] Disks partition "missing"** — `drives.py format` already builds
  a table and one partition; create/delete/resize/move/flags are still absent.
- **[was wrong] Terminal remote shell integration** — kitty's ssh-kitten is an
  emulator feature; our Terminal is an SSH manager that delegates to foot.
- **[was wrong] Software apt/dpkg/Snap** — OS updates deliberately go to Cassini.
- **[was wrong] Online accounts / ICC profiles / Wacom button remap / firmware
  in Settings** — GOA daemon, niri colour management and niri input-stack work;
  out of scope or blocked by the compositor, not by our UI.

### Real bugs found while verifying (all fixed)

- **[bug→fixed] Process tree was flat** — `TopProcesses.qml:94` emitted rows
  without `ppid`, so `Processes.qml` saw no parents and indented everything at
  0. Added `ppid` to the row object.
- **[bug→fixed] Contacts duplicate merge destroyed phone and email** —
  `Contacts.qml:145` sends `phones`/`emails` arrays but `contacts.py:_make()`
  read only the single `phone`/`email` strings. `bridge/contacts.py` now has
  `_from_payload()` honouring arrays; add/edit use it too.
- **[bug→fixed] Notes "Lock…" called a command the bridge never had** —
  `QuickNotes.qml:597` called `note-crypto.py lock`, which only implemented
  `encrypt`/`decrypt`/`probe`, so it exited 2 and showed a false "Encryption
  failed". Added the `lock` command (encrypt + remove plaintext) with a test.
- **[bug→fixed] Video Trimmer overwrote the previous cut** — a fixed
  `.trimmed.mp4` / `.trimmed.opus` plus `ffmpeg -y` silently destroyed an
  earlier cut. Output names now carry a timestamp.
- **[bug] `Contacts.qml:setGroups()` / `setSelf()` still drop array fields** —
  `bridge/contacts.py` honours arrays on add/edit, but those two service calls
  send only scalars; a groups or self change can still flatten multi-phone
  data. **[open]**
- **[bug] Camera picker was cosmetic** — capture used `cameras[0].index`
  regardless of `Camera.selected`; fixed (one line). **[fixed]**

### Cheap verified wins built in this pass

- **[fixed]** Notification progress bars — `NotificationCard.qml` now renders
  a bar for the freedesktop `progress` hint (0–1; -1 hides it).
- **[fixed]** Alt/workspace menu — `WindowMenu.qml` now lists every workspace
  from `Niri.workspacesOn()` instead of hard-coding 1–3.
- **[fixed]** Feed Mark-all-read — `feeds.py markall` + `Feeds.markAll()` +
  header button.
- **[fixed]** Photos tile actions — slideshow from a tile and move-to-trash,
  both reusing existing Viewer/Files calls.
- **[fixed]** Process end-signal choice — TERM/KILL/INT/HUP/STOP/CONT, validated
  against a fixed set in `TopProcesses.end()` before reaching `kill`.
- **[fixed]** Software screenshot gallery — all four bridge screenshots render
  in a horizontal list instead of only `[0]`.
- **[fixed]** Camera microphone toggle for video.
- **[fixed]** Weather wind in hourly tiles + a temperature Sparkline using the
  existing `Common/Sparkline.qml`.
- **[fixed]** Text Editor word and character count in the status bar.
- **[fixed]** Calendar `.ics` import button (`Agenda.importFile`) and a
  quick-add field using the existing `_parseNaturalDateTime()`.

### Text Editor / Notes / Calendar / Contacts — still open

- **[open]** Editor: smart indent + bracket/quote auto-close; regex / case /
  whole-word search with live highlights (`Common/HighlightText.qml` is an
  unused helper); MRU / quick-open; current-line and matching-brace highlight;
  Ctrl+B bookmarks; Ctrl+G go-to-line UI (only `+LINE` IPC exists); split view;
  TextMate theme chooser and `textmateEnabled` toggle; session restore on
  startup (`TextDocs.docs` is memory-only).
- **[open]** Notes: Markdown preview; trash/restore; version history;
  formatting toolbar; tags; due dates on checkboxes; sort control and a
  subtitle in the NotesPanel list; body-search results in NotesPanel; import
  of Markdown / Obsidian vaults; backlinks graph, writing stats, spellcheck;
  a "Go To Anything" quick switcher.
- **[built — wave 6]** Calendar: description field and readback in `agenda.py`
  (an unrelated edit keeps DESCRIPTION; a VALARM's own description is ignored)
  (`a1c78da`, `test_contacts_calendar_wave6.py`). **[open]** Still: a
  click-to-view detail popover before editing; per-event timezone (zone chips
  are display-only); repeat / end-repeat UI; per-event VALARMs (one hard-coded
  10-minute notice today); drag to create / move events; current-time line;
  local-calendar create / rename / colour (bridge only reads EDS calendars);
  drag-and-drop `.ics` import with a preview; read-only-calendar banner in the
  editor (`readOnly` is exposed by `agenda.py:122`).
- **[built — wave 6]** Contacts: multiple typed phones/emails in the form —
  home/work/mobile/other choices, named rows, `cell`→mobile normalisation and
  typed arrays forwarded by the service (`a1c78da`,
  `test_contacts_calendar_wave6.py`). **[open]** Still: read-only detail sheet
  with `tel:` / `mailto:` / map rows; QR export (`Qr.show()` is ready, needs a
  `vcard` bridge command); avatars;
  favorites (the star means "This is me"); given/family sort chooser;
  unlink for auto-merged duplicates; export all / export selected; multi-select
  for batch link/delete.

### Files / Photos / PDF / Mail / Feeds — still open

- **[built — wave 4]** Files: finer search-filter popover (type/date/size and
  content), test-covered (`test_files_filter_popover.py`).
  **[built — wave 6]** Files: breadcrumb dropdowns form a prefix chain from
  Home, cap long paths to the first and last three, and work in the split pane
  with a right-click sibling menu (`95d2fa2`, `test_photos_files_wave6.py`).
  **[open]** Still: visible-column chooser and clickable headers; "Select Items
  Matching…" (the matcher in `Common/FileFilter.js` exists, just no action);
  symlink creation; grid caption settings; sort by Type / Date Created.
- **[built — wave 6]** Photos: multi-select batch ops and sort order, now also
  by size through the one existing scan (`95d2fa2`,
  `test_photos_files_wave6.py`). **[open]** Still: EXIF panel (bound to Files'
  selection today); ratings and tags; date-subfolder import with
  delete-from-source.
- **[built — mass pass]** Viewer/PDF: user bookmarks; clickable PDF links (`get_links()`);
  embedded attachments; history and First/Last page; two-page layout;
  annotations *list* (we create flattened annotations but never read them);
  case/whole-word/wrap search; print range and copies; form radio widgets
  (`pdfform.py` emits `radio`, the reader handles only text/checkbox/choice);
  a UI for the existing `merge()` / `split()`.
- **[open]** Mail: Cc/Bcc; attachment preview;
  mark unread / star / move / archive (`imap_flag()` exists, only `markread`
  is exposed); view source; opt-in remote images; multiple accounts;
  conversation threading (`In-Reply-To`/`References` unused); IMAP labels.
- **[open]** Feeds: next-unread navigation; tags/categories; search/filter;
  save article for later; show-read toggle; feed auto-discovery; podcast
  enclosures; query feeds (`query:<name>:<filter>`).

### Terminal / Disks / Software / Processes / Settings — still open

- **[built — mass pass]** Terminal: remote (`-R`) and dynamic (`-D`) tunnels; import/export
  the hosts JSON; advanced per-host options (ProxyJump, agent forwarding,
  X11, compression, `-o`); recents / connection status; host export.
- **[open]** Disks: proportional space-allocation bar; detailed SMART attribute
  table and self-tests; partition create/delete/resize/move/type/flags;
  job progress and cancel in the Disks surface (the Files surface has it);
  mount options; benchmark; take-ownership and detach-loop actions.
- **[open]** Software: ODRS ratings/reviews; featured/editorial discovery;
  version history / changelog; EOL/age warning; screenshot gallery is fixed,
  repository enable/disable and add-ons/extensions remain.
- **[open]** Processes: click-to-sort; load-average / swap / PSI meters;
  process details dialog; renice and CPU affinity; Users view; configurable
  columns/meters; saved views. Signal choice and search are fixed.
- **[open]** Settings: WWAN GB data cap and primary-SIM slot; removable-media
  defaults (`x-content/*` in `SettingsDefaultApps.qml`); DNS search domains;
  a text-size slider (there is only a "Large text" toggle).

### Media / Camera / Voice / Trimmer / Translate / Weather — still open

- **[built — wave 6]** Media Player: playlist import/export, recent-media UI,
  an open-network-stream field and save `.m3u` (`e83fcc6`,
  `test_media_wave6.py`). **[open]** Still: 10-band EQ and effects; A→B loop;
  video effects (crop/rotate/deinterlace); Stop control (MPRIS stop maps to
  pause+seek(0)); MPRIS `HasTrackList` is `False`.
- **[open]** Camera: live QR/barcode scan mode (post-capture Lens path exists);
  self-timer choice (`countdown` is fixed); composition grid; shutter sound;
  H.264/MP4 and hardware encoding; picture format choice; in-window gallery;
  delete from gallery.
- **[built — wave 6]** Voice Recorder: seekable waveform and persistent peaks
  (`2ad21b7`, `test_recorder_wave6.py`). **[open]** Still: format / mono-stereo
  choice; export; skip back/forward; sequential names and per-row duration;
  cancel/discard; in-app playback; name-on-save.
- **[built — mass pass]** Video Trimmer: thumbnail timeline; multi-segment merge; I/O/S
  shortcuts; scene/black/silence detection; keyframe snapping; capture frame;
  speed/mute/volume; remux and track selection; cancel/progress on a cut.
- **[built — mass pass]** Translate: source language pick, auto-detect and swap; file/HTML
  translation; model endpoint UI (hard-wired env default); model/package
  status. Pivot and history are out of scope (direct LLM, Argos keeps none).
- **[built — mass pass]** Weather: multiple saved locations / in-app search; daily/weekly
  temperature graph (the hourly sparkline is now there); morning/afternoon/
  evening/night breakdown; more than 7 days (`forecast_days=7`).

### Shell surface (new — never audited before)

Compared with GNOME Shell, KDE Plasma, macOS and open-source shells. None of
these needs a compositor-level feature. **[fixed]** items above are from this
pass; the rest are **[open]**.

1. **[open]** Grouped notification stacks — `Popups.qml:47-66` is a flat list;
   `Notifs.qml:30` already computes per-app keys.
2. **[open]** Tray overflow drawer — `Bar.qml:638-688` renders every
   `SystemTray.items` inline.
3. **[fixed]** Notification progress bars.
4. **[open]** Alt+Tab grouping by app — `Switcher.qml:34` uses a flat MRU list.
5. **[open]** Drag a window in the workspace map to move workspaces —
   `Bar.qml:215-234` is click-only; `Niri.moveWindowTo` exists (`shell.qml:924`).
6. **[open]** Drag an app from launcher to dock to pin — `Dock.qml:436-455`
   has a drop pattern; `Launcher.qml` has none.
7. **[built — CuboCore pass]** OSK word suggestions — a bounded dictionary,
   prefix match, per-word dismissal, plus compact / fixed size and opacity
   modes (`test_osk_modes.py`). **[built — wave 4]** paste (clipboard as one
   `wtype` argv element), bounded held-key repeat that stops on release/hide/
   remote, and one-handed centre/left/right with the board narrowed to 82% and
   persisted in OSK's own JSON (`test_osk_extras.py`). Still open in the input
   section below: emoji page and swipe typing.
8. **[open]** Dock on left/right/top — `Dock.qml:24` hardcodes `anchors.bottom`
   and the parabolic zoom assumes a horizontal row.
9. **[fixed]** Move to any named workspace in the window menu.
10. **[open]** Full app menu in the bar — `Bar.qml:440` takes `menus.slice(0, 5)`.
11. **[open]** "Run as administrator" from the launcher — `> cmd` and
    Shift-for-terminal exist, no pkexec path; `Polkit` / `shani-admin.rules`
    are already in place.
12. **[open]** Per-app attribution on privacy chips — `Bar.qml:615-633`
    shows generic glyphs; `Privacy.qml` has no client field.
13. **[open]** Alt+Tab "close all windows of this app" — `Switcher.qml:72-76`
    closes only the selected window.

Still impossible in a QML layer-shell client: true always-on-top, arbitrary
window PiP, drag-to-edge snapping, global shortcuts niri grabs, window
thumbnails in Alt+Tab, colour filters / HDR, gamma, "find my pointer", and
Sticky / Slow / Bounce Keys. Rechecked "by choice" items: a **session chooser
on the greeter is now feasible** (`greeter/shell.qml:30-31,231` already keeps
the session command in a variable); switch-user remains impossible (no
`loginctl` switch command and a `WlSessionLock` forbids a second surface);
the live camera viewfinder remains blocked (no PipeWire-video QML element).

### Infrastructure / installer / updates (new — never audited before)

Ranked; evidence is in the named repos under the workspace root.

1. **[open, big]** No dual-boot / install-alongside / OEM path —
   `os-installer-config/config.yaml:57` `partition_ok: no`; whole-disk only.
2. **[open, easy]** No generated release notes per promotion — no workflow
   calls `gh release` or `generate_release_notes`.
3. **[open, easy–medium]** No user-facing update schedule, maintenance window
   or bandwidth cap — fixed 2 h agent timer, disabled prefetch timer,
   `AUTO_REBOOT=no`, no `--limit-rate` in the downloader.
4. **[open, needs server]** Delta updates effectively off — zsync2 skips
   seeds > 2 GB (`shani-deploy.sh:3920-3925`) while images are multi-GB.
5. **[open, easy–medium]** No "verify this medium" boot path in the ISO —
   boot entries are only normal/nomodeset.
6. **[open, easy]** Only niri is auto-promoted — the schedule matrix is
   hard-coded to `["niri"]` (`promote-stable.yml:57`).
7. **[open, medium]** Images are not reproducible — no `SOURCE_DATE_EPOCH`;
   the AMI builder floats `latest.txt`.
8. **[out of scope]** No measured boot / remote attestation — needs hardware
   and a key server.
9. **[open, needs virtualization]** Hard-failure boot fallback unverified —
   the repo itself says automated rollback on hard failure is unproven.
10. **[open, needs privileged runner]** No end-to-end CI for `shani-deploy` —
    verification is manual.
11. **[open, medium]** No reboot auto-apply / staged-update UX.
12. **[open, needs server]** Torrents generated but no seeder / torrent-based
    updates.
13. **[open, medium]** No separate recovery environment — recovery is slot
    rollback plus manual USB repair instructions.
14. **[open, very easy]** `min_password_length: 1`
    (`os-installer-config/config.yaml:95`); mainstream distros require 8+.
15. **[open, easy]** No release-engineering troubleshooting page (stale
    `stable.txt`, failed gate, CDN drift, signature mismatch at install).

Risk: items 8 and 9 are security / correctness claims that remain unverified.
The `[fixed]` labels in this section come from static tests and code reading —
no QML runtime or hardware was available in this environment.

## Third-pass audit (Nov 2026) — unaudited apps, accessibility, cross-platform

A third round of parallel agents covered apps that had never been audited, a
full accessibility review, and comparisons against Android / iOS / macOS /
Windows. This section is additive to the two above. Legend as before:
**[bug→fixed]** a real defect found and repaired in this pass; **[fixed]** a
cheap verified win built; **[open]** still missing; **[out of scope]** needs a
server, radio, modem or proprietary ecosystem. No runtime or hardware was
available — all verdicts are from source.

### Security / i18n / developer ecosystem — see per-app sections below

The fourth agent in this round covered password/authenticator security, i18n
and the developer ecosystem; its findings are folded into the relevant app
sections below and into "Corrections" where they overturned an earlier claim.

### Archive Manager → File Roller

- **[bug→fixed] jar / apk appends failed** — `appendable` listed them but the
  append branch used `bsdtar -rf` only for `zip`; jar and apk are zip containers
  and now go through `zipadd.py`.
- **[bug] `zipadd.py` stores `../outside.txt`** for a file added from above the
  archive's folder; extraction refuses `..` paths. **[open]**
- **[open]** Delete a member, rename a member, open a member in its own app,
  integrity test, archive comments/properties, progress on long operations.
- **[open]** Add to 7z / rar / ISO (`appendable` excludes them).
- **[open]** `zipadd.py names` has no caller; `extractSingle(dir, done)` has an
  unused `done` parameter.

### Calculator → GNOME Calculator

- **[bug] `Ui.calculatorTab` is written but never read at startup** — the
  chosen tab is not restored. **[open]**
- **[bug] Programming "Base ▸" is visually inert** — it changes `base` but
  `doProgramming()` calls `baseOutputs()`, which always renders all four.
  **[open]**
- **[bug] char↔code breaks for non-BMP characters** — `charCodeAt(0)` is
  UTF-16, `codeToChar` uses `fromCodePoint`. **[open]**
- **[open]** DEG/RAD/GRAD toggle; variables and `Ans`; `mod` and integer
  division; hyperbolic and inverse functions; `log(x, base)`; history
  persistence (memory-only today); currency/date conversions; copy the
  expression, not just the result.

### Clocks → GNOME Clocks

- **[bug] An alarm for the already-fired minute is missed** — `lastFired` is a
  single minute string, so adding an alarm for that minute is silently skipped.
  **[open]**
- **[built — wave 4]** Per-alarm sound choice (an allowlisted freedesktop hint
  sent as a single `notify-send` argv item) and inline alarm rename, with the
  weekday repeat and 5/9/15-minute snooze choice pinned by tests
  (`test_clocks_wave4.py`); custom timer duration, pause/resume, labels,
  multiple named timers, per-lap splits, in-app city search and keyboard Home/
  End/Page navigation were already built (`test_large_clocks_time_fixes.py`).
  **[open]** One-shot alarms, a ringing panel with Dismiss/Snooze (only
  `notify-send` today), sunrise/sunset/twilight and state persistence.

### Characters → Gucharmap

- **[bug] Browse starts at ASCII punctuation** (`entries[:limit]`, first code
  point 0x21), though the docstring claims symbols and script letters first.
  **[open]**
- **[open]** Favorites/recents; Unicode-block browsing beyond six fixed chips;
  insert-into-last-app and repeat insertion; multi-codepoint emoji (flags and
  ZWJ are skipped); copy as U+/HTML entity/decimal; glyph detail panel;
  font preview of the actual glyph.

### Fonts → GNOME Font Viewer

- **[bug→fixed] Installing a font whose path has a space failed** — the file
  dialog path was not `decodeURIComponent`-ed.
- **[bug] `installFont` silently overwrites a same-named user font.** **[open]**
- **[open]** Family/style search (styles beyond the 400-style cap are
  unreachable); uninstall; drag-and-drop a font file; license/copyright text
  and a glyph grid in the file viewer; `.ttc` face list; "use this font in
  Settings" handoff; side-by-side comparison; recent fonts.

### Maps → GNOME Maps

- **[bug→fixed] "Open in browser" used the device location, ignoring a typed
  start** — `routeUrl` now honours `fromLat`/`fromLon` when set.
- **[open]** `limit=1` geocoding (no disambiguation); transit routing; live
  traffic; offline maps and cache eviction; map/night style; a marker for the
  typed start and waypoints; reverse geocoding on long-press; alternative
  routes; keyboard pan/zoom; structured (not flattened) route steps.

### Disk Usage → Baobab

- **[bug] Marks survive navigation** — `enter()`/`back()` kept `marked`, so a
  file marked in one folder could be trashed from another. **[fixed]**
- **[bug] `dir_size()` walks every subtree synchronously per child** — large
  homes hit the timeout. **[open]**
- **[open]** Rings/sunburst chart and sortable list; scan progress and partial
  results; exclude/skip configuration; an in-app location/drive chooser;
  hardlink double-counting; preview before marking; used/free bar.

### Document Scanner → GNOME Document Scanner

- **[bug] `scanErr` is collected but never displayed** — failures show a
  generic message although the panel promises the scanner's own words.
  **[open]**
- **[bug] `--resolution` is not a universal SANE option** — the image's v4l
  backend does not expose it, so scanning would fail there. **[open]**
- **[open]** Batch/multi-page and duplex; post-scan crop/rotate/brightness/
  contrast; page reorder and multi-page PDF merge; "scan to" destination;
  scan-area selection; per-device option discovery; OCR; scan history.

### Logs, Password Generator, Authenticator, Nearby, Converter, PDF Signer, Kundali

- **[bug] Logs' "Show raw entry" button closes details** (the raw text is
  already inline). **[open]** Also: `priColor()` is defined but never used;
  no severity / unit / boot filters; fixed `-n 200` buffer; no export or copy;
  search misses PRIORITY/_TRANSPORT fields; no new-error notification.
- **[bug] Authenticator's 1 s tick can miss a TOTP rollover** — it refreshes
  only when `Date.now()%period === 0` at the tick, so drift shows a stale code.
  **[open]** Also: UI cannot set digits/period/algorithm (the bridge can);
  no edit/rename; no export/backup (a lost keyring loses all tokens); no
  search/sort/grouping; no per-issuer icon; clipboard not cleared after copy.
  **Positive:** secrets are in GNOME Secret Service, never on disk or argv.
- **[bug→fixed] PDF Signer's "signed copy" kept only one page** —
  `pdftoppm -f N -singlefile` produced a one-page PDF and destroyed every
  other page. All pages are now rendered, only the chosen page is stamped,
  and the pages are merged back.
- **[open]** PDF Signer: no real cryptographic signature (a pasted image is
  forgeable, so "Signed" overstates it); no drag-to-place (six blind numeric
  fields); no rotation/opacity/multi-signature/date stamp; no AcroForm fill;
  no placement undo; no final-render preview.
- **[bug] Converter's documented fade and artist options were never wired**
  (the bridge implements them). **[fixed]** Speed control is now wired too.
  Still **[open]**: cancel a running conversion, per-job options (the global
  row applies to all queued jobs), output-folder choice, metadata strip /
  codec / subtitle / track selection, and an error for invalid numbers
  (they are silently coerced).
- **[bug→fixed] Nearby had no way to cancel a transfer** — the bridge already
  implemented `{"op":"cancel"}`. **[open]**: text/clipboard sharing; a
  persistent device/trust store (`Devices.known` is in memory); receive
  location choice and per-file accept; rename this computer; transfer history
  (the UI shows only the last three); folder send and resume.
- **[security] Nearby disables all TLS verification** (`CERT_NONE`,
  `check_hostname=False`) and pins an announced fingerprint from an
  unauthenticated multicast message — anyone on the LAN can claim an alias.
  **[open]**
- **[open]** Password Generator: exclude look-alike characters; custom
  excluded-character set and hex-only mode; save straight into the keyring
  (generation and Passwords are disconnected); custom length; passphrase
  word count; strength/entropy readout; GPG actions (`passwords.py` already
  implements them); clipboard auto-clear. **Positive:** uses `secrets`, not
  `Math.random`. If the wordlist is missing, "Words" silently emits a random
  string.
- **[bug] Kundali always treats the typed birth time as UTC** (QML appends
  `Z`), so a local time yields the wrong Lagna/chart; a `12:00:30` input
  becomes malformed `12:00:30:00Z`. **[open]** Also: nine bridge commands are
  dead/unwired (`nakshatra`, `aspects`, `dignity`, `transit`, `timelords`,
  `arabicparts`, `temperament`, `lunarmansion`, `bazi`) and `aspects` computed
  by `kundali()` is discarded by the QML parser; no visual 12-house chart;
  no city search (manual lat/lon only); no save/export/share/history; no
  "today" shortcut for Panchang; hardcoded Lahiri ayanamsa and house system.

### Messages, Calls, Phone — Android / iOS / macOS / Windows

The GTK4 app `shani-link` owns Messages and Calls; the QML shell has only
entry points (`Services/Phone.qml:41-59`) and the modem dialog
(`Services/Modem.qml`). Most gaps are therefore GTK4 work, not QML.

- **[open]** Conversation search (bodies and senders); inline Reply on text
  notifications; multi-recipient/group threads (KDE Connect accepts an
  address array, Bluetooth does not); image attachments on send; SMS
  backup/export (there is no own message store — threads come from GSConnect's
  `sms.json` or Bluetooth MAP); drafts; speed dial / favourites in the shell;
  a call-waiting card (ModemManager decodes `"waiting"` but the QML tracks one
  call); call recordings named by caller; delivery/read status.
- **[open]** Messages are not E2EE and bodies are echoed to `notify-send`.
  **Positive:** bidirectional control characters are stripped
  (`phone.py:229-242`), and message read/send switches default to off.
- **[dead] `PhonePanel.add_tab()` is an empty stub**; `Phone.openRecentCalls()`
  opens the Calls tab rather than a dedicated recents view.
- **[out of scope]** Real SMS/MMS/voice without a modem or paired phone;
  iMessage, FaceTime, RCS and iPhone calls/texts; typing indicators, read
  receipts, reactions and scheduled server-side send (provider signals absent
  from MAP, KDE Connect and ModemManager); visual voicemail/transcription;
  E2EE for SMS; real MMS picture receive (MAP exposes text metadata only).
- **Already built (not gaps):** one call history with duration across
  landline/phone/modem; hold/swap/merge for the landline; two-sided call
  recording with a consent notice; SMS OTP copy and Reply from modem
  notifications.

### Entirely missing app categories vs Android / iOS / macOS / Windows

Codes: **Q** = QML + existing bridge; **D** = small daemon; **S** = server;
**H** = hardware.

- **[open, Q]** Podcasts — highest value × ease; reuse `feeds.py` polling and
  cache plus Media Player's `PlayQueue` for enclosures.
- **[open, Q]** Audiobook mode — bookmarks, chapters and a sleep timer in
  Media Player (no new app).
- **[open, Q]** IRC client — `bridge/irc.py` (socket/WebSocket), Feeds-style
  list/entry UI.
- **[open, Q]** SQLite/database client — `bridge/db.py` with the stdlib
  `sqlite3`.
- **[open, Q]** Teleprompter — QML only; reuse Text Editor's font/window
  settings.
- **[open, Q]** Network tools (LAN scan, ping, DNS, whois) — wrap
  `nmcli`/`iw`/`dig`/`ping`.
- **[open, Q+D]** Local-first health/fitness — shani-link already sees
  watches/bands; log steps/sleep, import sensor data, no cloud.
- **[open, Q]** Startup/login-items manager — XDG `autostart/*.desktop`.
- **[open, Q]** Scheduled-tasks view — thin view over the existing Hooks and
  Automations services, not a new engine.
- **[open, Q]** Offline dictionary/thesaurus — local wordnet data, reuse
  Lens' selection-to-query path.
- **[open, partial]** VPN client — Quick Settings tile and Settings VPN list
  exist; full NetworkManager D-B management is missing.
- **[open, D/S]** Cloud-storage client — Files has rclone cloud folders; a
  real sync daemon needs a service and account.
- **[open, D]** System-level restore — Backup restores home snapshots only.
- **[open, WebApp]** Video conferencing — needs WebRTC/GStreamer; Flatpak/WebApp
  fallback.
- **[open, partial]** E-book reflow — Document Viewer opens EPUB/FB2/MOBI with
  a fixed layout (already in the first app list).
- **[out of scope]** Find My device, wallet/payments, iMessage/FaceTime/iCloud,
  a native-package app store, browser/office/torrent/VM/games (Flatpak-only,
  already in the first list), remote desktop *control* (no portal backend),
  NFC tools, Emergency SOS.

### Accessibility — "Accessible by default" is overstated

A real foundation exists (`Contrast.js`, computed `accentInk`, a high-contrast
palette, `fontScale` on 1057/1074 font-size lines, `reduceMotion` via
`Theme.anim`/`Theme.mot`, `KeyFocus`, Orca from `Services/Access.qml`, fcitx5
from `Services/Ime.qml`). The specific claim that "every control has a name,
verified with real accessibility tools" is not supported by code or tests.

- **[fixed]** Toast announces its message via `Qt.accessibleAnnounce`.
- **[fixed]** `SliderRow` now exposes `Accessible.Slider` + name + value;
  previously Orca read "slider" with no value.
- **[fixed]** Super+Alt+S now toggles the screen reader in the running shell
  (setup and the greeter already had it).
- **[open]** No live regions anywhere else: error text (`TextField.qml`),
  captions (`CaptionBar.qml`) and status changes are silent to Orca/TalkBack.
- **[open]** Custom controls with no AT-SPI name/role: `SegmentedTabs`,
  `DatePicker`, `Toast` (other than the announce), `EmptyState`, `AppPicker`,
  `FolderPicker`. `KeyFocus` is `Accessible.ignored`, so the keyboard path
  exists but the screen-reader path does not.
- **[open]** Slider values baked into names in `QuickPanel.qml`,
  `SettingsSound.qml` and `MediaPlayer` go stale; `Accessible.value` is the
  fix.
- **[open]** The a11y lint only covers bar/control-centre/launcher/settings/
  Chronoa and SKIPs without a testbed client; none of the ~45 app windows are
  linted. `test_qml_patterns.py:307-316` only checks a Button role has a name
  within 10 lines.
- **[open]** `Theme.faint` measures about 2.73:1 light / 3.75:1 dark — below
  AA 4.5:1 — across 173 uses; accent-on-`accentSoft` is ~3.85:1 in light mode
  across ~72 uses.
- **[open]** Captions are a visual card only: no AT-SPI role/name,
  `keyboardFocus: None`, two-line elide truncation, 10 px dim label.
- **[open]** Muted state is colour-only in `SliderRow`; `StatusPill` encodes
  ok/warn/error by hue alone (WCAG 1.4.1).
- **[open]** Touch targets: `Theme.touchTarget` in only 13 files;
  `SegmentedTabs` is 40 px fixed, `DatePicker` 30 px, `Toast` 28 px — above
  AA 24 px but below Android 48 dp / Apple 44 pt.
- **[open]** `Theme.fontScale` is binary (1.0 / 1.25), not continuous;
  unscaled fonts remain in `GamepadVisual`, `KundaliPanel`, `DesktopWidgets`,
  `NotificationCard` and `MediaPlayerWindow`.
- **[open]** No focus trap in modal dialogs (only three `modal: true` in the
  tree); Tab can leave a dialog behind its scrim.
- **[open]** No Escape handler in MailWindow, FeedsWindow and Processes.
- **[open]** No `Accessible.heading` or landmark roles anywhere — Orca's
  rotor and VoiceOver's rotor cannot navigate by structure.
- **[open]** TextField focus is a 1 px colour swap, not a distinct ring;
  `inputMethodHints` is set only for secrets, not email/URL/numeric/time
  fields; there is no `LayoutMirroring` anywhere (latent until an RTL locale
  is added).
- **[open]** One unguarded animation: `NotificationCard.qml:408`
  ignores `reduceMotion`.
- **[out of scope]** Colour filters and gamma are compositor-level (already
  in the first list); native Wayland Qt 6 / Chromium menus are not reachable
  through the AT-SPI fallback (already in the first list).

Static verdicts only: no Orca session, qmllint or per-app walk of all 45
windows was possible in this container.

### Capture and screen tools

- **[bug→fixed] Color Picker promised to copy the picked colour but never did** —
  `Color.qml` updated recents and fired a signal nobody listened to; now copies
  the hex with `wl-copy`. Its `picked` signal still has no listener and the
  `code !== 0` branch is dead because the command ends in `|| true`.
- **[bug→fixed] Live Captions used `hh-mm` (12-hour) in transcript filenames** —
  AM and PM sessions appended to one file; now `HH-mm`. Still **[open]**:
  out-of-order captions from background subshells, the mic-source flag needs
  runtime verification, no history/scrollback, pause/resume, timestamps,
  font/position/opacity settings, named save or a language picker in the bar.
- **[bug→fixed] Quick Look's PDF cache key was `md5(path)` only** — a changed
  PDF at the same path showed a stale first page forever; mtime is now part of
  the key. Still **[open]**: PDF page navigation/zoom, metadata, extract-one
  from archives, video seek/volume, share/open-with, image zoom/pan, and
  Viewer redo for strokes / fullscreen / copying pixels rather than a path.
- **[bug→fixed] Ruler's `ratio` was never assigned** — it multiplied by 1.0,
  so "real pixels" was false on scaled outputs. Derived from the output scale.
  Still **[open]**: diagonal length and angle, ticks/origin guides, saved
  measurements, px/cm/in units, arrow-key nudge, a loupe, multi-monitor
  coordinate alignment (grim captures all outputs), and temp-PNG cleanup.
- **[wrong claim] `PinCapture.qml:3` says the pin can be moved and resized** —
  there is no drag or resize handler; it is a fixed 480×360 window. **[open]**
- **[wrong claim] `scroll-capture.py:6` documents a manual mode** that does not
  exist; `stitch` is unwired. **[open]**
- **[open]** Screenshot: region/window capture (slurp is already used elsewhere),
  all-monitors capture, a history browser (encrypted captures are written but
  never listed or decrypted by any UI), OCR preview, configurable directory
  and pin zoom/fit.
- **[open]** Recorder: pointer show/hide, pre-start delay, single-window capture,
  WebM/MKV container choice, cancel/discard, max-duration auto-stop, a mic
  level meter.
- **[open]** Color Picker: no picker *window* at all (only a headless singleton
  and a sidebar tile), recents stored but never rendered, colour wheel and
  palette generation, copy-as CSS/Qt/int, sample from an image, favourites.
- **[open]** Lens: QR actions for `WIFI:`/`mailto:`/`geo:`/`tel:`, OCR language
  choice, editable OCR text, TSV structure, history, keyboard-driven region.
  **Bugs:** `save()` hardcodes `.png` for jpg sources, `openImage()` does not
  encode spaces, and the language probe regex assumes codes `^[a-z_]{3,}$`.
- **[open]** Magnifier: auto-refresh, full-screen zoom mode, colour inversion,
  resizable/persisted loupe, arrow-key pan, reset key, cross-monitor follow.
- **[open]** Tour: five card bodies are raw literals (English-only) — wrap in
  `Tr.t()`; `Settings.data.tourEnabled` is checked in `shell.qml` but never in
  `Tour.qml`; no spotlight, capture-tools card, try-it steps, replay/reset or
  visible Back button.

### Backup, Models, Studio, Firewall, Passwords, Greeter, Setup, Lock

- **[bug] Backup's two restore buttons are identical** — both resolve to
  `open("home")`; `what` and `restoring` are dead. The CLI `restore <target>
  --snapshot <id>` restores into a *new* folder with no file filter, so it does
  not yet implement the "files only" promise. **[open]** Also: no progress or
  cancel for `backupNow`, swallowed JSON errors, no restore-verification badge
  (the bridge already computes one), no retention/schedule read-out, exclusions,
  off-site status or snapshot diff.
- **[bug→fixed] AI-provider keys were never stored** — `Keyring.set()` called
  `passwords.py set <id>`, but `set_secret()` expects a D-Bus object path, so it
  failed silently behind `|| true`; `getKey()` called a nonexistent `Passwords`
  singleton. Added `passwords.py put/lookup/drop` by `shani-id` attribute and
  rewired `Keyring`/`AIProviders`. **Note:** keys are still mirrored to
  plaintext dconf for Chronoa — **[open]** to remove that and rely on the
  keyring. Also **[open]**: `download()` uses `;` so it announces success even
  when `ollama pull` fails and sends one notify per output line; the preferred
  model is set before download succeeds; "Installed" claims GGUF but only
  `ollama list` runs; VRAM is read but unused in the fit check; no live model
  registry, per-provider models, test-connection or in-window errors.
- **[bug→fixed] Studio's `busy` was never cleared** — Generate stayed disabled
  and "Working…" permanent. Now cleared when Chronoa's turn ends. Still
  **[open]**: the `find` expression can never match a `.desktop` under
  `~/Developer`, so `desktopPath` is always empty and `gio launch` plus
  desktop cleanup are dead; no code preview before adding to the launcher,
  revision/version history, syntax check, export, or privilege warning.
- **[bug] Firewall zone create/delete use `--permanent` without `--reload`** —
  the new zone is absent from runtime until reload, despite the comment claiming
  otherwise. **[open]** Also: `parseZones` drops hyphenated keys (`forward-ports`,
  `source-addresses`); interfaces and target are parsed but never displayed;
  presets are hardcoded English; no success confirmation; no panic mode,
  logging/MASQUERADE, rule-validation preview or translated presets.
- **[bug→fixed] The password audit never ran** — it read `item.secret` from a
  list that deliberately omits secrets, so weak/reused always reported zero and
  the banner never appeared. Added a bridge `audit` command that reveals
  secrets in-process and returns only counts/labels. **[open]**: the passkey
  copy action copies the random local `id`, not the displayed `cred_id`;
  `passkey-add` reports success even when saving fails; the FIDO2 promises have
  no create/assert commands; locked collections cannot be unlocked; attribute
  editing, GPG expiry/type choice, keyring import/export and generator→keyring
  handoff are missing.
- **[bug→fixed] The greeter kept a typed password when another user's avatar
  was picked**, so it could be submitted for the wrong account. **[open]**: no
  `Tr.t()` at all (login screen is English-only), no IME/fcitx, caps probe needs
  a keyboard LED sysfs node, no network/auth status, last-layout restore,
  user dconf a11y settings, PIN-only path or retry countdown.
- **[bug→fixed] Setup accepted a 1-character password**; now requires 8.
  **[open]**: `finish()` writes `chronoa-enabled` from the `greeter` user's
  gsettings, so the setting never reaches the new account; `tryAuto()` joins the
  first open network without asking; `onAuthMessage` answers every prompt with
  password/username, so a real second-factor prompt would get the password;
  no hidden/enterprise Wi-Fi, proxy, restore-from-backup, disk/encryption
  choice, USB settings import or license/telemetry page.
- **[open]** Lock screen: wrong-password strings are raw English; `lockPhotos`
  accumulates but only the newest is shown; biometric PAM can call
  `unlocked()` independently of the password conversation with only three
  retries; `queued` is discarded on success; `tests/test_lock.py` tests the
  file bridge, not the lock surface.

### Security, i18n and developer ecosystem

- **[bug→fixed] Command injection through hook placeholders** —
  `Hooks.qml` text-substituted a wallpaper path into a shell string, so a file
  named `x;touch ~/.config/autostart/x` executed on wallpaper change. Hook
  arguments are now positional parameters (`sh -c "$script" sh "$1" "$2" "$3"`).
- **[bug→fixed] The clipboard QR tile wrote a predictable world-readable
  `/tmp/shani-qr.png`** via a shell pipeline; now calls `Qr.show()`, which uses
  `XDG_RUNTIME_DIR` and argv.
- **[bug→fixed] WebApps referenced undeclared `safeUrl`** in `script()`, so
  `sync()` threw before writing any desktop entry. **[open]**: stale
  `*.desktop` files are never removed (the glob is quoted).
- **[bug] Permission Undo follows symlinks** — `files.py:797-802` reads mode
  with `lstat` but changes with `chmod()` (which follows the link). **[open]**
- **[bug→fixed] Three Settings quick-op chips were fake** — "Backup now" and
  "Update check" only `echo`ed to `/tmp/quick-op.log`, and "System info" showed
  hardcoded `Memory: 477 MB · CPU: 54 ms/s`. They now call the real Backup and
  Cassini services and read `SysStats`.
- **[open, i18n]** The greeter and setup wizard have no translation path —
  two disconnected catalog systems (`setup/strings.js` vs `shani/i18n/`), and
  `tools/i18n.py` scans only `shani/**/*.qml`. English plural suffixes are
  smuggled through `%2` (`Tr.t("Copying %1 photo%2…", n, n === 1 ? "" : "s")`),
  which Marathi/Hindi cannot express; there is no plural API or placeholder
  parity validation (`%1` can be dropped by a translation unnoticed), 83
  unwrapped literals remain, and `Tr.t("%1 items").arg(n)` breaks translator
  reordering in three files.
- **[open, ecosystem]** No CONTRIBUTING.md, issue templates or code of conduct;
  ~515 IPC functions with six documented examples and no version/deprecation
  contract; no man page or shell completion for the `shani` CLI; the
  `com.canonical.Unity.LauncherEntry` D-Bus API is undocumented; Settings
  pages cannot be added without editing the hardcoded `cats` array; no
  user theme-pack API; no CI config in this repo (all verification is manual
  via `dev/check.sh`).

All third-pass verdicts are static — no QML runtime, hardware, PAM, polkit or
live keyring was available in this container.

## Gap-closing pass + fourth-pass research (Nov 2026)

### Mass gap-closing pass — what is now BUILT

Six parallel implementation agents closed the largest feasible slice of the
open list above. Each added assert-based tests; the full suite is now
**829 passed, 3 skipped**. Everything below in this subsection is **[built]**
with a test. Previously-open items not named here are still open.

- **Shell surface**: grouped notification stacks with expand; tray overflow
  drawer; Alt+Tab app grouping (`G` toggles flat MRU, `Shift+Q` closes an app's
  windows); window-drag onto workspace-map targets; launcher→dock pin drag;
  app-menu `⋯` overflow; "Run as administrator" from the launcher.
- **Feeds**: next-unread; tags/categories; article search; save/bookmark;
  show-read toggle; feed auto-discovery; podcast enclosures.
- **Mail**: Cc/Bcc; mark unread / star / move-archive;
  view source; opt-in remote images. Also fixed a latent `imap_flag` bug.
- **Files**: symlink creation; select-items-matching; breadcrumb dropdowns;
  sort by type and date-created.
- **Photos**: sort order; multi-select batch trash/album; EXIF details panel;
  ratings/tags.
- **Viewer/PDF**: per-document bookmarks; clickable links; attachments;
  annotation list; navigation history + first/last; case/whole-word/wrap
  search; radio form widgets; merge/split UI.
- **Editor**: smart indent and bracket/quote auto-close; case/whole-word/regex
  find with live highlights and replace-all; bookmarks Ctrl+B; go-to-line UI;
  cross-restart session restore; current-line/matching-brace overlays;
  TextMate theme chooser.
- **Notes**: trash/restore; dated version history; Markdown formatting toolbar;
  tags; sort/previews; browseable body search; `@due(...)` checklist dates.
- **Calendar**: description read/write; detail popover; repeat/end-repeat;
  per-event alarms and timezones; current-time lines; read-only banner.
- **Contacts**: typed/repeating phones and emails; read-only detail sheet with
  call/mail/map/QR actions; `vcard` + `export-all`; avatars and favorites;
  given/family sort chooser; `setGroups`/`setSelf` array fix.
- **Media Player**: go-to-time; recent-media list; network-stream field; A→B
  loop; Stop; chapters via ffprobe.
- **Camera**: self-timer choice; shutter sound; WebM/H.264-MP4 choice; JPG/PNG
  picture choice; gallery delete.
- **Voice Recorder**: Opus/FLAC + mono/stereo; sequential names and durations;
  cancel/discard; export; in-app playback.
- **Video Trimmer**: frame-step and I/O/S shortcuts; capture frame; progress
  and cancel; multi-segment cut-and-join.
- **Translate**: source language + swap; endpoint status; file/HTML; batch mode.
- **Weather**: multiple locations + search; dayparts; 7/10/14/16-day forecasts.
- **Settings**: removable-media defaults; DNS search domains; WWAN GB cap.
- **Processes**: click-to-sort; load/swap/PSI meters; details dialog + renice;
  Users view.
- **Software**: ODRS ratings/reviews; featured picks; version history; EOL
  warning; add-ons; repository management.
- **Terminal**: `-L/-R/-D` tunnels; hosts import/export; advanced options;
  recents/status.
- **Disks**: allocation bar; detailed SMART + self-tests; job progress/cancel;
  mount options; benchmark; take-ownership.
- Integration fixes from this pass: `shani-pkgbuilds` commit `c692899` added
  `picocom` and `smartmontools` as PKGBUILD optdepends and added `chown` and
  `renice` to `tools/program-packages.tsv`; commit `c692899` also repinned
  `shani-shell/PKGBUILD` to this work (`pkgrel=40`). Three new settings keys
  were declared and the tray-overflow row got a keyboard path.

### Fourth-pass research — new gaps (all **[open]** unless marked)

Four new audits covered ground no earlier pass touched. Static verdicts only.

#### Cross-app integration and data portability

- **[open]** `mailto:` has no handler: `dev.shani.Mail.desktop` has an empty
  MIME list (`bin/shani:524-525`) and the niri skel sets no default, so XF86Mail
  falls to a browser. Register `x-scheme-handler/mailto` + `message/rfc822`.
- **[open]** The share sheet (`Services/Share.qml:20-35`) has no targets into
  our own apps; Photos has no share action at all. Add Notes/Photos/Editor
  targets and a Photos context action.
- **[open]** "Copy path" copies plain text, not `text/uri-list`
  (`Viewer.qml:287`, `TerminalAppWindow.qml:328`), so it cannot be pasted as a
  file. Mail compose, Text Editor and Photos have no inbound drop targets
  (`Common/DropZone.qml` and `Modules/Files/FileDropArea.qml` are reusable).
- **[open]** Our apps never write to `recently-used.xbel`; Launcher recents are
  one-way from GTK apps. Calendar has ICS import but no export. Notes `.md`
  and Contacts `.vcf` have no default associations in the niri image.
- **[open]** `geo:`, `web+*`, `obsidian://` and `file://` have no registration
  or dispatch policy. Desktop entries emit no `Actions=`, so right-click
  desktop actions cannot exist.
- **[open]** No portable data bundle ("take my data to another OS"): Backup is
  local snapshots, and Photos/Mail/Passwords have no export UI.
- **[open]** Mail cannot attach a file — `send()` takes no file list and
  Share's "Email" target shells out to `xdg-email`, bypassing our Mail.
- **[open]** Our portal backend implements only FileChooser; Email/Share/
  SendFiles intents from Flatpaks bypass the shell. Rich-text and file-URI
  clipboard formats are dropped on history replay.
- **[open]** No notification→file affordance (`x-file` hints); portal/share
  handoffs call `Ui.closeAll()` and discard the person's surface; Files
  bookmarks have no import/export; no shared cross-app session document
  registry; skel default-app lists drift across editions.
- **[stale]** "Files can't drag files out to other apps" in the first list is
  false — `FilesPanel.qml:863,985,1197` does drag out.

#### Multi-user, family, guest and enterprise/MDM

- **[already built]** per-user settings and screen-time data, app blocking via
  malcontent, guest on/off, usershares, a current-grants privacy dashboard,
  and a fleet agent with inventory and signed remote exec.
- **[open]** Screen time is advisory only — no enforced per-app or daily caps;
  no bedtime/downtime schedule; no weekly/monthly report or export; the
  parental filter is set outside the shell; no approval/ask-a-parent flow; no
  per-user web/content filtering; no privacy access *timeline*; no bulk
  revoke or app-data deletion; no "why does this app need X?" rationale; no
  simplified/caregiver mode; guest has no rules; no kiosk/single-app mode; no
  settings-profile copy between accounts; no child-visible weekly digest.
- **[needs server/daemon]** MDM enrolment and policy plane, remote
  wipe/lock, signed configuration profiles, per-user certificate/identity
  management, enforced (signed) settings, a trustworthy access log,
  cross-account parental supervision, guided access/switch control, a family
  account layer (CalDAV/CardDAV/IMAP services), and an enterprise inventory
  surface in Settings › About.

#### Hardware and peripheral depth

- **[open]** Bluetooth codec choice (LDAC/aptX/AAC/SBC) — no
  `org.bluez.MediaTransport1` reference exists; USB device blocking (no
  usbguard); general key remapping/layers (only xkb options today); camera
  hardware privacy switch state (currently inferred from a kernel module);
  camera focus/exposure/zoom controls; microphone AGC/gain; audio loopback;
  per-app power profiles; thermal sensor depth; EDID/panel info; extended
  printer options; Thunderbolt enrolled-device management; UPS depth (one UPS,
  six variables, no graceful shutdown); per-sink audio delay; sound-theme
  choice; named multi-monitor arrangement profiles.
- **[partly out of scope]** per-app camera/mic permission for native apps
  needs a PipeWire policy hook. **[out of scope]** virtual displays,
  overscan, libinput accel threshold, fan curves, USB gadget modes, and
  per-output HDR/gamma/colour filters are compositor, kernel or firmware work.

All fourth-pass verdicts are static — no QML runtime, hardware, Flatpak portal,
BlueZ/bolt/usbguard daemons or real disks were available in this container.

## Fifth-pass research (Nov 2026) — reliability, resilience, UX depth

Seven more read-only audits covered concerns no earlier pass examined. All
verdicts are **[open]** unless noted, all static (no runtime, hardware or
network blackhole tests). Lines are from the tree at commit `4772748`.

### Reliability and data integrity

- **[high]** Deterministic temp filenames defeat atomicity under concurrency:
  `feeds.json.tmp` (`bridge/feeds.py:72`), `conf.json.tmp` (`mail.py:67`),
  `appstore-index.json.part` (`appstore.py:216`), `starred.tmp` (`files.py:799`),
  `library.json.tmp` (`music-library.py:164,221`), `translate.py:185`,
  `copyjob.py:91`, `u2f.py:65`. A refresh timer and a user action racing can
  interleave writes and corrupt the JSON, which is then silently reset.
  Use `tempfile.mkstemp(dir=path.parent)` as `pdfform.py`/`note-crypto.py` do.
- **[high]** `bridge/files.py:1684` writes bookmarks with a direct `open("w")`,
  truncating before the new content is written — a crash or ENOSPC leaves an
  empty file. AppImage `.desktop` entries have the same issue (`appstore.py:599`).
- **[high]** `Services/TerminalApp.qml` uses one shared `cbStore`/`testProc` for
  Test Connection; two quick clicks strand one callback. `QuickNotes.qml` uses
  one crypto Process with four shared mutable fields (`mode`, `pendingPass`,
  `newName`, `payload`) — an autosave racing a lock can apply the wrong mode.
- **[high]** `Services/Keyring.qml:26-33` still hides write failures with
  `|| true` — the same class that caused "AI keys never stored". A locked
  keyring or full disk silently loses the secret.
- **[high]** `bridge/lock.py` has no timeout on three of four gpg calls
  (`:139,146,235`) and a 3600 s "timeout" on the fourth; a blocked pinentry
  hangs the Files bridge forever. `convert.py` conversions have no timeout or
  SIGTERM cleanup, and QML `Process` has no watchdog (bsdtar, pdftoppm,
  wf-recorder, libcamera can leave the UI stuck).
- **[high]** `nearby.py` receive leaves `.part` files with no startup sweep or
  resume after a crash; `clipboard-crypto.py` can leave a plaintext
  `*.db.wrap` symlink after SIGKILL; conversions/transfers accumulate `.part`
  files across crashes.
- **[high]** Voice Recorder takes are lost on an ungraceful SIGTERM/logout —
  only the SIGINT path finalizes the Opus file (`VoiceRecorder.qml:90-105`).
- **[med]** Disk-full errors are hidden: `feeds.py`/`mail.py` never check the
  write result and the UI reports success. Caches keyed only by path+mtime
  (`appstore.py:206`, `music-library.py:145`, `files.py:960`) can serve stale
  data. `Tasks.qml:75-86` assigns `JSON.parse` output with no type check, so a
  `{}` breaks every delegate. `files.py:1672` re-records IPC paths without
  rejecting newlines or `..`.

### Offline and network resilience

- **[high, shell-fixable]** Proxy settings never reach running bridges —
  `Proxy.qml` writes gsettings + an environment.d file for *next login*, while
  bridges inherit the shell's startup env; SOCKS mode sets no `ALL_PROXY`.
- **[high]** `bridge/mail.py` IMAP calls have no timeout at all (`:376-382`);
  `Updates.qml:66-69` has no timeout/re-entrancy guard, so one hung
  `shani-deploy --status --check` wedges all future checks; `fwupdmgr` likewise.
  Translate interactive requests inherit a 300 s timeout meant for batches.
- **[high]** Captive-portal detection exists (`Net.qml:22-40`) but apps emit
  generic "could not reach" errors; Weather keeps stale values with no "as of"
  label, Feeds stores `fetched` but never shows it, Radio wipes its station
  list on any error, Mail makes no offline/empty distinction.
- **[med]** No 429/503 handling on geocoding/OSRM (`curl -sf` collapses it into
  a generic error); Feeds retry has no backoff; multi-GB model/pull and Flatpak
  installs run on metered connections; Flathub streams have no timeout.
- **[daemon-level]** Landline SIP TLS disables verification and read timeouts
  (`shani-link/.../ua.py:186-193`); deploy retries use fixed delays and honour
  no proxy.

**Already good:** Chronoa cloud LLM has exponential backoff with jitter and
429/503 classification; most API probes have bounded timeouts; Screenshot OCR
is fully local.

### Search and navigation depth

- **[high]** Feeds and Mail are invisible to the launcher's global search
  (`Launcher.qml:370-489`); contact search covers only name/phone/email, event
  search is title-only, and content search hardcodes folders instead of using
  `Settings.data.searchFolders`.
- **[high]** `>` is a raw `sh -c` runner, not a command palette — no fuzzy
  command list, descriptions, recent commands or argument completion.
- **[high]** Matches are never highlighted in launcher results despite
  `Common/HighlightText.qml` existing; no saved/recent searches anywhere.
- **[med]** Launcher category chips disappear once a query is typed (keyboard
  users lose filtering); Escape closes rather than unwinds search; no shared
  document MRU; no focus-last-workspace keybinding (`session.kdl:260-274`);
  no named-workspace-by-name navigation; scratchpads have no cycle/list.
- **[med]** Chronoa handoff from a launcher result passes only the query or a
  file path — the selected contact/event/note's identity is discarded.

### Theming and visual customization depth

**Correction:** automatic dark schedules (time-of-day *and* sunrise/sunset)
already exist in `Appearance.qml:28-73` — not a gap.
- **[high]** Font hinting/antialiasing is hardcoded (`Appearance.qml:130`);
  no independent lock-screen wallpaper; accent is one global token with fixed
  alphas and no per-surface control; bar height/opacity are constants.
- **[med]** No online wallpaper sources or transition choice; slideshow/live
  wallpaper are global while still wallpapers are per-monitor; bar widgets can
  be toggled but not reordered (control-centre tiles can); icon/cursor themes
  have no preview and require restart; no theme export/import; focus ring is a
  fixed `#ff7f50` in `session.kdl` rather than bound to `Theme.accent`; no
  window-border toggle; matugen templates are hardcoded to one GTK template;
  no wallpaper-specific day/night schedule independent of appearance; font
  sizes fixed 10–14 with no font install, no compact/dense bar mode.
- **[out of scope]** server-side titlebars, per-window transparency, colour
  filters/gamma/HDR, pointer effects.

### Performance and scalability

Measured: 348 QML files, 143 services, 75 bridges, 191 Timers (54 repeating),
86 `running: true` bindings (72 eager Processes), 64 ListViews (16 without
`reuseItems`/`cacheBuffer`), 473 Repeaters, 272 `execDetached` calls.
- **[high]** Viewer thumbnail strip decodes every image at full resolution with
  no `sourceSize`/`asynchronous` (`Viewer.qml:494-510`); its main image is a
  synchronous uncapped decode (`:92-104`); wallpaper preview likewise.
- **[high]** Launcher instantiates the whole app grid via `Repeater` rather
  than a recycling `GridView`; 18 ListViews have no `reuseItems`/`cacheBuffer`;
  live notifications are unbounded; Feeds read-state map and Photos metadata
  never prune deleted items.
- **[med]** 72 eager Processes at startup, ~40 of them one-shot `command -v`
  probes; Photos re-walks Pictures on every open; Music library re-walks on
  every open; a 10 s `/proc/*/fd` polling fallback in `Privacy.qml:42`; one
  `wtype` process per OSK keystroke; two always-on 10-minute timers in Tasks
  and Agenda.
- **[med]** `dev/shell-test.sh` has real budgets but no large-data fixture and
  a 30 s idle window that cannot catch 10-minute timers.

**Already good:** `Common/Proc.qml` debounces and times out; `Files.qml` uses one
persistent worker with a watchdog; process/stats polling is gated on visibility;
app windows are LazyLoaded.

### Input methods and multilingual text entry

Handwriting is genuinely implemented (`WritePad.qml`, `bridge/handwriting.py`).
- **[high]** Plain TextFields have no undo/redo; OSK has no emoji page (the
  launcher's picker covers it) and no swipe typing; paste, held-key repeat and
  one-handed mode are built in wave 4 (`test_osk_extras.py`); no IME
  preedit/candidate integration (fcitx5 draws its own window unpositioned);
  Indic handwriting silently degrades to English OCR and only
  `tesseract-data-eng` ships.
- **[med]** No long-press accent popups; pre-desktop keyboard is Latin-only;
  voice typing is tap-to-toggle with no push-to-talk; no spellcheck, password
  autofill, autocapitalize hints, deterministic text expansion or per-app IME
  profiles. (One-handed OSK mode, paste and repeat are built in wave 4.)
- **[low]** Mixed-script font fallback relies on fontconfig but has no render
  test; switch access is absent (eye/head pointer are compositor-level).

### Notification and alerting depth

- **[high]** The `resident` hint is ignored so persistent popups auto-expire;
  low-battery (15%) and peripheral alerts are normal urgency and get suppressed
  by DND while only the 7% warning is critical; no call/message or repeat-caller
  DND exceptions; snooze is relative-only, loses actions/urgency, has no list
  UI and re-delivers up to 20 s late after boot.
- **[high]** No per-app sounds/volume/vibrate, no escalation, no unified silent
  gate across sound/flash/speech, no storm coalescing. Lock-screen
  notifications are inert `Text` rather than actionable `NotificationCard`s.
- **[med]** Any app can self-declare urgency 2 and bypass DND, rules and
  silent-apps; DND `dndUntil` bypassed by automations; history capped at 50 with
  no export/TTL; Backup/PdfSigner/VoiceRecorder/Camera completion notices have
  no "open result" action.

### Test and docs consistency after the mass pass (audit findings, fixed)

- **[fixed]** The `shani-shell` PKGBUILD was 9 commits behind and would have
  installed a package with none of the new features — repinned to `4772748`,
  `pkgrel=40`. Added deps `picocom`, `smartmontools` to the PKGBUILD and `chown`,
  `renice` to the dependency map in `c692899`.
- **[fixed]** 77 stale `[open]` markers in the earlier catalogues were flipped
  to `[built — mass pass]`; the integration/deps note was corrected.
- **[open]** 11 of 21 `test_gap_*.py` files are pure source-string assertions
  that cannot catch runtime breakage; the counts in README/FEATURES were
  updated from 700+ to 800+, but `hi.json`/`mr.json` remain at 1525 keys while
  `template.json` grew to 3699 — 242 new strings ship English-only.
- **[open]** `data/whats-new.md` and the FEATURES/README app catalogue have not
  been updated with the mass-pass capabilities.
- **[open]** No test asserts the PKGBUILD pin tracks shani-shell HEAD, and no
  test checks translation-catalog parity. Podcast enclosures are metadata +
  an open link, not a download queue (the earlier GAPS claim was overstated).

All fifth-pass verdicts are static — no QML runtime, hardware, hung-process,
blackholed-network or real-package-install verification was possible.

## Sixth-pass research (Nov 2026) — AI, automations, windowing, docs, security, installer

Seven more read-only audits. All findings are **[open]** unless marked, all
static (no QML runtime, hardware, PAM/polkit, TPM/MOK or network capture).

### AI / Chronoa integration depth

- **[security bug, open]** `ChronoaPanel.qml:201-214` forwards `options[0]` for
  any unrecognised approval decision, so a scripted `approve "deny"` can grant
  "Allow this once" — exactly what its own comment warns against. Match
  `deny`/`always` semantically and never default to the allow option.
- **[open]** No conversation history / new / switch / delete in the panel
  (the backend already has the D-Bus actions). Cloud fallback is invisible in
  the Island; tool-choice events are dropped; replies are plain text with no
  Markdown, copy or regenerate; suggested prompts are four static chips.
- **[open]** Window context is only a title string; no per-turn local/cloud or
  model switch; panel state labels ship untranslated; no voice wake / barge-in
  / cloud-fallback switches or push-to-talk in the shell (backend actions exist);
  approvals have no audit trail or per-app "always" granularity; no shell-side
  privacy/memory controls; no streaming cancel (the Agent contract has no
  Cancel action).
- **[needs backend]** persistent screen/camera context, shell-app tool/prompt
  registration, per-app data-access provenance, live model registry, voice/style
  controls, multi-session and cross-device continuity.

### Automations, hooks and routines

- **[open]** Captured special keys (F1–F12, Space, arrows) are silently
  discarded by the `^[A-Za-z0-9+_]+$` filter in `InputConfig.qml:146`.
- **[open]** No way to fire a rule manually; trigger vocabulary is only 5 items
  (wifi/power/output/displays/time) and action vocabulary 6 (focus/dnd/volume/
  style/open/run); rule failures are invisible; no loop or rate guard (a rule
  can reverse its own trigger and ping-pong forever).
- **[open]** Five unrelated "when X then Y" systems (shell rules, shell hooks,
  keybinds, Chronoa event rules, Chronoa phrase routines) with separate stores,
  UIs and logs; no templates, import/export or sharing; no dry-run or undo.
- **[open]** `notificationRules` is a declared-but-unused setting; GUI caps at
  3 screens and 6 volumes; hooks share one global on/off; user `sh -c` scripts
  are unpermissioned and unbounded; time rules are daily-only with no weekday,
  one-shot, sunrise/sunset or timezone.
- **[open]** Chronoa routines are phrase-only, not scene/schedule-driven;
  percept rules have no unattended product caller; event-rule authoring is
  skill-driven, not a GUI.
- **Risk:** widening trigger sources widens an already-unpermissioned `sh -c`
  execution path — failure reporting and loop guards should land first.

### Window management / niri depth

- **[open]** Column swap (as opposed to window swap) is absent from the UI;
  fullscreen/float menu labels never reflect current state; force-kill works only
  on the focused window; no create/delete workspace action; overview search
  discards its context; urgency is shown but never acted on (no "focus urgent").
- **[open]** Edge swipes are four hard-coded actions with no per-edge assignment;
  no workspace-level drag reorder; "move to monitor" only targets the *next*
  monitor; resize is percentage-only; floating-workspace key is not
  monitor-namespaced (named workspaces on two monitors collide); session restore
  brings back app identities, not layout/geometry/monitor placement; no
  focus-stealing policy; swap-monitors only swaps the active workspaces.
- **[open]** No monitor-hotplug workspace placement restore; no niri crash-recovery
  UX (reconnect after 1.5 s but no banner or config check).
- **[out of scope]** trackpad gestures (compositor-owned), always-on-top, Activities
  / workspace-set abstraction, per-window thumbnails in the switcher.

### User documentation accuracy

- **[fixed]** The generated HTML stubs for overview, FAQ and troubleshooting were
  from 2026-11-01 while the markdown was from 2026-11-22 — they omitted the whole
  app section, the new Q&As and the new troubleshooting entries, showed
  "Updated 2026-08-28" and the old provider list. Regenerated with
  `node generate-manifest.js`.
- **[fixed]** Five intro/FAQ files still said COSMIC was "announced"/"upcoming"
  although it builds today; corrected. The app name "Translator" was corrected
  to "Translate".
- **[fixed]** Added a "A shell app says a tool is missing" troubleshooting table
  (smartctl, picocom, llama-server, at-spi2-core, rclone, GeoClue) and extended
  `shani-doctor.py` to check those tools. Added a "Recent refinements" section to
  `shani-docs/docs/overview.md` for the mass-pass features.

### Security and privacy depth

- **[critical, documented elsewhere]** MOK private key shipped inside the base
  image and two real keys still in git history (`shani-install-media/SECURITY.md`,
  `AUDIT-HISTORY.md`) — rotate and rewrite history (human decision). Podman
  builds set `SigLevel = Never` and the AMI path soft-fails verification.
- **[high]** The 45 s clipboard clear covers only 1 of ~25 copy paths; 6-digit
  OTPs are admitted to cliphist; phone-share leaks the clipboard with no confirm;
  suspend can happen unlocked (toggleable); the "notification previews" toggle
  also governs agenda and media titles; no audit trail of unlocks, grants, admin
  actions or deletes; polkit `caller()` silently passes when `PKEXEC_UID` is unset.
- **[high]** `settings.json` is 0644 and holds pinned clipboard text and server
  URLs; clipboard encryption is off by default; no per-item recent-list removal;
  Flatpak `.flatpakref` installs from arbitrary URLs without showing the remote;
  AppImage files get `chmod +x` with no signature/hash check; no per-request
  consent for cloud LLM calls.
- **[med]** Camera kill switch unloads only `uvcvideo`; no DoH/DoT option; no
  WebRTC leak protection; no TPM/Secure Boot state or stale-seal warning in the
  shell; voice recordings, transcripts and call logs have no retention control.
- **Deliberate win, not a gap:** no diagnostic log upload and "Nothing is sent"
  in About — keep it opt-in if ever added.

### Installer / upgrade / recovery UX

- **[open, shell-fixable]** Failed updates show a toast with no cause or retry;
  pending reboot cannot be deferred; no update history on the Updates page; no
  support bundle at the point of failure; no "last checked" time; health results
  are text-only with no remediation actions; setup failure is a raw error string
  with no retry; no Wi-Fi-only/metered warning before a multi-GB update; channel
  switch has no explanation; Boot & Recovery is read-only; two divergent health
  systems exist; Settings › About has no in-OS recovery entry.
- **[open, installer/daemon]** No basic-graphics/safe-mode boot entry on the
  installed system; image size/ETA not in the deploy JSON; health recommendations
  not in JSON so the UI cannot render actions; no "reinstall keeping files";
  restoring an older snapshot is manual btrfs; failed-install help button is dead
  (no browser on the live ISO); encryption choice and recovery key are not
  explained at install; metered enforcement needs the daemon.
- **Deliberate win:** no log-upload consent flow exists — report as a privacy win.

### Specialized subsystems

- **Printing — [open]** ink/supply levels, scan-to destinations, a real print
  dialog (copies/page-range/duplex/preview), in-shell job queue with cancel/hold,
  printer-state alerts. Driverless setup, default printer and defaults already
  exist.
- **Fonts system — [open]** hinting/antialiasing UI, font DPI control, font
  uninstall, cache refresh watcher.
- **Gamescope console — [open]** MangoHUD overlay control, per-game TDP/frame-cap
  profiles, in-game screenshot/recording hotkeys, controller-remap and fan-curve
  tiles. A full gamescope session already ships in a separate package.
- **Casting — [open]** cast session state/sink list/stop control, mirror-area
  choice (currently `--fullscreen`), audio routing with a cast.
- **Time/date — [open]** NTP server configuration, sync status/source readout,
  dual-boot RTC mode, timezone-change feedback. The settings UI is otherwise solid.
- **Freedesktop compliance — [open]** cross-volume trash restore, recent-files
  destruction by `Housekeeping.qml` (truncates every app's recents daily),
  thumbnail metadata and cache bound, more thumbnail sizes.

All sixth-pass verdicts are static — no runtime, hardware, PAM/polkit, TPM/MOK,
printer, gamescope or live deploy verification was possible.

## Seventh-pass research (Nov 2026) — formats, locales, a11y by disability, web, sandbox, help

Seven more read-only audits. All findings are **[open]** unless marked, all
static (no QML runtime, hardware, real browser/Flatpak, braille/Orca or live
format samples).

### Regional and locale formats (beyond translated words)

**Core finding:** `Common/Tr.qml` follows `locale.conf` live for *words*, but no
`QLocale.setDefault` and no locale argument to `Qt.formatDate`/`Qt.formatTime`
exists anywhere in the tree. The locale preview in Settings promises grouped,
locale-ordered output no app actually renders.

- **[high]** Dates ignore QLocale across Files, Feeds, Mail, Calendar, Backup and
  QuickLook; the `use24h` setting is honoured in only 3 of 12 surfaces; hardcoded
  English weekday/month arrays in Weather, DatePicker and both calendars; fixed
  day-first order where en-US expects month-first.
- **[high]** File sizes divide by 1024 but print KB/MB/GB (should be KiB/MiB/GiB);
  no number grouping, Indian digit grouping (`१,०००` / `1,00,000`) or Devanagari
  numerals; AM/PM missing entirely in three clocks, so 12-hour time is ambiguous.
- **[med]** First day of week is monday|sunday only, not locale-derived; ISO week
  numbering hardcoded; Weather's imperial toggle changes temperature only
  (wind stays km/h, distance km); Maps distance always metric; no real currency
  conversion (the `100 USD in INR` case is handed to the LLM); collation is
  codepoint/lowercase, wrong for Indic/accented names; locale formats written to
  LC_* at setup are never consumed by QML; first-boot sets LANG only; no
  alternate calendars (Vikram Samvat/Hijri); percent spacing hardcoded.

### File-format compatibility matrix

**Core finding:** the real format matrix is three dependencies (`kimageformats`,
`qt6-multimedia-ffmpeg`, `pymupdf`+`libarchive`) wrapped in a 130-entry MIME list
that is asserted, never measured.

- **[high]** Text Editor ships zero `.tmLanguage` grammars (all files fall back to
  the regex highlighter); UTF-16/32 files are classified "binary" by `grep -qI`
  before the BOM-aware reader can see them.
- **[high]** Viewer's next/prev list accepts only 13 image extensions while the
  app claims JXL/PSD/TGA/EXR/etc. that `kimageformats` can decode; Photos grid
  omits HEIC/raw though its importer accepts HEIC; QuickLook's format table lags
  every app; RPM is offered in the Archive picker but has no reader.
- **[med]** OPML round-trip destroys feed categories (tags are first-class but
  export only writes `text`/`title`/`xmlUrl`); Office documents have no shell path
  (OnlyOffice Flatpak); Mail cannot open local `.eml`/mbox/Maildir/MSG; Media
  Player claims ~130 MIME types with no capability probe; Converter's input and
  output codecs are much narrower than the player's (no HEVC/AV1/10-bit); DjVu/PS
  defaults depend on optional tools; Calendar imports only VEVENT, dropping
  VTODO/VJOURNAL; multipage TIFF shows only page one; e-book conversion has no
  test; QuickLook treats any small extensionless file as text; Archive creates
  only 4 formats while reading 20.
- **Cheapest systemic fix:** one startup capability probe filtering `MimeType=`
  claims against what installed decoders actually report. Flatpak fallbacks exist
  for most items.

### Accessibility by disability group

**Correction:** Flatseal-style per-app permission editing *is* built
(`SettingsAppPermissions.qml`, `bridge/flatperm.py`) — do not re-file that gap.
- **[high]** High contrast stops at the shell (GTK apps stay on `adw-gtk3`);
  flash alerts die at the lock screen, so a deaf user gets no call visual; the
  braille stack (`brltty`/`espeakup`) is installed but no service is enabled;
  TTS has no voice/language/pitch choice; voice typing transcribes but cannot
  act as voice control; no switch access (gamepad navigation is the closest).
- **[med]** Orca is fire-and-forget (no AT-SPI env assertion or preferences
  entry); captions have no call source or speaker labels; non-visual
  notifications speak title only and are inert; magnifier follows the pointer
  only, not keyboard focus; no simple/essential mode, reading assistance,
  dictation language picker, AD-track identification, distraction-free beyond
  notifications, or global "always show labels".
- **[out of scope]** colour filters/HDR/gamma (niri), dwell/eye-pointer (no
  pointer position for layer-shell), Sticky/Slow/Bounce Keys (compositor), and
  native Wayland Qt 6/Chromium AT-SPI menus (no appmenu protocol).

### Browser and web integration

**Consistent:** skel `mimeapps.list` maps all web types to Vivaldi; Settings can
change the browser. The edges are broken:
- **[high]** Web Apps never open in app mode — `WebApps.qml:92` generates `Exec`
  lines looking for host browser binaries (`chromium`, `vivaldi`, …), but the
  image has none (Vivaldi is Flatpak-only), so every entry falls to `xdg-open`
  and loses `--app=`/`--class`/`--name`; changing the default browser in Settings
  updates only 3 types while ~15 other web types stay Vivaldi; XF86WWW uses
  `xdg-settings` (unreliable per the shell's own comment) while Settings uses
  `gio mime`.
- **[med]** No favicon fetch for web apps; "Open containing folder" has no
  `org.freedesktop.FileManager1` implementor (niri ships no Nautilus); web apps
  cannot be URL handlers/share targets; no password/autofill bridge; no tab
  handoff to the phone; no download layer (XDG dir, notifications, meter scan);
  no isolated per-app profile; no `x-www-browser` provider.
- **[browser-level]** no image-wide Vivaldi privacy policy, independent password
  store, and no shell page for browser version/permissions.

### App permissions and sandboxing

- **[fixable, security-relevant]** Microphone grant cannot be edited —
  `flatperm.py:35-37` PORTALS map omits microphone although `SettingsPrivacy.qml`
  knows it. Software's app page is read-only and never links to the permission
  editor. `--user` Flatpak overrides are applied to `--system`-installed apps
  (needs real-system verification). Parental blocking is checked in the UI only
  (`Launcher`/`Dock`/`TvHome`), not in `bridge/launch-app.py`, so terminal and
  autostart can run blocked apps. Persistent (AppData) folders and D-Bus
  *own-name* are parsed but not exposed; the `devel` toggle has no warning; no
  developer-mode gate for sideloading; no restart prompt after a permission
  change.
- **[needs daemon/AppArmor]** no confinement for shell-launched apps or bridges
  (`systemd-run --scope` is cgroup lifetime only); one shell app can read
  another's data (Notes plaintext, Contacts vCards, Calendar EDS); AppImages run
  with full privilege; Studio-generated apps are unconfined; first-use prompts
  are entirely external; USB permission is one coarse switch; firewall is not
  per-application.

### Onboarding, tutorials and in-app help

- **[high]** No per-app Help/"?" button in any of the 52 apps (`AppWindow` has
  only tools + window controls; no F1 handler); no link from the shell to the
  docs site (`docs.shani.dev`); `SwitchRow`'s "explain why" `info` property is
  set on exactly 1 of 28 uses and is hover-only (no AT-SPI/keyboard path).
- **[med]** Shortcut list cannot be printed/exported or grouped by scope;
  existing niri shortcuts cannot be rebound from the shell; a bare `?` in the
  launcher means "ask Chronoa", not help; no progressive onboarding checklist
  (only three first-use flags); empty states often give no next step; no app
  "What is this?" mode; tooltips say WHAT not WHY; setup has no help path;
  capture tools have no in-place key list; the static niri hotkey overlay
  bypasses the shell's own searchable shortcut list; launcher help actions are
  never contextual.

### Other desktops and OS migration

- **[feasible]** Unity-style HUD over app-menu actions; named panel profiles;
  desktop right-click menu; A–Z app-grid scrubber; launcher "Today" service
  cards; "make it look like Windows/macOS" presets; interactive shortcut cheat
  sheet; auto workspace-per-app; multiple independent panels; ten-foot mode.
- **[feasible migration]** browser bookmark import (HTML/`places.sqlite`),
  password import (Chrome CSV/KeePass/Bitwarden), mail import (mbox/maildir;
  PST via libpst), a first-run migration step in Setup, guided Windows-drive
  import with ownership fixups, BitLocker status/recovery-key UI, Android
  restore via ADB, macOS shortcut muscle-memory mode, in-shell "what replaces
  Photoshop/Excel/Outlook?" helper.
- **[out of scope]** APFS/Time Machine and iMessage/WhatsApp backup restore
  (proprietary/encrypted), HarmonyOS handoff (server), always-on ambient
  cards (hardware).

All seventh-pass verdicts are static — no runtime, hardware, real browser/Flatpak,
braille/Orca, installed image or live format samples were available.

## CuboCore-inspired pass (Nov 2026) — built, with tests

Waves 1–3 borrowed ideas from the CuboCore / C-Suite desktop suite. Everything
below is in the tree and has an assert-based test; the named test files were run
together on 2026-11-24 (148 passed). They pin source wiring and bridge logic
(some with real temporary files) — not a QML runtime, hardware or installed-image
run. An item being built here is not a claim that its whole upstream equivalent
is covered; every **[open]** item above stays open.

- **Wave 1** (`7351c3d`, `tests/test_cubocore_inspired_ux.py`): Files shortcuts
  (F4 terminal here, Shift+Ctrl+F2 batch rename, view/sort cycle, Ctrl+Return
  open-with, back/up), Text Editor insert date and time, alarm weekday repeat
  and snooze, and severity tints matching the bar chip.
- **PDF facing pages and Viewer** (`4dd5ccb`, `tests/test_pdf_facing_viewer.py`):
  an odd current page pairs with the next, an even page stays in its spread,
  navigation moves on spread boundaries, a missing page image falls back to one
  full-width page, and search highlights map to the right half. Save As names a
  copy and save-page-image survives the spread; the Viewer has an explicit
  full-screen entry and exit. Pages are still rendered PNGs, not reflowed text.
  Per-document bookmarks, an annotations list, navigation history/first-last and
  a print-page range were not part of this pass; wave 4 below now covers them
  with `test_pdf_extras.py`, resolving the inconsistency with the older
  mass-pass list.
- **Terminal close guard** (`147fc38`, `tests/test_terminal_shot_annot.py`): a
  window that launched a session needs a second Esc to close; a passive window
  still closes on the first, and the confirmation disarms on timeout and on hide.
- **System overview strip** (`1c9857a`, `tests/test_monitor_overview.py`): a strip
  above the sparklines using only the existing SysStats — no second poller or
  reader — with theme tokens, accessible names and quick links that each map to
  exactly one existing surface. It adds no new sensor source.
- **Gesture hints** (`c6b0049`, `tests/test_gesture_hints.py`): a one-time hint
  strip under search, dismissed once and remembered, with accessible and
  keyboard-reachable dismissal, badges read from the key delegate, text-scaled
  tokens and compact translated tips; the taught bindings are checked against
  the source. It teaches a few bindings, not a full shortcut sheet.
- **Text Editor font picker** (`8d4ddf6`, `tests/test_editor_font_status.py`):
  a font-family picker over installed system fonts whose choice persists without
  a settings QML key; line/column status is visible. Font size and weight are
  not part of this.
- **Files capacity and search** (`24d5756`, `tests/test_files_places_props.py`;
  `f34d899`, `tests/test_files_power_tools.py`): Properties shows free-of-total
  for a local folder from `files.py free` (an argv-only `statvfs` probe, not
  faked); pseudo-places and remote URIs are refused. Search category chips feed
  backend filters, and history is deduped, capped at 8, persisted and shown as
  suggestions with a clear action. The finer filter popover is built in wave 4
  below (`test_files_filter_popover.py`).
- **Folder-tree export and batch rename** (`f34d899`,
  `tests/test_files_power_tools.py`): the tree command renders an ASCII tree with
  counts, dedupes symlink loops, caps depth and entries, and writes through a save
  picker as a process, not a shell. Batch rename gains case and regex transforms
  in preview and commit, resets the transforms between dialog uses, and its path
  validation message was translated in `d780021`.
- **Archives multi-select** (`ea0ba73`, `tests/test_archives_multiselect.py`):
  checkbox and Ctrl/Shift-click selection, batch extract as a queue with a
  per-entry report (a failure is recorded and the rest still run), a modified
  badge with reload, free-space preflight over the selection, and an unlock path
  that resumes the batch. Deleting a member is still refused without a safe
  backend.
- **Battery time warnings** (`e0942ba`, `tests/test_battery_time_warnings.py`):
  one-shot five-minute and one-minute time-to-empty notices driven by UPower's
  estimate, no new timer, with urgency, re-arming on charge/no-battery/new run,
  jitter suppression and an honest unknown state. No warning is issued on an
  unknown estimate. Needs a real battery — the container has none.
- **Disk I/O** (`48821dc`, `tests/test_disk_io_stats.py`): whole-disk read/write
  rates from `/proc/diskstats` (sector bytes over a measured delta), partitions
  and virtual devices excluded, a gated capacity read for root/home, rates reset
  when nobody wants stats, and Processes plus the desktop widget tint their
  meters. No new poller was added.
- **Sessions** (`af6a982`, `tests/test_sessions_service.py`): named sets of apps
  and documents captured from the shell (not process command lines), restored by
  launching apps and opening paths, persisted in QuickShell state, with a
  Settings page that confirms removal, short validated names and capped
  entry/session counts. Not portable between users.
- **OSK modes** (`b6ec0a4`, `tests/test_osk_modes.py`): compact / fixed size and
  opacity plus opt-in word suggestions (bounded dictionary, prefix match,
  shortest-first, capped, per-word dismissal, a strip above the keys). Wave 4
  below adds one-handed mode, paste and held-key repeat (`test_osk_extras.py`);
  emoji page and swipe typing remain open in the input section above.
- **File facts / rich metadata** (`a434cb2`, `tests/test_filemeta_bridge.py`):
  Quick Look details, media properties reusing the existing probe, `pdfinfo`
  pages and title, optional `exiftool` (absent is fine), argv-only paths, JSON
  instead of a traceback for a bad path, and a save-page image from the rendered
  PNG through a file picker.

Two QA commits are part of this pass: `1afa43e` added
`tests/test_deep_pass_qa.py` regression coverage for the first-wave features and
`1e61f1c` fixed five bugs that sweep found. No new packaging dependency came out
of these bridges: `filemeta.py` guards `ffprobe`/`pdfinfo`/`exiftool` behind
`shutil.which`, the capacity and tree code in `files.py` uses the standard
library, and vnStat belongs to `shani-tools-network` rather than a wave-3 bridge.
The PKGBUILD and program map were therefore left unchanged; this was checked
with `tests/test_declared_deps.py` at committed HEAD. Not covered here: the
`3ede7e6` large-feature/Picasa work or any **[open]** item above.

## Wave 4 (Nov 2026) — built, with tests

Waves 1–3 are recorded above; wave 4 closed the six named surfaces below with
assert-based tests. The six test files were run together on 2026-11-24 (93
passed). They check the shipped QML as source and execute the small predicates
in node or against real temporary files — not a QML runtime, hardware or an
installed-image run. An item being built here is not a claim that its whole
upstream equivalent is covered; every **[open]** item above stays open.

- **Files filter popover** (`tests/test_files_filter_popover.py`): the finer
  filters beside the category chips — type (reusing the chips), date presets,
  size bounds and content vs filename — with an active-count badge, a Clear
  action, a keyboard route and accessible names. The predicate lives in QML;
  content reuses `files.py`'s bounded ripgrep deep search, so no `--after=` /
  `--min-size=` bridge flags were added.
- **PDF bookmarks / history** (`tests/test_pdf_extras.py`): per-document
  bookmarks keyed by content md5 (a rename keeps the marks), a bounded visit
  history with `[` / `]` and First/Last (search jumps are visits), a read-back
  annotation list, and a validated print-page range passed to `lp` as its own
  argument. Print copies and preview stay open.
- **OSK extras** (`5f88648`, `tests/test_osk_extras.py`): paste as one `wtype`
  argv element, held-key repeat (400 ms delay, 80 ms tick, stops on release,
  hide and remote), and one-handed centre/left/right persisted in OSK's own
  JSON. Emoji page and swipe typing stay open — the launcher's picker covers
  emoji.
- **Release notes reader** (`0200288`, `tests/test_release_notes.py`):
  Settings > About hosts a scrollable, accessible reader that parses a plain
  configured path (no shell interpolation), turns headings/bullets into rows,
  splits version sections and accepts only absolute plain paths. CI
  release-note generation and the undated `whats-new.md` content stay open.
- **Clocks** (`tests/test_clocks_wave4.py`): per-alarm sound choice from an
  allowlisted freedesktop hint set sent as one `notify-send` argv item, inline
  alarm rename, and pinned repeat-day / snooze paths; the custom timer,
  city-search, lap and keyboard paths were already covered by
  `test_large_clocks_time_fixes.py`. One-shot alarms, a ringing panel,
  sunrise/sunset and state persistence stay open.
- **Trimmer / Translate polish** (`d79e758`, `tests/test_trimmer_translate_wave4.py`): an
  explicit, non-stale save destination for the Video Trimmer with exact-range
  progress and error states, and on-screen copy confirmation plus preserved
  swap/clear/keyboard routes in Translate.

No new packaging dependency: these surfaces reuse `wtype`, `lp`, `cat`,
`notify-send` and `ffmpeg`, all already in `tools/program-packages.tsv`, and the
Files content filter calls `files.py`'s existing ripgrep/grep fallback. The
program map was left unchanged; `tests/test_declared_deps.py` at the current
HEAD reports only unrelated Camera.qml false positives (`ch`, `crop`, `cw`,
`px`, `sy`) from concurrent work, not real binaries. The i18n catalogs were not
regenerated here: `tests/test_i18n.py` reports 19 wave-4 Files-filter keys
missing from `template.json` (18 in `FilesPanel.qml`, plus the shared
`Filters` key), which belong to the agent that owns those strings.

## Wave 6 (Nov 2026) — built, with tests

The earlier passes are recorded above; wave 6 closed the six named surfaces
below with assert-based tests. The five test files were run together on 2026-11-25 (133
passed, 2 skipped). They check the shipped QML as source, run the small
predicates in node, exercise the stdlib bridges against real temporary files,
and read the persisted caches — not a QML runtime, hardware or installed-image
run. An item being built here is not a claim that its whole upstream equivalent
is covered; every other **[open]** item above stays open.

- **Media Player** (`e83fcc6`, `tests/test_media_wave6.py`): one stream allowlist
  in `PlayQueue` (http/https/rtsp/rtmp/srt/mms, case-insensitive; local paths
  and `javascript:`/`ssh:` refused) shared by the window and the media-info
  probe, an explicit stream-address field, `.m3u` save/load through a stdlib
  bridge that writes standard `#EXTM3U`, resolves relative entries beside the
  playlist and refuses relative/control-character write targets, and a
  persisted, capped (20), deduped recent-media list with a clear action.
  Record/stream output, the 10-band EQ and video effects stay open.
- **Voice Recorder** (`2ad21b7`, `tests/test_recorder_wave6.py`): persistent
  peaks decoded by `bridge/waveform.py` (WAV via the `wave` module, other
  formats via ffmpeg), capped at 256 and cached in a sibling `.peaks.json`
  keyed by path/size/mtime so a changed take cannot borrow a stale waveform;
  the panel draws them as a seekable, named slider with ±5 s keyboard steps.
  Stereo/24-bit downmix and a missing take are exercised. Format choice, skip
  back/forward, name-on-save and ungraceful-exit finalisation stay open.
- **Contacts and Calendar** (`a1c78da`,
  `tests/test_contacts_calendar_wave6.py`): typed phone/email rows in the form
  (home/work/mobile/other), accessible row names, `cell`→mobile normalisation
  and typed arrays forwarded by the service; and a Calendar description field
  with readback that keeps DESCRIPTION on an unrelated edit and ignores a
  VALARM's own description. Manual unlink, avatars/QR export and the
  Calendar's other listed items stay open. Two QA checks in
  `tests/test_wave6_qa.py` skip because the Calendar's
  `Accessible.name: "Event description"` marker has not landed.
- **Photos and Files** (`95d2fa2`, `tests/test_photos_files_wave6.py`): Photos
  multi-select batch ops and sort order now include size, reusing the one
  existing scan; Files breadcrumbs form a prefix chain from Home, cap long
  paths to the first and last three, and reach the split pane with a
  right-click sibling menu. Photos' EXIF panel, ratings/tags, date-subfolder
  import and Files' column chooser stay open.

Two QA commits are part of this pass: `f0c610b` added `tests/test_wave6_qa.py`
regression coverage (67 passed, 2 skipped) pinning two bugs found by the sweep;
`a887879` fixed an album directory, translated new contact/calendar labels and
registered their i18n keys (`d49e2cd` updated one stale test pin). No new
packaging dependency: the new bridges use only the standard library plus
ffmpeg, already in `tools/program-packages.tsv`. At this HEAD
`tests/test_i18n.py` passes 3296 tests (the wave agents regenerated the
catalogs), `tests/test_declared_deps.py` passes 1 and `tests/test_qml_static.py`
passes 2245; no catalog or package file was changed by the docs pass.
