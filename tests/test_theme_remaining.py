"""Static guards for the remaining pass-21 theme/appearance fixes.

Three source-level invariants a QML unit test cannot reach here: a "system"
dark schedule that reads GNOME's colour scheme without echoing it back, an
accent contrast warning against the current surface, and saved themes that
survive a moved picture plus a revert() for the last Apply.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPEARANCE = ROOT / "shani" / "Services" / "Appearance.qml"
WALLPAPER_STYLE = ROOT / "shani" / "Services" / "WallpaperStyle.qml"
THEME = ROOT / "shani" / "Common" / "Theme.qml"


def test_system_dark_schedule_follows_gsettings_without_echoing():
    """'system' reads color-scheme via a monitor; the shell stops writing it."""
    a = APPEARANCE.read_text(encoding="utf-8")

    # the monitor (WallpaperSync pattern) is the source of truth in this mode
    assert '"gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"' in a
    assert '"gsettings", "get", "org.gnome.desktop.interface", "color-scheme"' in a
    assert "function applySystemScheme(value)" in a
    assert '=== "prefer-dark"' in a
    assert 'root.d.darkSchedule === "system"' in a

    # the schedule timer must not drive a style the system is choosing
    assert (
        'running: Settings.loaded && root.d.darkSchedule !== "manual" '
        '&& root.d.darkSchedule !== "system"' in a
    )
    # and the write Process must not fight the key it is reading
    assert (
        'root.d.darkSchedule !== "system"'
        in a[a.index('"color-scheme", Settings.data.darkMode') :]
    )


def test_accent_contrast_warning_is_exposed_against_the_background():
    """Ink-on-accent exists; accent-on-surface must be measured too."""
    t = THEME.read_text(encoding="utf-8")
    assert "readonly property real accentContrast:" in t
    assert "Contrast.ratio(Qt.color(accent), Qt.color(bg))" in t
    # 3:1 is WCAG's minimum for non-text UI (accentLine, borders, icons)
    assert "readonly property bool accentContrastWarning: accentContrast < 3.0" in t


def test_saved_themes_materialise_a_snapshot_and_apply_can_be_reverted():
    """A moved image cannot kill a theme, and Apply has a one-call undo."""
    s = WALLPAPER_STYLE.read_text(encoding="utf-8")
    t = THEME.read_text(encoding="utf-8")

    # Theme can render a saved palette without re-reading its image
    assert "property var savedPalette: ({})" in t
    assert "const saved = root.savedPalette[role]" in t
    load = s[s.index("function loadTheme(") :]
    assert "Theme.savedPalette = JSON.parse(JSON.stringify(pal))" in load
    assert "root.open(" not in load, "loading must not depend on the picture path"

    # Apply snapshots the key set it mutates; revert puts every one of them back
    assert "property var beforeApply: null" in s
    apply = s[s.index("function apply()") : s.index("function revert()")]
    revert = s[s.index("function revert()") : s.index("function saveTheme(")]
    keys = (
        "adaptivePalette",
        "wallpaper",
        "themeWallpaper",
        "slideshowWallpaper",
        "savedPalette",
    )
    assert "root.beforeApply = {" in apply
    for key in keys:
        assert f"{key}:" in apply, f"apply does not snapshot {key}"
        assert f"= s.{key}" in revert, f"revert does not restore {key}"
    assert "Matugen.reload()" in revert
