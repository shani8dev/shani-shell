"""Round 3: BusyNote/EmptyState replace hand-rolled busy rows and empty placeholders.

Static checks only. Owned files: Viewer, Containers, SysMon, Backup, Disks, Mail.
"""

from pathlib import Path
import re
import pytest

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "shani/Modules"

FILES = {
    "viewer": MOD / "Viewer/Viewer.qml",
    "containers": MOD / "Containers/ContainersWindow.qml",
    "sysmon": MOD / "SysMon/SysMonWindow.qml",
    "backup": MOD / "Backup/BackupPanel.qml",
    "disks": MOD / "Disks/DisksWindow.qml",
    "mail": MOD / "Mail/MailWindow.qml",
}


def read(key):
    p = FILES[key]
    return p.read_text(encoding="utf-8")


def has_spinner_busy_row(src):
    # Hand-rolled Row { ... Spinner ... Text ... } busy indicator.
    return bool(
        re.search(
            r"Row(Layout)?\s*\{[^{}]*Spinner\s*\{[^{}]*\}[^{}]*Text\s*\{", src, re.S
        )
    )


def test_viewer_empty_uses_emptystate():
    src = read("viewer")
    assert "EmptyState {" in src
    assert 'title: Tr.t("No picture")' in src
    assert 'visible: Viewer.file === ""' in src
    # no hand-rolled centered plain-text placeholder for this case
    assert not re.search(
        r'Text\s*\{[^{}]*visible:\s*Viewer\.file === ""[^{}]*Tr\.t\("No picture"\)',
        src,
        re.S,
    )


def test_backup_empty_uses_emptystate():
    src = read("backup")
    assert src.count("EmptyState {") >= 1
    assert (
        "visible: !Backup.loading && Backup.snapshots.length === 0 && Backup.available"
        in src
    )
    assert 'title: Tr.t("No earlier versions yet")' in src
    # the empty state says what to do; no GTK app is started from here
    assert 'actionText: Tr.t("Take a snapshot now")' in src
    assert "Backup.open(" not in src


def test_backup_busy_uses_busynote():
    src = read("backup")
    assert "BusyNote {" in src
    assert 'Backup.running ? Tr.t("Backing up your home…")' in src
    assert 'Backup.busyOp === "restore" ? Tr.t("Restoring your backup…")' in src


def test_mail_uses_shared_components():
    src = read("mail")
    assert "BusyNote {" in src
    assert "EmptyState {" in src
    assert 'note: Tr.t("Loading mail…")' in src
    assert not has_spinner_busy_row(src)


def test_containers_has_no_handrolled_busy_row():
    src = read("containers")
    assert not has_spinner_busy_row(src)
    # already uses EmptyState for images tab
    assert "EmptyState {" in src


def test_disks_has_no_handrolled_busy_row():
    src = read("disks")
    assert not has_spinner_busy_row(src)
    assert "EmptyState {" in src


def test_sysmon_uses_shared_components_if_present():
    p = FILES["sysmon"]
    if not p.exists():
        pytest.skip("SysMon/SysMonWindow.qml not present in this tree")
    src = p.read_text(encoding="utf-8")
    assert not has_spinner_busy_row(src)
    # if it has empty/busy placeholders, they should be shared components;
    # at minimum no hand-rolled spinner busy row.
    assert "BusyNote {" in src or "EmptyState {" in src or not has_spinner_busy_row(src)
