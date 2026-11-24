"""Static checks for Wallpaper/ScreenCorners robustness fixes.

Covers: empty-wallpaper fallback, image error handling, stale-load guard,
backdrop async/error safety, decorative corner AT hiding, and menu a11y.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WALLPAPER = ROOT / "shani/Modules/Background/Wallpaper.qml"
CORNERS = ROOT / "shani/Modules/Background/ScreenCorners.qml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_wallpaper_empty_clears_both_images():
    t = read(WALLPAPER)
    # clearing the wallpaper must not leave a stale image visible
    assert "if (!src) {" in t
    assert "a.opacity = 0; b.opacity = 0;" in t
    assert 'a.source = ""; b.source = "";' in t


def test_wallpaper_stale_load_guard():
    t = read(WALLPAPER)
    # a late Ready from an older source must not replace the current wallpaper
    assert 'wallpaperWin.wanted ? "file://" + wallpaperWin.wanted : ""' in t
    assert "status === Image.Ready && source === want" in t


def test_wallpaper_error_handling_hides_broken_image():
    t = read(WALLPAPER)
    # a missing/corrupt image falls back to Theme.bg instead of sticking
    assert "status === Image.Error" in t
    assert 'opacity = 0; source = "";' in t


def test_wallpaper_backdrop_async_and_error_safe():
    t = read(WALLPAPER)
    # backdrop decodes off the UI thread and hides broken images without
    # breaking the source binding
    backdrop = t.split('WlrLayershell.namespace: "shani-backdrop"', 1)[1].split(
        "PanelWindow {", 1
    )[0]
    assert "asynchronous: true" in backdrop
    assert "visible: status !== Image.Error" in backdrop
    assert 'source = ""' not in backdrop


def test_screen_corners_decorative_and_antialiased():
    t = read(CORNERS)
    assert "Accessible.ignored: true" in t
    assert "antialiasing: true" in t


def test_wallpaper_desktop_menu_accessible():
    t = read(WALLPAPER)
    assert "Accessible.role: Accessible.Pane" in t
    assert 'Accessible.name: Tr.t("Desktop menu")' in t
