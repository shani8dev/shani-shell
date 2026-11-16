# One shell, every form factor

The plan for shani-shell on a phone, a tablet, a handheld (Steam Deck, ROG
Ally, Legion Go), a laptop, a computer, a TV and a classroom board (an
interactive touch panel). One shell with form-factor profiles, not seven shells: a fix to the launcher
lands on every device. An item leaves this file when it is built *and* a test
runs it (the same rule as GAPS.md).

Measured 2026-11-16 against `master` (70 modules, ~33,000 lines of QML).

## Where each one stands

| Form factor | Done | What is there | What is missing |
|---|---|---|---|
| Computer | ~95% | six desktop layouts (LayoutSwitcher), multi-monitor, keyboard and mouse everywhere | — |
| Laptop | ~90% | battery and charging, lid, brightness, keyboard backlight, power profiles, touchpad toggle | the layout following dock / undock by itself |
| Tablet | ~55% | the Touch layout, the screen keyboard on fold-to-tablet (TabletMode), auto-rotate, the Smart Touch bubble | edge-swipe gestures, the keyboard on text-field focus, finger-sized controls everywhere (only the dock is), one size control for the whole UI |
| Handheld | ~45% | InputPlumber (the built-in pad, lent to the desktop over a game), controller navigation and typing, the controller pointer, touch, battery | a handheld profile (7–8" at arm's length: bigger than a laptop, smaller than a TV), a quick panel over a running game (brightness, volume, performance), portrait panels turned the right way (the Deck's and the Legion Go's are portrait), TDP control (PowerStation and ryzenadj are not in Arch's repos) |
| Board | ~30% | drawing over anything on screen (Annotate), Magnifier, Ruler, the PDF reader, casting, the Touch layout, the screen keyboard | a board profile (65–86" touch, used standing up: controls within a child's reach at the bottom, nothing important at the top), many fingers and pens at once, pen vs. finger (write with the pen, move with the finger), a whiteboard surface and saving it, a guest session that resets after a lesson, a teacher's laptop cast onto it |
| TV | ~40% | the whole desktop by remote and controller (KeyFocus, GamepadNav, InputPlumber, `remote*` IPC), typing from a remote, a controller pointer | a 10-foot home, sofa-sized type and targets, knowing a TV is connected |
| Phone | ~15% | the SIM PIN and texts (Modem), the phone link (Phone), the screen keyboard | a portrait layout of every surface, gesture navigation, a notification shade, a phone lock screen, a calls UI, one app at a time |

## The blocker they share: fixed sizes

1,875 sizes in the QML are literal pixels (`width: 320`, `pixelSize: 13`);
855 already go through `Theme`. The only global scale is text
(`Theme.fontScale`, 1.25 with Large text). Tablet, TV and phone all need the
same foundation before any of their own work:

1. **A form-factor profile per screen** in `Common/Theme`: `phone`,
   `tablet`, `handheld`, `laptop`, `computer`, `tv`, `board`. Per screen, not global: a
   laptop with a TV on HDMI is a laptop on its panel and a TV on the TV, at
   once; and it switches live (a 2-in-1 folded into a tablet, a laptop docked). Chosen from the output's physical size and density, the
   input there is (touchscreen, keyboard, `InputKinds`, the tablet switch) and
   whether the output is a TV (EDID); the owner can always override it.
2. **One UI scale**: every size through `Theme` (`Theme.px(n)` or named
   sizes), so a profile can scale the whole shell, not only its text.
   Mechanical for the most part — a script rewrites the literals, then
   `dev/render.sh` shows what moved. Worst first: Settings (262), Quick Settings
   (107), Files (83), Background (47), Chronoa (43), MediaPlayer (42).
3. **Width breakpoints**: surfaces reflow by available width (one column,
   two, a sidebar or a sheet). The shell has one breakpoint today.

## Progress

- **Profile per screen** - done: `Common/FormFactor.js` (the rules, tested in
  `tests/test_form_factor.py`), `Services/FormFactor` (per screen, live, the
  owner's choice in Settings > Displays > Kind of screen), `Theme.ui` /
  `Theme.px()`; `SHANI_FORM_FACTOR=tv sh dev/check.sh render` draws every
  surface as that kind (`dev/shell-parts/form-factor.sh`).
- **One UI scale** - done: `tools/ui-scale.py` drew 2,600 literal sizes through
  `Theme.px()` (identical on a computer, where the scale is 1); `check` keeps
  it at 0. Left: sizes computed in expressions (`list.width / 132`).
- **Width breakpoints** - not started.
- **TV home** - done: `Modules/TvHome` on every screen whose kind is TV - shelves
  of what is open, pinned apps, games, every app, settings and power, the clock
  and status on top, what the buttons do below; arrows / OK / Back / Home from a
  remote, the controller (Guide is Home), mouse and touch. Tested in
  `dev/shell-parts/tv-home.sh` with real key presses. Left for TV: auto-detection
  from EDID (a TV that reports no size is a computer until chosen), and the
  gamescope image's desktop mode switching to this shell.

## The order

| Step | What | Sessions (rough) |
|---|---|---|
| 1 | Foundation: profile, UI scale, breakpoints, the size conversion | 2–3 |
| 2 | **TV**: a full-screen home (shelves of apps, games, settings; clock and status on top; the buttons' meanings below), the 10-foot scale, TV auto-detection | 1–2 |
| 3 | **Handheld**: the handheld profile (the TV home at arm's length, with touch), a quick panel over a running game on the Guide / ⋯ button, portrait panels rotated by device | 1–2 |
| 4 | **Tablet**: edge swipes (bottom: launcher, top: Quick Settings, sides: back / switch), the keyboard on text-field focus, touch-sized targets | 2 |
| 5 | **Laptop**: the layout follows dock / undock | <1 |
| 6 | **Board**: the board profile (reach zones, big targets), the pen as a pen (pressure, palm rejection, its buttons), a whiteboard mode that saves to a PDF, a resetting guest session, receiving a cast | 2–3 |
| 7 | **Phone**: portrait versions of the bar, launcher, Quick Settings (as a shade), notifications, lock screen and Settings; gesture navigation; calls; one full-screen app at a time | 5–8 |
| | **Total** | ~13–20 |

TV comes first because the gamescope image's desktop mode can then be this
shell in its TV profile, and the console stops having a second UI of its own
(the sway + GTK home in shani-desktop-gamescope). The phone comes last: it is
the largest step and needs hardware ShaniOS does not target yet.

## How each step is tested

- Every profile renders in `dev/render.sh` at its own size and scale (phone
  412×915 @3, handheld 1280×800 @1.25, tablet 1280×800 @2, laptop
  1366×768 @1 and 2880×1800 @2, computer 2560×1440, TV 3840×2160 @2, board
  3840×2160 @1.5, and a laptop with a TV beside it); a render that clips or overflows fails.
- The shell suite gets a part per form factor (`dev/shell-parts/`), driven
  the way that device is driven: touch for phone and tablet (not keys), the
  built-in pad and touch for the handheld, the remote and the controller for TV,
  the pen and several touches at once for the board (`remote.sh`, `pad-tour.sh` are the start).
- Nothing counts as done until it has run on real hardware of that kind
  through shani-testbed, not only in the dev container.

## Also considered

- **2-in-1 convertibles, docks, a TV on HDMI**: not form factors of their own
  but changes between them, which is why the profile is per screen and live.
- **Touchscreen all-in-ones**: the computer profile with touch input;
  `InputKinds` decides what is offered, not the screen size alone.
- **Projectors and presenting**: the existing presenting mode (`Plugged`).
- **Kiosk and signage**: a separate image (cage + labwc + Firefox) with one
  app on purpose; not this shell.

## Decisions it depends on

- **The console's desktop mode becomes this shell** (TV profile) instead of
  sway + the Control Center. Assumed by step 2; to be confirmed.
- **Native or Flatpak Steam** on the gamescope image. Separate from this plan,
  but it decides how much of the console's Steam glue survives.
