"""Static wiring checks for the second Files selection pass.

- the main status line adds the human-readable total size of the selection
- Ctrl+Space toggles the keyboard-focused item; plain Space stays Quick Look
- Shift+arrows extend the range selection from the existing anchor

Shift+arrows are handled here rather than in Common/KeyFocus.qml because that
shared component does not pass arrow modifiers to its owner (it is outside this
pass's file ownership); the limit is documented in the QML comment.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_selection_status_shows_total_size():
    panel = read("shani/Modules/Files/FilesPanel.qml")
    service = read("shani/Services/Files.qml")
    assert "function selectedSize()" in service
    assert "root.entryFor(p)" in service
    assert 'Tr.t("%1 selected · %2")' in panel
    assert "Files.humanSize(Files.selectedSize())" in panel
    # the count-only form is gone
    assert 'Tr.t("%1 selected").arg(Files.selected.length)' not in panel


def test_ctrl_space_toggles_focused_selection():
    panel = read("shani/Modules/Files/FilesPanel.qml")
    assert 'sequence: "Ctrl+Space"' in panel
    assert 'Files.select(Files.current, "toggle")' in panel
    # plain Space still opens Quick Look, and only without a modifier
    assert "Qt.Key_Space && !control && !alt" in panel
    assert "QuickLook.open(at, Files._paths)" in panel


def test_shift_arrows_extend_selection():
    panel = read("shani/Modules/Files/FilesPanel.qml")
    assert "function extendSelection(key)" in panel
    extend = panel.split("function extendSelection(key) {", 1)[1].split("\n    }", 1)[0]
    assert "kf.move(n)" in extend
    assert 'Files.select(focused, "range")' in extend
    for key in ("Left", "Right", "Up", "Down"):
        assert '"Shift+%s"' % key in panel
