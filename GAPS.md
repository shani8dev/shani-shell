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
- **Switch user from the lock screen.** greetd has no session switching.
- **Online accounts.** GNOME Online Accounts needs GNOME's own settings app.
- **Remote desktop.** gnome-remote-desktop does not support niri.
- **ICC colour profiles.** niri has no colour management yet.
- **Location services.** Nothing in the shell locates the computer; weather uses
  the city typed in Settings.
- **What Windows and macOS have that niri cannot give.** Always-on-top (niri
  has no such window state), minimise / "show desktop" (a scrolling layout
  has no hidden windows — Overview is the stand-in), colour filters for colour
  blindness and HDR (no colour management), "find my pointer" (no pointer
  position for a layer-shell client to draw at). Out of scope for a shell:
  desktop widgets, presence sensing, receiving AirPlay, a phone as webcam.

## Not built — yet

- **Headphone virtual surround** (PipeWire's SOFA spatializer needs an HRTF
  file shipped) and a **compressor** (needs an LV2/LADSPA plugin) — the rest of
  JamesDSP is in Settings > Sound.
- **Phone texts and calls as shell surfaces.** Chronoa's `map_notify` and
  `incoming_call` show their own windows; the shell should draw them
  (notification with reply, an Island call activity). Chronoa-side, beside
  another person's uncommitted work there.
- **Chronoa steps aside for the shell's Bluetooth file agent** only by losing
  the race: whichever registers with obexd first keeps it.
- **More setup-wizard languages** than English, मराठी, हिन्दी, Deutsch, Español,
  Français (strings.js); the shell's own settings are English only.
- **Translations**: 104 of ~575 strings reviewed in Marathi and Hindi (the bar,
  control centre tiles, Settings categories, launcher's main actions); German,
  Spanish and French have none yet. The rest show in English, or - opt-in - are
  translated by Chronoa's local model, which got about a third of short labels
  wrong when measured with Qwen3-8B. Strings built by concatenation are not yet
  wrapped (`tools/i18n.py` says how).
- **One run on a real installed niri image**: everything here is proven in the
  nested container only. Needs the niri image built (shani-shell has no remote
  yet, and its PKGBUILD fetches from GitHub) and a shani-testbed UEFI boot.
- **Cassini** has no account management and no lid/power settings (the shell
  has both now).

## Built, but not provable in the dev container

Each needs real hardware or shani-testbed:

- Wi-Fi: wrong-password retry, forget, hidden network; Wi-Fi in first-boot setup.
- Bluetooth: pairing, receiving and sending files against a real
  BlueZ/obexd (both agents are tested against fakes; sending is untested).
- The dock's right-click menu (no pointer clicks are injected in the dev session).
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
