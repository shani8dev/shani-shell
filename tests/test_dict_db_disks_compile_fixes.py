"""Static checks for the Dictionary/DatabaseBrowser/Disks QML compile fixes.

No QML runtime here: assert the import that provides FileView/Process is present
and that the non-existent TextField handler is gone.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DICT = ROOT / "shani" / "Modules" / "Dictionary.qml"
DB = ROOT / "shani" / "Modules" / "DatabaseBrowser.qml"
DISKS = ROOT / "shani" / "Modules" / "Disks" / "DisksWindow.qml"


def read(path):
    return path.read_text(encoding="utf-8")


def test_dictionary_imports_io_for_fileview():
    d = read(DICT)
    assert "import Quickshell.Io" in d
    assert "FileView {" in d
    assert "id: pinnedFile" in d
    assert 'path: Quickshell.statePath("dictionary-pinned.json")' in d


def test_dictionary_keeps_accessible_names():
    d = read(DICT)
    assert 'Accessible.name: Tr.t("Search a word")' in d
    assert 'Accessible.name: Tr.t("Pinned words")' in d


def test_database_browser_uses_canonical_accepted_handler():
    db = read(DB)
    assert "onEditingFinished" not in db
    assert "Keys.onAccepted" not in db
    assert "onAccepted: win.dbPath = text.trim()" in db


def test_database_browser_keeps_io_import_and_accessible_name():
    db = read(DB)
    assert "import Quickshell.Io" in db
    assert "Process {" in db
    assert 'Accessible.name: Tr.t("SQL query")' in db


def test_disks_window_imports_io_for_process():
    w = read(DISKS)
    assert "import Quickshell.Io" in w
    assert "Process {" in w
    assert "id: bigFinder" in w
    assert "StdioCollector {" in w


def test_disks_window_keeps_accessible_names():
    w = read(DISKS)
    assert 'Accessible.name: Tr.t("Operation progress")' in w
    assert "Accessible.role: Accessible.ProgressBar" in w
