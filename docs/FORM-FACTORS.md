# One shell, every form factor

One shell for a computer, laptop, tablet, handheld, phone, TV, classroom
board and projector. Profiles describe how a screen is used; they are not separate shells.
A laptop panel and a TV on HDMI must retain their own behaviour.

Reviewed against the implementation on 2026-11-17. There are no completion
percentages: a container test, a screenshot and a real-device test prove
different things. **Implemented** below does not mean hardware-certified.
Other application gaps live in [GAPS.md](GAPS.md).
Upstream implementations and physical test procedures are recorded in
[HARDWARE-VALIDATION.md](HARDWARE-VALIDATION.md), including the distinction
between upstream device support, replay tests and Shani hardware verification.

## What exists, and what remains

| Profile | Implemented | Still needs work or hardware verification |
|---|---|---|
| Computer | Desktop layouts, keyboard/mouse navigation, multi-monitor output configuration | Mixed-profile scaling; unusual aspect ratios; large-text and screen-reader audits |
| Laptop | Battery/lid/power controls; separate remembered layouts when docked and undocked | Actual docks, disabled internal panels, suspend/resume, hotplug during settings changes |
| Tablet | Profile scaling; edge gestures; shell text-field keyboard; rotation; long-press actions | Keyboard in other apps; touch-only targets and scrolling throughout all apps; pen/rotation testing |
| Handheld | Arm's-length home; Guide → Start quick-panel fallback; controller typing/pointer; panel orientation rules | Real InputPlumber pass-through, gamescope and portrait-mounted panels; TDP integration |
| Board | Bottom bar; dock above it; the tools (the Ring) by a swipe in from the left or right edge and the apps from the bottom, as Promethean, SMART, ViewSonic and BenQ panels reach theirs from either side; whiteboard pages/PDF; pen pressure/eraser/palm handling; guest account integration | Real pens and simultaneous users; reach of all controls, including the Island; guest isolation checks; cast receiver |
| TV | Ten-foot home; remote/controller navigation; EDID size/name detection | Real remotes/CEC and TVs; overscan; mixed laptop/TV setup; gamescope desktop integration |
| Projector | Told by its EDID name (projector, beamer, "PJ", Optoma) or chosen; bigger shell, no rail; Presenting offered as for any new screen; the Focus layout suits it | Real projectors' EDIDs, keystone/overscan, mirrored versus extended presenting |
| Phone | Compact bar/launcher, bottom Quick Settings shade, bounded notifications/lock cards, compact Settings, dial/messages/contacts via Shani Link | Whole-app portrait layouts, safe areas, landscape/keyboard occlusion, native modem/audio testing, suspend/wake and mixed-output policy |

## Shared foundation

- Each kind has a desktop layout made for it, offered first in Screen and layout
  (LayoutSwitcher), with the general ones that suit it after: computer - Shani;
  laptop - Laptop (slimmer dock, two-thirds windows); tablet - Touch (thumb-reach
  rail and dock); phone - Phone (full screen, a dock of favourites); handheld -
  Handheld (a strong focus ring for the pad); TV - TV (huge icons, a thick ring for
  the remote, a wide margin); board - Classroom (everything within reach at the
  bottom); projector - Focus (what is on screen fills it). TV and handheld open on
  the ten-foot home; their layout is for the desktop behind it. For any screen:
  Classic, Minimal, Dashboard; and familiar arrangements - Taskbar (apps and a
  search box in a bottom bar), Centred taskbar, Side launcher. No two alike, and
  none named after another product (tests/test_left_rail_fixes.py).
- `Common/FormFactor.js` identifies profiles from built-in connectors, physical
  size, EDID names and available input; the owner's choice takes precedence.
  `tests/test_form_factor.py` covers the rules, including absent EDID sizes.
- `Services/FormFactor` keeps a profile per output. Settings > Displays offers
  **Kind of screen** and **Shell size** (100–200%, or Automatic). Shell size
  changes shell UI, not application DPI; **Scale** is the compositor's setting.
  Invalid shell-size values fall back to the profile default.
- `Theme.px()` scales much of the UI. `tools/ui-scale.py check` guards against
  selected fixed-size patterns; a clean result is **not** proof that every
  expression, icon, hit target or app fits.
- Width breakpoints exist in `Common/FormFactor.js` and Settings. Launcher
  preview suppression and the phone shade also use profiles. Reflow of all
  other surfaces remains an audit task, not a completed mechanical conversion.
- **Mixed-profile scaling is incomplete.** Many controls read the focused
  output's global `Theme.ui`, including children of windows on other outputs.
  Edge gesture distances now use their own output's scale. The rest needs
  output-local scaling without double-applying compositor DPI.

## Input and navigation

How it fits together: **inputs → kind of screen → situation → layout.**

| Input | Detected by | Set up in | What follows |
|---|---|---|---|
| Keyboard | `input-kinds.py` (udev) | Keyboard & input | none at all: the screen keyboard opens by itself; plugged into a tablet: it is a laptop again |
| Touchscreen | `input-kinds.py` (machine-wide) | Drawing tablet & touchscreen (which screen) | kind (tablet, board), edge swipes, 44 px targets, Back and the keyboard in the dock |
| Pen, drawing tablet | `input-kinds.py`, greeted by `plugwatch.py` | same section (screen, left-handed, calibration) | whiteboard pressure, eraser |
| Touchpad | `input-kinds.py` | Touchpad (shown when there is one) | — |
| Mouse | `input-kinds.py` | Mouse (shown when there is one) | touchpad off while a mouse is in, if chosen |
| Pointing stick, trackball | `input-kinds.py` | Pointing stick & trackball (when there is one) | scroll by holding the middle button |
| Tablet-mode switch | niri's switch events | — | folded: the tablet kind, its layout (Docking), the screen keyboard |
| Game pad, wheel, flight stick | `input-kinds.py`, greeted by `plugwatch.py` | Game controllers | GamepadNav drives the shell; a built-in pad makes a handheld |
| Presenter clicker | `plugwatch.py` (its keys) | — | greeted; its keys page the slides |
| TV remote | its keys (a keyboard to the kernel) | — | the TV home's focus; HDMI-CEC is missing below |

Settings > Keyboard & input shows the sections for the devices that are there,
the rest behind "Show all" (a mouse used only at a desk). The situation
(`Services/Docking`: docked, a laptop, folded into a tablet, a phone, a handheld,
a TV, a board, a desktop's screen) keeps the layout last used in it; the touch
and ten-foot ones start in the layout made for them, once, with Undo.

`Modules/EdgeStrips`, `Services/EdgeSwipe` and `Common/Gestures.js` implement:

| Input | Action |
|---|---|
| Bottom-edge swipe | Launcher/home surface |
| Bottom-edge swipe, then pause | Overview |
| Top-edge swipe | Quick Settings |
| Left-edge swipe | Close a shell surface, otherwise send Alt+Left to the app |
| Right-edge swipe | Overview |
| Phone shade's top handle, dragged down | Dismiss the shade without taking list scrolling |

The hold clock starts only after crossing the swipe threshold. Motion outside
an 8-logical-pixel tolerance resets it; a slow moving swipe is not a hold.
Cancellation discards the gesture. The 400 ms pause and tolerance still need
real-finger calibration. These are our choices, not a measured reproduction of
Android or iOS.

Edge strips reserve a narrow part of the screen: taps there do not pass through
to applications. They do not yet provide compositor-level touch navigation.
Alt+Left is not a universal Android-style Back action. The current recognizer
does not implement multi-finger arbitration or animated gesture progress.

Long press, pinch and swipe-away actions exist in several surfaces. Keyboard,
mouse, pen and touch must remain independent: adding a hold must not disable a
normal click, context menu or keyboard Menu key. The dock's trash keeps its
two-step empty confirmation for both keyboard and pointer users.

### Input work still missing

- [ ] Test real touchscreen gestures, cancellation, palm contacts, multi-touch,
  jitter, edge conflicts and movement between outputs.
- [ ] Check minimum touch targets and spacing throughout Settings and apps;
  profile scaling alone does not establish a 44–48 logical-pixel hit target.
- [ ] Check drag-versus-tap behaviour and inertia in lists, sliders and maps;
  default Flickable support is not an end-to-end touch test.
- [ ] Verify all operations with keyboard only, screen reader, large text,
  reduced motion, RTL and long translations.
- [ ] Verify automatic keyboard dismissal, language switching, secure password
  fields and avoidance of the keyboard in both orientations.
- [ ] Integrate external-app text input only through supported compositor/input
  protocols. Do not infer password-field contents through accessibility.

## Windowing, screens and phone use

Niri [window opening rules](https://niri-wm.github.io/niri/Configuration%3A-Window-Rules.html)
are global and have no output matcher. Automatic
`open-maximized` (one app at a time, the bar kept above it as a phone's status
bar, the Island in it rather than over the app's header) therefore applies
**only when every detected output is a phone**. Attaching a desktop monitor removes that rule; changing focus alone
does not rewrite it. This protects the desktop, but is not a complete
phone-plus-monitor policy. Existing windows are not resized by an opening rule.
Per-app rules are applied afterwards, but floating/width rules do not themselves
cancel fullscreen; an explicit fullscreen override is not exposed in Settings.

The phone checks cover a 412×915 nested output: actual output dimensions,
fullscreen width and height, launcher/search, shade, lock/unlock and restoration
of desktop rules. They are smoke tests, not proof that every app is phone-ready.

Calls, messages and contacts reuse **Shani Link**, rather than a second address
book or dialer in the shell. Launcher actions open its phone/messages/contacts
pages; addressed actions prefill a destination rather than silently calling.
Read `shani-link`'s own tests and permissions before changing those routes.

### Screen and lifecycle work still missing

- [ ] App layouts at narrow widths, landscape, small-height handhelds and
  ultrawide screens; no clipped buttons or unreachable dialogs.
- [ ] Cutouts, rounded corners and safe areas; software keyboard overlap;
  display zoom combined with large text.
- [ ] Physical touch-device-to-output mapping. Input presence is currently
  machine-wide, so a touchscreen laptop must not make an unrelated TV a board.
- [ ] Multi-output phone docking, moving existing fullscreen apps, per-output
  focus/activation and preserving user window choices.
- [ ] Plug/unplug while locked, mirrored outputs, scale/orientation changes
  while a popup is open, and primary-screen disappearance.
- [ ] Resume with keyboard/controller reattached; app restoration after shell
  restart; rotation lock and accelerometer failure.
- [ ] Native modem calls, audio routing, incoming calls while locked, notification
  privacy, SIM unlock and emergency-calling behaviour. A dialer UI is not a
  certified phone stack.
- [ ] Battery/thermal budgets, screen-off behaviour, idle GPU redraws and
  low-memory operation on actual mobile/handheld hardware.

## Board, TV and distribution integration

- The board's pen logic and PDF output have unit/container coverage. Pressure,
  hover, palm rejection, eraser buttons and simultaneous pen/touch require
  physical devices. A bottom bar does not make every control reachable.
- The guest account/reset integration lives partly in `shani-desktop-niri`.
  Verify failed login/logout, crashes, reboot, files outside the home, mounted
  drives, keyrings, network credentials and sessions left running. A reset home
  is not a sandbox for untrusted guests.
- Receiving a cast is not implemented here. Evaluate/package a maintained
  receiver (for example UxPlay for AirPlay), including pairing, firewall,
  audio/video delay and stop controls. Old statements that no suitable package
  exists are not current repository research.
- TDP controls require device-specific backend support, permissions, safe
  limits and rollback. Do not treat package availability as the only blocker.
- Gamescope desktop-mode integration and native versus Flatpak Steam remain
  distribution decisions; do not silently change the session or remove an
  existing desktop.
- Test TV remote/CEC key mappings, visible focus, overscan, high-DPI reading
  distance and returning from a game. Large cards alone are not a TV audit.
- Kiosk/signage remains a separate image/profile. Foldables and convertibles
  are changing screen/input states, not reasons to fork another shell.

## Verification and next order

1. Keep pure profile/gesture tests, plus focused runtime regression parts.
2. Exercise narrow and landscape sizes and inspect screenshots/accessibility
   bounds; opening a window does not prove that it fits.
3. Fix output-local scaling and touch-target gaps before adding more profiles.
4. Integrate and test external-app keyboard, phone docking and gamescope with
   their owning components.
5. Run the installed-image hardware matrix before claiming a profile complete.

Useful commands (run container suites serially: their logs share `out/`):

```sh
python3 -m pytest tests -q
python3 tools/ui-scale.py check
SHANI_WIDTH=412 SHANI_SCREEN=915 sh dev/check.sh shell=phone
SHANI_WIDTH=915 SHANI_SCREEN=412 sh dev/check.sh shell=phone
SHANI_FORM_FACTOR=phone SHANI_WIDTH=412 SHANI_SCREEN=915 sh dev/check.sh shell=phone
sh dev/check.sh shell=form-factor shell=tablet shell=handheld shell=board shell=laptop
sh dev/check.sh shell=touch-actions shell=breakpoints
```

`SHANI_FORM_FACTOR` forces a profile; it does not set resolution, DPI or input
hardware. `SHANI_WIDTH`/`SHANI_SCREEN` configure nested shell tests.
`dev/render.sh` has its own screen setup; do not assume these environment
variables make all renders portrait. A full suite validates its particular
source tree and fixtures, not real telephony, pens, casting or gamescope.

The render run also fails on a QML layout warning (`QQuickLayout`, "is larger
than"): Qt only warns when a layout's minimum is wider than its window, and the
picture still looks plausible. 101 surfaces render at the phone profile with none.
