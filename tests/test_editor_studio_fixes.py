"""Static checks for the text-editor/studio fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EDITOR = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text(
    encoding="utf-8"
)
STUDIO = (ROOT / "shani/Modules/Studio/StudioWindow.qml").read_text(encoding="utf-8")


def test_caret_is_survived_by_the_selection_restore():
    fn = EDITOR[
        EDITOR.index("function restoreCaret()") : EDITOR.index(
            "// the document in front"
        )
    ]
    assert "edit.cursorPosition = Math.max(0, Math.min(c.pos, n));" in fn
    assert "edit.select(a, b);" in fn
    assert fn.index("edit.cursorPosition") < fn.index("edit.select(a, b);"), (
        "assigning the caret after select() would collapse the selection"
    )
    assert "property var caretByDoc: ({})" in EDITOR
    assert "function saveCaret()" in EDITOR


def test_read_only_files_are_not_overwritten_by_save():
    fn = EDITOR[EDITOR.index("function save()") : EDITOR.index("function find(")]
    assert "TextDocs.current.readOnly" in fn
    assert "win.saveAs();" in fn


def test_replace_requires_the_selection_to_be_exactly_one_match():
    fn = EDITOR[
        EDITOR.index("function selectionIsMatch()") : EDITOR.index(
            "function replaceOne()"
        )
    ]
    assert "m.index === 0 && m[0].length === edit.selectedText.length" in fn
    assert (
        "if (win.selectionIsMatch())" in EDITOR[EDITOR.index("function replaceOne()") :]
    )


def test_shift_enter_walks_find_results_backwards():
    field = EDITOR[
        EDITOR.index("onAccepted: win.find(true)") : EDITOR.index(
            'CheckBox { text: "Aa"'
        )
    ]
    assert "input.Keys.onPressed" in field
    assert "Qt.Key_Return || e.key === Qt.Key_Enter" in field
    assert "win.find(!(e.modifiers & Qt.ShiftModifier))" in field


def test_studio_names_its_list_and_shows_pending_delete():
    assert "Accessible.role: Accessible.List" in STUDIO
    assert "Accessible.role: Accessible.ListItem" in STUDIO
    assert (
        "win.confirmDelete === modelData.name ? Theme.alpha(Theme.danger, 0.14)"
        in STUDIO
    )
    assert 'Tr.t("Click again to delete")' in STUDIO
