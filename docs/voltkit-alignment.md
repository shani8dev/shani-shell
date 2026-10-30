# Voltkit ↔ shani-shell alignment

**Source:** https://github.com/arios4k/voltkit, cloned to `/tmp/opencode/voltkit` (v0.2.2, Rust, GTK4 + libadwaita, ~4 MB binary).
**Subject:** what of voltkit aligns with shani-shell (niri 26.04 + Quickshell 0.3.2, Chronoa AI shell, `shani-shell/`).

## One-line positioning

- **Voltkit** is a desktop *app*: a control-center-style suite of micro-utilities (OCR text extractor, color picker + eyedropper + WCAG contrast, QR read/make, screen ruler, image/video compressor, text expander/snippets, Keep Awake, hosts & environment editor) in one GTK4/libadwaita binary, scriptable via CLI + man pages, with a background D-Bus daemon (`io.github.arios4k.Voltkit.Daemon`).
- **shani-shell** is a desktop *shell*: niri + Quickshell QML (bar, Island, Sidebar control center, Dock, Launcher, Lens, Ring …) with Chronoa (AI assistant) bridged onto D-Bus over a unix socket (`bridge/chronoa-bridge.py`).

They are different layers (app vs shell, GTK4 vs QML), but voltkit's integration patterns and several of its utilities map cleanly onto shani-shell surfaces/modules.

---

## Capability alignment

| voltkit feature | how voltkit does it | shani-shell equivalent | status |
|---|---|---|---|
| **Text Extractor** (OCR, `Super+Shift+T`, Tesseract 100+ langs, drag box, even from video/images, lands on clipboard) | `src/modules/ocr.rs`, region capture via Screenshot portal with grim/slurp/gnome-screenshot/spectacle/maim fallbacks | **Lens** (`shani/Services/Lens.qml`): slurp + grim + Tesseract offline, `Super+S`; also decodes QR/barcodes (zbar), copy/search/translate/ask-Chronoa | **Aligned** — same capability; Lens adds Chronoa context; voltkit's "works on frozen video frames" is a nice extra |
| **Color Picker** (eyedropper `Super+Shift+C`, PickColor portal, HEX/RGB/HSL, WCAG AA/AAA, history in `~/.local/share/voltkit/colors.txt`) | `src/modules/color.rs`, `src/portal.rs` `Color::pick()` | Sidebar lists a **"color picker"** tile (`README.md` Bar/Sidebar table); no `Color` service exists under `shani/Services/` | **Partial** — shani names it in the UI but hasn't built it; voltkit is the reference implementation |
| **QR Code** (read `Super+Shift+Q` or make; Wi-Fi config; logo; re-scan verification) | `src/modules/qr.rs` (rqrr/qrcode) | **Lens** decodes QR/barcodes via `zbar` (`Lens.qml` `hasZbar`) | **Aligned on read** — voltkit additionally *makes* QR codes |
| **Screen Ruler** (freeze screen, drag to measure px, Shift = straight line, Ctrl+C copy) | `src/modules/ruler.rs` | None found | **Gap** — candidate for a Lens-adjacent module or an Island tool |
| **Asset Compressor** (PNG/JPEG/WebP/MP4, `oxipng`/`jpegoptim`/`cwebp`/`ffmpeg`, metadata stripped, `name.min.ext`, never touches originals) | `src/modules/compress.rs` | None found | **Gap** |
| **Text Expansion** (snippet picker `Super+Shift+E`, `{arg:NAME}` forms, typed triggers opt-in via evdev+uinput + `input` group, clipboard copy/paste/restore) | `src/modules/snippets.rs`, `src/expander.rs` | Launcher has actions/files/calculator/emoji/clipboard/web typing; no snippet system | **Gap** — the launcher's ranked list is the natural home |
| **Keep Awake** (Inhibit portal, 30 min–4h or until off, survives closing the app) | `src/modules/awake.rs`, Inhibit portal | **Focus modes** (Work/Sleep/Personal) + caffeine tile in the Sidebar (`README.md`) | **Aligned conceptually** — voltkit = portal Inhibit; shani = focus modes; both keep the machine from sleeping/locking |
| **Hosts & Environment** (`/etc/hosts` toggle, `environment.d` session vars, backups, system entries protected) | `src/modules/hosts.rs`, `src/modules/envvars.rs` | `Settings > …` covers wallpaper/bar/dock/blur/reduce motion/night-light/idle; no hosts/env editor found | **Gap** — likely Cassini/system-settings territory rather than shell |
| **Blur / glass** | None (plain GTK4/libadwaita) | **Required**: `ext-background-effect-v1` per-surface region (`SHANI_BLUR=1`, `dev/niri/protocol.kdl`), measured 90× flatter, bounded to the card (RMSE 0 vs desktop); `Common/Glass.qml` card primitive; `reduceTransparency` makes opaque | **shani-shell leads** |
| **Companion / approvals in place** | Notifications only | **Island** (mascot in the bar) + **ChronoaPanel** (one button per exact approval option, expiry drawn, `✓ Allow for this session`) | **shani-shell leads** (AI-native) |
| **Turn stream / per-turn approval** | None | `dev.shani.chronoa.Agent` contract (Turn/Approve/Event) via the bridge, `bridge/turn_filter.py` (claim/take/see, MAX_KNOWN=64, MAX_UNCLAIMED=8, MAX_HELD=64), per-turn `contextvars.ContextVar` resolver | **shani-shell leads** |
| **Global hotkeys** | GlobalShortcuts portal (GNOME 48+/KDE 5.27+/Hyprland portal ≥1.19); fallbacks: GNOME custom keybindings via `gsettings` (`voltkit shortcuts install`), or compositor bindings to `voltkit trigger` | niri ignores virtual-keyboard input for binds; niri keybinds use `qs -c shani ipc call shani <fn>`; bridge owns logind lock+sleep | **Different compositor model** — same portal-where-available principle |
| **CLI scriptability** | Every feature a subcommand (`voltkit ocr`, `voltkit color …`), man pages auto-generated with clap_mangen; `cargo test` fails until man pages regenerated | `qs -c shani ipc call shani <fn>` drives all surfaces; `state` returns live JSON | **Aligned principle** — different mechanism (CLI subcommands vs Quickshell IPC) |
| **Config** | `~/.config/voltkit/config.toml` (TOML), `data/config.example.toml` | `~/.config/shani-shell/settings.json` (live-reloaded JSON), `Common/Settings.qml` | **Aligned** |
| **Notifications** | `org.freedesktop.Notifications` directly (portal needs an app ID unsandboxed apps can't give on older portals) | `Services/Notifs.qml`, DND lets critical through | **Aligned** |
| **Packaging** | GPG-signed apt repo on GitHub Pages, `cargo-deb` .deb, `.desktop`, full-color + symbolic icons, man pages | `shani-pkgbuilds/shani-shell` (PKGBUILD, Arch) | **Aligned** (both distro-packaged; voltkit's man-page-gating test is worth copying) |
| **Self-check / doctor** | `voltkit doctor` — lists exactly what's missing and the install command per distro | Idle-cost test (`strace` execve budget 12/min, CPU 15 ms/s), AT-SPI a11y lint via shani-testbed, i18n restart test | **Partial** — voltkit's per-feature tool check is a good model for a shell `doctor` |
| **Live Activities** | None | Island carries recording/music/call/focus timer/etc. while Chronoa is idle; a click acts on it | **shani-shell leads** |
| **Accessibility** | Not mentioned | Every control has an accessible role/name, verified via AT-SPI; high contrast, reduce motion, mono audio | **shani-shell leads** |

### Verdict by category
- **Already aligned (shani matches or exceeds):** OCR/Lens, QR decode, Keep Awake/focus modes, config file, notifications, D-Bus daemon-with-well-known-name, portals-where-available, CLI scriptability, packaging.
- **Partial (shani names it, hasn't built it):** color picker (sidebar tile exists, no service).
- **Gaps (voltkit has it, shani doesn't):** screen ruler, hosts & environment editor, `voltkit doctor`-style per-feature tool check, man-page gating, "one app instead of eight" suite packaging.

---

## Integration patterns compared (the transferable part)

| pattern | voltkit | shani-shell | alignment |
|---|---|---|---|
| **D-Bus well-known name, single instance** | `io.github.arios4k.Voltkit.Daemon` at `/io/github/arios4k/Voltkit/Daemon`, `RequestNameFlags::DoNotQueue` so a second instance exits instead of waiting (`daemon.rs`) | bridge owns `org.shani.Chronoa.Mascot`, `org.shani.Chronoa.Windows`, `dev.shani.chronoa.Gateways`; `dev.shani.chronoa.Agent` proposed | **Aligned pattern.** Difference: voltkit daemon is Rust/zbus/tokio in the app itself; shani bridge is Python/GLib bridging to QML over a unix socket because Quickshell can't export D-Bus objects |
| **Per-method D-Bus API documented as a table** | `docs/ARCHITECTURE.md`: Trigger/Status/Reload/Quit/KeepAwake/… with signatures | `agent_contract.py` (Turn/Approve/Event + introspection XML); bridge `MASCOT_XML`/`WINDOWS_XML` inline | **Aligned** — shani's contract doc lives in shani-chronoa (`agent_contract.py`) |
| **Portal-first Wayland integration with tool fallbacks** | Screenshot/PickColor/GlobalShortcuts/RemoteDesktop/Inhibit via ashpd; fallbacks grim/slurp, gnome-screenshot, spectacle, maim; GNOME keybinding fallback | Lens capture = slurp + grim over wlr-screencopy (niri offers both); OSK = niri virtual-keyboard protocol; **niri has no `org.gnome.Mutter.RemoteDesktop`** (`GAPS.md`) → Sunshine+Moonlight instead | **Aligned principle**; niri lacks RemoteDesktop so the portal set differs |
| **Approval UI with exact option labels** | Notifications only | ChronoaPanel draws one button per `ask()` option label and sends the *label* back (`permissions.parse_reply` matches labels); expiry card drawn | **shani-shell leads** |
| **Turn isolation on a shared bus** | N/A (daemon is per-user, one instance) | `bridge/turn_filter.py` — only the bridge's own turns reach the panel; held events flushed on `Turn`; caps so a foreign turn can't grow the bridge | **shani-shell leads** |
| **Man pages gated on code changes** | `clap_mangen` + hand-written sections; `cargo test` fails until regenerated | None | **Adoptable** — worth copying for any shell CLI |
| **`doctor` self-check** | `voltkit doctor` prints missing tools + the distro install command | Idle-cost / a11y / i18n test suite, but no per-feature "is this installable" check | **Adoptable** |
| **Non-destructive by default** | Compressor writes `name.min.ext`, never touches originals | Undo ring / pre-image ring for file changes (`recent_changes()`, `undo_last_change`) | **Aligned principle** |
| **Logic UI-free** | `src/modules/` is plain Rust with unit tests; `app.rs` is only wiring | `shani/Services/*.qml` are singletons; `shani/Modules/*.qml` bind only to services | **Aligned pattern** |

---

## Where each leads

**shani-shell leads on:** blur/glass (bounded per-surface, measured), AI companion + in-place approvals, per-turn Agent contract with turn filter, Live Activities in the Island, accessibility-first surfaces, Marathi + 598-layout screen keyboard, focus modes, niri tiling integration.

**Voltkit leads on (worth porting/adapting):** color picker + eyedropper with WCAG contrast and history, QR *generation*, screen ruler, image/video compressor with metadata stripping, text expander with typed triggers (evdev/uinput), hosts & environment editor, `doctor` per-feature tool check, man-page CI gating, signed apt repo flow.

---

## Just landed (this session)

- **Color picker tile** — Sidebar's existing "color picker" row now wires to a new `qs.Services.Color` singleton ported from voltkit's `src/modules/color.rs` (HEX/RGB/HSL parsing, WCAG AA/AAA contrast, luminance, 32-entry deduped recents). The tile shows the last picked hex, copies it to the clipboard, and sends a notify with contrast ratings against white/black.
- **Snippets tile** — voltkit's Text Expansion: opens a zenity entry dialog, copies entered text to the clipboard.
- **Compress tile** — voltkit's Asset Compressor: zenity file picker + ffmpeg downscale/re-encode, writes `name.min.ext` next to the original.
- **QR code tile** — voltkit's QR generator: reads clipboard text via `wl-paste`, generates QR with `qrencode` (graceful "not installed" notice if qrencode is absent).
- **Ruler tile** — voltkit's Screen Ruler: full-screen frozen screenshot overlay (grim), drag to measure width × height in pixels, Shift for straight line, right-click to clear, Esc to close, Ctrl+C to copy. Crosshair lines and size badge drawn on a Canvas.

## Recommended next steps for shani-shell

1. **Hosts & Environment editor** — voltkit's hosts/env editor (`/etc/hosts` toggle, `environment.d` vars). Needs root; likely Cassini/system-settings territory rather than shell.
2. **Screen ruler service** — the Ruler QML service + panel is wired but uses `grim` for capture; could add a `niri msg pick-color`-style direct color pick to the Color service for a faster path.
3. **`voltkit doctor`-style per-feature tool check** — `bin/shani-doctor.py` was added this session; wire it into Settings or first boot.
4. **Man-page gating** — if the shell gains CLI surface beyond `qs -c shani ipc call`, gate CI on regenerated man pages like voltkit (`cargo test` fails until regenerated).
2. **`voltkit doctor` equivalent** — a shell health check that lists missing per-feature tools (tesseract, zbar, grim/slurp, wpctl, bluetoolctl…) with distro install commands; run it from Settings or first boot. shani already tests idle cost; this is the per-feature complement.
3. **Man-page gating** — if the shell gains CLI surface beyond `qs -c shani ipc call`, gate CI on regenerated man pages like voltkit (`cargo test` fails until regenerated).
4. **DoNotQueue name ownership** — shani's bridge should confirm its D-Bus name acquisition fails fast if another instance owns it (voltkit's `RequestNameFlags::DoNotQueue` pattern).
5. **Micro-utility modules** — screen ruler (Lens-adjacent), image/video compressor, text expander (launcher snippet row), hosts/env settings page — each maps to an existing shani surface (Lens, Sidebar control center, Launcher, Settings).
6. **Do not port voltkit's UI** — it's GTK4/libadwaita widgets inside an app window; shani-shell is QML/Quickshell with niri layer surfaces. Take the *logic* (portals, fallbacks, D-Bus contract, doctor checks), not the widgets.

---

## Files referenced

Voltkit (`/tmp/opencode/voltkit`):
- `README.md` — feature list, shortcuts, portals, packaging, project layout
- `docs/ARCHITECTURE.md` — principles, Wayland realities table, D-Bus API table, roadmap
- `src/daemon.rs` — `BUS_NAME`, `DoNotQueue`, `Trigger`/`Status`/`KeepAwake`/…, autostart `.desktop`
- `src/portal.rs` — Screenshot/PickColor/Notifications, `parent_handle`, fallback behavior
- `src/modules/{ocr,color,qr,ruler,compress,snippets,expander,awake,hosts,envvars}.rs`
- `Cargo.toml` — GTK4 0.11.5/v4_14, libadwaita 0.9.2/v1_5, ashpd portals, zbus

shani-shell (`/home/shrinivaskumbhar/Documents/shani/shani-shell`):
- `README.md` — surfaces (Island, Bar, Sidebar, Lens, color-picker tile), layout tree
- `shani/shell.qml` — root ShellRoot, `ipc call shani <fn>` surface, Chronoa actions
- `shani/Modules/Chronoa/ChronoaPanel.qml` — approval cards (one button per option label), transcript Column+Flickable
- `shani/Modules/Island/Island.qml` — mascot in the bar, Live Activities, `BackgroundEffect.blurRegion`
- `shani/Common/Glass.qml` — translucent card primitive, `reduceTransparency`
- `shani/Services/Lens.qml` — slurp+grim+Tesseract+zbar OCR & QR
- `shani/Services/Chronoa.qml` — Chronoa service singleton
- `bridge/chronoa-bridge.py` — D-Bus names, unix socket JSON-lines, `SHANI_CHRONOA_SOCK` / `$XDG_RUNTIME_DIR/shani-chronoa.sock`
- `bridge/turn_filter.py` — TurnFilter claim/take/see, MAX_KNOWN=64, MAX_UNCLAIMED=8, MAX_HELD=64
- `bridge/agent_contract.py` — Agent contract mirror
- `FINDINGS.md` — blur verification (39×–90× flatter, RMSE 0 bounded), Agent contract real turn stream
- `GAPS.md` — niri has no RemoteDesktop (Sunshine+Moonlight), what niri cannot give
- `CROSS-REF.md` — glass palette mapping, blur separate from plasma
- `tests/`, `dev/shell-test.sh` — idle cost, a11y, i18n
