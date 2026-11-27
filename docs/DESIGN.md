# Design

How the shell's apps, settings and surfaces look, on every kind of screen
(docs/FORM-FACTORS.md). The tokens live in `shani/Common/Theme.qml`, the
pieces in `shani/Common/` (contracts: `shani/Common/COMPONENT-CONTRACTS.md`).
A Module never picks its own size, colour or spacing.

## Principles

1. **The answer first.** A screen opens with what the person came to know -
   "Backed up yesterday at 21:04", "Everything looks good" - as a
   `StatusHero` or a row of `StatTile`s. Settings come after, in cards.
2. **Calm by default.** Surfaces are near-neutral: the wallpaper gives them
   a hue, not a colour. Colour is for state (green fine, amber look, red
   wrong, blue news: `Theme.toneColor`) and for what can be pressed (the
   accent). A healthy screen is mostly grey with one green mark.
3. **One main action per screen.** At most one `Button { kind: "primary" }`
   in view. Others are plain or outline; destructive ones are `danger`,
   never the boldest thing on the screen unless removing is what the screen is for.
4. **Group in cards.** Related controls sit in one `Card` / `SettingsSection`
   with a title and a one-line subtitle. No bare uppercase labels over loose
   rows. A card inside a card draws flat by itself.
5. **Plain words.** Titles say what it is, subtitles say what it does for
   the person. No paths, keys or product names in labels.
6. **Readable everywhere.** Nothing below 12 px; body text is 14. Every size
   goes through `Theme.type()` / `Theme.px()`, so a TV, a tablet and large
   text scale it.
7. **Glass where it helps.** Panels over the desktop (bar, sidebar, launcher,
   notifications) are `Glass`: the wallpaper shows through, softened. App
   content sits on solid cards so text never fights the picture.

## Tokens

| | |
|---|---|
| Type (`Theme.type(step)`) | caption 12 · small 13 · body 14 · heading 16 · subtitle 20 · title 26 · display 32 |
| Spacing (`Theme.space(n)` = 4n px) | 4 · 8 · 12 · 16 · 20 · 24 · 32 |
| Surfaces | `bg` window · `glass` panels over the desktop · `card` + `cardBorder` groups · `surface1..3` raised parts inside a card |
| Text | `text` · `dim` secondary (subtitles, hints) · `faint` only for decoration, never for words to read |
| State | `Theme.toneColor("ok" / "warn" / "error" / "info" / "neutral")` |
| Shape | `radiusSmall` controls · `radius` · `radiusLarge` cards · `radiusLarge + 4` heroes |

## Pieces

| Piece | Use |
|---|---|
| `AppPage` | An app's page: title, subtitle, actions, centred scrolling column |
| `StatusHero` | The answer first: glyph, overline, headline, detail, chips, one action |
| `StatTile` in a `TileGrid` | Facts at a glance; 4 → 2 → 1 columns by width |
| `Card` / `SettingsSection` | A group: icon badge, title, subtitle, actions, rows |
| `ListRow`, `SwitchRow`, `SettingRow` | Rows inside a card |
| `StatusPill`, `StatusGlyph`, `StatusRing` | State at a glance, coloured by `toneColor` |
| `SidePane` | An app's sections: a column when wide, a drawer when narrow |

## The app pattern

Every app follows this. Files is the worked example (`Modules/Files/FilesPanel.qml`,
`FilesHome.qml`).

1. **One top bar.** Back (when there is somewhere to go back to), the place's
   name, at most three everyday actions, and More (⋮, the panel's menu) for the
   rest. A `RowLayout`, never a `Flow` of buttons that wraps into rows. Wide
   windows may show a few more actions inline; the rare ones stay in More on
   every width.
2. **No second bar on a phone.** An app with its own top bar sets
   `header: !compact` on its `AppWindow`: the phone's bar has back, home and
   the app switcher, and Refresh / Close move into More.
3. **A home first.** An app with places, sections or a list opens on a home on
   a narrow window (Files: search, kinds, storage, places; a settings-like app:
   its sections as a list) instead of a drawer hidden behind ⋮. Back from the
   first page returns there.
4. **The answer first.** An app about a state (backups, health, updates,
   storage) opens with a `StatusHero` or `StatTile`s, then its settings in
   `Card`s.
5. **Lists on phones, grids for pictures.** Rows are `ListRow` (icon, title,
   subtitle, trailing value); grids share their width evenly (no ragged gap).
6. **Filters as one row that scrolls sideways**, never wrapping, never with a
   "Show:" label.
7. **Empty, busy and failed** each have their own state (`EmptyState`,
   `BusyNote`, `InfoBanner`) - never a blank pane or a raw error string.
8. **Every size, colour and gap from Theme.** `Theme.type()`, `Theme.space()`,
   `Theme.toneColor()`; nothing below 12 px; one primary button in view.
9. **Check it** with `sh dev/check.sh render=apps` (every windowed app on all
   eight profiles, plus landscape phone). Inspect the captures under
   `out/renders/apps/<profile>`. Use `render=apps:phone,tv` to select profiles
   and `SHANI_APPS=files,calendar` to select apps. The interaction checks
   live in `shell=apps-phone` and `shell=apps`.

## Every form factor

Layouts follow the window's width, not the form factor's name: a narrow
window on a computer behaves like a phone.

- **Wide** (≥ 1000 px): side pane + page, tiles in fours, hero in one row.
- **Medium** (600-1000): narrower pane, tiles in twos.
- **Narrow** (< 600, phones, splits): the pane is a drawer, one column, the
  title one step smaller, the hero stacked, the main action at the bottom.
- **Touch** (phone, tablet, handheld, board): every target ≥ `Theme.touchTarget`;
  nothing only on hover.
- **TV and handheld** (`FormFactor.tenFoot`): everything reachable by
  arrows/gamepad (`KeyFocus` on every card and button that acts), a visible
  focus ring, no hover-only parts. `Theme.px` already scales for the distance.

## Checking a change

`sh dev/check.sh render=matrix` draws the key surfaces on all 8 kinds of
screen; look at them. The pilot apps (Backup, Health, Background) are
compared side by side before a pattern spreads.
