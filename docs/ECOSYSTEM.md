# The app ecosystem, against the others

What a desktop ships as its own apps, side by side, so a gap is visible
before someone goes looking for an app. Surveyed 2026-11-12 from each
desktop's own app set: GNOME core apps, KDE Gear, Deepin (DDE), Kylin (UKUI),
Cutefish, Budgie, Cinnamon (X-Apps and Mint tools), macOS, Windows (with
PowerToys) and Android (AOSP and Pixel). The Deepin, UKUI and Cutefish columns
were re-read on 2026-11-22 from each project's own repositories — READMEs and,
for the control centres, their plugin/page directories — see
[Deepin, UKUI and Cutefish closely](#deepin-ukui-and-cutefish-closely-2026-11-22).

**Ours** are the shell's apps (`shani app` lists them, `bin/shani`'s `APPS`):
each a window (`Common/AppWindow`), opened in the suite by
`dev/shell-parts/apps.sh` and photographed there. **Image** means another
ShaniOS package (native or a Flatpak of the niri profile) covers it.

| Need | GNOME | KDE | Deepin | Kylin | Cutefish | Cinnamon | macOS | Windows | Android | ShaniOS niri |
|---|---|---|---|---|---|---|---|---|---|---|
| Files | Files | Dolphin | File Manager | Peony | Files | Nemo | Finder | Explorer | Files | **Files** (ours) · Nautilus |
| Text | Text Editor | Kate | Editor | — | Text Editor | Xed | TextEdit | Notepad | — | **Text Editor** |
| Notes | — | KNotes | Voice Notes | Notebook | — | Sticky Notes | Notes, Stickies | Sticky Notes | Keep | **Notes** |
| To-dos | Endeavour | (Merkuro) | — | — | — | — | Reminders | To Do | Tasks | **Tasks** (EDS) |
| Calendar | Calendar | Merkuro | Calendar | Calendar | — | — | Calendar | Calendar | Calendar | **Calendar** |
| Contacts | Contacts | KAddressBook | Contacts | — | — | — | Contacts | People | Contacts | **Contacts** · shani-shell |
| Phone, texts | Calls | KDE Connect | Phone Master | Connectivity | — | — | Phone, Messages | Phone Link | Phone, Messages | shani-shell · Mirror (scrcpy) |
| Mail | Geary | KMail | Mail | — | — | Thunderbird | Mail | Outlook | Gmail | **Mail** (IMAP + SMTP) |
| Browser | Web | Konqueror | Browser | — | — | Firefox | Safari | Edge | Chrome | Vivaldi |
| Office | — | Calligra | — | WPS | — | LibreOffice | Pages… | Office | Docs | ONLYOFFICE |
| Calculator | Calculator | KCalc | Calculator | Calculator | Calculator | — | Calculator | Calculator | Calculator | **Calculator** |
| Clocks, timer | Clocks | KClock | — | — | — | — | Clock | Clock | Clock | **Clocks** |
| Weather | Weather | KWeather | — | Weather | — | — | Weather | Weather | Weather | **Weather** |
| Maps | Maps | Marble | — | — | — | — | Maps | Maps | Maps | **Maps** · GNOME Maps |
| Translate | — | — | — | — | — | — | Translate | — | Translate | **Translate** (local model) |
| Pictures (one) | Image Viewer | Gwenview | Image Viewer | Photo Viewer | — | Xviewer | Preview | Photos | — | **Image Viewer** · Loupe |
| Photo library | Shotwell¹ | digiKam¹ | Album | — | — | Pix | Photos | Photos | Gallery | **Photos** |
| PDF | Papers | Okular | Reader | — | — | Xreader | Preview | Edge | — | **Document Viewer** · Papers |
| Sign / fill a PDF | — | Okular | — | — | — | — | Preview | Edge | — | **PDF Signer** |
| Video, music | Showtime, Decibels | Haruna, Elisa | Movie, Music | Video, Music | — | Celluloid | QuickTime, Music | Media Player | YouTube Music | **Media Player** (MPRIS) · Showtime, Decibels, Gapless |
| Music library | Music | Elisa | Music | Music | — | Rhythmbox | Music | Media Player | — | **Media Player › Library** (albums, artists, songs, videos) |
| Podcasts, radio | Podcasts¹ | Kasts | — | — | — | Hypnotix (TV) | Podcasts | — | — | Shortwave · **Feeds** (RSS/Atom) |
| Camera | Snapshot | Kamoso | Camera | Camera | — | — | Photo Booth | Camera | Camera | **Camera** |
| Sound recorder | Sound Recorder | — | Voice Notes | Recorder | — | — | Voice Memos | Sound Recorder | Recorder | **Voice Recorder** |
| Screenshot | (shell) | Spectacle | Screen Capture | Screenshot | Screenshot | — | Screenshot | Snipping Tool | (system) | **Screenshot** · satty |
| Screen recording | (shell) | Spectacle | Screen Capture | — | — | — | Screenshot | Snipping Tool | (system) | **Screen Recorder** |
| Video trim | — | Kdenlive | — | — | — | — | QuickTime | Clipchamp | Photos | **Video Trimmer** |
| Drawing | — | KolourPaint | Draw | — | — | — | — | Paint | — | Drawing |
| Scanner | Document Scanner | Skanpage | Scanner | Scanner | — | — | Image Capture | Scan | — | **Scanner** |
| Archives | (Files) | Ark | Archive Manager | — | — | File Roller | Archive Utility | (Explorer) | — | **Archive Manager** · File Roller |
| Disk usage | Disk Usage | Filelight | — | — | — | — | Storage | Storage | Storage | **Disk Usage** · Baobab |
| Disks | Disks | Partition Manager | Disk Manager | — | — | — | Disk Utility | Disk Management | — | **Disks** · GNOME Disks |
| Write an image to USB | — | — | Boot Maker | USB Creator | — | USB Image Writer | — | — | — | **Files** (write an image) · Impression |
| Task manager | System Monitor | System Monitor | System Monitor | System Monitor | — | — | Activity Monitor | Task Manager | — | **System Monitor** |
| Logs | Logs | KSystemLog | Log Viewer | Log Viewer | — | — | Console | Event Viewer | — | **Logs** |
| Device info | (Settings) | Info Center | Device Manager | Device Manager | — | System Reports | System Information | System Information | — | Settings › About · Cassini |
| Fonts | Fonts | Font Management | Font Manager | Font Viewer | — | — | Font Book | Fonts | — | **Fonts** · Font Viewer |
| Characters, emoji | Characters | KCharSelect | — | — | — | — | Character Viewer | Character Map | — | **Characters** · launcher ":" |
| Passwords, keys | Passwords and Keys | KWalletManager, Kleopatra | — | GPG | — | — | Passwords | Credential Manager | Passwords | **Passwords** · Seahorse |
| Two-factor codes | Authenticator¹ | Keysmith | — | — | — | — | Passwords | Authenticator | Authenticator | **Authenticator** (keyring) · Cassini for sign-in codes |
| Software | Software | Discover | App Store | Software Center | Store | Software Manager | App Store | Store | Play | GNOME Software · Warehouse |
| Updates | Software | Discover | Update | Updater | Updater | Update Manager | Software Update | Windows Update | System update | Cassini · shani-deploy |
| Backup | Backups¹ | — | Clone | Backup | — | Timeshift | Time Machine | Backup | Backup | shani-backup |
| Send to a nearby device | — | KDE Connect | Cooperation | IP Messenger | — | Warpinator | AirDrop | Nearby Share | Quick Share | **Nearby Share** (LocalSend) · shani-shell (KDE Connect, paired phone) · Bluetooth |
| Remote desktop | Connections | KRDC | — | — | — | — | Screen Sharing | Remote Desktop | — | Connections |
| Virtual machines | Boxes | — | — | — | — | — | — | Hyper-V | — | Boxes |
| Clean up storage | — | Sweeper | System Cleaner (Defender) | OS Manager | — | — | Storage | Disk Cleanup | Files (clean) | **Settings › Storage** (your space) · Cassini Maintenance (the system's) |
| Screen time | (Settings) | — | — | — | — | — | Screen Time | Family | Digital Wellbeing | **Settings › Screen time** |
| Colour picker | — | KColorChooser | Picker | — | — | — | Digital Color Meter | PowerToys | — | **Color Picker** |
| Measure the screen | — | KRuler | — | — | — | — | — | PowerToys | — | **Screen Ruler** |
| Read text off the screen | — | — | OCR | — | — | — | Live Text | PowerToys, Snipping Tool | Lens | **Lens** |
| Magnifier, captions | (a11y) | KMag | — | — | — | — | Zoom, Live Captions | Magnifier, Live captions | Magnifier, Live Caption | **Magnifier**, **Live Captions** |
| Web apps | Web | — | — | — | — | Web App Manager | Safari (Add to Dock) | Edge (Install) | (PWA) | Settings › Web apps |
| Tour, help | Tour, Help | Help Center | Manual | Service & Support | — | Welcome | Tips | Tips, Get Help | Tips | **Tour** |
| Theme | (Settings) | (Settings) | — | — | — | — | — | — | Wallpaper & style | **Settings › Personalisation** (colours from a picture) |

¹ not part of the desktop's own set, but its usual choice.

## Deepin, UKUI and Cutefish closely (2026-11-22)

The three are the desktops this shell borrows its ideas from, so they were read
again at source: each project's README for its apps, and each control centre's
own plugin/page directories for its surface. What follows is what they actually
have, not what a review says they have.

### The control centre, side by side

| Desktop | How it is split | Parts |
|---|---|---|
| **Deepin** (dde-control-center) | 19 plugins | accounts, authentication, bluetooth, commoninfo, datetime, deepinid, defaultapp, display, dock, keyboard, mouse, notification, personalization, power, privacy, sound, systeminfo, touchscreen, wacom |
| **Cutefish** (settings) | 29 pages | about, accounts, appearance, battery, bluetooth, cursortheme, datetime, defaultapps, display, dock, fonts, general, hotcorners, icontheme, input, keyboard, language, menubar, mouse, network, notifications, power, privacy, shortcuts, softwareupdate, sound, touchpad, touchscreen, wallpaper |
| **UKUI** (ukui-control-center) | 8 groups | account, devices, messages-task, network, personalized, security-updates, system, time-language |
| **Ours** | 24 categories | personal, notifications, network, displays, windows, sound, access, input, time, apps, search, printers, sharing, firewall, backup, automations, privacy, chronoa, account, users, power, storage, screentime, about |

All four cover the same ground; the difference is where the seams are. Deepin
and Cutefish both split input by device — keyboard, mouse, touchpad,
touchscreen, and in Deepin a Wacom page — where we have one "Keyboard & input"
category with a tablet readout inside it. Cutefish is the most granular
(29 pages) and the only one with a separate *hotcorners* page; we have hot
corners inside Personalisation. UKUI is by far the thinnest and the oldest — its
control centre was last touched in 2022 — with "devices" and "system" carrying
what the others spread over ten pages.

### Apps, and what each one is for

- **Deepin** ships the widest set of the three: file manager, editor,
  compressor, album, movie, music, reader (PDF/DJVU, tabs, bookmarks, notes,
  magnify, slideshow, rotate), draw, image-editor (the editing library behind
  both viewer and album), disk manager (partition, health, data
  administration), device manager (hardware inventory), log viewer, screen
  recorder, screensaver, downloader (aria2), **deepin-anything** (an offline,
  instant filename index — "like Everything, but nothing is really like
  anything"), **dde-grand-search** (one search across files, apps and
  documents), **dde-clipboard** (clipboard history), **dde-cooperation**
  (cross-platform transfer and device cooperation), print manager, manual,
  update UI, clone, boot maker, recover manager, installer, launchpad, app
  manager and a plugin-based `dde-shell`.
- **UKUI** is mostly the desktop's own plumbing plus a few apps: peony (file
  manager, with extensions), ukui-notebook (sticky notes), ukui-media, system
  monitor (processes, CPU/memory, file systems), **ukui-search** (desktop
  search, marked work-in-progress), **ukui-sidebar** (notification centre *and*
  a clipboard in one tray panel), **ukui-paste** (a clipboard that also builds
  for other platforms), **ukui-shutdown-timer**, **kylin-display-switch** (a
  Super+P display popup that also watches CapsLock/NumLock),
  **kylin-nm** (a NetworkManager applet), **ukui-biometric-manager**
  (enrol a fingerprint or face), ukui-menu (an app menu with common/all,
  alphabetical and functional groupings plus search), **ukui-theme-customizer**
  (packs icons, cursors and wallpapers into installable debs), screensaver,
  greeter, panel, window switch and settings daemon.
- **Cutefish** is the smallest app set and the most modern underneath: settings
  (29 pages), file manager, terminal (state, parsing, scrollback, selection and
  search from **libghostty-vt**), calendar (iCalendar read *and* write,
  repeating events, alerts, coloured calendars, web-published calendars),
  calculator, text editor (tabs, find and replace, encoding detection, syntax
  highlighting), system monitor (CPU, memory, disk, network **and GPU**),
  preview (images and PDF together, folder stepping, thumbnails), video player
  (libmpv, subtitles, folder playlists, resume, seek-bar previews), disk utility
  (partitions, volumes, capacity, usage, connection, SMART, mount/unmount/
  eject), display manager, installer, a WebKit shell, a portal, and
  **cutefish-computer-use** — an MCP server that lets an agent app see the
  desktop and use its pointer and keyboard once the person allows it.

### What they have that we do not

Each of these was checked against our tree before being written down; none of
them is already here under another name.

1. **A download manager** (Deepin: aria2; nothing in the shell — Files has copy
   and move jobs, not a queue with pause, retry and per-file progress).
2. **An instant, offline filename index** (Deepin's *anything*). Our launcher
   and Chronoa's meaning index answer *what a file is about*; neither answers
   "which file is called X" across the whole disk in milliseconds.
3. **A hardware inventory** (Deepin's device manager). We show SMART per disk
   (Models), disks and partitions (Disks), processes (System Monitor) and a
   system summary (Settings › About); there is no one tree of the machine's
   devices.
4. **A shutdown timer** (UKUI). The power menu has Shut down, Restart,
   Suspend, Log out and Lock — nothing that says "shut down in 90 minutes".
5. **Biometric enrolment** (UKUI's biometric manager, Deepin's authentication
   plugin). The image ships fprintd; nothing in the shell enrols a finger or a
   face, so Settings › Your account can only set a password.
6. **A display-switch popup** (UKUI's, on Super+P) that also reports
   CapsLock/NumLock. We have Displays settings and a layout switcher, not the
   transient popup.
7. **A notification centre with a clipboard beside it** (UKUI's sidebar). We
   have notifications, the Island and a clipboard history reachable from the
   launcher's `c` mode — but not as one tray panel with both in it.
8. **A theme packager** (UKUI's): icons, cursors and wallpapers turned into an
   installable package. Ours are settings and files.
9. **An MCP door onto the desktop** (Cutefish's computer-use). Chronoa can act
   through the shell's own tools; an outside agent cannot see or drive the
   desktop.

Two of these are deliberate rather than missing: Deepin's clone, boot maker and
recover manager are the installer's job on a single-image system (we have
shani-backup and the installer), and Deepin's grand search overlaps our
launcher plus Chronoa's meaning search.

### What we have that they do not

Worth saying in the other direction, so the comparison is not read as a
deficit: Chronoa (the assistant, with approvals and an Island that shows what
it is doing), the launcher's own ranking (typos, actions, files, windows and
app-provided results in one list), Nearby Share and shani-shell, Feeds, the
firewall page, Containers, Window Layouts, Screen time and the accessibility
surface (Magnifier, Live Captions, Lens, Characters, dictation).

## The gaps

Filled 2026-11-12: a music and video library (in the Media Player), two-factor
codes (Authenticator), nearby sharing (Nearby, LocalSend's protocol; and
shani-shell's KDE Connect link, now two-way), and storage clean-up (Settings › Storage). Before building
each, Cassini, Chronoa and shani-shell were checked for one already: Cassini's
TOTP page is codes for signing in to *this computer* (pam_oath) and its
Maintenance cleans the *system*; shani-shell spoke KDE Connect but its file
sending had never worked against the protocol. Each new one hands over to
the existing one where they meet.

**Mail** now has a shell client (`Modules/Mail`, IMAP + SMTP with a MailHog
development mode), so the desktop is covered without a separate install.

Not proven on real hardware yet (the nested session cannot): LocalSend and
KDE Connect against real phones, and the firewall prompt through polkit.

## In Settings, not apps

What every other desktop keeps in its settings is in ours too, not a window
of its own: screen time and break reminders (Settings › Screen time, as
GNOME, macOS and Android do), freeing space (Settings › Storage, as macOS,
Windows and Android do), colours from a picture (Settings › Personalisation,
Android's "Wallpaper & style"), battery health (Settings › Power) and being
visible to Nearby Share (Settings › Sharing). The sidebar and the launcher
open them there (`Ui.openSettings(cat, section)`).
