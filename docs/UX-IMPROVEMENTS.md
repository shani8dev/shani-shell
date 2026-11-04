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
