"""Static wiring checks for Backup / Disks panel gaps not listed in docs/GAPS*.md.

Five low-risk fixes: backup in-flight feedback, backup empty-state next step,
stale two-click confirmation, always-visible error banner, and AT names on disk rows.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_backup_panel_shows_in_flight_backup_or_restore():
    p = read("shani/Modules/Backup/BackupPanel.qml")
    assert 'visible: Backup.busyOp !== "" || Backup.copyBusy' in p
    assert 'Tr.t("Restoring your backup…")' in p
    assert 'Tr.t("Backing up your home…")' in p


def test_backup_empty_state_offers_setup_next_step():
    p = read("shani/Modules/Backup/BackupPanel.qml")
    assert 'Tr.t("No backup drive set up")' in p
    # Plain words, not a button that would start the GTK app
    assert 'Tr.t("Choose another drive or a folder outside your home' in p
    assert "Backup.open(" not in p
    assert "EmptyState {" in p


def test_disks_confirm_is_rearmed_on_device_or_op_change():
    w = read("shani/Modules/Disks/DisksWindow.qml")
    assert (
        'onSelectedDiskChanged: { win.confirmAction = ""; confirmTimer.stop(); }' in w
    )
    assert 'onOpModeChanged: { win.confirmAction = ""; confirmTimer.stop(); }' in w


def test_error_banner_is_outside_the_op_form():
    w = read("shani/Modules/Disks/DisksWindow.qml")
    assert "// ---- error banner" in w
    banner = w.index("// ---- error banner")
    form = w.index("// ---- operation form")
    assert banner < form
    block = w[banner:form]
    assert 'visible: Disks.error !== ""' in block
    assert "text: Disks.error" in block
    # no duplicate error Text left hidden behind the form's visibility
    assert "text: Disks.error" not in w[form:]


def test_disk_rows_expose_accessible_role_and_name():
    w = read("shani/Modules/Disks/DisksWindow.qml")
    assert "Accessible.role: Accessible.ListItem" in w
    assert 'Accessible.name: (modelData.model || modelData.name || "")' in w
    assert "win.diskKind(modelData)" in w
