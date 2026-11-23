"""Static guards for the pass-21 theme/appearance fixes.

Three source-level invariants a QML unit test cannot reach here: the slideshow
and theme Apply must not destroy separately-set light/dark wallpapers, the
quantizer must encode every path segment of a file:// URL, and the theme fade
must honour animationSpeed (and still collapse to 0 with reduce motion).
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPEARANCE = ROOT / "shani" / "Services" / "Appearance.qml"
WALLPAPER_STYLE = ROOT / "shani" / "Services" / "WallpaperStyle.qml"
THEME = ROOT / "shani" / "Common" / "Theme.qml"


def test_slideshow_and_theme_apply_keep_per_style_wallpapers():
    """Both use dedicated overrides; neither clears the light/dark pictures."""
    appearance = APPEARANCE.read_text(encoding="utf-8")
    style = WALLPAPER_STYLE.read_text(encoding="utf-8")
    theme = THEME.read_text(encoding="utf-8")

    slide = appearance[appearance.index("onStreamFinished:") :]
    assert "Theme.slideshowWallpaper = pics[root.slide]" in slide
    apply = style[style.index("function apply()") : style.index("function saveTheme(")]
    assert "Theme.themeWallpaper = root.image" in apply

    for name, body in (("slideshow", slide), ("theme Apply", apply)):
        for key in ("wallpaperLight", "wallpaperDark"):
            assert f'Settings.data.{key} = ""' not in body, f"{name} clears {key}"

    resolution = theme[theme.index("readonly property string wallpaper:") :]
    assert (
        "root.slideshowWallpaper" in resolution and "root.themeWallpaper" in resolution
    )


def test_quantizer_encodes_every_url_segment():
    """#/?/% and unicode in a wallpaper path must not break the file:// URL."""
    t = THEME.read_text(encoding="utf-8")
    source = next(
        line
        for line in t.splitlines()
        if "ColorQuantizer" not in line
        and "source: Settings.data.accentFromWallpaper" in line
    )
    assert 'split("/").map(encodeURIComponent).join("/")' in source
    assert ".replace(/ /g" not in source


def test_fade_duration_uses_animation_speed_and_reduce_motion():
    """The 300 ms theme fade is scaled by animationSpeed, 0 with reduce motion."""
    t = THEME.read_text(encoding="utf-8")
    assert "readonly property int fadeDuration:" in t
    assert "Fade.fadeMs(Settings.data.reduceMotion)" in t
    assert "Settings.data.animationSpeed" in t
    assert "Behavior on darkT { NumberAnimation { duration: root.fadeDuration;" in t
