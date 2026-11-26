# Components

Everything here lives in `shani/Common/` and is imported as `qs.Common`. A
surface passes data and semantics; the component owns geometry, colour, states
and accessibility. **Canonical** marks the one to use when a pattern repeats —
fix it there, not at the call site.

Consumer counts are `grep -rl "<Name> {" shani/Modules | wc -l` at time of
writing; treat them as a reach warning, not a target.

## Layout and grouping (docs/DESIGN.md)

### AppPage.qml — an app's page  ·  canonical for app pages
- `title`, `subtitle`, `actions` (alias: buttons on the right), default content
  in a centred column (`maxContentWidth` `Theme.px(1100)`) that scrolls;
  `compact` under 600 px: title one step smaller, actions under it.

### Card.qml — a group on its own surface  ·  canonical for groups
- `icon` (on a tinted badge), `title`, `subtitle`, `tint`, `actions` (alias),
  default content (rows), `spacing` (`Theme.space(3)`), `padding`.
- Draws flat (no surface) inside another card by itself (`isCard` on an ancestor).
- `SettingsSection` is a Card with `hint` as its subtitle.

### StatTile.qml — one fact at a glance
- `icon`, `label`, `value` (subtitle size), `detail`, `progress` (0..1 bar, <0
  none), `tint`, `interactive` + `signal clicked()`.

### StatusHero.qml — the answer first
- `tone` (`ok | warn | error | info | busy`), `overline`, `headline`, `detail`,
  `chips` (short facts, as StatusPills), `actions` (alias); stacks under 560 px.

### TileGrid.qml — tiles that wrap to their width
- `minTileWidth`, `maxColumns` (4); columns from its own width; every child fills
  an equal share.

## Feedback

### InfoBanner.qml — inline status message  ·  canonical for banners  ·  17 surfaces
- `tone`: `info` (default) | `ok` | `warn` | `error` | `danger` | `accent`.
  `ok`/`accent`→`Theme.accent`, `warn`→`Theme.amber`, `error`/`danger`→
  `Theme.danger`, `info`→`Theme.blue`.
- `title`, `text`, `iconName`, `toneColor` (readonly), `cornerRadius`
  (`Theme.radius`), `padding` (`Theme.px(12)`), `iconSize` (`Theme.px(18)`),
  `accessibleRole` (StaticText), default `actions` alias.
- Pass an explicit `tone`; never infer tone from a translated string.

### EmptyState.qml — nothing-here card  ·  canonical for empty lists  ·  56 surfaces
- `icon` (`"preferences-system"`), `title`, `subtitle`, `actionText`,
  `iconSize` (`Theme.px(40)`), `padding` (`Theme.px(8)`), `accessibleRole`
  (StaticText), `signal action()`.
- Shares the radius/padding/iconSize scale with InfoBanner — change together.

### ConfirmButton.qml — two-tap destructive confirm  ·  canonical for confirm  ·  12 surfaces
- `text`, `armedText` (`Tr.t("Tap again")`), `value` (id passed to `confirmed`;
  `id` is reserved in QML), `interval` (4000 ms), `kind`: `plain | danger |
  outline` (default `plain`), `armed`, `danger` (readonly).
- `signal confirmed(string id)`, `disarm()`. Call `disarm()` on tab/surface
  change.

### BusyNote.qml — one busy row  ·  canonical for "spinner + note"  ·  18 surfaces
- `note`, `iconSize` (`Theme.px(16)`), `align` alias.
- `Accessible.role: StatusBar`. Do not hand-roll `Row { Spinner; Text }`.

### Toast.qml — transient message
- `Toast.qml`; short-lived overlay. Use for non-blocking confirmations that do
  not belong to a surface's own layout.

### Spinner.qml — busy indicator
- `size`; the atom BusyNote wraps. Animate honour `reduceMotion`.

## Navigation and selection

### Button.qml  ·  `text`, `kind` (`plain|outline|primary|danger`, default `plain`),
`flat`, `checked`, `busy`, `clicked()`.
### IconButton.qml  ·  canonical for icon-only buttons.
- `icon`, `on`, `checked` (alias of `on`), `size` (`Theme.px(32)`), `iconColor`,
  `tip`, `keys`, `accessibleName`, `hasMenu`; `clicked`, `rightClicked`,
  `pressAndHold`. `enabled` disables pointer, keys and a11y and dims the icon.
### Choice.qml  ·  `text`, `selected`, `checked` (alias), `danger`,
`accessibleName`, `columns`; `clicked()`.
### ListRow.qml  ·  canonical for list content  ·  58 surfaces.
- `icon`, `title`, `subtitle`, `selected`, `interactive` (default true),
  `trailing`, `columns` (grid width for Up/Down), `extra` (default alias),
  `clicked()`. Do not draw a raw `Rectangle` as a row.
### PhoneFiles.qml  ·  the one view of files to and from the paired phone.
- Send (shell file picker → `PhoneTools.filesSend`), the receive switch and the
  received list (open, show in Files). Used by Calls and Devices; the Files
  app's context menu calls the same service.

### SegmentedTabs.qml  ·  `options`, `currentIndex`, `segmentWidth`
(`Theme.px(100)`), `activated(int)`. Height `max(Theme.px(40),
Theme.touchTarget)`.
### SwitchRow.qml  ·  canonical for a settings toggle.
- `text`, `hint`, `info` (hover why), `checked`, `defaultValue` (shows reset
  icon when changed), `highlighted`; `toggled(bool)`, `reset()`. Always give a
  `hint`; `enabled` disables the whole row.
### SliderRow.qml  ·  `icon`, `value`, `muted`, `hasDetail`, `expanded`, `level`
(0..1 live level, -1 none), `label`; `moved(real)`, `iconClicked()`, `detail()`.
### AppIcon.qml  ·  canonical app/entry icon  ·  used where an app id is shown.
- `icon` (name or path), `name` (initial fallback), `implicitSize` (32),
  `path` (readonly, via `AppIconPath.pathFor`). Falls back to an initial when missing.
### AppIconPath.qml  ·  singleton icon resolution  ·  used by AppIcon and modules.
- `nameFor(entry, fallback)` → icon name string. `pathFor(entry, fallback)` → `""` / `file://...` / theme icon path. One place for fallback logic.
### Icon.qml  ·  canonical glyph  ·  63 surfaces.
- `name`, `color` (`Theme.text`), `size` (`Theme.px(18)`).
`SegmentedTabs`, `Choice` and `ListRow` all carry `Accessible.role` + `name`
and a `Theme.touchTarget` hit area (pinned by
`tests/test_common_consistency.py`).

## Input

### TextField.qml  ·  canonical single-line input.
- `text`, `input`, `readOnly`, `placeholder`, `label` (a11y name; placeholder
  when empty), `secret`, `mode`, `revealed`, `error`; `accepted()`. Set `error`
  inline instead of a toast for invalid input.
### SearchField.qml  ·  canonical search box  ·  9 surfaces.
- `text`, `input`, `placeholder`, `label` (defaults to placeholder),
  `showClear` (default true); `cleared()`. Do not hand-roll a magnifier + clear.
### DatePicker / TimePicker  ·  calendar and clock pickers.
- `DatePicker.qml`, `TimePicker.qml`; modal popovers returning a date / `hhmm`.
### DayCell.qml  ·  one day in any calendar grid  ·  3 surfaces.
- `label`, `date`, `isToday`, `isSelected`, `isWeek`, `interactive`,
  `activated()`; children (event dots) sit over the label. Selected = accent
  fill, today = soft accent. DatePicker, the sidebar calendar and CalendarPanel.
### FolderPicker / FileDirectory / DropZone
- `FolderPicker.qml` (choose a directory), `FileDirectory.qml` (list a dir),
  `DropZone.qml` (drag-and-drop target). Shared path rules in `FilePaths.js`.

## Shell chrome

### AppWindow.qml  ·  canonical app window root.
- `appName` (matches `bin/shani` APPS), `doc`, `margins` (`Theme.px(14)`),
  `header` (true), `compact` (readonly, width < `Theme.px(600)`), `tools`
  alias, `content` default alias; `gone()`, `requestClose()`, `canClose()`,
  `toggleMaximised()`. Resolves `desktopId` via `ShellApps.idFor(appName)` and
  registers nav-audit roots. Root every app window in this. `sidePane`: the
  window's SidePane; when `compact` a menu button in the header opens it.
### SidePane.qml  ·  an app's sidebar that folds into a drawer on a narrow window.
- `compact` (bind to the window's), `open`, `paneWidth` (`Theme.px(176)`),
  `label` (what the header button opens), `content` default alias (fill it with
  `anchors.fill: parent`). Wide: a column in the RowLayout; narrow: no width,
  slides in from the left over the content, a tap beside it closes it. Close it
  when the user picks something. Every sidebar app uses it (phones).
### NavWindow.qml  ·  navigation-mode window variant (`NavWindow.qml`).
### Glass / GroupBox / SectionTitle / Hint
- `Glass.qml` (translucent panel), `GroupBox.qml` (titled section),
  `SectionTitle.qml` (heading), `Hint.qml` (inline help).
### StatusPill.qml / StatusGlyph.qml / StatusRing.qml / Sparkline.qml / Avatar / Ribbon
- Status indicators and small data marks. `Ribbon.qml` is the bar's tool ribbon
  (catalog-driven by `Ribbon.js`); `Avatar.qml` the user badge.

## Pure JS catalogs (`pragma library`)

- **Tools.js** — the nine shell tool apps: `list` of `{ label, icon, flag, op,
  words }`. LauncherActions, WindowMenu, Dock, SidebarTiles, SettingsIndex and
  QuickPanel all derive from it. Add a tool here only.
- **ToolPath.js** — `DEFAULT_DIR` (`/usr/lib/shani-shell`) + `of(name, envKey,
  fallback)`: the one place a bridge path and its env override are resolved.
  Every service that spawns a bridge tool calls `ToolPath.of(...)`.
- **Time.js** — `clock`, `clockLong`, `duration`, `dayKey`, `dayLabel`,
  `fullDate`, `minutes`. Surfaces call these instead of hand-formatting
  `Qt.formatDate`/`Qt.formatTime`.
- **Format.js** — `humanSize(bytes, style)` with `style`: `binary` (default),
  `si`, `tb`, `whole`; plus `msToNextMinute`, `isoWeek`, `minutes`. Each surface
  passes its style to preserve displayed values.
- **Calc.js** — `calc(expr, angleUnit)` and `convert(q)` / `convertUnit(v, from, to)`:
  the one evaluator and unit table for the launcher and the Calculator app.
- **Month.js** — `lead`, `daysIn`, `cells` (week numbers optional) and
  `weekNames(sundayFirst, Tr.dayNamesShort)` for every month grid.
- **Markup.js** — `draw(ctx, w, h, kind, …)`: one markup mark (pen, line,
  arrow, box, blur, text), shaped by the mark's kind. Viewer and PdfReader.
- **FilePaths.js / FileFilter.js / FileIcons.js** — path, extension and icon
  rules shared by Files, QuickLook and the pickers.
- **ServiceRun.js / FilesReveal.js / JobQueue.js / NetToolsOpen.js** — the four
  once-copied QML bodies: start a service command, reveal a file in Files,
  pump one queued bridge job, and hand a host to Network Tools.
- **Accents.js / Contrast.js / Hct.js / Tonal.js / Shape.js** — colour:
  `derive()`, named `PRESETS`, measured contrast. `Theme.accent` is the single
  resolved colour.
- **WorkspaceMap.js / Gestures.js / FormFactor.js / TextMate.js / Highlight.js
  / Calibrate.js / Pen.js / WheelInput.js / ThemeFade.js** — workspace geometry,
  gesture and form-factor rules, editor highlighting, calibration, pen and wheel
  input, theme cross-fade.
- **Proc.qml** — process wrapper for services that shell out.

## Service-level single sources

- `Services/Files.qml`: `routeForPath(path)` / `openEntry(path)` decide which
  app opens a file. QuickLook, launcher recents and the shelf call these.
- `Common/Settings.qml`: `Settings.data` is the one persisted store. Local
  `JsonAdapter` siblings exist only for non-setting data (`osk.json`, …).
## Full inventory

Every file in `shani/Common/` (the docs-list contract in
`tests/test_component_contracts.py` pins this list). Ones not detailed above:

- **Ui.qml** — the transient-state singleton (every `Ui.<flag>`).
- **Theme.qml** — design tokens (colour, spacing, type, motion, `px()`,
  `touchTarget`, `radius`, `mot()`); the one theme source.
- **Settings.qml** — `Settings.data`, the persisted settings store.
- **Tr.qml** — `Tr.t()` translation.
- **SettingsSection.qml / SettingRow.qml** — settings-page section and row.
- **Advanced.qml / AppPicker.qml / Picks.qml** — advanced-options panel, app
  chooser, and a small pick-list.
- **Fade.qml** — opacity cross-fade wrapper.
- **FileIcon.qml** — the file-type glyph (pairs with `FileIcons.js`).
- **GamepadVisual.qml** — controller button glyphs.
- **HighlightText.qml** — search-match highlighting for text.
- **HoverPeek.qml** — hover-to-preview popover.
- **KeyFocus.qml** — arrow-key focus chain for grids.
- **Log.qml** — the log surface's row.
- **Matugen.qml** — wallpaper-derived dynamic theming.
- **PowerState.qml** — power/battery state badge.
- **ScreenKeyboard.qml** — the on-screen keyboard.
- **WorldMap.qml** — the world map (pairs with `WorkspaceMap.js`).
