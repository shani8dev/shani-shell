"""Static checks: hand-rolled Spinner+Text busy rows now use the shared BusyNote."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "shani/Modules"
NET = (MODULES / "NetTools.qml").read_text()
DB = (MODULES / "DatabaseBrowser.qml").read_text()
SCANNER = (MODULES / "Scanner/ScannerPanel.qml").read_text()
STARTUP = (MODULES / "Settings" / "SettingsStartup.qml").read_text()   # the Startup manager, merged
KUNDALI = (MODULES / "Kundali/KundaliPanel.qml").read_text()
RECORDER = (MODULES / "VoiceRecorder/VoiceRecorderPanel.qml").read_text()
BUSY = (ROOT / "shani/Common/BusyNote.qml").read_text()


def _busy_row(source, visible, note, icon):
    """A BusyNote carries the old row's visible/note and the spinner's size."""
    pos = source.index("BusyNote {")
    block = source[pos : source.index("}", pos)]
    assert visible in block, visible
    assert note in block, note
    assert icon in block, icon
    assert "Spinner {" not in source


def test_busy_note_owns_at_role_and_name():
    assert "Accessible.role: Accessible.StatusBar" in BUSY
    assert "Accessible.name: root.note" in BUSY


def test_nettools_loading_row_uses_busy_note():
    _busy_row(
        NET,
        "visible: win.loading",
        'note: win.activeTool + "…"',
        "iconSize: Theme.px(16)",
    )


def test_database_busy_row_uses_busy_note():
    _busy_row(
        DB,
        "visible: listProc.running || win.busy",
        'note: win.busy ? Tr.t("Running query…") : Tr.t("Reading tables…")',
        "iconSize: Theme.px(16)",
    )


def test_scanner_looking_row_uses_busy_note():
    _busy_row(
        SCANNER,
        "visible: win.looking",
        'note: Tr.t("Looking…")',
        "iconSize: Theme.px(16)",
    )


def test_scanner_scanning_row_uses_busy_note():
    assert SCANNER.count("BusyNote {") == 2
    block = SCANNER[SCANNER.rindex("BusyNote {") :]
    assert "visible: win.scanning" in block
    assert 'note: Tr.t("Scanning…")' in block
    assert "iconSize: Theme.px(28)" in block


def test_startup_busy_row_uses_busy_note():
    _busy_row(
        STARTUP,
        "visible: list.running",
        'note: Tr.t("Loading…")',
        "iconSize: Theme.px(16)",
    )


def test_kundali_busy_row_uses_busy_note():
    _busy_row(
        KUNDALI,
        "visible: win.loading",
        'note: Tr.t("Loading…")',
        "iconSize: Theme.px(24)",
    )


def test_voice_recorder_spinner_row_uses_busy_note():
    _busy_row(
        RECORDER,
        "visible: VideoTrimmer.cutting",
        'note: Tr.t("Saving…")',
        "iconSize: Theme.px(18)",
    )
    # the confirm/save button row is untouched
    assert (
        'text: VideoTrimmer.cutting ? Tr.t("Saving…") : Tr.t("Save trimmed copy")'
        in RECORDER
    )
