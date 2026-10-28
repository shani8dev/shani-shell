# Known gaps

What the ShaniOS niri desktop does not do yet, or does without proof, surface
by surface. An item leaves this file when it is built *and* a test runs it.
Compared against GNOME Settings, KDE System Settings and Deepin's control
centre, and against what a session needs before any app runs.

## Session plumbing

- **Done:** greetd + first-boot setup, polkit agent, keyring unlocked at login
  (`/etc/pam.d/shani-greetd`), xdg autostart (niri.service wants
  `xdg-desktop-autostart.target`), portals, notifications, media keys,
  volume/brightness keys, idle/lock/suspend, clipboard history, Bluetooth agent.
- **Receiving files over Bluetooth (OBEX)** only works while Chronoa's window
  runs (`shani_chronoa/obex_receive.py`). Belongs in the shell.
- **Startup apps** run (xdg autostart) but there is no list to add/remove them.
- **No system sound besides notifications** (volume-change click, screenshot
  shutter, plug/unplug).

## Login screen (greeter)

- **Done:** users to pick, power off / restart / sleep, accessibility (larger
  text, contrast, screen reader), keyboard-layout indicator.
- **No session chooser** (only niri-session; Plasma/GNOME images have their own
  greeters, so mostly moot).
- **Fingerprint / smart card** sign-in depends on the PAM stack (Cassini's
  Biometrics page configures it); not tested with greetd here.

## Lock screen

- **No media controls and no notification previews** (it shows a count only —
  private by design; a "show content" option is missing).
- **No "switch user"** (greetd has no session switching; would need a second VT).

## Shell surfaces

- **Bar position** (always on top) and workspace indicator style.
- **Keyboard shortcuts** — no viewer or editor (niri's own hotkey overlay,
  Mod+Shift+/, lists them).
- **Setup wizard text is English only** (it sets any language for the machine).

## Settings, by area

| Area | Missing |
|---|---|
| Network | wired details, proxy, IPv4/IPv6/DNS per connection — only via nm-connection-editor |
| Sound | device profiles (HDMI/analog, headset mic mode), alert volume, per-app output routing; JamesDSP's loudness levelling (PipeWire ebur128), headphone virtual surround (SOFA HRTF file needed), compressor, mic noise suppression |
| Displays | ICC colour profiles (niri has no colour management) |
| Keyboard | compose key / special characters, shortcut editor |
| Privacy | location services (geoclue) switch, per-app camera/mic/screen permissions (portal permission store), auto-empty trash, clear recent files |
| Apps | Flatpak app permissions, startup apps |
| Power | battery charge limit (needs root: sysfs threshold) |
| Windows | niri layout: gaps, focus ring, default column width, focus-follows-mouse, animations |
| Search | which launcher providers are on |
| Screenshots | save folder and format |
| Sharing | remote desktop (no niri support in gnome-remote-desktop), media sharing; file sharing and printers are in Cassini |
| Online accounts | none (GNOME Online Accounts not wired) |

## Other repos

- **Chronoa cannot manage windows on niri** — `shani_chronoa/windows/` has no
  niri backend. **Phone texts and calls** should be shell surfaces (Chronoa's
  `map_notify`, `incoming_call` keep their engines). Chronoa-side work.
- **Cassini has no account management** (add/remove users, admins, autologin —
  the shell does it now) and no lid/power-button settings.
- **Cast (Miracast):** gnome-network-displays is in the AUR, not packaged.

## Built, but not provable in the dev container

Each needs real hardware or shani-testbed:

- Wi-Fi: wrong-password retry, forget, hidden network; Wi-Fi in first-boot setup.
- Bluetooth against a real BlueZ (the agent is tested against a fake one).
- KDE Connect discovery and pairing.
- Camera: real libcamera stills and PipeWire video (the still path is tested with a fake `cam`).
- Night light warming a real screen; screen recording; auto-rotate; adaptive brightness; flashlight.
- Display modes, rotation and turning a screen off (nested niri applies scale and position only).
- Sound effects on real speakers (measured against a null sink).
- Keyring unlock at login (PAM; not in the dev image).
- Hostname from first-boot setup (Docker bind-mounts /etc/hostname).
- The polkit tiers of `50-shani-admin.rules` through pkexec with a real agent.
- The full first boot → factory reset → first boot cycle.
