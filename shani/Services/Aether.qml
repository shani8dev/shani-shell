pragma Singleton
// Aether: an Omarchy theme-extractor parity on this shell's own palette code —
// a picture goes in, a named theme out. Themes themselves are extracted by
// Matugen (Common/Matugen.qml), never re-implemented here:
//   - Extract runs Matugen.previewFor(image): the same `matugen wall` call
//     themeReload runs (`run` in Matugen), for an explicit picture, writing an
//     isolated preview file — so the live palette is untouched until Apply.
//   - Apply is the cp workaround: Matugen only reads the current wallpaper
//     file (Matugen.wallpaper), so the picture is copied over that file first
//     (`cp -- <image> <wallpaper path>`), then the very same Matugen.reload()
//     the `themeReload` IPC calls regenerates the colours from it. The
//     adaptive palette is turned on, otherwise the regen would land in
//     colors.json and nothing would use it. If the wallpaper file is not
//     writable (e.g. a shipped one under /usr/share), Apply falls back to
//     pointing the wallpaper setting at the picture instead, then reloads —
//     same command, same result.
//   - Save theme persists the palette snapshot to Settings as a named theme
//     (Settings.data.aetherThemes); re-applying one is re-applying its image.
// Shown by Modules/Aether/AetherPanel.qml until closed; `themeFromImage(path)`
// opens it (`shani aether`).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string image: ""        // the picture being considered; "" until opened
    property string note: ""         // the last action's words, for the panel + `state`
    property string lastSaved: ""    // the name saved last, for `state`

    readonly property string lastWallpaper: Theme.wallpaper || Settings.data.wallpaper

    function open(path) {
        const p = (path || "").trim() || root.lastWallpaper || Settings.data.wallpaper;
        root.image = p || "";
        root.note = "";
        Ui.aether = true;
        if (root.image)
            root.extract();
    }
    function close() { Ui.aether = false; }

    function extract() {
        if (!root.image) { root.note = Tr.t("Pick a picture first"); return; }
        if (!Matugen.available) { root.note = Tr.t("matugen is not installed — Aether needs it to extract colours"); return; }
        Matugen.previewFor(root.image);
        root.note = Tr.t("Extracting with matugen (preview — nothing changes until Apply)…");
    }

    // the picture becomes the wallpaper, the palette follows (themeReload)
    function apply() {
        if (!root.image) { root.note = Tr.t("Pick a picture first"); return; }
        if (!Matugen.available) { root.note = Tr.t("matugen is not installed — cannot extract colours"); return; }
        Settings.data.adaptivePalette = true;
        const target = Matugen.wallpaper;
        if (!target) {
            Settings.data.wallpaper = root.image;
            Settings.data.wallpaperLight = "";
            Settings.data.wallpaperDark = "";
            Matugen.reload();
            root.note = Tr.t("Wallpaper set; colours regenerated (themeReload)");
            return;
        }
        if (target === root.image) {
            Matugen.reload();
            root.note = Tr.t("Colours regenerated from the current wallpaper (themeReload)");
            return;
        }
        // matugen only reads the current wallpaper file: copy the picture over
        // it, then run the same reload themeReload runs
        root.note = Tr.t("Copying over the wallpaper file, then regenerating…");
        cpProc.dest = target;
        cpProc.command = ["sh", "-c", 'cp -- "$1" "$2"', "sh", root.image, target];
        cpProc.running = true;
    }

    Process {
        id: cpProc
        property string dest: ""
        running: false
        onExited: code => {
            if (code === 0) {
                Matugen.reload();
                root.note = Tr.t("Applied: wallpaper updated, colours regenerated (themeReload)");
            } else {
                // the wallpaper file is not writable here (a shipped one):
                // point the wallpaper setting at this picture instead, then
                // the same reload — matugen reads whichever file the setting
                // resolves to
                Settings.data.wallpaper = root.image;
                Settings.data.wallpaperLight = "";
                Settings.data.wallpaperDark = "";
                Matugen.reload();
                root.note = Tr.t("Wallpaper file is not writable here, so the wallpaper setting now points at this picture; colours regenerated (themeReload)");
            }
        }
    }

    // persist the extracted palette snapshot as a named theme
    function saveTheme(name) {
        const n = String(name || "").trim() || "Untitled theme";
        const src = root.image || root.lastWallpaper || Settings.data.wallpaper || "";
        const live = Matugen.previewPalette || {};
        const pal = Object.keys(live).length ? live : (Matugen.palette || {});
        if (!Object.keys(pal).length) { root.note = Tr.t("Extract the palette first, then save"); return; }
        const themes = Array.from(Settings.data.aetherThemes || []);
        themes.push({ name: n, image: src, palette: JSON.parse(JSON.stringify(pal)), savedAt: new Date().toISOString() });
        Settings.data.aetherThemes = themes;
        root.lastSaved = n;
        root.note = Tr.t("Saved “" + n + "” to Settings");
    }

    // re-open a saved theme's picture (Apply then re-extracts it)
    function loadTheme(idx) {
        const t = (Settings.data.aetherThemes || [])[idx];
        if (t)
            root.open(t.image || "");
    }
}
