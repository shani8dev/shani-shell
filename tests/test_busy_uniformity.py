"""Uniform busy rows: every migrated surface uses the one shared BusyNote.

Static, per-file checks catch a surface no test opens. The note->visible
mapping below is pure so the same expectation drives both the static checks
and the small table of edge cases at the bottom.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "shani/Modules"
BUSY = (ROOT / "shani/Common/BusyNote.qml").read_text(encoding="utf-8")

# (file, visible expression, note expression, properties that had to survive)
MIGRATED = [
    (
        "Backup/BackupPanel.qml",
        'Backup.running || Backup.restoring !== ""',
        'Backup.restoring !== "" ? Tr.t("Restoring %1…", Backup.restoring) : Tr.t("Backing up your home…")',
        ["align: Text.AlignHCenter", "Layout.fillWidth: true"],
    ),
    (
        "DiskUsage/DiskUsagePanel.qml",
        "DiskUsage.scanning",
        'Tr.t("Scanning…")',
        ["anchors.centerIn: parent"],
    ),
    (
        "Files/FilesPanel.qml",
        "dir.loading && win.visibleEntries.length === 0",
        'Tr.t("Loading…")',
        ["anchors.centerIn: parent"],
    ),
    ("Files/FilesPanel.qml", "Files.syncBusy", 'Tr.t("Syncing…")', []),
    (
        "Mail/MailWindow.qml",
        "Mail.busy && Mail.messages.length === 0",
        'Tr.t("Loading mail…")',
        ["Layout.fillWidth: true"],
    ),
    ("Nearby/NearbyWindow.qml", "Nearby.scanning", 'Tr.t("Looking…")', []),
    (
        "Overview/OverviewStats.qml",
        "TopProcesses.list.length === 0",
        'Tr.t("Reading…")',
        [],
    ),
    (
        "PdfReader/PdfReader.qml",
        "PdfViewer.loading",
        'Tr.t("Rendering pages…")',
        ["anchors.centerIn: parent"],
    ),
    (
        "Processes/Processes.qml",
        "Sensors.loading && !Sensors.answered && Sensors.sensors.length === 0",
        'Tr.t("Reading sensors…")',
        ["Layout.fillWidth: true"],
    ),
    (
        "QuickLook/QuickLookSheet.qml",
        "win.metaShown && FileMeta.loading",
        'Tr.t("Reading…")',
        [],
    ),
    (
        "QuickLook/QuickLookSheet.qml",
        "win.metaShown && FileMeta.loading",
        'Tr.t("Reading file details…")',
        ["anchors.centerIn: parent"],
    ),
    (
        "Settings/SettingsWallpaperStyle.qml",
        "Matugen.previewRunning",
        'Tr.t("Extracting…")',
        [],
    ),
    (
        "Software/SoftwareWindow.qml",
        "win.permsLoading",
        'Tr.t("Reading permissions…")',
        [],
    ),
    (
        "Studio/StudioWindow.qml",
        "Studio.busy",
        'Tr.t("Chronoa is generating your app… check the Chronoa panel for progress")',
        [],
    ),
    (
        "VoiceRecorder/VoiceRecorderPanel.qml",
        "win.peaksLoading",
        'Tr.t("Reading waveform…")',
        ["Layout.fillWidth: true"],
    ),
]


def note_visibility(visible, *notes):
    """Pure note -> visible mapping: one busy row shows all its notes under one guard."""
    assert notes, "a busy row needs at least one note"
    return {note: visible for note in notes}


def blocks(source, kind):
    """Every `Kind { … }` block in the file, matched on outer braces."""
    out = []
    for m in re.finditer(r"\b" + re.escape(kind) + r"\s*\{", source):
        depth = 0
        for j in range(m.end() - 1, len(source)):
            if source[j] == "{":
                depth += 1
            elif source[j] == "}":
                depth -= 1
                if depth == 0:
                    out.append(source[m.start() : j + 1])
                    break
    return out


SOURCES = {rel: (MODULES / rel).read_text(encoding="utf-8") for rel, *_ in MIGRATED}


def test_busy_note_is_the_single_shared_shape():
    assert "import QtQuick.Layouts" in BUSY
    assert "property string note" in BUSY
    assert "property real iconSize" in BUSY
    assert "property alias align: text.horizontalAlignment" in BUSY
    assert "Spinner { size: root.iconSize }" in BUSY
    assert "text: root.note" in BUSY
    assert "Accessible.role: Accessible.StatusBar" in BUSY
    assert "Accessible.name: root.note" in BUSY


@pytest.mark.parametrize("rel,visible,note,extra", MIGRATED)
def test_migrated_row_keeps_note_visible_and_alignment(rel, visible, note, extra):
    source = SOURCES[rel]
    assert "import qs.Common" in source, rel
    assert note_visibility(visible, note) == {note: visible}

    matches = [
        b
        for b in blocks(source, "BusyNote")
        if f"visible: {visible}" in b and f"note: {note}" in b
    ]
    assert len(matches) == 1, f"{rel}: expected one BusyNote for {note}"
    block = matches[0]
    for prop in extra:
        assert prop in block, f"{rel}: lost {prop}"


@pytest.mark.parametrize("rel", sorted(SOURCES))
def test_no_hand_rolled_busy_text_is_left(rel):
    source = SOURCES[rel]
    expected = [(v, n) for r, v, n, _ in MIGRATED if r == rel]
    for block in blocks(source, "Text"):
        for visible, note in expected:
            assert not (f"visible: {visible}" in block and f"text: {note}" in block), (
                f"{rel}: hand-rolled busy row still shows {note}"
            )


@pytest.mark.parametrize(
    "visible,notes,expected",
    [
        (
            "Mail.busy && Mail.messages.length === 0",
            ('Tr.t("Loading mail…")',),
            {'Tr.t("Loading mail…")': "Mail.busy && Mail.messages.length === 0"},
        ),
        (
            'Backup.running || Backup.restoring !== ""',
            (
                'Tr.t("Restoring %1…", Backup.restoring)',
                'Tr.t("Backing up your home…")',
            ),
            {
                'Tr.t("Restoring %1…", Backup.restoring)': 'Backup.running || Backup.restoring !== ""',
                'Tr.t("Backing up your home…")': 'Backup.running || Backup.restoring !== ""',
            },
        ),
    ],
)
def test_note_visibility_pure_mapping(visible, notes, expected):
    assert note_visibility(visible, *notes) == expected


def test_note_visibility_rejects_an_empty_row():
    with pytest.raises(AssertionError):
        note_visibility("win.busy")
