pragma Singleton
// Wallpaper & Style: colours from a picture, on this shell's own palette code —
// a picture goes in, a named theme out. Themes themselves are extracted by
// Matugen (Common/Matugen.qml), never re-implemented here:
//   - Extract runs Matugen.previewFor(image): the same `matugen wall` call
//     themeReload runs (`run` in Matugen), for an explicit picture, writing an
//     isolated preview file — so the live palette is untouched until Apply.
//   - Apply points the wallpaper setting at the picture (Matugen reads the
//     file the setting names), then the very same Matugen.reload(). It once
//     copied the picture over the current wallpaper's file - the person's own
//     photo, overwritten; never again
//     the `themeReload` IPC calls regenerates the colours from it. The
//     adaptive palette is turned on, otherwise the regen would land in
//     colors.json and nothing would use it. If the wallpaper file is not
//     writable (e.g. a shipped one under /usr/share), Apply falls back to
//     pointing the wallpaper setting at the picture instead, then reloads —
//     same command, same result.
//   - Save theme persists the palette snapshot to Settings as a named theme
//     (Settings.data.wallpaperStyleThemes); re-applying one is re-applying its image.
// Shown in Settings > Personalisation (Modules/Settings/SettingsWallpaperStyle.qml); `themeFromImage(path)`
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
        if (!(Ui.settingsOpen && Ui.settingsCat === "personal")) Ui.openSettings("personal", "section:colours");
        if (root.image)
            root.extract();
    }
    function close() { if (Ui.settingsCat === "personal") Ui.settingsOpen = false; }

    function extract() {
        if (!root.image) { root.note = Tr.t("Pick a picture first"); return; }
        if (!Matugen.available) { root.note = Tr.t("matugen is not installed — Wallpaper & Style needs it to extract colours"); return; }
        Matugen.previewFor(root.image);
        root.note = Tr.t("Extracting with matugen (preview — nothing changes until Apply)…");
    }

    // the picture becomes the wallpaper, the palette follows (themeReload)
    function apply() {
        if (!root.image) { root.note = Tr.t("Pick a picture first"); return; }
        if (!Matugen.available) { root.note = Tr.t("matugen is not installed — cannot extract colours"); return; }
        Settings.data.adaptivePalette = true;
        // the wallpaper setting points at the picture, and the colours follow it.
        // Never a copy over the current wallpaper's file: that file is often the
        // person's own photo, and Apply used to replace it on disk (2026-11-12).
        if (Matugen.wallpaper === root.image) {
            Matugen.reload();
            root.note = Tr.t("Colours made again from this wallpaper");
            return;
        }
        Settings.data.wallpaper = root.image;
        Settings.data.wallpaperLight = "";
        Settings.data.wallpaperDark = "";
        Matugen.reload();
        root.note = Tr.t("This picture is the wallpaper now, and the colours come from it");
    }

    // persist the extracted palette snapshot as a named theme
    function saveTheme(name) {
        const n = String(name || "").trim() || "Untitled theme";
        const src = root.image || root.lastWallpaper || Settings.data.wallpaper || "";
        const live = Matugen.previewPalette || {};
        const pal = Object.keys(live).length ? live : (Matugen.palette || {});
        if (!Object.keys(pal).length) { root.note = Tr.t("Extract the palette first, then save"); return; }
        const themes = Array.from(Settings.data.wallpaperStyleThemes || []);
        themes.push({ name: n, image: src, palette: JSON.parse(JSON.stringify(pal)), savedAt: new Date().toISOString() });
        Settings.data.wallpaperStyleThemes = themes;
        root.lastSaved = n;
        root.note = Tr.t("Saved “" + n + "” to Settings");
    }

    // re-open a saved theme's picture (Apply then re-extracts it)
    function loadTheme(idx) {
        const t = (Settings.data.wallpaperStyleThemes || [])[idx];
        if (t)
            root.open(t.image || "");
    }
}
