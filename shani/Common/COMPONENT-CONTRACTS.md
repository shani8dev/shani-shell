# Shared component contracts

Rule: when a look or behaviour must change everywhere, edit the component in
`shani/Common/` (or the catalog below). Do not copy its body into a surface.
Surface QML passes data and semantics; Common owns geometry, colour, states and
accessibility. A change in one place then reaches every consumer.

Everything below is in `qs.Common`. Import once, use directly.

## Status and feedback

### `InfoBanner.qml` — inline status message
- `tone`: `info` (default) | `ok` | `warn` | `error` | `danger` | `accent`.
  `ok` and `accent` use `Theme.accent`; `warn` uses `Theme.amber`; `error` and
  `danger` use `Theme.danger`; `info` uses `Theme.blue`.
- `title`, `text`, `iconName`, `toneColor` (readonly), `cornerRadius`, `padding`,
  `iconSize`, `accessibleRole`, default `actions` alias.
- **Use for** save success/failure, load errors, policy warnings. Never guess
  a tone from a translated string — pass an explicit `tone` and keep a
  boolean (`noteOk`) in the surface.
- Consumers: 17 surfaces. Change padding/radius/colour here, not per page.

### `BusyNote.qml` — one busy row
- `note`, `iconSize` (default `Theme.px(16)`), `align` alias.
- `Accessible.role: StatusBar`, `Accessible.name` is `note`.
- **Use for** `visible: busy` spinner + note. Do not hand-roll
  `Row { Spinner {}; Text {} }`.
- Consumers: 18 surfaces.

### `ConfirmButton.qml` — two-tap destructive confirm
- `text`, `armedText` (default `Tr.t("Tap again")`), `value` (id passed to
  `confirmed`; `id` is a reserved QML attribute), `interval` (4000 ms),
  `kind`: `plain | danger | outline`, `armed`, `danger` (readonly).
- `signal confirmed(string id)`, `disarm()`.
- `Accessible.name` from the caller reaches the inner Button; a bare label is
  the fallback only.
- **Use for** any "tap again to confirm" action. Call `disarm()` on tab or
  surface change.
- Consumers: 12 surfaces.

### `EmptyState.qml` — nothing-here card
- `icon`, `title`, `subtitle`, `actionText`, `iconSize`, `padding`,
  `accessibleRole`, `signal action()`.
- Shares `cornerRadius`/`padding`/`iconSize` scale with `InfoBanner`; change
  both together.
- Consumers: 56 surfaces — the widest reach of any shared widget.

## Navigation and selection

### `Button.qml` — `text`, `kind` (`plain|outline|primary|danger`), `flat`,
`checked`, `busy`, `clicked()`.
### `IconButton.qml` — `icon`, `on`, `checked` (alias), `size`, `iconColor`,
`tip`, `keys`, `accessibleName`, `hasMenu`; `clicked`, `rightClicked`,
`pressAndHold`. `enabled` disables pointer, keys and a11y and dims the icon.
### `Choice.qml` — `text`, `selected`, `checked` (alias), `danger`,
`accessibleName`, `columns`; `clicked()`.
### `SwitchRow.qml` — `text`, `hint`, `info`, `checked`, `defaultValue`,
`highlighted`; `toggled(bool)`, `reset()`. Always give a `hint` explaining what
the switch does; `enabled` disables the whole row.
### `TextField.qml` — `text`, `input`, `readOnly`, `placeholder`, `label`,
`secret`, `mode`, `revealed`, `error`; `accepted()`. Set `error` inline instead
of showing a toast for invalid input.
### `SearchField.qml` — `text`, `input`, `placeholder`, `label`, `showClear`;
`cleared()`. Use for every search box; do not hand-roll a magnifier + clear.
### `ListRow.qml` — `icon`, `title`, `subtitle`, `selected`, `interactive`,
`trailing`, `columns`, `extra`; `clicked()`. Use for list content; do not draw
a raw `Rectangle` as a row.
### `SettingRow.qml` — `ListRow` for Settings pages: `control` aliases the
trailing slot (`extra`), so a row reads as "label + control". Same a11y/flash
as `ListRow`. Use for icon+title+subtitle rows with a trailing control.
### `SettingsSection.qml` — titled settings block: `title`, `hint`, default
children are the rows. Replaces repeated `SectionTitle + hint Text + rows`
scaffolding; one spacing/typography change reaches every adopting page.
### `SegmentedTabs.qml` — `options`, `currentIndex`, `segmentWidth`,
`activated(int)`. Height is `max(Theme.px(40), Theme.touchTarget)`.
### `Fade.qml` — one accent pulse: `active` (loop while true), `flash()` (one
shot), `duration`, `pulseFrom`/`pulseTo`. Honours `Settings.data.reduceMotion`
in one place; use instead of hand-rolled `SequentialAnimation on opacity`.
### `DayCell.qml` — one day in a calendar grid: `label`, `date` (spoken name),
`isToday`, `isSelected`, `isWeek` (faint week number, not a button),
`interactive` (default: not a week and not blank), `fontSize`, `activated()`;
children (event dots) sit over the label. One look everywhere: selected =
accent fill + accent ink, today = soft accent + accent text. Blank cells are
hidden from screen readers. Consumers: DatePicker, sidebar Calendar,
CalendarPanel (month grid, week strip).

## Catalogs (pure JS, `pragma library`)

- `Tools.js` — the nine shell tools: `label`, `icon`, `flag`, `op`, `words`.
  LauncherActions, WindowMenu, Dock, SidebarTiles, SettingsIndex and QuickPanel
  all derive from this list. Add a tool here only. Open one with
  `Ui.openTool(flag)` — never a local table of `Ui.<flag> = true` closures.
- `Month.js` — a month as a grid: `lead(month, sundayFirst)`, `daysIn(month)`,
  `cells(month, sundayFirst, weekNumbers)` (`{week}` / `{day}`, day ≤ 0 is a
  blank), `weekNames(sundayFirst, Tr.dayNamesShort)` (localized header).
- `Markup.js` — `draw(ctx, w, h, kind, color, size, pts, words)`: one mark
  (pen, highlight, line, arrow, box, blur, text) on a Canvas, shaped by the
  mark's own kind. Viewer and PdfReader draw through it.
- `Format.js` — `humanSize(bytes, style)` with `style`: `binary` (default),
  `si`, `tb`, `whole`. Each surface passes its style to preserve displayed
  values; changing a style here changes that surface everywhere.
- `Time.js` — date/day labels and duration helpers (`dayKey`, `dayLabel`,
  `fullDate`, `minutes`, `clock`, `clockLong`, `duration`, `clockPadded`,
  `hhmmss`, `stopwatch`, `fileStamp`). Surfaces call these rather than
  hand-formatting `Qt.formatDate`/`Qt.formatTime` for shared patterns.
- `ToolPath.js` — single source of the bridge-tool install prefix
  (`DEFAULT_DIR`). Call `ToolPath.of(Quickshell.env("KEY"), "file.py")`;
  never spell `/usr/lib/shani-shell/...` in a service.
- `FilePaths.js` / `FileFilter.js` — path and extension rules, shared by Files,
  QuickLook and pickers.
- `Accents.js` — `derive()` and named `PRESETS`; `Theme.accent` is the single
  resolved colour. Contrast is measured, not guessed.

## Service-level single sources

- `Services/Files.qml`: `routeForPath(path)` / `openEntry(path)` decide which
  shell app opens a file. QuickLook, launcher recents and the shelf call these;
  do not re-implement extension checks. Preview kind (`QuickLook.exts`) is a
  separate concern from app routing.
- `Services/Files.qml` GTK bookmarks are the flat bookmark store; `SpeedDial`
  is the sectioned store. They are intentionally separate.
- `Services/RecentFiles.qml`: `files` — recently-used.xbel, newest first (max
  40). The launcher and the overview search bind to it; never parse the xbel
  in a surface.
- `Theme.inkOn(fill)`: the readable ink (near-black or white, WCAG 4.5:1) on
  any computed fill. Never pick text colour by `Theme.dark ? "#…" : "#…"`.
- `Settings.data` in `Common/Settings.qml` is the one persisted settings store;
  surfaces may have local JsonAdapter siblings only for data that is not a
  user setting (e.g. `osk.json`, `processes-sort.json`).

## Maintenance checklist

1. New widget: add it here with its API and intended consumers.
2. Changing a shared widget: check the consumer count above, then run the
   full suite and one render pass — a geometry change reaches every surface.
3. Adding a catalog entry: update the JS list, not each surface.
4. Never copy a Common widget body into a Module. If a surface needs a variant,
   add a property to the shared widget.
5. `tests/test_design_drift.py` bans the copies that already drifted once and
   ratchets literal colours, radii and font sizes: lower its ceilings when you
   remove literals, never raise them.
