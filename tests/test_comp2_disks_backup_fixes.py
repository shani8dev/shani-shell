"""Competitive-research fixes: Disks vs GNOME Disks/KDE PM, Backup vs Time Machine.

Five gaps not listed in docs/GAPS.md or GAPS-RESEARCH.md. Static wiring checks,
in the style of the sibling test_gap_* / test_competitive_* tests: no QML runtime
or real hardware is available in this container.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW = ROOT / "shani" / "Modules" / "Disks" / "DisksWindow.qml"
PANEL = ROOT / "shani" / "Modules" / "Backup" / "BackupPanel.qml"


def read(path):
    return path.read_text(encoding="utf-8")


def between(text, start, end):
    block = text.split(start, 1)[1]
    return block.split(end, 1)[0]


def test_disks_keeps_selection_across_refresh():
    """Competitor: the selected drive stays selected after a list update.

    Every mount/unmount/job calls Disks.refresh(), which rebuilds the model; the
    old selectedDisk object is then no longer any delegate's modelData.
    """
    w = read(WINDOW)
    block = between(
        w,
        "// refresh() rebuilds the model: keep the same drive selected by path",
        "// Esc: leave op mode first, then close",
    )
    assert "target: Disks" in block
    assert "function onDisksChanged()" in block
    assert "Disks.disks.find(d => d.path === p)" in block
    assert "win.selectedDisk = fresh || null" in block


def test_disks_mount_toggle_targets_the_partition():
    """Competitor: mount/eject acts on a volume, not on the whole disk device."""
    w = read(WINDOW)
    assert "function partPath(p)" in w  # lsblk -p gives the full path in `name`
    block = between(
        w,
        "// per-volume mount toggle: mount the partition, not the whole disk",
        "// proportional space-allocation bar",
    )
    assert "function toggle()" in block
    assert "const p = win.partPath(modelData)" in block
    assert "Disks.unmount(p)" in block and "Disks.mount(p)" in block
    assert "Accessible.role: Accessible.Button" in block
    assert "MouseArea {" in block and "onClicked: toggleText.toggle()" in block


def test_disks_filesystem_checks_need_an_unmounted_volume():
    """Competitor: fsck/bad-block checks require the filesystem to be unmounted."""
    w = read(WINDOW)
    assert "function isMounted(d)" in w
    assert "(d.children || []).some(c => (c.mountpoints || []).length > 0)" in w
    assert "function canScan(d)" in w
    assert "!win.isMounted(d)" in w
    assert w.count("enabled: win.canScan(modelData)") == 2
    assert 'Tr.t("Unmount this filesystem before checking it")' in w
    # the existing two-click confirmation is untouched
    assert 'win.confirmAction === "fsck-" + modelData.path' in w
    assert 'win.confirmAction === "badblocks-" + modelData.path' in w


def test_backup_panel_offers_back_up_now():
    """Competitor: Time Machine / Deja Dup have a Back Up Now action in the app."""
    p = read(PANEL)
    start = p.index('text: Tr.t("Back up now")')
    block = p[start - 200 : start + 500]
    assert 'Tr.t("Back up now")' in block
    assert "Backup.available && Backup.driveSetUp && !Backup.running" in block
    assert "busy: Backup.running" in block
    assert "Backup.backupNow()" in block


def test_backup_panel_says_when_the_backup_tool_is_missing():
    """Competitor: an unavailable backup service is named, not mistaken for empty."""
    p = read(PANEL)
    start = p.index("visible: !Backup.available")
    block = p[start - 80 : start + 400]
    assert "The backup tool is not installed" in block
    assert (
        "visible: !Backup.loading && Backup.snapshots.length === 0 && Backup.available"
        in p
    )
