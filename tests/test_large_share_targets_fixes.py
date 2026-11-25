"""Static guards for the "Share targets" upgrade on the share sheet.

These surfaces need live services (Bluetooth, Nearby, Archive) that the suite
cannot start, so the tests pin the wiring in the QML source of the Share
service (shani/Services/Share.qml) and the Share sheet
(shani/Modules/Share/ShareSheet.qml): multi-file input, drag-on, recent
targets first, quality indicator text, normalised icons, denied/no-app
states, the archive-then-share target, the cancel button, AT names and the
empty/error states.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHARE = "shani/Services/Share.qml"
SHEET = "shani/Modules/Share/ShareSheet.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_drag_files_onto_the_sheet():
    """Drop files onto the sheet: they become what Share shares."""
    s, q = read(SHEET), read(SHARE)
    assert "DropArea" in s and "onDropped: drop =>" in s
    assert 'Share.open(drop.urls.map(u => u.toLocalFile()).filter(p => p !== ""))' in s
    assert "property var files" in q and "function open(paths)" in q


def test_recent_targets_come_first():
    """Recently chosen targets sort to the top of the sheet."""
    q, s = read(SHARE), read(SHEET)
    assert "property var recent" in q and "noteRecent" in q
    assert "root.recent = [l].concat(root.recent.filter(x => x !== l)).slice(0, 6)" in q
    assert "out.push(Object.assign({}, t, { recent: true }))" in q
    assert 'modelData.recent ? Tr.t("Recent: %1").arg(modelData.label)' in s


def test_target_quality_indicator():
    """Each row carries a status word (Ready/Off) next to its icon."""
    q, s = read(SHARE), read(SHEET)
    assert 'case "ready": return Tr.t("Ready")' in q
    assert 'case "off": return Tr.t("Off")' in q
    assert (
        'state: (Nearby.running || Nearby.visible_ || Nearby.scanning) ? "ready" : "off"'
        in q
    )
    assert (
        'modelData.subtitle !== "" ? modelData.subtitle : Share.targetStateText(modelData.state)'
        in s
    )


def test_icon_names_are_normalised():
    """Whatever a device or a caller offers, the row paints a known icon."""
    q, s = read(SHARE), read(SHEET)
    assert "function iconFor(s)" in q
    assert '? n : "text-x-generic"' in q
    assert "Share.iconFor(modelData.icon)" in s


def test_access_denied_and_no_app_states():
    """Failing targets show words, not a blank row."""
    q, s = read(SHARE), read(SHEET)
    assert 'case "none": return Tr.t("No app")' in q
    assert 'case "denied": return Tr.t("Access denied")' in q
    assert "property string lastError" in q
    assert 'visible: Share.lastError !== ""' in s
    assert 'Tr.t("The copy to the clipboard failed")' in q


def test_archive_and_share():
    """The sheet can archive the files first and reopen on the archive."""
    q, s = read(SHARE), read(SHEET)
    assert 'label: Tr.t("Archive and share (zip)")' in q
    assert "Archive.createAsk(root.files)" in q
    assert "property bool archiveWait" in q
    assert "Archive.creating" in q
    assert "archiveTimer" in s and "Share.archiveChanged()" in s


def test_cancel_stops_running_shares():
    """Cancel closes the sheet and stops anything already running."""
    q, s = read(SHARE), read(SHEET)
    assert "function cancel()" in q
    assert 'BtSend.file = ""' in q and "Nearby.pending = []" in q
    assert "Share.cancel()" in s


def test_a11y_names_on_sheet():
    """The sheet and its rows name themselves to screen readers."""
    s = read(SHEET)
    assert 'Accessible.name: Tr.t("Share %1").arg(Share.name)' in s
    assert (
        'Accessible.name: modelData.recent ? Tr.t("Recent: %1").arg(modelData.label) : modelData.label'
        in s
    )
    assert 'Accessible.name: Tr.t("Cancel")' in s


def test_empty_state_and_error_banner():
    """With no targets the sheet says so; a failed target says why."""
    s = read(SHEET)
    assert "EmptyState" in s and 'title: Tr.t("No targets yet")' in s
    assert "visible: Share.targets.length === 0" in s


def test_visible_switches_to_the_files_list():
    """The sheet opens only for files now; Share.file still works for callers."""
    s, q = read(SHEET), read(SHARE)
    assert "Share.files.length > 0 && !Lock.locked" in s
    assert 'readonly property string file: files.length ? files[0] : ""' in q


def test_multi_file_targets():
    """Every target runs on the file list, not the first file."""
    q = read(SHARE)
    assert '["xdg-email", "--attach"].concat(root.files)' in q
    assert '["gio", "open", root.files[0]]' in q
