pragma Singleton
// A full Material You palette from the wallpaper, via matugen (ShaniOS ships
// it; the person opts in). When Settings > Look > "Adaptive palette" is on:
//   1) ~/.config/shani-shell/matugen.toml and the templates under
//      ~/.config/shani-shell/matugen/ are kept in sync with Settings (written
//      on every ensure, but only when their content actually changed, so a
//      hand edit survives until the generating side of it changes);
//   2) `matugen wall <wallpaper> --config … --mode dark|light` runs on every
//      wallpaper, style or app-set change, writing ~/.config/shani-shell/colors.json
//      which Theme maps onto its tokens; scheme/contrast/source-color options
//      from Settings are passed through (wayle-inspired).
//   3) the apps chosen in Settings (>chose GTK) get templates written into
//      their own config dirs — the GTK set adapted from mylinuxforwork/dotfiles,
//      in the dotted {{colors.X.default.hex}} style, and without their non-standard
//      set_alpha filter (its one use is replaced by a plain hex colour).
// Adoption (an include/@import of the generated file) is added to an app's
// config only when that app is actually present on this system, and only if
// it is not already there. Theme stays the one place colours live: this
// service only reads producers, so the greeter and lock screen follow too.
// When matugen is absent or the toggle is off, Theme falls back to its
// built-in tonal material.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.config/shani-shell"
    readonly property string tplDir: dir + "/matugen"
    readonly property string configFile: dir + "/matugen.toml"
    readonly property string colorsFile: dir + "/colors.json"

    property bool available: false   // the matugen binary exists
    property bool running: false     // a run is in flight ("Applying…" in Settings)
    property bool ready: false       // a palette for this style+wallpaper is loaded
    property var palette: ({})       // Material role -> colour string

    readonly property string mode: Settings.data.darkMode ? "dark" : "light"
    // the wallpaper the Theme itself resolves (per style); reactivity rides Settings bindings
    // theming monitor (wayle-inspired): use that monitor's wallpaper if set
    readonly property string wallpaper: {
        if (Settings.data.wallpaperPerMonitor && Settings.data.themingMonitor) {
            const perMon = Settings.data.wallpapersByMonitor || {};
            const monWall = perMon[Settings.data.themingMonitor];
            if (monWall) return monWall;
        }
        return (Settings.data.darkMode ? Settings.data.wallpaperDark : Settings.data.wallpaperLight) || Settings.data.wallpaper;
    }
    readonly property bool enabled: Settings.data.adaptivePalette && available

    Component.onCompleted: probe.running = true

    // ---- presence probe ---------------------------------------------------------
    Process {
        id: probe
        command: ["sh", "-c", "command -v matugen >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: { root.available = this.text.trim() === "yes"; root._ensure(); }
        }
    }

    function _ensure() {
        if (!root.enabled || !root.wallpaper) { root.ready = false; root.palette = {}; return; }
        ship.command = _shipCommand();
        ship.running = true;
    }
    function reload() { _ensure(); }   // `qs -c shani ipc call shani themeReload`
    // themeReload regenerates from the current wallpaper file only (root.wallpaper
    // above): matugen has no "any image" entry point here. Aether's Extract runs
    // the *same* `matugen wall <image> --config … --mode … --type … --contrast …
    // --source-color-index …` invocation as `run`, for an explicit picture and
    // with an isolated config/output, so the live palette (colors.json) is not
    // clobbered until Apply. No new extractor: same binary, same template
    // (tplColors below), same scheme/contrast/source-color from Settings.
    property var previewPalette: ({})
    property string previewSource: ""
    property bool previewRunning: false
    property string previewError: ""
    readonly property string previewFile: dir + "/aether-preview.json"
    readonly property string previewConfig: dir + "/aether-preview.toml"

    function previewFor(path) {
        const src = path || root.wallpaper;
        if (!root.available) {
            root.previewRunning = false;
            root.previewPalette = {};
            root.previewError = "matugen is not installed — Aether needs it to extract colours";
            return;
        }
        if (!src) {
            root.previewRunning = false;
            root.previewError = "No wallpaper is set — pick a picture first";
            return;
        }
        root.previewSource = src;
        root.previewRunning = true;
        root.previewError = "";
        // ship the template, then a minimal colors-only config pointing at the
        // preview file (no GTK writes: previewing must not repaint anything)
        let s = "mkdir -p '" + root.tplDir + "'; "
            + "w(){ d=$(dirname \"$1\"); mkdir -p \"$d\"; "
            + "printf %s \"$2\" | base64 -d > \"$1.w\"; "
            + "if [ -f \"$1\" ] && cmp -s \"$1.w\" \"$1\"; then rm \"$1.w\"; else mv \"$1.w\" \"$1\"; fi; }; ";
        s += "w '" + root.tplDir + "/colors.json.tpl' " + Qt.btoa(root.tplColors) + "; ";
        s += "w '" + root.previewConfig + "' " + Qt.btoa("[config]\n\n[templates.colors]\ninput_path = '" + root.tplDir + "/colors.json.tpl'\noutput_path = '" + root.previewFile + "'\n") + "; ";
        s += "rm -f '" + root.previewFile + "'; ";
        // $1 is the picture (command arg), so its path never fights shell quoting
        s += "matugen wall \"$1\" --config '" + root.previewConfig + "' --mode '" + root.mode
            + "' --type '" + Settings.data.matugenScheme + "' --contrast '" + String(Settings.data.matugenContrast)
            + "' --source-color-index '" + String(Settings.data.matugenSourceColor) + "'";
        preview.command = ["sh", "-c", s, "sh", src];
        preview.running = true;
    }

    Process {
        id: preview
        running: false
        onExited: code => {
            root.previewRunning = false;
            if (code === 0) {
                root.previewError = "";
                previewReader.reload();
                root._previewAbsorb();
            } else {
                root.previewPalette = {};
                root.previewError = "matugen could not read this picture (" + root.previewSource + ")";
            }
        }
    }
    // reactivity: the toggle, wallpaper choice, style flip, app membership and scheme options
    readonly property var _watch: [
        Settings.data.adaptivePalette, Settings.data.darkMode,
        Settings.data.wallpaper, Settings.data.wallpaperDark, Settings.data.wallpaperLight,
        (Settings.data.matugenApps || []).join(","),
        Settings.data.matugenScheme, Settings.data.matugenContrast, Settings.data.matugenSourceColor]
    on_WatchChanged: _ensure()

    // ---- keep config + templates on disk, then run ------------------------------
    function _shipCommand() {
        // write(file, body64): write only when the content is new, so a hand
        // edit survives — until the source of it (the app set) changes and the
        // generator must win again
        let s = "mkdir -p '" + root.tplDir + "'; "
            + "w(){ d=$(dirname \"$1\"); mkdir -p \"$d\"; "
            + "printf %s \"$2\" | base64 -d > \"$1.w\"; "
            + "if [ -f \"$1\" ] && cmp -s \"$1.w\" \"$1\"; then rm \"$1.w\"; else mv \"$1.w\" \"$1\"; fi; }; ";
        const put = (f, b) => { s += "w '" + f + "' " + Qt.btoa(b) + "; "; };
        const on = Settings.data.matugenApps || [];
        put(root.configFile, _configToml());
        put(root.tplDir + "/colors.json.tpl", tplColors);   // Theme's own, out of scope of b
        for (const id in b) put(root.tplDir + "/" + _meta[id].tpl, b[id]);
        // adoption: wire the generated file into GTK's own config, but only when
        // GTK is actually on this system (its files exist)
        if (on.indexOf("gtk") >= 0) {
            for (const g of ["gtk-3.0", "gtk-4.0"]) {
                s += "g='" + home + "/.config/" + g + "/gtk.css'; if [ -d '" + home + "/.config/" + g
                   + "' ] && ! grep -q colors.css \"$g\" 2>/dev/null; "
                   + "then printf '%b' \"$im\" >> \"$g\"; fi; ";
            }
        }
        put(root.tplDir + "/gtk-reload.sh", _gtkScript);
        s += "chmod +x '" + root.tplDir + "/gtk-reload.sh'; ";
        // adoption: wire the generated file into the app's own config, but only
        // when that app is actually on this system (its file or dir exists)
        const K = home + "/.config/kitty/kitty.conf";
        const W = home + "/.config/waybar";
        // %b expands the \n escapes; quoted so the css directive's own single
        // quotes never fight the shell's
        s += "im=\"" + "\\n@import 'colors.css';\\n" + "\"; ";
        if (on.indexOf("kitty") >= 0)
            s += "k='" + K + "'; if [ -f \"$k\" ] && ! grep -q colors-matugen \"$k\"; then "
               + "printf '\\n%s\\n' 'include colors-matugen.conf' >> \"$k\"; fi; ";
        if (on.indexOf("waybar") >= 0)
            s += "wb='" + W + "'; if [ -d \"$wb\" ] && [ -f \"$wb/style.css\" ] && ! grep -q colors.css \"$wb/style.css\"; "
               + "then printf '%b' \"$im\" >> \"$wb/style.css\"; fi; ";
        if (on.indexOf("gtk") >= 0)
            for (const g of ["gtk-3.0", "gtk-4.0"])
                s += "g='" + home + "/.config/" + g + "/gtk.css'; if [ -d '" + home + "/.config/" + g
                   + "' ] && ! grep -q colors.css \"$g\" 2>/dev/null; "
                   + "then printf '%b' \"$im\" >> \"$g\"; fi; ";
        return ["sh", "-c", s + "echo ok"];
    }
    Process {
        id: ship
        running: false
        onExited: if (root.enabled) root._start()
    }

    function _start() {
        if (!root.enabled) return;
        if (run.running) { root._pending = true; return; }   // will re-run when it lands
        root.running = true;
        run.running = true;
    }
    property bool _pending: false
    // matugen regenerates from the templates; Theme re-loads on file change
    Process {
        id: run
        running: false
        onExited: { root.running = false; if (root._pending) { root._pending = false; Qt.callLater(root._start); } }
        command: ["matugen", "wall", root.wallpaper, "--config", root.configFile, "--mode", root.mode,
                 "--type", Settings.data.matugenScheme,
                 "--contrast", String(Settings.data.matugenContrast),
                 "--source-color-index", String(Settings.data.matugenSourceColor)]
    }

    // ---- the shipped config (built per app membership) --------------------------
    function _configToml() {
        let t = "[config]\n\n[templates.colors]\n"
            + "input_path = '" + root.tplDir + "/colors.json.tpl'\n"
            + "output_path = '" + root.colorsFile + "'\n";
        for (const id of (Settings.data.matugenApps || [])) {
            const a = _meta[id]; if (!a) continue;
            for (let i = 0; i < a.outs.length; i++) {
                // several outputs from one template (GTK 3 + 4) get suffixes
                t += "\n[templates." + id + (a.outs.length > 1 ? String(i + 1) : "") + "]\n"
                   + "input_path = '" + root.tplDir + "/" + a.tpl + "'\n"
                   + "output_path = '" + a.outs[i].replace("$X", root.home) + "'\n"
                   + (i === 0 && a.hook
                       ? "post_hook = '" + a.hook.replace("$TPLDIR", root.tplDir) + "'\n" : "");
            }
        }
        return t;
    }

    // the app set: template file, where the result goes, and how the app is told
    // (GTK repaints via a small script shipped beside the tpls, ml4w's colour-scheme
    // flip-flop). $X expands to $HOME, $TPLDIR to the template dir; GTK is the only
    // matugen target we ship (foot, not kitty; shani's own bar, not waybar).
    readonly property var _meta: ({
        gtk: { tpl: "gtk-colors.css", outs: ["$X/.config/gtk-3.0/colors.css", "$X/.config/gtk-4.0/colors.css"],
              hook: "$TPLDIR/gtk-reload.sh" }
    })

    // ---- the templates (adapted from mylinuxforwork/dotfiles) -------------------
    // the shell's own: a flat JSON like ml4w's, regenerated per run, mode-keyless
    readonly property string tplColors: JSON.stringify({
        surface: "{{colors.surface.default.hex}}",
        surface_dim: "{{colors.surface_dim.default.hex}}",
        surface_low: "{{colors.surface_container_low.default.hex}}",
        surface_high: "{{colors.surface_container_high.default.hex}}",
        surface_highest: "{{colors.surface_container_highest.default.hex}}",
        on_surface: "{{colors.on_surface.default.hex}}",
        on_surface_variant: "{{colors.on_surface_variant.default.hex}}",
        outline: "{{colors.outline.default.hex}}",
        outline_variant: "{{colors.outline_variant.default.hex}}",
        primary: "{{colors.primary.default.hex}}",
        on_primary: "{{colors.on_primary.default.hex}}",
        primary_container: "{{colors.primary_container.default.hex}}",
        secondary_container: "{{colors.secondary_container.default.hex}}",
        tertiary: "{{colors.tertiary.default.hex}}",
        error: "{{colors.error.default.hex}}",
        inverse_primary: "{{colors.inverse_primary.default.hex}}",
        inverse_surface: "{{colors.inverse_surface.default.hex}}"
    }, null, 2)

    readonly property var b: ({
        // gtk: ml4w's @define-color set, verbatim; the css-+2/-4 wrappers are
        // handled in the config (two templates, one file)
        gtk: "/* generated with matugen — do not edit by hand */\n"
           + "@define-color accent_color {{colors.primary_fixed_dim.default.hex}};\n"
           + "@define-color accent_fg_color {{colors.on_primary_fixed.default.hex}};\n"
           + "@define-color accent_bg_color {{colors.primary_fixed_dim.default.hex}};\n"
           + "@define-color window_bg_color {{colors.surface_dim.default.hex}};\n"
           + "@define-color window_fg_color {{colors.on_surface.default.hex}};\n"
           + "@define-color headerbar_bg_color {{colors.surface_dim.default.hex}};\n"
           + "@define-color headerbar_fg_color {{colors.on_surface.default.hex}};\n"
           + "@define-color popover_bg_color {{colors.surface_dim.default.hex}};\n"
           + "@define-color popover_fg_color {{colors.on_surface.default.hex}};\n"
           + "@define-color view_bg_color {{colors.surface.default.hex}};\n"
           + "@define-color view_fg_color {{colors.on_surface.default.hex}};\n"
           + "@define-color card_bg_color {{colors.surface.default.hex}};\n"
           + "@define-color card_fg_color {{colors.on_surface.default.hex}};\n"
           + "@define-color sidebar_bg_color @window_bg_color;\n"
           + "@define-color sidebar_fg_color @window_fg_color;\n"
           + "@define-color sidebar_border_color @window_bg_color;\n"
           + "@define-color sidebar_backdrop_color @window_bg_color;\n",
    })

    // ---- reading the result ------------------------------------------------------
    FileView {
        id: reader
        path: root.colorsFile
        printErrors: false
        blockLoading: false
        watchChanges: true
        onFileChanged: root._absorb()
        onLoaded: root._absorb()
    }
    // the preview's result file: same flat JSON as colors.json, absorbed into
    // previewPalette instead of the live palette (Aether exhibits it)
    FileView {
        id: previewReader
        path: root.previewFile
        printErrors: false
        blockLoading: false
        watchChanges: true
        onFileChanged: root._previewAbsorb()
        onLoaded: root._previewAbsorb()
    }
    function _previewAbsorb() {
        const text = previewReader.text();
        if (!text)
            return;   // no run yet (or a failed one): keep the previous preview
        try {
            const o = JSON.parse(text);
            const split = o[root.mode];
            root.previewPalette = (split && typeof split === "object") ? split : o;
        } catch (e) {
            // half-written or broken: the Process exit code already reported it
        }
    }

    // flat JSON (as shipped); a {dark:{},light:{}} shape is tolerated
    function _absorb() {
        const text = reader.text();
        if (!text) { root.ready = false; root.palette = {}; return; }
        try {
            const o = JSON.parse(text);
            const split = o[root.mode];
            root.palette = (split && typeof split === "object") ? split : o;
            root.ready = Object.keys(root.palette).length > 0;
        } catch (e) { root.ready = false; root.palette = {}; }
    }
}
