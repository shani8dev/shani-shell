"""Static wiring checks for the Files selection fixes (18th pass).

- the context menu trashes the whole chosen set, not just the anchor
- Escape and a left-click on empty background clear the selection
- a re-list prunes vanished paths, unless a copy/move job still holds them
- the view toggle cycles grid <-> list only (there is no columns delegate)
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def body(text, header):
    return text.split(header, 1)[1].split("\n    }", 1)[0]


def test_move_to_trash_uses_all_chosen_paths():
    panel = read("shani/Modules/Files/FilesPanel.qml")
    assert "run: () => Files.trashEntries(chosen)" in panel
    assert "Files.trashEntries([e.path])" not in panel


def test_escape_and_background_clear_the_selection():
    panel = read("shani/Modules/Files/FilesPanel.qml")
    escape = body(panel, "Keys.onEscapePressed: {")
    # the first Escape lets go of a selection; the next one walks up or closes
    assert "Files.clearSelection()" in escape
    assert escape.index("Files.clearSelection()") < escape.index("Files.canUp")
    assert "acceptedButtons: Qt.RightButton | Qt.LeftButton" in panel
    assert "if (mouse.button === Qt.LeftButton)" in panel
    assert panel.count("Files.clearSelection()") >= 2


def test_set_paths_prunes_stale_selection_but_keeps_job_paths():
    service = read("shani/Services/Files.qml")
    set_paths = body(service, "function setPaths(paths) {")
    assert (
        "root.selected = root.selected.filter(p => root._paths.indexOf(p) >= 0)"
        in set_paths
    )
    # jobs snapshot their paths, but keep the visible selection while one is in flight
    assert "root.jobRunning || root._jobs.length" in set_paths
    assert "if (!busy)" in set_paths


def test_view_cycle_is_only_grid_and_list():
    panel = read("shani/Modules/Files/FilesPanel.qml")
    service = read("shani/Services/Files.qml")
    assert 'Files.setViewMode(Files.viewMode === "grid" ? "list" : "grid")' in panel
    assert '"columns"' not in panel and '"columns"' not in service
    # a persisted legacy "columns" resolves to grid, never a blank pane
    assert 'Settings.data.filesViewMode === "list" ? "list" : "grid"' in service
