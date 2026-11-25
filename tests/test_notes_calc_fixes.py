"""Static checks for the notes and calculator fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTES = (ROOT / "shani/Modules/Notes/NotesPanel.qml").read_text(encoding="utf-8")
CALC = (ROOT / "shani/Modules/Calculator/Calculator.qml").read_text(encoding="utf-8")


def test_note_switch_drops_pending_delete_and_history():
    conn = NOTES[NOTES.index("target: Services.QuickNotes") :]
    assert "function onCurrentChanged()" in conn
    assert "deleteNoteConfirm.disarm();" in conn
    assert 'win.note = "";' in conn
    assert "win.showHistory = false;" in conn


def test_any_filter_gives_a_no_match_empty_state():
    assert (
        'readonly property bool hasFilter: filterText !== "" || tagFilter !== "" || selectedNotebook !== ""'
        in NOTES
    )
    empty = NOTES[
        NOTES.index("visible: noteList.count === 0") : NOTES.index("onAction:")
    ]
    assert "icon: win.hasFilter" in empty
    assert "title: win.hasFilter" in empty
    assert "actionText: win.hasFilter" in empty
    assert 'win.tagFilter = ""; win.selectedNotebook = "";' in NOTES


def test_calculator_names_division_by_zero():
    assert "readonly property bool divideByZero" in CALC
    assert (
        'win.divideByZero ? Tr.t("Cannot divide by zero") : Services.Calculator.error'
        in CALC
    )
