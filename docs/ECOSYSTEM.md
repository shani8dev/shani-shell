# The app ecosystem, against the others

What a desktop ships as its own apps, side by side, so a gap is visible
before someone goes looking for an app. Surveyed 2026-11-12 from each
desktop's own app set: GNOME core apps, KDE Gear, Deepin (DDE), Kylin (UKUI),
Cutefish, Budgie, Cinnamon (X-Apps and Mint tools), macOS, Windows (with
PowerToys) and Android (AOSP and Pixel).

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
| Contacts | Contacts | KAddressBook | Contacts | — | — | — | Contacts | People | Contacts | shani-link |
| Phone, texts | Calls | KDE Connect | Phone Master | Connectivity | — | — | Phone, Messages | Phone Link | Phone, Messages | shani-link · Mirror (scrcpy) |
| Mail | Geary | KMail | Mail | — | — | Thunderbird | Mail | Outlook | Gmail | none in the image, by choice (install from Software) |
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
| Podcasts, radio | Podcasts¹ | Kasts | — | — | — | Hypnotix (TV) | Podcasts | — | — | Shortwave |
| Camera | Snapshot | Kamoso | Camera | Camera | — | — | Photo Booth | Camera | Camera | **Camera** |
| Sound recorder | Sound Recorder | — | Voice Notes | Recorder | — | — | Voice Memos | Sound Recorder | Recorder | **Voice Recorder** |
| Screenshot | (shell) | Spectacle | Screen Capture | Screenshot | Screenshot | — | Screenshot | Snipping Tool | (system) | **Screenshot** · satty |
| Screen recording | (shell) | Spectacle | Screen Capture | — | — | — | Screenshot | Snipping Tool | (system) | **Screen Recorder** |
| Video trim | — | Kdenlive | — | — | — | — | QuickTime | Clipchamp | Photos | **Video Trimmer** |
| Drawing | — | KolourPaint | Draw | — | — | — | — | Paint | — | Drawing |
| Scanner | Document Scanner | Skanpage | Scanner | Scanner | — | — | Image Capture | Scan | — | **Scanner** |
| Archives | (Files) | Ark | Archive Manager | — | — | File Roller | Archive Utility | (Explorer) | — | **Archive Manager** · File Roller |
| Disk usage | Disk Usage | Filelight | — | — | — | — | Storage | Storage | Storage | **Disk Usage** · Baobab |
| Disks | Disks | Partition Manager | Disk Manager | — | — | — | Disk Utility | Disk Management | — | GNOME Disks |
| Write an image to USB | — | — | Boot Maker | USB Creator | — | USB Image Writer | — | — | — | Impression |
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
| Send to a nearby device | — | KDE Connect | Cooperation | IP Messenger | — | Warpinator | AirDrop | Nearby Share | Quick Share | **Nearby Share** (LocalSend) · shani-link (KDE Connect, paired phone) · Bluetooth |
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

## The gaps

Filled 2026-11-12: a music and video library (in the Media Player), two-factor
codes (Authenticator), nearby sharing (Nearby, LocalSend's protocol; and
shani-link's KDE Connect link, now two-way), and storage clean-up (Settings › Storage). Before building
each, Cassini, Chronoa and shani-link were checked for one already: Cassini's
TOTP page is codes for signing in to *this computer* (pam_oath) and its
Maintenance cleans the *system*; shani-link spoke KDE Connect but its file
sending had never worked against the protocol. Each new one hands over to
the existing one where they meet.

Left, by choice: **mail** - no client in the niri image; one is a Software
install away.

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
