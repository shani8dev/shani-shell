"""Static guards and live checks for the two new windows.

DatabaseBrowser and StartupManager use one fixed inline Python script each;
their inputs travel as argv. The unit tests pull that very script out of the
QML and run it, so a guard failing means the shipped code broke, not a copy.
"""

import json
import os
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_QML = ROOT / "shani" / "Modules" / "DatabaseBrowser.qml"
# the Startup manager window was merged into Settings > Default apps > Startup
# apps, which runs bridge/autostart.py (the same validated script)
START_QML = ROOT / "shani" / "Modules" / "Settings" / "SettingsStartup.qml"
START_BRIDGE = ROOT / "bridge" / "autostart.py"
db_text = DB_QML.read_text()
start_text = START_QML.read_text()


def inline_script(path, prop="pyCode"):
    m = re.search(r"property string " + prop + r": `(.*?)`", path.read_text(), re.S)
    assert m, prop + " is missing"
    return m.group(1)


DB_SCRIPT = inline_script(DB_QML)
START_SCRIPT = START_BRIDGE.read_text()


def run_startup(user, mode, arg="", env=None):
    """The bridge with its user folder at `user` (XDG_CONFIG_HOME/autostart)."""
    from pathlib import Path as _P
    assert _P(user).name == "autostart"
    e = os.environ.copy()
    e.update(env or {})
    e["XDG_CONFIG_HOME"] = str(_P(user).parent)
    p = subprocess.run([sys.executable, str(START_BRIDGE), mode, arg], capture_output=True, text=True, env=e)
    assert p.returncode == 0, p.stderr
    return json.loads(p.stdout.strip().splitlines()[-1])


def run_code(script, *args, env=None):
    e = os.environ.copy()
    if env:
        e.update(env)
    p = subprocess.run(
        [sys.executable, "-c", script, *args], capture_output=True, text=True, env=e
    )
    assert p.returncode == 0, p.stderr
    return json.loads(p.stdout.strip().splitlines()[-1])


def make_db(path, rows=0, with_blob=False):
    c = sqlite3.connect(path)
    c.execute("CREATE TABLE plain (id INTEGER, text TEXT)")
    for i in range(rows):
        c.execute("INSERT INTO plain VALUES (?, ?)", (i, "row %d" % i))
    if with_blob:
        c.execute("INSERT INTO plain VALUES (?, ?)", (999, sqlite3.Binary(b"\x00\xff")))
    c.commit()
    c.close()


# ---- DatabaseBrowser --------------------------------------------------------


def test_db_script_is_fixed_and_argv_driven(tmp_path):
    """Fix 1: path and SQL are argv, never shell text."""
    assert 'command = ["python3", "-c", win.pyCode' in db_text
    assert "win.pyCode, win.dbPath.trim(), s" in db_text
    assert 'command: ["sh"' not in db_text
    db = tmp_path / "my db.sqlite"
    make_db(db, 2)
    weird = tmp_path / "sentinel"
    r = run_code(DB_SCRIPT, str(db), 'SELECT * FROM "plain"')
    assert r["columns"] == ["id", "text"] and len(r["rows"]) == 2
    injected = (
        "SELECT 'a;b; $(touch " + str(weird) + ") `touch " + str(weird) + '`; "x"\''
    )
    r = run_code(DB_SCRIPT, str(db), injected)
    assert r["rows"] == [
        ["a;b; $(touch " + str(weird) + ") `touch " + str(weird) + '`; "x"']
    ]
    assert not weird.exists(), "SQL was run by a shell"


def test_db_is_read_only_and_reports_bad_sql(tmp_path):
    """Fix 2: browsing cannot write, and errors surface as JSON."""
    db = tmp_path / "ro.db"
    make_db(db, 1)
    assert "?mode=ro" in DB_SCRIPT and "uri=True" in DB_SCRIPT
    r = run_code(DB_SCRIPT, str(db), "UPDATE plain SET text = 'hacked'")
    assert "error" in r
    assert (
        "hacked"
        not in sqlite3.connect(db).execute("SELECT text FROM plain").fetchone()[0]
    )
    assert "error" in run_code(DB_SCRIPT, str(db), "SELECT nope FROM plain")


def test_db_caps_rows_and_handles_blob_values(tmp_path):
    """Fix 3: 200-row cap with a truncation flag; BLOBs do not crash JSON."""
    db = tmp_path / "big.db"
    make_db(db, 250, with_blob=True)
    r = run_code(DB_SCRIPT, str(db), "SELECT * FROM plain")
    assert len(r["rows"]) == 200 and r["truncated"] is True and r["count"] == 200
    r = run_code(DB_SCRIPT, str(db), "SELECT text FROM plain WHERE id = 999")
    assert r["rows"], "BLOB row made the query fail"


def test_db_table_list_and_safe_identifier_quoting(tmp_path):
    """Fix 4: sqlite_master list, with DB-supplied names quoted as identifiers."""
    assert "win.listSql" in db_text and "sqlite_master" in db_text
    assert 'replace(/"/g, \'""\')' in db_text and "win.openTable(modelData)" in db_text
    db = tmp_path / "tables.db"
    c = sqlite3.connect(db)
    c.execute('CREATE TABLE "odd "" name" (v INTEGER)')
    c.execute("INSERT INTO 'odd \" name' VALUES (7)")
    c.commit()
    c.close()
    list_sql = re.search(r'property string listSql: "(.*?)"', db_text).group(1)
    r = run_code(DB_SCRIPT, str(db), list_sql)
    names = [row[0] for row in r["rows"]]
    assert 'odd " name' in names
    quoted = '"' + 'odd " name'.replace('"', '""') + '"'
    r = run_code(DB_SCRIPT, str(db), "SELECT * FROM " + quoted)
    assert r["rows"] == [[7]]


def test_db_keyboard_and_accessible_names():
    """Fix 5: every control is named, Tab/Enter/Escape reach the right action."""
    for token in (
        'label: Tr.t("Database file")',
        'Accessible.name: Tr.t("SQL query")',
        'accessibleName: Tr.t("Reload tables")',
        'Accessible.name: Tr.t("Query results")',
        'Accessible.name: Tr.t("Run again: %1")',
        "onGone: Ui.databaseBrowser = false",
        "Qt.Key_Return",
        "Qt.ControlModifier",
        "KeyFocus { onActivated",
    ):
        assert token in db_text, token


def test_db_history_run_cancel_and_states():
    """Fix 6: guarded run, real cancel, capped history, and honest empty states."""
    assert "if (win.busy) return;" in db_text and "function cancelQuery()" in db_text
    assert (
        "queryProc.running = false" in db_text and 'Tr.t("Query cancelled")' in db_text
    )
    assert "h.slice(0, 20)" in db_text and "win.history.filter(x => x !== s)" in db_text
    for token in (
        "EmptyState",
        "BusyNote {",
        'win.error !== ""',
        "onExited:",
        'Tr.t("The query returned no rows")',
        'Tr.t("Nothing to show yet")',
    ):
        assert token in db_text, token


# ---- StartupManager ---------------------------------------------------------


def test_startup_script_is_fixed_and_argv_driven():
    """Fix 7: one fixed script (bridge/autostart.py); folder/action/details are argv (JSON)."""
    assert '"autostart.py")' in start_text and 'command: ["python3", page.tool, "list"]' in start_text
    assert "JSON.stringify({ file: e.file, on: on })" in start_text
    assert "sed -i" not in start_text and 'command: ["sh"' not in start_text
    assert 'SYSTEM = "/etc/xdg/autostart"' in START_SCRIPT


def test_startup_lists_user_entries_with_name_description_and_hidden(tmp_path):
    """Fix 8: list mode reads both folders, with name, comment and Hidden state."""
    user = tmp_path / "autostart"
    user.mkdir()
    (user / "zeta.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Zeta App\nComment=Does things\nExec=zeta\n"
    )
    (user / "alpha.desktop").write_text(
        "[Desktop Entry]\nName=Alpha\nHidden=true\nExec=alpha\n"
    )
    r = run_startup(str(user), "list", "")
    entries = {e["file"]: e for e in r["entries"]}
    assert entries["zeta.desktop"]["name"] == "Zeta App"
    assert entries["zeta.desktop"]["desc"] == "Does things"
    assert (
        entries["zeta.desktop"]["on"] is True
        and entries["zeta.desktop"]["mine"] is True
    )
    assert entries["alpha.desktop"]["on"] is False
    assert [e["file"] for e in r["entries"]].index("alpha.desktop") < [
        e["file"] for e in r["entries"]
    ].index("zeta.desktop")


def test_startup_toggle_writes_hidden_field(tmp_path):
    """Fix 9: disable adds Hidden=true, enable removes it; traversal is refused."""
    user = tmp_path / "autostart"
    user.mkdir()
    f = user / "app.desktop"
    f.write_text(
        "[Desktop Entry]\nName=App\nExec=app\nHidden=true\nX-GNOME-Autostart-enabled=false\n"
    )
    assert run_startup(str(user), "set", json.dumps({"file": "app.desktop", "on": True})
    )["ok"]
    body = f.read_text()
    assert (
        "Hidden=true" not in body
        and "X-GNOME-Autostart-enabled" not in body
        and "Exec=app" in body
    )
    assert run_startup(str(user), "set", json.dumps({"file": "app.desktop", "on": False})
    )["ok"]
    assert "Hidden=true" in f.read_text()
    assert "error" in run_startup(str(user),
        "set",
        json.dumps({"file": "../evil.desktop", "on": True}),
    )
    assert "error" in run_startup(str(user),
        "set",
        json.dumps({"file": "missing.desktop", "on": True}),
    )
    assert "shutil.copyfile(s, p)" in START_SCRIPT, "a system entry needs a user copy"


def test_startup_add_validates_app_id_and_desktop_path(tmp_path):
    """Fix 10: add copies a real desktop file, and rejects bad ids and paths."""
    user = tmp_path / "autostart"
    user.mkdir()
    share = tmp_path / "share"
    (share / "applications").mkdir(parents=True)
    (share / "applications" / "dev.test.App.desktop").write_text(
        "[Desktop Entry]\nName=Test App\nExec=test\n"
    )
    env = {"XDG_DATA_HOME": str(share)}
    r = run_startup(str(user), "add", json.dumps({"id": "dev.test.App"}), env=env
    )
    assert r["ok"] and "Name=Test App" in (user / "dev.test.App.desktop").read_text()
    assert "error" in run_startup(str(user), "add", json.dumps({"id": "bad id;touch x"}), env=env
    )
    assert "error" in run_startup(str(user),
        "add",
        json.dumps({"path": str(tmp_path / "nope.txt")}),
        env=env,
    )
    src = tmp_path / "custom.desktop"
    src.write_text("[Desktop Entry]\nName=Custom\nExec=custom\n")
    assert run_startup(str(user), "add", json.dumps({"path": str(src)}), env=env
    )["ok"]
    assert (user / "custom.desktop").exists()


def test_startup_remove_and_empty_error_states():
    """Fix 11: removal is confined to the user folder and asks twice; states are visible."""
    assert "def cmd_remove" in START_SCRIPT and "os.remove(p)" in START_SCRIPT
    assert "if not safe(arg" in START_SCRIPT
    for token in ('Tr.t("No startup apps")', "visible: page.startupError !== \"\"",
                  "accessibleRole: Accessible.AlertMessage", "ConfirmButton {",
                  "onConfirmed: page.remove(row.modelData)", "onExited: page.refresh()"):
        assert token in start_text, token


def test_startup_picker_names_keyboard_and_description():
    """Fix 12: apps found in place, any .desktop file picked (not typed), names and descriptions."""
    for token in ("function addFile()", "FilePicker.open(", 'filters: ["desktop"]',
                  'placeholder: Tr.t("Or find another app…")', "row.modelData.desc",
                  'Accessible.name: Tr.t("Remove %1 from startup")', "SwitchRow {"):
        assert token in start_text, token
    # keyboard reach comes from the shared controls, not a copy in this page
    for common in ("SwitchRow", "ListRow"):
        assert "KeyFocus" in (ROOT / "shani" / "Common" / (common + ".qml")).read_text()
    assert "keyboard and controller" in (ROOT / "shani" / "Common" / "Button.qml").read_text()