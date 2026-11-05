# The ShaniOS desktop — features

**A desktop where everything is a click or a glance away.** Sign in by looking at
the camera. Find anything by typing a few letters. Change any setting by picking
from choices — never by typing values you'd have to know. And when you're not
using it, it costs almost nothing.

![The ShaniOS desktop](docs/showcase-desktop.png)

Built on the [niri](https://github.com/YaLTeR/niri) scrolling compositor and
[Quickshell](https://quickshell.org). Every feature below ships today and is
covered by an automated test that drives the real shell.

---

## Sign in without typing

- **Face sign-in** — look at an infrared camera, like Windows Hello. Works on the
  sign-in screen and the lock screen. Set up in five guided looks.
- **Fingerprint** — touch the reader to unlock; enrol fingers in Settings.
- **Security keys** (YubiKey and other FIDO keys) — register one, touch it to unlock
  or sign in.
- **Your password always works too**, and is still asked for changes to the system.
- **Pick who's signing in** — your picture and name are already chosen; no user
  name to type. "Someone else" is one click away.
- **An on-screen keyboard at sign-in, setup and lock**, opening by itself on
  touchscreens. Plus a **Caps Lock warning** and **Show password**.
- **A lock screen you can use** — notifications, now playing, a camera button,
  restart and power off (each asks twice).

## A desktop that stays out of your way

- **Bar, dock and Island** — workspaces, the focused window with its own minimise,
  maximise and close, now playing, status at a glance. The bar and dock **step
  aside for your windows** and come back at the edge.
- **The Island** — the middle of the bar shows what's happening: a recording, a
  call, a timer, a print job — click to act on it.
- **Overview** of every window, an **Alt+Tab** switcher, a **pie menu** at the
  pointer, **hot corners**, **desktop layouts** to try on with one click.
- **Name your workspaces** from the bar. **Rounded screen corners.**
- **A drop shelf** — drop files on the dock to keep them for later, then drag them
  into any app.
- **Trash on the dock** — drop to bin, empty with two clicks.
- **A desktop right-click menu** — wallpaper, widgets, icons, displays, terminal.
- **Per-app window rules** — choose how each app opens: floating or tiled, which
  workspace, how wide.
- **A drop-down terminal** (or any app) one key away, over whatever is open.
- **Your apps reopen** at your next sign-in, the way you left them.
- **Desktop widgets** — clock, calendar, weather, now playing — placed where you like.

## Find anything

- **One launcher for everything** — apps, open windows, files (and words inside
  them), actions like "dark style" or "lock", a **calculator** with unit
  conversion, **emoji**, **clipboard history**, web search.
- **Picks go where you were** — choose an emoji or a clipboard entry and it's typed
  or pasted into the window you came from.
- **Apps' own answers** — GNOME Calculator, Files, Characters and more add their
  results.
- **Lens** — select part of the screen to read its text, scan a QR code, copy,
  search, translate, or ask the assistant about it.
- **Smart suggestions when you copy** — a link to open, an address to email, a
  number to call, a foreign script **translated on your computer**, an error
  explained.

## Quick Settings and notifications

- **Quick Settings** — volume, brightness and ~40 tiles (Wi-Fi, Bluetooth, VPN,
  hotspot, Do Not Disturb, night light, dark style, screen record, screenshot,
  colour picker, keyboard light, compass…). Each tile **appears only where it can
  work**; rearrange them in place.
- **Do Not Disturb for an hour, until your meeting ends, or until tomorrow** — and
  **quiet hours** every night.
- **Notification rules** — no pop-ups from an app, or drop it altogether, from the
  notification itself or Settings.
- **Swipe a notification away**, **snooze it**, reply inline; **clicking it brings
  its app forward**. Unread notifications **survive a restart**.
- **A sound for each notification**, **flash alerts** for the hard of hearing.
- **Quiet by itself while you present or play** — fullscreen holds notifications
  back, and a game also gets the performance power profile.

## Your day, organised

- **Your calendar in the sidebar** with a **heads-up ten minutes before** each
  meeting — from the calendars you already use.
- **Focus modes** (Work, Sleep, Personal) that hold back everything but the apps you
  allow — by hand or on a schedule.
- **A focus timer** (25 minutes on, then a nudge to rest).
- **Screen time** — how long each app had your attention, today and this week, with
  an optional daily reminder.
- **Quick notes** in the sidebar, saved as you type to a plain Markdown file.
- **Weather and world clocks** at a glance.

## Automate the routine

- **"When this, do that" automations** — on a Wi-Fi network, when headphones plug in,
  at a time of day: turn on Do Not Disturb, change the volume, run a command.
- **Hooks** — run your own command when the wallpaper or dark style changes, the
  screen locks or unlocks, or the desktop starts.

## Type however suits you

- **On-screen keyboard** in English, **Marathi** with smart matras, and **any of
  598 keyboard layouts** — including 45 Indian ones.
- **A globe key** to switch languages, the way phone keyboards do.
- **Handwriting** — write on ruled lines with a pen, finger or mouse; scribble over
  a word to rub it out; it's read **on your computer** (English, Hindi, Marathi)
  and typed where you were.
- **Sticky Ctrl and Alt** — tap once for the next key, twice to hold.
- **Voice typing** into any app.
- **Input methods** (fcitx5) with English and Hindi phonetic ready to go.

## Accessible by default

- **Screen reader** support throughout — every control has a name, verified with
  real accessibility tools.
- **Larger text, high contrast, reduce motion, mono audio, magnifier.**
- **Live captions** and **read aloud** for any text.
- **A floating assist button** (AssistiveTouch) for touch and pointer users.
- **The whole desktop by keyboard or game controller** — every button, tile, list
  and menu is reachable, with a clear focus ring. A controller drives the desktop
  (A selects, B goes back, Start opens Quick Settings) and steps aside for games.
- **Never locked out without a keyboard** — the lock screen, sign-in, setup and
  admin prompts each have an on-screen keyboard, which opens by itself when no
  keyboard is connected. Hide it to see the whole screen; a small button brings it back.
- **Every keyboard and laptop key works** — screen and keyboard brightness,
  touchpad on/off, airplane mode, display, calculator, search, mail, browser,
  files, settings, lock.

## Screen, camera and media

- **Screenshots** — region, window or screen; on a 3- or 10-second timer; offered
  for annotation right after.
- **Screen recording** — the screen or a region, with **computer sound and your
  microphone on two separate tracks**; make a GIF or a smaller copy in one click.
- **One media card for every player** — choose which to follow when several play;
  tinted from the album art; **synced lyrics** if you want them.
- **Camera** — photos and video, and a **privacy light** whenever anything uses the
  camera, microphone or screen.
- **Screen ruler, colour picker, QR codes** from the clipboard, **file actions**
  (convert a picture, shrink a file to a form's size limit, read the text in it).
- **Share sheet** for any file — to your phone, a Bluetooth device, nearby devices
  with LocalSend, email, or the clipboard.
- **Cast your screen** to a TV or Chromecast.
- **Call recording** for any call app, mixing your microphone and the other side —
  with a reminder to tell them.
- **Sound effects** — an equaliser with presets, bass boost, **headphone correction**
  (AutoEq), and per-app volume. Small system sounds for volume, screenshots, the
  charger and drives.
- **A clock screensaver** and a **charging screen** you can glance at across the room.

## Devices and your phone

- **Bluetooth** pairing with the code shown big and clear; a **low battery warning**
  for headphones, mice and watches right in the bar.
- **Drives** — mount, eject, and unlock encrypted ones from Quick Settings.
- **Printers** added automatically; print jobs shown as they run.
- **Your phone (Shani Link)** — calls on your phone, your landline or the laptop's
  own modem; texts; **one address book**; one call history; a dial pad that finds
  contacts as you type; phone links anywhere open the dial pad; use the phone's
  internet over Bluetooth. Watches and fitness bands too.
- **Calls ring once**, on the Island, wherever they come from.
- **Your phone's screen in a window** (Android), driven with your mouse and keyboard.
- **Dynamic lock** — the screen locks itself when your phone walks out of range.
- **Send and receive files over Bluetooth**, each asked first.
- **Share your Wi-Fi** as a QR code a phone's camera joins from.
- **Run an app on the faster graphics card** on laptops with two.
- **Plug something in and it says hello** — a monitor asks extend, mirror, only this
  screen or **presenting** (Do Not Disturb and no sleep until it's unplugged); a camera
  offers to import photos; a phone opens its files; a drawing tablet asks which screen;
  a controller shows its battery; a security key offers sign-in; a scanner offers to
  scan; MIDI, capture cards, serial boards, card readers, braille displays and eGPUs
  are named, each with one next step.
- **Gaming mice** — DPI, polling rate and buttons, picked from the mouse's own options.
- **Game controllers** — battery and a live button test.
- **Drawing tablets** — draw on one screen, the screen you're working on, or left-handed.
- **Sound follows you** — plug in headphones and an on-screen notice says where the
  sound went.
- **A convertible folded into tablet mode** brings up the screen keyboard.
- **A slow charger is called out** when the battery keeps draining while plugged in.
- **Sensors** (light, rotation, compass, GPS) are recognised.

## Power that thinks ahead

- **Sleep, then hibernate** on laptops so a flat battery never loses your work — or
  **hybrid sleep** for a copy on disk. Offered only where your computer can.
- **60 Hz on battery** for fast laptop screens, back up on the charger.
- **Battery saver** at 20 %, a **charge limit** to keep the battery healthy.
- **Caffeine** to stay awake (it doesn't survive a reboot by accident).
- **Displays** — arrange, scale, rotate, mirror, set the refresh rate; every change
  is **confirmed or undone in 15 seconds**.

## Make it yours, without hunting

- **Settings you pick, not type** — weather from your own city, suggested computer
  names, ready-made bar buttons, popular web apps, DNS in plain words (fast,
  blocks harmful sites, blocks ads, safe for family).
- **Your own keyboard shortcuts** — press the keys, pick an app or action. A taken
  combination is refused before it can break anything.
- **Wallpapers** — your own, a slideshow, one per screen, or **found online** with
  one search. **Accent colour from your wallpaper.**
- **Light and dark** that follow the time of day.
- **First setup in six short steps**, in six languages, with a screen keyboard and
  accessibility options from the first screen.
- **A friendly tour** of the essentials on first login.

## Safe, private and family-friendly

- **Earlier versions of your files** from daily snapshots, and **backups to another
  drive** — restored from the sidebar or Settings.
- **ShaniOS updates** shown in Quick Settings, with a reboot nudge when one is ready.
- **Parental controls** — apps a child shouldn't use stay out of their launcher and
  dock.
- **Privacy tidying** — empty old trash automatically, clear or switch off recent
  files.
- **A proxy for every app**, set once.
- **Share folders** on your network and turn remote login on or off — with plain
  explanations.
- **Several people, one computer** — add accounts, set who's an administrator.

## An assistant that's part of the desktop

- **Chronoa** lives in the middle of the bar: ask from the Island, the launcher, a
  notification, a screen selection or the pie menu.
- **Approve or deny in place** when it wants to act.
- **Live captions and voice typing** use its speech engine — on your computer.
- **Ask about a file, a window, an error or a notification** in one click.

## Fast and light

- **Nothing redraws while you're not doing anything** — measured: at most a few
  frames in 15 seconds at rest.
- **Rarely used surfaces are only made when opened**, then dropped.
- **No polling where the system can tell us** — devices, cameras, displays and
  notifications arrive as events.
- **Apps run in their own scope**, so restarting the desktop never closes them.
- **A task manager** a click from the bar's CPU chip, refreshing only while it's open.
- Every release is checked for **idle cost, memory, open speed, leaks and startup
  time** by the test suite.
