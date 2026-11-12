# UI/UX improvement backlog

Gathered from a scan of `shani-shell` settings and surfaces plus standard
discoverability/picker guidance. Items are ordered by impact; none require
changing the IPC contract or settings schema.

## 1. Discoverability

- **Highlight the matched term in settings search results** (SettingsIndex
  already returns matches; the flash lands on the row but the word is not
  highlighted). Add a `HighlightText` component to `ListRow`/search rows.
- **Empty state for "no matches"** in settings search: currently the list
  just empties. Show "No setting matches — try 'proxy', 'fonts', 'lid'…"
  with the three most popular settings as chips.
- **Recently changed** rail at the top of Settings: the last 5 settings
  touched, so a person who opened Settings to undo something finds it.
- **Per-setting "reset to default"** affordance (hover/long-press) in
  addition to the section-level reset; scalars only, lists survive.
- **"What's new" toast** on first run after an update, listing 3 changed
  settings with a button that opens them.

## 2. Clickability and pickers

- Every picker already keeps a custom typed field; make that field visually
  distinct (dashed border + "Custom…" label) so it is obvious it is the
  escape hatch, not the primary path.
- **Numeric settings that are still sliders** (display scale, animation
  speed) should also expose choice chips for the common values, with the
  slider as the "fine" control.
- **App pickers** (terminal, screenshot annotation tool, autostart) should
  show the app icon and name, and group "Installed" vs "Custom command".
- **Folder pickers** should remember the last 5 browsed folders as quick
  chips, and offer "Use default" to clear a custom path.
- **Time picker** (alarm/schedule) should accept natural language
  ("tomorrow 9am") in the custom field, not only HH:MM.
- **Date picker** should highlight today and offer "Today / Tomorrow /
  Next week" chips above the calendar.

## 3. Feedback and safety

- **Toast on every setting change** that has a visible effect ("Accent
  changed", "Wallpaper applied"), auto-dismissing, with an Undo button for
  5 seconds.
- **Confirm before destructive actions** (forget network, remove account,
  reset section) — currently some do, some do not. Unify behind one dialog.
- **Inline validation** with a red underline and a one-line reason, instead
  of a separate status line, for username/hostname/password fields.
- **Disabled-why tooltips**: when a toggle is greyed out, hover shows the
  reason ("needs a battery", "no Wi-Fi adapter") instead of silent.

## 4. Accessibility

- All interactive controls already carry Accessible names (verified by
  `shell-test.sh`); extend the same to the new pickers and the setup rail.
- **Visible focus rings** on keyboard navigation in Settings and the control
  centre (currently hover-only in several places).
- **Reduce-motion respect**: when `reduceMotion` is on, replace the
  ripple/scale presses with instant state changes.
- **High-contrast palette** should also recolour picker chips and dots,
  not only the cards.

## 5. Empty and loading states

- Lists (networks, Bluetooth devices, printers, web apps, saved networks)
  show nothing while empty. Add an icon + one-line explanation + the action
  that fixes it ("Turn on Bluetooth", "Add a printer").
- **Skeleton placeholders** while settings load on first open, instead of
  a blank panel.

## 6. First-boot setup (follow-ups)

- **Scroll the language list to the selected locale on load** (implemented)
  and also when switching language via a chip.
- **Keyboard test field** should show the typed characters in the chosen
  layout's script, with a "this is what it looks like" preview.
- **Network page** should auto-connect to an open network and show a
  spinner, instead of requiring a click.
- **Time page map** should show the nearest city name next to the marker.
- **Account page** summary should be editable inline (click a value to
  jump to that page) — the rail already allows this.
- **Done page** should show a 3-second countdown and the user's avatar
  before signing in, instead of an instant transition.

## 7. Consistency and polish

- Unify button kinds: primary (accent), outline (secondary), danger (red),
  ghost (text). Document in `Common/Button.qml` header (done for outline).
- All section titles use `SectionTitle`; a few pages still use ad-hoc
  `Text` with `font.weight: DemiBold`.
- Spacing tokens: replace magic numbers (6/8/10/12/14) with named
  `Theme.space*` constants for consistent rhythm.
- Icon sizes: standardise on 16 (inline), 18 (row), 24 (tile), 32 (hero).

## 8. Performance and reliability

- Settings search index is 204 entries; rebuild it only when the settings
  file changes, not on every keystroke.
- Avoid live-reload resetting wizard state: guard `onCompleted` so a file
  change during a test does not restart the wizard (relevant for dev only).
- Lazy-load heavy pages (Printers, About) so Settings opens faster.

## Tracking

- Add each implemented item to `FINDINGS.md` with the date and the setting
  keys touched.
- Remove from `GAPS.md` "not built — yet" only when a test covers it.
EOF
echo done
## 9. Design references and what to borrow

### Deepin (dde-control-center)
- **Grouped, glanceable categories** with one-line descriptions under each
  tile; no nested menus deeper than two levels.
- **Quick operations row** at the top of the control center (backup/restore,
  updates, network status) — actions, not just settings.
- **Channel merging** in Sound: per-app streams fold into the device they
  play on; our mixer already lists streams, but grouping by output device
  would match.
- **Gesture tracking visualiser** for touchpad: show the recognised gesture
  live while the user tries it.
- **Real-time multi-monitor scaling** without logout — niri supports this;
  our Displays page should apply immediately.

### Pantheon (elementary Switchboard)
- **Minimal preferences**: only expose what most people change; hide the
  rest behind "Advanced" (we already do this in places — extend it).
- **Headerbars instead of title bars** for dialogs; consistent with our
  Glass cards.
- **Single-click to open** throughout; already our default.
- **Common design patterns across apps** so knowledge transfers — keep
  `Common/` components the single source of truth.

### Cutefish
- **Simplicity first**: fewer, larger, well-spaced controls; avoid dense
  grids of small toggles.
- **Attention to detail**: every icon, spacing and animation checked; our
  spacing tokens (section 7) address this.
- **Respect the user**: never block, never surprise; confirm before
  destructive actions (section 3).

### Android / Android TV
- **Cards with clear affordance** (chevron or switch) and large touch
  targets (min 48 px) — relevant for touch screens and tablets.
- **Chips for finite choices** (already adopted) and **bottom sheets** for
  pickers on small screens instead of full dialogs.
- **10-foot UI for TV**: focus rings, large text, remote-friendly
  navigation; our `largeText`/`highContrast` modes are the seed — add a
  "TV mode" layout preset with bigger tiles and focus outlines.
- **Pull-to-refresh** on lists (networks, Bluetooth) instead of a
  separate Refresh button.

### Cross-cutting lessons
- Prefer **progressive disclosure**: show the common case, reveal advanced
  options on demand.
- **Inline, immediate feedback** beats a separate "Apply" button.
- **Empty states are features**, not afterthoughts.
- **Search is the escape hatch** for everything not on the first screen.

## 10. Patterns from macOS, Windows and Android / custom ROMs

### macOS (System Settings)
- **Sidebar search that filters the sidebar itself** (not just content):
  typing "proxy" collapses the sidebar to the matching panes. Our settings
  search already returns rows; also collapse the category list to matching
  categories.
- **Inline disclosure triangles** for advanced options instead of a separate
  "Advanced" button — keeps the page short.
- **Hover-revealed "i" info buttons** next to technical terms, opening a
  popover with the explanation.
- **Reset button per pane** in the toolbar (not buried in a menu).

### Windows 11 Settings
- **Breadcrumb / back chevron** at the top of every page; our settings
  already have category navigation, but a visible breadcrumb helps.
- **"Find a setting" search box always visible** in the sidebar header
  (we have this; keep it).
- **Toggle with a one-line description** under the label; our SwitchRow
  already supports `hint` — ensure every switch has one.
- **"Learn more" links** next to non-obvious settings, opening the docs.

### Android / AOSP
- **Cards with a leading icon, title, summary and trailing control** —
  our ListRow/SwitchRow already follow this; standardise padding.
- **Bottom sheets for pickers** on small screens; full dialogs on large.
- **Pull-to-refresh** on lists (networks, Bluetooth, printers).
- **Chips with a leading icon** for filters (already possible).
- **Long-press for context actions** (forget, rename, share) on list rows.

### Android custom ROMs (LineageOS, GrapheneOS, MIUI, One UI)
- **One UI: bottom-aligned primary actions** for thumb reach on tall
  screens — put the primary button in the bottom bar on phone/tablet sizes.
- **MIUI: grouped settings with coloured section headers** and a
  "Frequently used" strip at the top.
- **LineageOS: trust/privacy dashboard** summarising permissions granted
  — a single "Privacy checkup" page.
- **GrapheneOS: per-app permission toggles with explanations** and
  "sensors off" quick tile — maps to our privacy toggles.

### Cross-cutting additions
- **Undo toast** (5 s) for every destructive or hard-to-reverse change.
- **"What changed" diff** when resetting a section.
- **Keyboard shortcuts** for the 10 most common settings (e.g. Ctrl+, to
  open Settings, / to search).
- **Recent settings** and **pinned settings** (star a setting to keep it
  at the top).

## 11. Features worth borrowing from Android custom ROMs

### LineageOS
- **System profiles**: named profiles (Home, Work, Sleep) that change ring
  mode, brightness, lock behaviour, alarm volume at once — we already have
  Focus modes; extend them to also switch wallpaper, accent and dock layout.
- **Hardware button remapping**: long-press power → flashlight; our niri
  binds are fixed, but exposing them in Settings (Keyboard shortcuts) would
  match.
- **Status bar icon toggles**: choose which status-bar icons show.
- **Privacy guard / per-app permission revocation** with a single "revoke
  all" — maps to our app filter and privacy toggles.
- **Button backlight / LED control** for notifications.

### GrapheneOS / CalyxOS
- **Privacy dashboard**: a single page summarising which apps used
  location, mic, camera, with timestamps and a "revoke" action.
- **Sensors off quick tile**: one toggle killing all sensors (we have
  privacy toggles; a single "sensors off" mode is simpler).
- **Network permission per app** (allow/deny internet) — our app filter
  could gain this.
- **Auto-reboot after inactivity** for security.
- **Duress PIN** that wipes on entry.

### MIUI / HyperOS
- **Super wallpapers** (animated, depth-aware) — our wallpaper system
  could accept a video/animated wallpaper.
- **Floating windows / pop-up view** with a handle — niri floating windows
  already; a "pop-up view" mode pinning a small window on top.
- **Second space / work profile** for separating personal and work.
- **Game turbo / performance mode** — our GameMode service already exists;
  surface it as a visible tile with FPS counter.

### One UI (Samsung)
- **Bottom-aligned primary actions** for thumb reach on tall screens.
- **Edge panels** (swipe-in sidebar of apps/contacts/tools) — our dock
  could gain a swipe-in edge panel.
- **Good Lock style modular customization** — let users install "modules"
  that add tiles/panels without core changes.
- **Eye comfort / blue light schedule** with a slider — our night light
  already; add a quick slider in the control centre.

### ColorOS / OxygenOS
- **Shelf**: swipe-down dashboard of widgets (we have a shelf; extend with
  user widgets).
- **Zen mode**: lock the phone to a few apps for a set time — a "focus
  session" mode.
- **Quick settings tiles customizable** with drag-and-drop (we have tile
  reorder; extend to quick settings).
- **Scrolling screenshots** — our screenshot tool could capture a full
  scrollable window.

### Cross-ROM
- **Per-app volume** (we already have per-app mixer).
- **App cloning** for two accounts.
- **Hidden apps** behind a PIN.
- **Scheduled power on/off**.
- **Battery health and charge limit** (we surface charge limit where
  available).

## 12. What else dux (DMS) has that we could take

dux is the other shell in this workspace (`../dux-shell`): a Quickshell shell
with a **Go** backend (a unix socket, ~146k lines) and a **plugin framework**.
Scanned 2026-11-11 against `dux-shell/quickshell/{Modules,Services,Common,
PLUGINS}`, `dux-shell/core/` and the shared widget library
`dux-qml-common/DCommon/`. Its file manager is already ported (see
`FINDINGS.md`); this is the rest of the survey.

### 12.1 The plugin system — the big one

dux's `quickshell/PLUGINS/` is a real framework, and we have none — while
§11 (One UI) already asks for exactly this: "Good Lock style modular
customization — let users install 'modules' that add tiles/panels without core
changes".

How it works there: plugins are directories in `~/.config/dms/plugins/` with a
`plugin.json` manifest (JSON Schema: `id`, `name`, `type`, `capabilities`,
plus optional `components`, `settings`, `permissions`, `startupCheck`, `dash`).
`Services/PluginService.qml` watches the directory, parses the manifests and
loads the components with `Qt.createComponent(url, Component.PreferSynchronous,
root)` — with a `?revision=N` cache-buster, because **Qt caches a failed
component per URL** (a file added after startup otherwise fails with "File
name case mismatch" until a restart). Surface types: `widget | daemon |
launcher | desktop | dash | dashCard | composite`. Plugin *settings* live in
their own file, plugin *state* in another, and state writes are debounced
(150 ms) so a chatty plugin costs one write, not hundreds.

What we would need before it can work here:
- **A plugin store** — `Common/Settings.qml` is a `JsonAdapter` with a fixed
  key set, so plugin namespaces cannot live there. It needs its own
  `~/.config/shani-shell/plugin_settings.json`.
- **A `Style` shim** — dux's widgets read `Style.primary` / `Style.surfaceText`;
  ours are `Theme.accent` / `Theme.text`. A missing token renders
  black-on-black rather than erroring, so the mapping must exist *before* the
  first widget port.
- **`Tr.tFor(pluginId, s)`** — `Common/Tr.qml` is a flat string→string map with
  no per-plugin namespace.
- **A popout framework** — we have no `DPopout`/`PopoutService`; that is the
  hardest surface. A v1 could ship bar pills + desktop widgets + launchers and
  defer popouts.

The most valuable artefact is not the code but the **12-document plugin spec**
in `dux-shell/.agents/skills/dms-plugin-dev/` — a complete, versioned API
description that can be re-pointed at `qs.Common`/`qs.Services`.

### 12.2 Pure logic worth copying verbatim

No UI dependencies, no `Style`; each is testable in node the way
`tests/test_fuzzy.py` already runs `Fuzzy.js`.

**Landed (2026-11-11, `tests/test_shell_helpers.py`):**

- **`Common/Contrast.js` (85)** — `Services/Color.qml` had its own copy of the
  WCAG maths; it now uses the shared one, and `Theme.accentInk` is
  *measured* (`readableOn`) instead of guessed from the accent's lightness.
- **`Common/Shape.js` (79)** — the corner scale, with the shell's own radii in
  it (s = 10, l = 16, xl = 22). `Theme.radius*` comes from it, and the
  hardcoded `radius: 10` / `radius: 8` in `Common/` are tokens now.
- **`Common/WheelInput.js` (42)** — a wheel notch is one step, a finger slides
  by its own pixels. `Common/SliderRow.qml` used to jump 5 % per pixel of
  finger movement.
- **`Common/Proc.qml` (188)** — run a command with a debounce and a timeout, so
  a burst of calls runs once and a command that hangs cannot wedge the shell.
  Used by `Services/Disktree.qml` (a disk walk) and, with its own queue, by
  `Services/Files.qml`.
- **`Common/Log.qml`** — a scoped logger: `Log.scoped("Files")`, quiet by
  default, `SHANI_LOG=Files,Audio` to name the ones that should speak.
- **`Common/Hct.js` + `Tonal.js` + `Accents.js`** (439) — Material's colour
  space, with the Apache-2.0 notice beside them. In the tree and tested, but
  **not wired**: ranking a wallpaper by chroma picks the Saturn ring's
  lavender over the planet's amber, and the accent is meant to be the brand's
  amber. Deriving the palette is a design decision, not a port.

**Still to take:**

- **`Common/FocusNavigation.js` (60)** — tree-order focus traversal (a helper
  for ported list widgets; **not** a replacement for `Common/KeyFocus.qml`,
  which is richer).
- **`Common/fzf.js` (1416)** — ranked fuzzy matching with highlighting. Keep
  our `Modules/Launcher/Fuzzy.js` for the launcher (typo tolerance, already
  tested); BSD-3 attribution needed.
- **`Common/MaterialWallpaper.js` (529)** + `MaterialShapes.js` — procedural
  wallpapers, for §11's "super wallpapers".
- **`Common/IconImagePool.qml` (71)** — an LRU pool of `IconImage`s under a
  4 MB budget. Worth little here: our icons are 18–54 px and Qt already
  caches the decoded pixmap by path. Take it only if a surface ever shows
  hundreds of large icons.

### 12.3 Widgets worth porting (once the `Style` shim exists)

`DSparkline` (198) and `DRingGauge` (84) — live CPU/mem/net graphs;
`Modules/Processes` shows numbers only today. `DFilterChips` (160) — our
`Common/Choice.qml` is single-select. `DSearchField` (15) and
`DTooltipHost` (66). `DReorderList` (274) — we reorder tiles by hand.
`DAnalogClock` (186) — our desktop clock is digital. `DCarousel` (36).
`DCollapsibleSection` (174) — extends `Common/Advanced.qml`. `DBottomSheet`
(320) — §9's bottom sheets for touch. `DIconPicker` (317) — we have no icon
picker, but **its icon names do not transfer**: dux is Material Symbols, we
are Adwaita symbolic.

### 12.4 Surfaces and behaviours we lack or could improve

- **A colour picker you can *choose* from** — `Services/Color.qml` only
  samples one off the screen (`niri msg pick-color`); dux has an SV picker, a
  hue slider, hex/rgb/hsv fields and a 49-colour palette.
- **A global toast service** — our `Common/Toast.qml` is used only by the
  Settings window. dux's `ToastService` queues, throttles and drops toasts
  from the top edge; it is also the enabler for §3's "toast on every setting
  change with Undo".
- **Blurred wallpaper and video wallpaper** — `BlurredWallpaperBackground.qml`
  (331) and `VideoWallpaperLayer.qml` (85); §11 wants animated wallpapers.
- **A richer desktop context menu** — `Modules/Background/Wallpaper.qml:91`
  has six rows that mostly open Settings; dux's has a wallpaper strip,
  per-monitor wallpaper and plugin entries.
- **Desktop widget resize and a widget registry** — ours has four fixed cards
  (clock, media, weather, stats) with drag-to-move only; the registry is also
  what would let plugin widgets place themselves.
- **Hold-to-confirm power menu** — dux's `PowerMenuContent.qml` (427) and
  `DCommon/Session/LockPowerMenu.qml` (885) use a progress ring; our lock
  screen uses "press twice".
- **A system monitor with history** — CPU/mem/net graphs, plus dux's drive
  health tree (`Services/Drives.qml` lists drives only).

### 12.5 Not to take

- **dux's Go core and socket protocol** — our Python-bridge architecture is
  deliberate; a Go daemon is a re-architecture, not a port. The one exception
  is a plugin registry, which could be a `bridge/plugins.py` doing a
  `git clone`, not `core/internal/plugins/`.
- **dux's `cups.*` namespace** (26 methods) — `GAPS.md` lists "print-queue
  state in the Island (CUPS)" as built-but-unproven, and
  `Services/Printing.qml` deliberately shows a job count and opens
  `system-config-printer`. Porting it would contradict our own scope.
- **`Frame`, `WorkspaceOverlays`** (Hyprland and niri-overview chrome),
  **`AppDrawer`**, **`Notepad`**, **`OSD`**, **`Network`**, the `sysupdate`
  backends — we have equivalents, or deliberately delegate (updating is
  Cassini's job).

### 12.6 Order to take them in

1. **Prerequisites (S)** — the `Style` shim, a `Log` singleton, `Tr.tFor`.
2. **The pure-logic batch (S)** — `Proc.qml` first, then the JS above, each
   with a node test.
3. **Small visible surfaces (S–M)** — global toast service, colour picker,
   blurred and video wallpaper, desktop-widget resize, desktop context menu.
4. **The plugin system (L)** — v1 only: plugin store + service + manifest
   schema + bar/desktop/launcher surfaces + a scan/enable/disable Settings
   page + two example plugins. The registry, the dash and popouts come later.

### 12.7 Open decisions

- How far the plugin system goes in v1 (bar/desktop/launcher only, or also
  popouts and a registry)?
- Is the `Style` shim a permanent compatibility layer over `Theme`, or a
  one-off translation during each port?

