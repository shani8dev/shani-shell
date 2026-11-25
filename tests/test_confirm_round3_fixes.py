"""Round-3 static checks: safe hand-rolled two-tap confirms migrated to ConfirmButton.

Icon-mode ConfirmButton carries the same confirm contract: armed/timer/confirmed,
stable value key, and disarm on hide or context change. Unsafe/index-shifting or
custom-flow confirms are documented with shortcut notes, not migrated.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def confirm_block(text, ident):
    start = text.index("id: " + ident)
    open_brace = text.index("{", text.rfind("ConfirmButton", 0, start))
    depth = 0
    for i in range(open_brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace : i + 1]
    raise AssertionError("unterminated ConfirmButton block for " + ident)


def test_confirm_button_supports_icon_mode():
    s = read("shani/Common/ConfirmButton.qml")
    assert 'property string icon: ""' in s
    assert "property string armedIcon" in s
    assert "property string tip" in s
    assert "IconButton {" in s
    assert "onClicked: root.trigger()" in s
    assert "onVisibleChanged: if (!visible) root.disarm()" in s
    assert "onEnabledChanged: if (!enabled) root.disarm()" in s


def test_notes_notebook_delete_uses_confirm_button():
    s = read("shani/Modules/Notes/NotesPanel.qml")
    b = confirm_block(s, "deleteNotebookConfirm")
    assert 'icon: "list-remove"' in b
    assert 'tip: Tr.t("Remove the notebook %1").arg(win.selectedNotebook)' in b
    assert 'armedText: Tr.t("Tap again to delete the notebook and its notes")' in b
    assert "value: win.selectedNotebook" in b
    assert "interval: 4000" in b
    assert (
        'onConfirmed: { Services.QuickNotes.deleteNotebook(win.selectedNotebook); win.selectedNotebook = ""; }'
        in b
    )
    assert "confirmNotebook" not in s
    assert "notebookTimer" not in s
    assert "deleteNotebookConfirm.disarm()" in s


def test_tasks_row_delete_uses_confirm_button_keyed_by_uid():
    s = read("shani/Modules/Tasks/TasksWindow.qml")
    b = confirm_block(s, "deleteTaskConfirm")
    assert 'icon: "user-trash"' in b
    assert 'tip: Tr.t("Delete") + " " + row.modelData.summary' in b
    assert 'armedText: Tr.t("Tap again to delete this task")' in b
    assert "value: row.modelData.uid" in b
    assert "interval: 4000" in b
    assert "onConfirmed: Tasks.remove(row.modelData)" in b
    assert "deleteTaskConfirm.disarm()" in s  # reused delegate must not retarget
    assert "confirmTask" not in s
    assert "taskTimer" not in s


def test_sidebar_notes_delete_uses_confirm_button():
    s = read("shani/Modules/ControlCenter/SidebarNotes.qml")
    b = confirm_block(s, "deleteNoteConfirm")
    assert 'icon: "edit-delete"' in b
    assert 'tip: Tr.t("Delete this note")' in b
    assert 'armedText: Tr.t("Tap again to delete")' in b
    assert "interval: 4000" in b
    assert "QuickNotes.remove(QuickNotes.current, QuickNotes.currentNotebook)" in b
    assert "confirmDelete" not in s
    assert "deleteTimer" not in s
    assert "deleteNoteConfirm.disarm()" in s


def test_files_empty_trash_uses_confirm_button():
    s = read("shani/Modules/Files/FilesPanel.qml")
    b = confirm_block(s, "emptyTrashConfirm") if "id: emptyTrashConfirm" in s else None
    # icon-mode confirm button in toolbar
    assert "ConfirmButton {" in s
    assert 'icon: "user-trash-full"' in s
    assert (
        'armedText: Tr.t("Click again: everything in the trash is deleted for good")'
        in s
    )
    assert "onConfirmed: Files.emptyTrash()" in s
    assert "confirmEmpty" not in s


def test_files_cloud_remove_uses_confirm_button():
    s = read("shani/Modules/Files/FilesPanel.qml")
    b = confirm_block(s, "removeCloudConfirm")
    assert 'icon: "window-close"' in b
    assert 'armedIcon: "edit-delete"' in b
    assert "value: cloudRow.modelData.name" in b
    assert "onConfirmed: Files.forgetCloud(cloudRow.modelData)" in b
    assert "removeCloudConfirm.disarm()" in s
    assert "cloudRow.confirm" not in s


def test_unsafe_skips_documented():
    viewer = read("shani/Modules/Viewer/Viewer.qml")
    assert "shortcut:" in viewer
    editor = read("shani/Modules/TextEditor/TextEditorPanel.qml")
    assert "shortcut:" in editor
    assert "index-keyed" in editor.lower() or "index" in editor
    files = read("shani/Modules/Files/FilesPanel.qml")
    assert "shortcut:" in files
