# Known gaps

What the ShaniOS niri desktop does not do yet, or does without proof, surface
by surface. An item leaves this file when it is built *and* a test runs it.
Compared against GNOME Settings, KDE System Settings and Deepin's control
centre, and against what a session needs before any app runs.

## Not built — by choice

- **Bar position.** The bar stays on top: the Island grows down from it for
  Chronoa's approvals and questions, and the dock owns the bottom edge.
- **Session chooser on the login screen.** The niri image has one session;
  Plasma and GNOME images have their own greeters.
- **Switch user from the lock screen.** greetd runs one session; there is no greeter to switch back to (loginctl has no such command).
- **Online accounts.** GNOME Online Accounts needs GNOME's own settings app.
- **Remote desktop through the portal.** niri 26.04 has screencasting
  (org.gnome.Mutter.ScreenCast) but no org.gnome.Mutter.RemoteDesktop, so
  GNOME Remote Desktop, RustDesk and FreeRDP's shadow server cannot capture or
  control it (niri issue #390; PR #1966 is open, not merged). What works is
  Sunshine + Moonlight (KMS capture, discussion #680): Settings > Sharing
  switches Sunshine's user service when it is installed (it needs
  `cap_sys_admin`; LizardByte's repo / AUR, not in the image).
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
  for a shell: desktop widgets, presence sensing, receiving AirPlay, a phone
  as webcam, "Find my device" (needs a server).
- **A live camera viewfinder on the lock screen.** The lock screen takes a
  photo (libcamera stills, after a countdown) and shows it; qcam, the live
  view, is a window, and nothing shows above the lock.

## Not built — yet

- **Headphone virtual surround.** Implemented via the matrix_spatialiser LADSPA plugin (shipped in ladspa) as a "Stereo widening" toggle in Settings › Sound effects, behind `SoundFx.canSpatial`. The convolver-based virtual surround (KEMAR/Hesuvi HRIR) still needs HRIR wav files that no package ships; stereo widening is what is available.
- **More setup-wizard languages** than English, मराठी, हिन्दी, Deutsch, Español,
  Français (strings.js).
- **Translations**: 104 of 684 strings reviewed in Marathi and Hindi (the bar,
  control centre tiles, Settings categories, launcher's main actions); German,
  Spanish and French have none yet. The rest show in English, or - opt-in - are
  translated by Chronoa's local model, which got about a third of short labels
  wrong when measured with Qwen3-8B. Strings built by concatenation are not yet
  wrapped (`tools/i18n.py` says how).
- **One run on a real installed niri image**: everything here is proven in the
  nested container only. Needs the niri image built (shani-shell has no remote
  yet, and its PKGBUILD fetches from GitHub) and a shani-testbed UEFI boot.

## The shell's apps: what each still lacks (Nov 2026)

`shani app` lists them (26). Each is a window of its own (`Common/AppWindow`),
opens cleanly in the suite and is photographed there (`out/shots/app-*.png`).
The shell's app is the default for its file types and the Flatpak is kept
after it as the fallback; a Flatpak leaves the niri image when its app has
been used on a real screen and nothing below is in the way.

- **Media Player** (default for video and audio; Showtime, Decibels behind
  it): no subtitles, no audio-track choice, no album art or tags, no
  resume-where-you-left-off. Hardware decoding is whatever QtMultimedia's
  FFmpeg backend picks - unmeasured on real hardware.
- **Image Viewer** (default for png, jpeg, webp, gif, bmp, svg, avif, tiff;
  Loupe behind it and still the default for HEIC and camera raw).
- **Document Viewer** (default for PDF; Papers behind it): PDF only - no
  DjVu, EPUB or comic archives; no form filling (PDF Signer places text).
- **Text Editor**: colours for ~20 languages by one regular expression each
  (not a parser); a file over 2 MB is refused, over 200 000 characters is
  shown without colours.
- **Archive Manager** (default for zip, tar.*, 7z, ISO; File Roller behind it):
  reads and extracts; it does not create archives, extract a single entry, or
  open one with a password.
- **Calendar**: which calendars show, and which a new event goes to. Adding
  an online account is still GNOME Online Accounts' (not in this image).
- **Files**: offered for folders; Nautilus stays the default and is the
  portal's file chooser.
- **Maps**: a 4x4 grid of OpenStreetMap tiles around one point - no
  dragging, no routes. GNOME Maps stays.
- **Document Scanner, Password Generator, Kundali**: they work and take the shell's
  colours, but are laid out with stock controls, not the shell's own widgets.
- **Still Flatpaks with no app of ours**: an office suite, a browser, a
  torrent client, internet radio, virtual machines, remote desktop, the games.
- **Not there at all**: a video wallpaper, a battery health centre beyond
  Settings > Power, a network speed test (tried and taken out, see FINDINGS).
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
- Translations: 104/684 Marathi/Hindi strings done; remaining strings documented here.
- Real-hardware runs: nested niri only; shani-testbed boot needed for Wi-Fi BT multi-screen recording.
# Improvements applied (Nov 2026)
- Scratchpads: plugin manifest + full settings schema + service lifecycle
- ScreenSaver: active cover + idle-stage hooks
- WebApps: site scraping + reveal hooks
- Traffic: full plugin architecture
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
- Recording: video codec choice (auto/H.264/HEVC/VP9/AV1) via wf-recorder -c; screenshot auto-copy to clipboard.
- Snooze length (5/10/30/60 min) and media controls on the lock screen are now settings.
