"""Safety regressions for Notes: lock history, out-of-band edits, delete confirm.

Static checks on the three surfaces plus one small unit check of the history
purge command, so a future refactor cannot silently reintroduce these.
"""

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = (ROOT / "shani/Services/QuickNotes.qml").read_text()
PANEL = (ROOT / "shani/Modules/Notes/NotesPanel.qml").read_text()
SIDEBAR = (ROOT / "shani/Modules/ControlCenter/SidebarNotes.qml").read_text()


def _section(src: str, start: str, end: str) -> str:
    i = src.index(start)
    return src[i : src.index(end, i)]


def test_lock_purges_plaintext_history(tmp_path):
    # A lock must clear .history/<id>-*.md, not just encrypt the current .md.
    branch = _section(
        SERVICE, 'noteCrypto.mode === "lock"', 'noteCrypto.mode === "encrypt"'
    )
    assert "root.historyDir" in branch
    assert 'rm -f -- "$1"/"$2"-*.md' in branch
    assert r"\.locked" in branch  # key is the pre-lock name

    hist = tmp_path / "history"
    hist.mkdir()
    for name in ("foo-1.md", "foo-2.md", "bar-1.md"):
        (hist / name).write_text("secret")
    subprocess.run(
        ["sh", "-c", 'rm -f -- "$1"/"$2"-*.md', "sh", str(hist), "foo"], check=True
    )
    assert sorted(p.name for p in hist.iterdir()) == ["bar-1.md"]


def test_autosave_detects_outside_edits_and_panel_offers_reload_discard():
    assert "property string readStamp" in SERVICE
    assert "property bool diskChanged" in SERVICE
    save = _section(SERVICE, "id: save", "// mtime+size of the file")
    assert "statCheck.running = true" in save
    assert "file.setText" not in save  # the write is gated on the stat callback
    check = _section(SERVICE, "id: statCheck", "function performSave()")
    assert "root.diskChanged = true" in check
    assert "save.stop()" in check
    assert "root.performSave()" in check
    assert "statBaseline.running = true" in SERVICE
    assert "function reloadFromDisk()" in SERVICE
    assert "function discardExternalChange()" in SERVICE

    assert "Services.QuickNotes.diskChanged" in PANEL
    assert 'Tr.t("Reload")' in PANEL
    assert 'Tr.t("Discard")' in PANEL
    assert "Services.QuickNotes.reloadFromDisk()" in PANEL
    assert "Services.QuickNotes.discardExternalChange()" in PANEL


def test_sidebar_delete_needs_two_taps():
    assert "id: deleteNoteConfirm" in SIDEBAR
    assert "ConfirmButton" in SIDEBAR
    assert "onConfirmed:" in SIDEBAR
    assert "QuickNotes.remove(" in SIDEBAR
