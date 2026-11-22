"""Clipboard encryption, notes sync, and mail folder fixes."""

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def test_notes_sync_uses_rsync_and_setting():
    q = (ROOT / "shani/Services/QuickNotes.qml").read_text()
    assert "TODO: notes sync" not in q
    assert "function syncNotes()" in q
    assert "rsync -au" in q
    assert "notesSyncPath" in q
    s = (ROOT / "shani/Common/Settings.qml").read_text()
    assert "notesSyncPath" in s
    sidebar = (ROOT / "shani/Modules/ControlCenter/SidebarNotes.qml").read_text()
    assert "Sync now" in sidebar and "FolderPicker" in sidebar


def test_mail_folder_aware():
    b = (ROOT / "bridge/mail.py").read_text()
    assert "def imap_read(c, uid, folder" in b
    assert "def imap_flag(c, uid, flag, on, folder" in b
    assert "def imap_delete(c, uid, folder" in b
    assert b.count('box.select(folder or "INBOX")') == 3
    q = (ROOT / "shani/Services/Mail.qml").read_text()
    assert 'run("read", [uid, root.folder])' in q
    assert 'run("delete", [uid, root.folder])' in q
    assert 'what === "send"' in q


def test_mail_syntax():
    assert (
        subprocess.run(
            ["python3", "-m", "py_compile", str(ROOT / "bridge/mail.py")],
            capture_output=True,
        ).returncode
        == 0
    )
