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
| Laptop | ~100% | battery and charging, lid, brightness, keyboard backlight, power profiles, touchpad toggle, the layout following dock / undock | — |
| Tablet | ~70% | the Touch layout, the screen keyboard on fold-to-tablet (TabletMode), auto-rotate, the Smart Touch bubble, edge swipes, a long press for the right-click | the keyboard on text-field focus, finger-sized controls everywhere (only the dock is), one size control for the whole UI |
| Handheld | ~60% | the TV home at arm's length, the built-in pad through InputPlumber (Guide is home, ⋯ the quick panel over a game), a sideways Deck or Legion Go panel turned the right way | TDP control (ryzenadj / PowerStation are not in Arch's repos); unverified on real hardware: InputPlumber's "pass" mode for the ⋯ button, the Legion Go's turn |
| Board | ~70% | a board profile (the bar and Quick Settings at the bottom within a child's reach, the dock above them), the whiteboard (pages, six inks, a PDF), the pen as a pen (pressure, its eraser end, palm rejection), the resetting guest | receiving a cast (no maintained receiver in Arch's repos; UxPlay, in the AUR, when it is back) |
| TV | ~60% | the 10-foot home, the whole desktop by remote and controller, typing from a remote, a controller pointer, a TV known by its EDID name | the gamescope image's desktop mode still isn't this shell (the open decision below) |
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
- **Handheld** - done: the TV home at arm's length (scale 1.25, touch on every
  card); through InputPlumber, Guide is the home and back to the game, the ⋯
  button the quick panel over the game (`Modules/QuickPanel`: brightness,
  volume, performance, the screen keyboard, home, close the app); a sideways
  panel turned the right way once a session by the machine's DMI name (Steam
  Deck LCD and OLED, Legion Go; any other portrait-made handheld panel as the
  Deck), unless the owner set a turn or auto-rotate is on. Tested in
  `dev/shell-parts/handheld.sh` (the pad's presses through the InputPlumber
  stand-in) and `tests/test_form_factor.py`. Unverified until real hardware:
  whether InputPlumber's "pass" mode hands the ⋯ button to the shell as it does
  Guide (the shell borrows the pad itself when either arrives), and the Legion
  Go's turn. Left: TDP control (not in Arch's repos).
- **Tablet** - done: edge swipes on tablet and phone screens (`Modules/EdgeStrips`,
  `Common/Gestures.js`: from the bottom the launcher, the top Quick Settings, the
  left back, the right the overview), the screen keyboard with a text field of the
  shell (and gone with it), scale 1.2. Tested in `dev/shell-parts/tablet.sh`
  (the actions through IPC: a nested niri has no finger to swipe with) and
  `tests/test_gestures.py`. Left: the keyboard for apps' own text fields (needs
  text-input from niri, which the shell cannot see).
- **Board** - mostly: scale 1.4, and the bar and Quick Settings at the bottom of
  the screen, within reach of someone standing at it - the owner can still put the
  bar back at the top (Settings > Personalisation > "The bar sits"). The
  whiteboard (`Modules/Whiteboard`, from the launcher): pages, six inks, three
  widths, a whole-stroke eraser, undo, several fingers writing at once, saved as
  one PDF in Documents/Whiteboards. Tested in `dev/shell-parts/board.sh` (the
  bar's edge, the whiteboard, the saved PDF). The pen as a pen: a line as wide
  as it is pressed, its eraser end and side button erase, touches ignored while
  it is near and a palm at any time (`Common/Pen.js`, `tests/test_pen.py`; the
  handlers need a real pen to verify). The guest: Settings > Users > Guest makes
  a passwordless, never-admin account; shani-desktop-niri's `guest-reset` makes
  its home new before and after every session (a `user-runtime-dir@` drop-in)
  and logind ends its programs at sign-out; the greeter sends its empty answer
  as the password (tested: `dev/check.sh admin`, `pam`, `greeter`). Left:
  receiving a cast - skipped for now; nothing in Arch's repos receives a screen,
  the one maintained receiver is UxPlay (AirPlay, in the AUR) to package when it
  comes back, and Miracast/Chromecast have none maintained.
- **Laptop** - done: the layout follows the desk (`Services/Docking`). Docked and
  on its own, the laptop each keeps the dock, bar, desktop widgets and icons,
  gaps, window width and hot corners the owner last used there; the first time in
  a state nothing changes and is remembered from then on. Only on a machine with a
  built-in panel, and one switch turns it off (Settings > Personalisation > "The
  layout follows the dock"). Tested in `dev/shell-parts/laptop.sh`, which drives
  the desk through the IPC hook a nested niri needs (it has no panel to unplug).
- **Phone** - started: one column. The bar keeps the launcher, the status cluster
  and the clock, and drops the workspaces, the world clock and the date; the
  launcher drops the preview pane beside its results, so the field and the
  results take the whole width; and Quick Settings is a shade that comes up from
  the bottom over the whole screen, not a column in from the right. All of them
  ask the screen's kind, not its pixels, so a phone-sized window on a computer
  keeps everything (`dev/shell-parts/phone.sh`: the profile and its scale, the
  one-column bar and launcher, the shade, and a wide screen keeping everything).
  A notification is a card the width of the screen now, not 437 of 412. Left:
  the lock screen in portrait - still unverified, and the reason is the harness:
  every run is a 1920x1080 nested niri, and the profile only changes the scale,
  so nothing here can tell a 412-wide screen from a small window. SHANI_WIDTH=412
  SHANI_SCREEN=915 now makes one (dev/session.sh), which is what the next piece
  needs; Settings in portrait; gesture navigation; calls; one app at a time.
- **Touch** - a long press is a right-click on a touch screen, wherever a right
  button opens something: the desktop, its files, the shelf, a quick-settings
  tile, the island, the ring, the viewer, the magnifier, the ruler and the bin
  (`Common/Gestures.js`, tested in `tests/test_gestures.py`; the click that ends
  a long press is swallowed, so one press does one thing).

## The order

| Step | What | Sessions (rough) |
|---|---|---|
| 1 | Foundation: profile, UI scale, breakpoints, the size conversion | 2–3 |
| 2 | **TV**: the 10-foot home, the buttons' meanings, TV auto-detection - done (the gamescope image is the open decision) | 1–2 |
| 3 | **Handheld**: the TV home at arm's length, the quick panel over a game, portrait panels turned - done (TDP control is not in Arch's repos) | 1–2 |
| 4 | **Tablet**: edge swipes, the long press, the keyboard for the shell's own fields - done; the keyboard for apps' fields (needs niri text-input), touch-sized targets | 2 |
| 5 | **Laptop**: the layout follows dock / undock - done | <1 |
| 6 | **Board**: the board profile (reach zones, big targets), a whiteboard mode that saves to a PDF - done; the pen as a pen (pressure, palm rejection, its buttons), a resetting guest session, receiving a cast (skipped for now) | 2–3 |
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
- **Kiosk and signage**: a separate image (shani-install-media's `kiosk`
  profile: gdm autologin into cage + Firefox, a passwordless `kiosk` account
  with its home on tmpfs, new at every boot) with one app on purpose; not this
  shell. The board's guest is the same idea for a person rather than a screen:
  a home made new at every sign-out, not only at boot.

## Decisions it depends on

- **The console's desktop mode becomes this shell** (TV profile) instead of
  sway + the Control Center. Assumed by step 2; to be confirmed.
- **Native or Flatpak Steam** on the gamescope image. Separate from this plan,
  but it decides how much of the console's Steam glue survives.
