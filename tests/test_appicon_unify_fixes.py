"""One static cross-check that app icons resolve through AppIcon's helpers.

Many sites used to hand-roll `Quickshell.iconPath(...)` or an inline
`application-x-executable` fallback, each slightly different. AppIcon.nameFor /
AppIcon.pathFor are now the one place that decides the name and the source path;
this reads the files as text (no running shell) and refuses the drift back.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPIcon = ROOT / "shani/Common/AppIcon.qml"


def _read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


# ---- the helper itself -------------------------------------------------------


def test_appicon_defines_both_helpers():
    """AppIcon keeps its visual component and gains nameFor/pathFor statics."""
    text = _read("shani/Common/AppIcon.qml")
    assert "static function nameFor(" in text
    assert "static function pathFor(" in text
    # the visual component still works: path now routes through pathFor
    assert "readonly property string path: AppIcon.pathFor(icon, false)" in text
    assert "IconImage {" in text


def test_pathfor_behaviour():
    """pathFor: empty -> "", absolute path -> file:// URL, else iconPath(name, fallback)."""
    text = _read("shani/Common/AppIcon.qml")
    body = text[text.index("static function pathFor(") :]
    body = body[: body.index("\n    }")]
    # empty entry short-circuits to ""
    assert "if (!entry)" in body and 'return "";' in body
    # absolute path becomes a file:// URL
    assert 'name.startsWith("/")' in body
    assert 'return "file://" + name;' in body
    # otherwise the theme answers with the caller's fallback
    assert "Quickshell.iconPath(name, fallback)" in body


def test_namefor_behaviour():
    """nameFor: empty -> fallback, string/object -> its icon, else fallback."""
    text = _read("shani/Common/AppIcon.qml")
    body = text[text.index("static function nameFor(") :]
    body = body[: body.index("\n    }")]
    assert "if (!entry)" in body
    assert 'typeof entry === "string" ? entry : entry.icon' in body
    assert 'return name ? name : (fallback || "");' in body


# ---- one static test per adopted site ---------------------------------------


def test_dock_uses_pathfor():
    text = _read("shani/Modules/Dock/Dock.qml")
    assert "AppIcon.pathFor(icon, true)" in text
    assert "Quickshell.iconPath(" not in text


def test_ring_uses_pathfor():
    text = _read("shani/Modules/Ring/Ring.qml")
    assert 'AppIcon.pathFor(slice.modelData.app, "application-x-executable")' in text
    assert "Quickshell.iconPath(" not in text


def test_tvhome_uses_namefor():
    text = _read("shani/Modules/TvHome/TvHome.qml")
    assert 'AppIcon.nameFor(a, "application-x-executable")' in text


def test_sidebarheader_uses_namefor():
    text = _read("shani/Modules/ControlCenter/SidebarHeader.qml")
    assert 'AppIcon.nameFor(app, "application-x-executable")' in text


def test_privacy_uses_namefor():
    text = _read("shani/Modules/Settings/SettingsPrivacy.qml")
    assert 'AppIcon.nameFor(entry, "application-x-executable")' in text


def test_defaultapps_uses_namefor():
    text = _read("shani/Modules/Settings/SettingsDefaultApps.qml")
    # both candidate lists (open apps + removable media) route through nameFor
    assert (
        text.count('AppIcon.nameFor(page.entry(modelData), "application-x-executable")')
        == 2
    )
    assert 'application-x-executable"; }' not in text


def test_studiowindow_uses_namefor():
    text = _read("shani/Modules/Studio/StudioWindow.qml")
    assert 'AppIcon.nameFor(modelData, "application-x-executable")' in text
    assert 'Icon { name: "application-x-executable"' not in text


def test_no_owned_site_hand_rolls_iconpath():
    """None of the adopted sites keep a raw Quickshell.iconPath(...) call."""
    owned = [
        "shani/Modules/Dock/Dock.qml",
        "shani/Modules/ControlCenter/SidebarHeader.qml",
        "shani/Modules/Ring/Ring.qml",
        "shani/Modules/TvHome/TvHome.qml",
        "shani/Modules/Studio/StudioWindow.qml",
        "shani/Modules/Settings/SettingsPrivacy.qml",
        "shani/Modules/Settings/SettingsDefaultApps.qml",
    ]
    offenders = [rel for rel in owned if "Quickshell.iconPath(" in _read(rel)]
    assert not offenders, f"still hand-rolls iconPath: {offenders}"
