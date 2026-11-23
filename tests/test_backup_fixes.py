"""Static wiring checks for the backup / restore shell fixes (pass 19)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_restore_job_notifies_with_open_result():
    # a restore run through the shell reports completion and offers to open the
    # folder it wrote into; the bridge exposes `restore <target> --snapshot <id>`
    text = read("shani/Services/Backup.qml")
    assert "id: restoreJob" in text
    assert '"restore", root.restoreTarget' in text
    assert 'Tr.t("Open result")' in text
    assert 'Qt.openUrlExternally("file://" + restoreNote.path)' in text


def test_loading_flag_gates_timeline_message():
    # "No snapshots yet" must not show before `home list` has answered
    svc = read("shani/Services/Backup.qml")
    assert "property bool loading: false" in svc
    assert "loading = true" in svc
    assert svc.count("root.loading = false") >= 2  # both collectors clear it
    panel = read("shani/Modules/Backup/BackupPanel.qml")
    assert "!Backup.loading && Backup.snapshots.length === 0" in panel


def test_backup_now_is_single_flight():
    # every surface (launcher, settings, control centre) calls backupNow();
    # a second call while a backup is running must be refused
    body = (
        read("shani/Services/Backup.qml")
        .split("function backupNow() {", 1)[1]
        .split("\n    }", 1)[0]
    )
    assert "if (running) return" in body
