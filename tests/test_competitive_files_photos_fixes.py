"""Competitive research (Nautilus / Dolphin / Finder) — Files and Photos fixes.

Static checks: the shell has no QML runtime in this container, so each fix is
asserted against the source it lives in. One test per behaviour.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


FILES = "shani/Modules/Files/FilesPanel.qml"
PHOTOS = "shani/Modules/Photos/PhotosWindow.qml"


def test_files_sort_direction_is_a_click_away():
    """Nautilus/Dolphin let you reverse a sort; Files' key button cycles keys,
    so its sortDesc property was unreachable from the UI. A second button uses
    the service's own same-key setSort() toggle, which persists the choice."""
    s = read(FILES)
    assert 'Files.sortDesc ? "view-sort-ascending" : "view-sort-descending"' in s
    assert "onClicked: Files.setSort(Files.sortKey)" in s
    assert 'Tr.t("Sort direction: %1 (click to reverse)"' in s


def test_files_ctrl_h_toggles_hidden_files():
    """Nautilus and Dolphin bind Ctrl+H to show hidden files; Files only had a
    toolbar icon, so the shortcut is added to the window's key handler."""
    s = read(FILES)
    assert re.search(
        r"if \(control && !alt && event\.key === Qt\.Key_H\)\s*\{"
        r"\s*Files\.toggleHidden\(\);",
        s,
    )


def test_files_ctrl_shift_n_creates_a_folder():
    """Finder/Nautilus use Ctrl+Shift+N for New Folder; Files had the toolbar
    button and the context-menu item, but no key path."""
    s = read(FILES)
    assert re.search(
        r"\(event\.modifiers & Qt\.ShiftModifier\) && event\.key === Qt\.Key_N\)\s*\{"
        r"\s*win\.openNewFolder\(\);",
        s,
    )


def test_photos_ctrl_a_selects_the_whole_view():
    """Finder/Nautilus select all with Ctrl+A; Photos could only Ctrl-click
    tiles one by one. The shortcut selects every photo in the current view."""
    s = read(PHOTOS)
    assert "function selectAll() { win.selected = win.shown.map(p => p.path); }" in s
    assert re.search(
        r"control && event\.key === Qt\.Key_A\)\s*\{\s*win\.selectAll\(\);", s
    )
    assert (
        "photoSearch.activeFocus || albumField.activeFocus || tagsField.activeFocus"
        in s
    )


def test_photos_delete_trashes_the_selection_or_the_detailed_photo():
    """Delete is the trash key in Finder/Nautilus/Dolphin; Photos only offered a
    hover icon. It now trashes the batch selection, or the detailed photo when
    there is no selection, and clears the stale detail path afterwards."""
    s = read(PHOTOS)
    assert re.search(
        r"event\.key === Qt\.Key_Delete && \(win\.selected\.length > 0 \|\| "
        r"win\.detailPath !== \"\"\)\)\s*\{\s*win\.trashSelected\(\);",
        s,
    )
    assert "win.detailPath ? [win.detailPath] : []" in s
    assert "paths.indexOf(win.detailPath) >= 0" in s
