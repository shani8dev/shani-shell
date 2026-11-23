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
//     (Settings.data.wallpaperStyleThemes); loading one materialises that
//     snapshot directly, so a moved/deleted picture cannot kill the theme.
//     Apply snapshots the theme keys it changes; revert() puts them back.
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
    property var beforeApply: null   // theme keys before the last Apply, for revert()

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
        // remember exactly what this call changes, so a single revert() can put
        // it back (a UI button can be added without touching the theme keys)
        root.beforeApply = {
            adaptivePalette: Settings.data.adaptivePalette,
            wallpaper: Settings.data.wallpaper,
            themeWallpaper: Theme.themeWallpaper,
            slideshowWallpaper: Theme.slideshowWallpaper,
            savedPalette: JSON.parse(JSON.stringify(Theme.savedPalette || {}))
        };
        Theme.savedPalette = {};   // a live extract now owns the palette
        Settings.data.adaptivePalette = true;
        // the wallpaper setting points at the picture, and the colours follow it.
        // Never a copy over the current wallpaper's file: that file is often the
        // person's own photo, and Apply used to replace it on disk (2026-11-12).
        if (Matugen.wallpaper === root.image) {
            Matugen.reload();
            root.note = Tr.t("Colours made again from this wallpaper");
            return;
        }
        // an override, not an edit of the per-style pictures: applying a theme
        // must not destroy the separately-chosen light/dark wallpapers
        Settings.data.wallpaper = root.image;
        Theme.themeWallpaper = root.image;
        Theme.slideshowWallpaper = "";
        Matugen.reload();
        root.note = Tr.t("This picture is the wallpaper now, and the colours come from it");
    }

    // put the theme keys back to their pre-apply values and regen from the old
    // wallpaper. Exposed for a future "Revert" button; the snapshot is taken in
    // apply(), so a revert before any apply is a no-op with a word.
    function revert() {
        const s = root.beforeApply;
        if (!s) { root.note = Tr.t("Nothing to revert"); return; }
        Settings.data.adaptivePalette = s.adaptivePalette;
        Settings.data.wallpaper = s.wallpaper;
        Theme.themeWallpaper = s.themeWallpaper;
        Theme.slideshowWallpaper = s.slideshowWallpaper;
        Theme.savedPalette = s.savedPalette || {};
        root.beforeApply = null;
        Matugen.reload();
        root.note = Tr.t("Reverted the last theme apply");
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

    // Re-apply a saved theme from its stored palette snapshot: the picture may
    // have been moved or deleted, so re-reading it must not be required. Live
    // matugen output takes over again on the next wallpaper change or Apply.
    function loadTheme(idx) {
        const t = (Settings.data.wallpaperStyleThemes || [])[idx];
        if (!t) return;
        root.lastSaved = t.name || "";
        root.image = t.image || "";
        const pal = t.palette || {};
        if (Object.keys(pal).length) {
            Settings.data.adaptivePalette = true;
            Theme.savedPalette = JSON.parse(JSON.stringify(pal));
            root.note = Tr.t("Restored “" + (t.name || "theme") + "” from its saved palette");
        } else {
            Theme.savedPalette = {};
            root.note = Tr.t("This saved theme has no palette snapshot");
        }
    }
}
