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
- **Cassini** has no account management and no lid/power settings (the shell
  has both now).

## Built, but not provable in the dev container

Each needs real hardware or shani-testbed:

- Wi-Fi: wrong-password retry, forget, hidden network; Wi-Fi in first-boot setup.
- Bluetooth: pairing and receiving files against a real BlueZ/obexd (both
  agents are tested against fakes).
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
