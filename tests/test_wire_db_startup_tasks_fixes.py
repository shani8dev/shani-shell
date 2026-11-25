"""Static checks for the Files -> Database, Tasks -> Scheduled wiring."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text()


FILES = read("shani/Modules/Files/FilesPanel.qml")
TASKS = read("shani/Modules/Tasks/TasksWindow.qml")
DB = read("shani/Modules/DatabaseBrowser.qml")
START = read("shani/Modules/StartupManager.qml")
SCHED = read("shani/Modules/ScheduledTasksWindow.qml")
SHELL = read("shani/shell.qml")


def test_files_offers_database_browser_for_sqlite_files():
    assert 'Tr.t("Open in Database Browser")' in FILES
    assert r"/\.(db|sqlite|sqlite3)$/i.test(e.path)" in FILES
    assert "Quickshell.clipboardText = e.path" in FILES
    assert "Files.hide(); Ui.closeAll(); Ui.databaseBrowser = true" in FILES


def test_tasks_header_opens_scheduled_through_the_shells_ui_path():
    assert 'text: Tr.t("Scheduled tasks")' in TASKS
    assert "Ui.closeAll(); Ui.scheduled = true;" in TASKS
    # the button mirrors the shell's own IPC handler, not a second open path
    assert "function scheduledOpen() { Ui.closeAll(); Ui.scheduled = true; }" in SHELL


def test_database_browser_prefills_its_path_from_the_clipboard():
    assert 'Quickshell.clipboardText || ""' in DB
    assert r"/\.(db|sqlite|sqlite3)$/i.test(seed)" in DB
    assert "win.dbPath = seed" in DB
    assert 'win.dbPath.trim() === ""' in DB  # never overwrite a typed path
    assert "win.listTables();" in DB


def test_database_browser_exposes_copy_query():
    assert 'text: Tr.t("Copy query")' in DB
    assert "Quickshell.clipboardText = win.sql" in DB
    assert 'Tr.t("Copy the SQL query to the clipboard")' in DB
    assert 'enabled: win.sql.trim() !== ""' in DB


def test_startup_manager_find_app_hands_off_to_the_launcher():
    assert 'text: Tr.t("Find app")' in START
    assert "onClicked: win.findApp()" in START
    assert "function findApp()" in START
    assert "Quickshell.clipboardText = q" in START
    assert 'Ui.toggleLauncher("app:" + q)' in START
    assert "Ui.startupManager = false" in START


def test_scheduled_tasks_adds_rules_from_open_tasks_without_duplicates():
    assert "Tasks.open.filter(t => t.due > 0)" in SCHED
    assert 'text: Tr.t("Add from Tasks")' in SCHED
    assert "Tasks.refresh()" in SCHED
    assert "function addFromTask(t)" in SCHED
    assert "Automations.rules.some(r => r.uid === t.uid)" in SCHED
    assert 'win.showNote(Tr.t("That task already has a rule"))' in SCHED
    assert 'when: "time", is: win.taskClock(t)' in SCHED
    assert '"notify-send " + win.shellQuote(t.summary' in SCHED
    assert r"""replace(/'/g, "'\\''")""" in SCHED
    assert "Settings.save()" in SCHED
