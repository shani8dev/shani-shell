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

## Built, but not provable in the dev container

Each needs real hardware or shani-testbed:

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
