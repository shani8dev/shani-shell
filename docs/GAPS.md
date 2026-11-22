# Known gaps

What the ShaniOS niri desktop does not do yet, or does without proof, surface
by surface. An item leaves this file when it is built *and* a test runs it.
Compared against GNOME Settings, KDE System Settings and Deepin's control
centre, and against what a session needs before any app runs.

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
- **Translations**: about 1525 of 3438 catalog strings are translated into
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
- **Document Scanner, Password Generator, Kundali**: they work and take the shell's
  colours, but are laid out with stock controls, not the shell's own widgets.
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
- Translations: ~1525/3438 Marathi/Hindi strings done; the rest (newer app windows and settings) are documented above.
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

- **Weather advisories** — rain, wind and heat read out of the forecast the
  shell already fetches; open-meteo has no warning feed, and these say so.
- **Mail** (Modules/Mail, bridge/mail.py) — IMAP and SMTP for a real account,
  or MailHog's API and SMTP for development. Shows the message as it was sent
  (Qt's TextDocument over a body the bridge has stripped of scripts, remote
  images and event handlers) or as plain text, and searches a word in the
  sender, the subject or the body (IMAP SEARCH, or the reader's own pass over
  MailHog). Attachments are listed with their name, type and size, but not yet
  saved - there is no "save this attachment" anywhere in the reader.
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
- **[open]** Smart indent after `{` and auto-close of `()[]{}""''`.
- **[open]** Regex, case-sensitive and whole-word search with live match highlighting (ours is lowercase `indexOf`).
- **[open]** Quick-open / MRU tab switcher (we have only a tab strip).
- **[open]** Current-line highlight and matching-brace highlight.
- **[open]** Line bookmarks (Ctrl+B, next / previous).
- **[open]** Word and character count in the status bar (only lines today).
- **[open]** Split view of one document, and session restore across restarts (`TextDocs` is memory-only).

### Notes → Joplin

- **[open]** Rendered Markdown preview (raw `TextArea` only; no Markdown renderer in `Common/`).
- **[open]** Trash / restore deleted notes (`remove()` is `rm -f`; no undo).
- **[open]** Version history (each autosave overwrites the file).
- **[open]** Formatting toolbar — bold, italic, heading, link, table, code (only Checklist and Attach today).
- **[open]** Tags with filtering (notebooks + name filter only).
- **[open]** First-class to-dos with due dates (only `- [ ]` checkboxes).
- **[open]** Note previews and sort by updated / created / title (`preview()` exists but is unused).
- **[open]** Browseable body-search results (`searchBodies()` exists but only `results[0]` opens).

### Calendar → GNOME Calendar

- **[fixed]** Editing keeps RRULE, DESCRIPTION, attendees and alarms (the editor previously re-composed the whole VEVENT).
- **[open]** Event description / notes field in the editor and popover; the bridge never reads `DESCRIPTION`.
- **[open]** Click-to-view detail popover before editing (currently opens the edit form directly).
- **[open]** Quick-add natural-language field (`_parseNaturalDateTime()` exists but is only in the full form).
- **[open]** Import `.ics` button (`agenda.py import` and `Agenda.importFile()` exist with no QML caller).
- **[open]** Repeat / end-repeat field for new events (only preservation is fixed).
- **[open]** Per-event reminders / alarms (one hard-coded 10-minute heads-up for all events).
- **[open]** Drag to create / move events in the week and month grids.
- **[open]** Current-time indicator line, and local calendar create / rename / colour.

### Contacts → GNOME Contacts

- **[fixed]** Editing keeps unknown vCard fields — BDAY, ADR, ORG, NOTE, URL were silently destroyed.
- **[open]** Multiple phone numbers and emails with type labels (mobile / home / work); backend handles arrays, UI edits one of each.
- **[open]** Read-only detail sheet with click-to-call, mailto and map rows.
- **[open]** Export / Share as QR (`Qr.show()` already takes arbitrary text).
- **[open]** Editable avatars / photos with crop.
- **[open]** Favorites (the star is used only for "This is me").
- **[open]** Alphabetical index and sort by first name / surname.
- **[open]** Manual link / unlink versus the existing automatic duplicate merge.

### Files → Nautilus

- **[open]** Search filter popover — file type, date preset, size, content vs filename (`files.py --filter=` exists; needs `--after=` / `--min-size=`).
- **[open]** Breadcrumb dropdowns listing sibling folders (crumbs are click-only).
- **[open]** Visible-columns chooser and clickable list headers (fixed Name / Size / Date).
- **[open]** "Select Items Matching…" wildcard select.
- **[open]** Create Link / symlink (Ctrl+M).
- **[open]** Grid caption settings.
- **[open]** Sort by Type / Date Created.
- **[open]** A second Files window (Ctrl+N).

### Photos → gthumb / Loupe

- **[fixed]** Camera / Screenshots filter chips were inert — they now filter by path.
- **[open]** Delete / move to trash from a tile.
- **[open]** Multi-select with batch delete, album add, move / copy.
- **[open]** Sort order control (newest / oldest / name); grid is hardwired `sort -rn`.
- **[open]** Slideshow from the grid (Viewer has one).
- **[open]** EXIF details panel (our `PhotoMeta` reads only Make / Model / Date and is bound to Files' selection).
- **[open]** Ratings and tags persisted per photo.
- **[open]** Import into date-based subfolders and delete from source.

### Viewer / PDF → Evince / Loupe

- **[open]** User bookmarks per document (outline is the PDF's own TOC).
- **[open]** Clickable PDF links — internal GoTo, external URI and email (clicking turns the page).
- **[open]** Embedded attachments sidebar — list / open / save.
- **[open]** Navigation history and First / Last page.
- **[open]** Two-page / facing-pages layout.
- **[open]** Annotations list sidebar (we can draw but not review them).
- **[open]** Search options — case-sensitive / whole word / wrap (always lowercased).
- **[open]** Print page range, copies and preview.

### Mail → Geary

- **[fixed]** Reply and Forward (compose opens prefilled with quoted text). Reply-to-all specifically is not separate.
- **[fixed]** Message date in the list; snippet still not shown.
- **[open]** Cc / Bcc in compose (`send()` takes three arguments).
- **[open]** Save attachments (names only today; bridge must decode the MIME part).
- **[open]** Mark unread / star / move / archive (bridge has `imap_flag` internally, exposes only `markread`).
- **[open]** View source.
- **[open]** Opt-in remote images (the bridge strips all remote content).
- **[open]** Multiple accounts and an account editor.

### Feeds → Newsboat

- **[fixed]** Article summary in the list (data was already in each item).
- **[open]** Next-unread navigation and Mark-all-read.
- **[open]** Tags / categories with a tag filter.
- **[open]** Search / filter articles.
- **[open]** Bookmark / save article for later.
- **[open]** Show-read toggle and sorting.
- **[open]** Feed auto-discovery from a site URL.
- **[open]** Podcast enclosures → download queue.

### Terminal → kitty / SSH managers

- **[fixed]** Test connection button (`testConnection()` existed with no caller).
- **[fixed]** Import key from the UI (`importKey()` existed with no caller).
- **[fixed]** Search / filter hosts by name, address and user.
- **[open]** Remote (`-R`) and dynamic SOCKS (`-D`) tunnels; only local `-L` today.
- **[open]** Import / export the hosts JSON.
- **[open]** Advanced per-host options — ProxyJump, agent forwarding, X11, compression, arbitrary `-o`.
- **[open]** Recents / last-connected and connection status.
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
- **[open]** Ratings / reviews (ODRS) and popularity.
- **[open]** Featured / editorial discovery (Explore starts at a plain category grid).
- **[open]** apt / dpkg / Snap apps alongside Flatpak (OS updates deliberately go to Cassini).
- **[open]** Version history / per-update changelog.
- **[open]** Screenshot gallery and age / content rating (first screenshot only).
- **[open]** Repository / remote management.
- **[open]** Optional add-ons / extensions.

### Processes → htop

- **[fixed]** Search / filter by process name.
- **[open]** Click-to-sort by PID / name / memory / disk (fixed CPU then memory).
- **[open]** Signal choice on kill — TERM / KILL / INT / HUP / STOP / CONT (`end()` hardcodes `-TERM`).
- **[open]** Process details dialog — command line, user, state, threads, open files, environment.
- **[open]** Renice and CPU affinity.
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
- **[open]** Go-to-time dialog and chapter list.
- **[open]** A→B loop.
- **[open]** Video effects — crop, rotate, deinterlace, filters.
- **[open]** Recent media list.
- **[open]** Open a network stream from the UI (`isStream` plays URLs; no field to enter one).
- **[open]** Save / load a playlist (.m3u); the queue is session-only.
- **[open]** Record / stream output.
- Subtitle timing shifts were fixed earlier (`1a55836`); chapters and go-to-time remain.

### Camera → GNOME Snapshot

- **[open]** QR / barcode scan mode (reuse Lens / zbar).
- **[open]** Configurable self-timer (hard-coded 3 seconds).
- **[open]** Composition guidelines grid over the viewfinder.
- **[open]** Shutter sound.
- **[open]** Audio on / off for video (always adds `pulsesrc`).
- **[open]** Hardware encoding / H.264 MP4 option (always VP8 / WebM).
- **[open]** Picture format choice (always PNG).
- **[open]** In-window gallery with photo / video viewer.

### Voice Recorder → GNOME Sound Recorder (Vocalis)

- **[open]** Waveform display — live while recording and seekable during playback.
- **[open]** Format / codec and mono / stereo choice (Opus only, fixed).
- **[open]** Export recording to a chosen file / format.
- **[open]** Skip back / forward during playback.
- **[open]** Friendly sequential names and per-row duration.
- **[open]** Cancel / discard a take.
- **[open]** In-app playback bar (playback is handed to another app today).
- **[open]** Persistent peaks per recording.

### Video Trimmer → LosslessCut

- **[open]** Thumbnail timeline with a scrubbable playhead (offsets are blind numbers).
- **[open]** Multiple segments and merge export (one cut today).
- **[open]** Keyboard shortcuts / frame stepping — I / O at playhead, S split.
- **[open]** Scene / black-frame / silence detection and split.
- **[open]** Smart cut / nearest-keyframe snapping.
- **[open]** Capture frame / snapshot.
- **[open]** Speed change / mute / volume on output.
- **[open]** Remux / format change and track selection.

### Translate → Argos Translate

- **[open]** Source-language pick, auto-detection and swap (target only today).
- **[open]** File / HTML translation.
- **[open]** Model / language-package status and install UI (only error is "The local model is not running").
- **[open]** Pivot translation through an intermediate language.
- **[open]** Batch / string-list translation (`translate.py strings` exists, no UI).
- **[open]** Translation history (low value — Argos keeps none either).

### Weather → GNOME Weather

- **[fixed]** Detailed current conditions — feels like, humidity, wind, pressure, visibility, sunrise and sunset.
- **[fixed]** Rain probability in hourly tiles (data was already fetched, not rendered).
- **[open]** Multiple saved locations and in-app city search (single city today).
- **[open]** Smooth temperature graph over the hourly points.
- **[open]** Morning / afternoon / evening / night breakdown per day.
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
- **[open]** Calendar: description field and readback in `agenda.py`; a
  click-to-view detail popover before editing; per-event timezone (zone chips
  are display-only); repeat / end-repeat UI; per-event VALARMs (one hard-coded
  10-minute notice today); drag to create / move events; current-time line;
  local-calendar create / rename / colour (bridge only reads EDS calendars);
  drag-and-drop `.ics` import with a preview; read-only-calendar banner in the
  editor (`readOnly` is exposed by `agenda.py:122`).
- **[open]** Contacts: multiple typed phones/emails in the form (backend and
  arrays exist); read-only detail sheet with `tel:` / `mailto:` / map rows;
  QR export (`Qr.show()` is ready, needs a `vcard` bridge command); avatars;
  favorites (the star means "This is me"); given/family sort chooser;
  unlink for auto-merged duplicates; export all / export selected; multi-select
  for batch link/delete.

### Files / Photos / PDF / Mail / Feeds — still open

- **[open]** Files: search-filter popover (type/date/size; bridge only has
  `--sort/--filter/--limit/--offset`); breadcrumb dropdowns; visible-column
  chooser and clickable headers; "Select Items Matching…" (the matcher in
  `Common/FileFilter.js` exists, just no action); symlink creation; grid
  caption settings; sort by Type / Date Created.
- **[open]** Photos: multi-select batch ops; sort order (`scan()` is `sort -rn`);
  EXIF panel (bound to Files' selection today); ratings and tags; date-subfolder
  import with delete-from-source.
- **[open]** Viewer/PDF: user bookmarks; clickable PDF links (`get_links()`);
  embedded attachments; history and First/Last page; two-page layout;
  annotations *list* (we create flattened annotations but never read them);
  case/whole-word/wrap search; print range and copies; form radio widgets
  (`pdfform.py` emits `radio`, the reader handles only text/checkbox/choice);
  a UI for the existing `merge()` / `split()`.
- **[open]** Mail: Cc/Bcc; save attachments (names only — payload discarded);
  mark unread / star / move / archive (`imap_flag()` exists, only `markread`
  is exposed); view source; opt-in remote images; multiple accounts;
  conversation threading (`In-Reply-To`/`References` unused); IMAP labels.
- **[open]** Feeds: next-unread navigation; tags/categories; search/filter;
  save article for later; show-read toggle; feed auto-discovery; podcast
  enclosures; query feeds (`query:<name>:<filter>`).

### Terminal / Disks / Software / Processes / Settings — still open

- **[open]** Terminal: remote (`-R`) and dynamic (`-D`) tunnels; import/export
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

- **[open]** Media Player: 10-band EQ and effects; go-to-time and chapters;
  A→B loop; video effects (crop/rotate/deinterlace); recent-media UI (resume
  points are persisted, just not listed); generic "open network stream" field
  (`PlayQueue.playStream()` exists); save `.m3u`; Stop control (MPRIS stop maps
  to pause+seek(0)); MPRIS `HasTrackList` is `False`.
- **[open]** Camera: live QR/barcode scan mode (post-capture Lens path exists);
  self-timer choice (`countdown` is fixed); composition grid; shutter sound;
  H.264/MP4 and hardware encoding; picture format choice; in-window gallery;
  delete from gallery.
- **[open]** Voice Recorder: seekable waveform (live level bar exists, peaks
  are discarded); format / mono-stereo choice; export; skip back/forward;
  sequential names and per-row duration; cancel/discard; in-app playback;
  persistent peaks; name-on-save.
- **[open]** Video Trimmer: thumbnail timeline; multi-segment merge; I/O/S
  shortcuts; scene/black/silence detection; keyframe snapping; capture frame;
  speed/mute/volume; remux and track selection; cancel/progress on a cut.
- **[open]** Translate: source language pick, auto-detect and swap; file/HTML
  translation; model endpoint UI (hard-wired env default); model/package
  status. Pivot and history are out of scope (direct LLM, Argos keeps none).
- **[open]** Weather: multiple saved locations / in-app search; daily/weekly
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
7. **[open]** OSK predictive word suggestions — `Keyboard.qml` has layouts,
   handwriting and voice typing but no candidates.
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
- **[open]** Weekday repeat, one-shot, snooze and sound choice; a ringing panel
  with Dismiss/Snooze (only `notify-send` today); custom timer duration,
  pause/resume, label and multiple timers; per-lap deltas (laps are cumulative
  strings); in-app city search; sunrise/sunset/twilight; state persistence;
  keyboard shortcuts beyond Space.

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
