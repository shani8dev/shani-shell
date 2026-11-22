"""Notes gaps: trash/restore, versions, formatting, tags, sort, body search, due dates."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = (ROOT / "shani/Services/QuickNotes.qml").read_text()
PANEL = (ROOT / "shani/Modules/Notes/NotesPanel.qml").read_text()


def test_trash_instead_of_rm_and_restore():
    assert 'root.trashDir + "/"' in SERVICE
    assert '\'mkdir -p "$1" && mv -f -- "$2" "$3"\'' in SERVICE
    assert "function restore(key)" in SERVICE
    assert "function emptyTrash()" in SERVICE
    assert "Services.QuickNotes.restore(modelData)" in PANEL


def test_version_history_copies_and_restores():
    assert "root.historyDir" in SERVICE
    assert "function snapshot()" in SERVICE
    assert 'cp -p -- "$1" "$3"' in SERVICE
    assert "function restoreVersion(path)" in SERVICE
    assert "Services.QuickNotes.history(" in PANEL


def test_formatting_toolbar_wraps_selection():
    assert "function wrapSelection(prefix, suffix)" in PANEL
    assert 'win.wrapSelection("**", "**")' in PANEL
    assert 'win.wrapSelection("*", "*")' in PANEL
    assert 'win.wrapSelection("[", "](https://)")' in PANEL
    assert "function prefixLine(prefix)" in PANEL


def test_tags_with_filter():
    assert "function tags()" in SERVICE
    assert "function notesWithTag(tag)" in SERVICE
    assert "win.tagFilter" in PANEL
    assert "model: Services.QuickNotes.tags()" in PANEL


def test_sort_control_and_previews_in_list():
    assert "function sortedNotes(list)" in SERVICE
    assert "property var previews" in SERVICE
    assert (
        "model: Services.QuickNotes.sortBy" in PANEL
        or "Services.QuickNotes.sortBy === modelData[0]" in PANEL
    )
    assert "Services.QuickNotes.preview(modelData.name, modelData.notebook)" in PANEL


def test_body_search_results_are_browseable():
    assert "property var bodyResults" in SERVICE
    assert "root.bodyResults = hits.map" in SERVICE
    assert "model: Services.QuickNotes.bodyResults" in PANEL
    assert "win.bodyQuery" in PANEL


def test_due_dates_on_checklists():
    assert "function setDueDate(lineIndex, due)" in SERVICE
    assert "function dueDates()" in SERVICE
    assert "@due(" in SERVICE
    assert "win.addDue(" in PANEL
