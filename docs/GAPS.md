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
- **Translations**: about 1525 of 3431 catalog strings are translated into
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
- Translations: ~1525/3431 Marathi/Hindi strings done; the rest (newer app windows and settings) are documented above.
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
