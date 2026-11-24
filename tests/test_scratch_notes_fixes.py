"""Static checks for the scratchpad/Notes surface fixes: visibility state,
notebook-aware wiki links, confirmation scope, editor empty state and the
locked-note export guard.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRATCH = (ROOT / "shani/Services/Scratchpads.qml").read_text()
NOTES_SERVICE = (ROOT / "shani/Services/QuickNotes.qml").read_text()
PANEL = (ROOT / "shani/Modules/Notes/NotesPanel.qml").read_text()


def test_scratchpad_visibility_state_and_explicit_show_hide():
    assert "function windowFor(name)" in SCRATCH
    assert "function isVisible(name)" in SCRATCH
    assert "function show(name)" in SCRATCH
    assert "function hide(name)" in SCRATCH
    assert "Niri.restore(w.id)" in SCRATCH
    assert "Niri.minimise(w.id)" in SCRATCH
    assert "isVisible(key) && w.id === Niri.focusedWindowId" in SCRATCH
    assert "show(key)" in SCRATCH and "hide(key)" in SCRATCH


def test_wiki_link_chips_resolve_notebook_qualified_targets():
    assert "onClicked: Services.QuickNotes.open(modelData)" in PANEL
    assert 'Services.QuickNotes.open(modelData, "")' not in PANEL
    # the service only splits "notebook/note" when notebook is omitted
    assert "function open(name, notebook)" in NOTES_SERVICE
    assert "if (nb === undefined && slash >= 0)" in NOTES_SERVICE


def test_delete_confirmation_does_not_survive_selection_change():
    assert "onSelectedNotebookChanged: win.confirmNotebook = false" in PANEL
    assert "target: Services.QuickNotes" in PANEL
    # stronger than the original one-liner: a switch also drops a stale editor
    # body and a history view that belonged to the previous note
    handler = PANEL[PANEL.index("function onCurrentChanged()") :]
    assert "win.confirmDelete = false;" in handler
    assert 'win.note = "";' in handler
    assert "win.showHistory = false;" in handler


def test_editor_empty_state_and_disabled_without_a_note():
    assert 'title: Tr.t("No note selected")' in PANEL
    assert 'actionText: Tr.t("New note")' in PANEL
    assert (
        'onAction: Services.QuickNotes.create(Tr.t("Untitled"), win.selectedNotebook)'
        in PANEL
    )
    view = re.search(r"ScrollView \{\s*visible: ([^\n]+)", PANEL)
    assert view and view.group(1).strip().startswith(
        'Services.QuickNotes.current !== ""'
    )
    editor = re.search(r"TextArea \{\s*id: editor\s*enabled: ([^\n]+)", PANEL)
    assert editor and 'Services.QuickNotes.current !== ""' in editor.group(1)


def test_locked_note_export_and_print_are_disabled():
    guards = re.findall(
        r'Button \{ text: Tr\.t\("(?:Export HTML|Print)"\); enabled: ([^;]+);',
        PANEL,
    )
    assert len(guards) == 2, guards
    assert all(
        "!Services.QuickNotes.locked || Services.QuickNotes.unlocked" in g
        for g in guards
    )
