# Architecture

Shani is a Quickshell desktop shell for niri. One `qs` process draws the whole
desktop; `bin/shani` and `qs ipc` drive it; Python bridges under `bridge/` do
the privileged or long-running work.

## Layers

```
  bin/shani  ·  qs ipc call shani <fn>        (entry points, keybinds, scripts)
        │  IPC / state JSON
        ▼
  shani/shell.qml                             (ShellRoot: the tree, the IpcHandler)
        │
        ├── shani/Modules/<App>/…             (surfaces: windows, panels, bars)
        │        │  bind only
        │        ▼
        ├── shani/Services/<Name>.qml         (one singleton per system: Niri, Audio, …)
        │        │  Process / FileView
        │        ▼
        └── bridge/<name>.py                  (privileged / long-running helpers)
                 │
                 ▼
  shani/Common/  Ui.qml · Theme.qml · Settings.qml · widgets · *.js catalogs
```

- **shell.qml** is the only `ShellRoot`. It instantiates the always-on surfaces
  (Bar, Island, Dock, Sidebar, Launcher) and wraps every on-demand surface in a
  `LazyLoader` gated by a `Ui` flag or a service property. It owns the single
  `IpcHandler { target: "shani" }`.
- **Modules** are surfaces. They bind to services and `Ui` flags, never to each
  other's internals and never to `bridge/` directly.
- **Services** are singletons (`pragma Singleton` QML, or `.js` libraries). One
  per system. They own a `Process`/`FileView` to a bridge tool and expose typed
  properties, signals and functions. `shani/shell.qml` lists the no-surface
  services in its `_services` array so they are instantiated.
- **bridge/** holds Python (and a few shell) helpers. Each is launched by a
  service through `Process`; the path comes from `Common/ToolPath.js`
  (`DEFAULT_DIR` + per-service env override). `bin/shani` never calls a bridge
  for UI state; it only sends IPC.

## IPC and state contract

`IpcHandler { target: "shani" }` in `shell.qml` is the whole external API.

- **Commands** are functions: `function <name>(args…)`. Convention:
  `openX` / `toggleX` / `closeX`. An open command runs `Ui.closeAll()` first,
  sets the `Ui` flag, then asks the service to refresh. `qs -c shani ipc call
  shani <name> [args…]` invokes one.
- **State** is `function state(): string` — a single `JSON.stringify` of the
  live values tests and scripts read. Add a field there when a surface gains
  observable state; never add a second state channel.
- **File arguments** arrive as one string (a JSON list is split on newlines by
  `qs ipc`); a command that takes paths does `paths.split("\n")`.
- `closeAll()` (`Ui.closeAll(); Ui.closeApps(); Ui.settingsOpen = false`) is the
  universal reset before opening anything.

## Ui flags

`Common/Ui.qml` is the one `pragma Singleton` holding every transient boolean
the surfaces read: `property bool <flag>: false`. A surface is shown by
`visible: Ui.<flag>` and cleared by `onGone: Ui.<flag> = false`. The flag is the
contract between the IPC command, the `LazyLoader` and the window. Tools that
are "an action, not a window" (screenshot, colour picker) have no flag; their
desktop entry calls a dedicated IPC function.

## Add a new app, end to end

1. **Ui flag** — add `property bool <flag>: false` to `Common/Ui.qml` with a
   one-line comment naming the module.
2. **Module** — create `shani/Modules/<App>/<App>Window.qml` (or a single
   `<App>.qml`). Root it in `Common/AppWindow { appName: "…"; visible: Ui.<flag>;
   onGone: Ui.<flag> = false }` so the title bar, desktop id, nav-audit and
   close handling come for free.
3. **shell.qml IPC** — add `function <flag>Open() { Ui.closeAll(); Ui.<flag> =
   true; <Service>.refresh() }` inside the `IpcHandler`.
4. **LazyLoader** — add `LazyLoader { active: Ui.<flag>; source:
   "Modules/<App>/<App>Window.qml" }` in `shell.qml`. If the app holds no
   surface, add its service to the `_services` array instead.
5. **bin/shani APPS** — add an entry to `APPS` in `bin/shani`:
   `name: (desktop id, Name, Comment, Icon, Categories, [mimes], [ipc-without-file,
   ipc-with-file], state-key, Ui-flag)`. The `op` names must match the IPC
   function; the state key must match a field in `state()`.
6. **ShellApps.js** — add `"<Name>": "<desktop id>"` to `Services/ShellApps.js`
   so the dock, switcher and bar resolve the window's icon and entry.
   `tests/test_apps.py` keeps APPS and ShellApps equal.
7. **SettingsIndex link** (only for the nine tool apps) — add the row to
   `Common/Tools.js`; `Settings/SettingsIndex.js` and the launcher derive from
   it. For a non-tool app, add a settings entry to `SettingsIndex.js` `entries`.
8. **Dev harness entry** — add a scene or part under `dev/` (`dev/check.sh
   <part>` / `dev/demo.sh <scene>` / `dev/render.sh`) so the app is drawn and
   driven in the nested session.

## Shared-component catalog

`shani/Common/` is imported as `qs.Common`. Widgets own geometry, colour,
states and accessibility; surfaces pass data and semantics. Full API in
`docs/COMPONENTS.md`. The rule: change a look in the component, never per call
site.

- **Feedback**: `InfoBanner`, `BusyNote`, `EmptyState`, `ConfirmButton`,
  `Toast`, `Spinner`.
- **Navigation/selection**: `Button`, `IconButton`, `Choice`, `ListRow`,
  `SegmentedTabs`, `SwitchRow`, `SliderRow`, `AppIcon`, `Icon`.
- **Input**: `TextField`, `SearchField`, `DatePicker`, `TimePicker`,
  `FolderPicker`, `FileDirectory`, `DropZone`.
- **Shell chrome**: `AppWindow`, `NavWindow`, `Glass`, `GroupBox`,
  `SectionTitle`, `Hint`, `StatusPill`, `StatusGlyph`, `StatusRing`,
  `Sparkline`, `Avatar`, `Ribbon`.
- **Pure JS catalogs** (`pragma library`): `Tools.js` (nine tool apps),
  `ToolPath.js` (bridge path + env override), `Time.js` (date/duration),
  `Format.js` (human size), `FilePaths.js`/`FileFilter.js`/`FileIcons.js`,
  `Accents.js`/`Contrast.js`/`Hct.js`/`Tonal.js`/`Shape.js` (colour),
  `WorkspaceMap.js`, `Gestures.js`, `FormFactor.js`, `Ribbon.js`,
  `TextMate.js`, `Highlight.js`, `Calibrate.js`, `Pen.js`, `WheelInput.js`,
  `ThemeFade.js`, `Proc.qml`.