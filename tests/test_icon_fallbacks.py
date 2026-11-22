"""Regressions in the icon fallback guards and the shipped brand mark.

QML cannot run under pytest, but these are the bits that silently rot: an
iconPath(..., true) that makes an emptiness guard dead, a generic fallback that
turns every missing glyph into a settings gear, and a logo that is installed but
never drawn.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_an_unknown_app_icon_can_fall_back_to_an_initial_tile():
    """AppIcon keys its initial tile off path === "". With iconPath's fallback
    flag on, every unknown icon returns the theme placeholder, so the guard
    never fires and the tile is unreachable. Icon's own || chain needs the same
    emptiness to try its next name."""
    app = source("shani/Common/AppIcon.qml")
    assert "Quickshell.iconPath(icon, false)" in app
    assert "Quickshell.iconPath(icon, true)" not in app
    assert 'visible: root.path === ""' in app

    icon = source("shani/Common/Icon.qml")
    assert ", true)" not in icon
    assert "Quickshell.iconPath(sym, false)" in icon
    assert "|| Quickshell.iconPath(" in icon


def test_a_missing_glyph_is_not_a_settings_gear():
    """A missing battery or Wi-Fi glyph must not look like a preferences gear.
    A question mark is neutral; if the theme lacks even that, the chain ends in
    an empty source, i.e. nothing painted."""
    icon = source("shani/Common/Icon.qml")
    assert '"dialog-question-symbolic"' in icon
    assert "preferences-system-symbolic" not in icon


def test_the_shipped_logo_brands_about_and_setup():
    """The image is installed at /usr/share/pixmaps/shani-logo.svg; both title
    areas must actually reference it, and hide it cleanly when it is absent."""
    for rel in ("shani/Modules/Settings/SettingsAbout.qml", "setup/shell.qml"):
        text = source(rel)
        assert '"file:///usr/share/pixmaps/shani-logo.svg"' in text, rel
        assert "visible: status === Image.Ready" in text, rel
