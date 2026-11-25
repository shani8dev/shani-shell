"""Named sessions: save/restore apps + documents (coresession/corebox idea).

Two layers, both checked here:

* static shape - the QML has to persist under Quickshell.statePath, read what is
  actually open from the shell's own services, and ask before a restore launches
  anything;
* the real rules - shani/Services/Sessions.js is plain JS, so the name checks,
  dedupe and caps are run in node (the way tests/test_whatsnew.py runs its rules)
  without a QuickShell runtime.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SERVICE = ROOT / "shani/Services/Sessions.qml"
LOGIC = ROOT / "shani/Services/Sessions.js"
PAGE = ROOT / "shani/Modules/Settings/SettingsStartup.qml"
SHELL = ROOT / "shani/shell.qml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def call(expr):
    prog = (
        LOGIC.read_text(encoding="utf-8").replace(".pragma library", "")
        + "\nprocess.stdout.write(JSON.stringify(%s));" % expr
    )
    got = subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True)
    return json.loads(got.stdout)


def clean(name):
    return call("cleanName(%s)" % json.dumps(name))


def capped(items, limit=None):
    return call("capped(%s, %s)" % (json.dumps(items), json.dumps(limit)))


# ---- static shape ----------------------------------------------------------


def test_service_and_logic_exist():
    assert SERVICE.exists() and LOGIC.exists()
    q = read(SERVICE)
    assert "pragma Singleton" in q
    assert 'import "Sessions.js" as Logic' in q
    assert "import Quickshell.Io" in q


def test_service_persists_in_quickshell_state():
    q = read(SERVICE)
    assert 'path: Quickshell.statePath("sessions.json")' in q
    assert "onLoaded:" in q and "Logic.normalise(JSON.parse(text()))" in q
    assert "store.setText(JSON.stringify(" in q


def test_service_exposes_the_required_api():
    q = read(SERVICE)
    for fn in [
        "function list(",
        "function save(",
        "function remove(",
        "function restore(",
        "function captureCurrent()",
        "function saveCurrent(",
    ]:
        assert fn in q, fn
    assert "function list() { return Logic.toList(root.sessions); }" in q
    assert "property var sessions: ({})" in q


def test_capture_reads_the_shell_not_process_cmdlines():
    q = read(SERVICE)
    assert "Object.values(Niri.windows)" in q
    assert "DesktopEntries.byId(w.app_id)" in q
    assert "Files.path" in q and "Files.splitPath" in q
    assert "TextDocs.docs" in q and "PdfViewer.file" in q
    assert "/proc" not in q and "cmdline" not in q


def test_restore_launches_apps_and_opens_paths():
    q = read(SERVICE)
    assert "Reopen.reopen(s.apps)" in q
    assert '[ -d "$1" ]' in q
    assert "Files.show(p)" in q and "TextDocs.open(p)" in q
    assert "PdfViewer.open(p)" in q and "Viewer.open(p)" in q


def test_settings_page_has_sessions_with_confirm():
    q = read(PAGE)
    assert 'Tr.t("Sessions")' in q
    assert "Sessions.list" in q and "Sessions.validName(" in q
    assert "Sessions.saveCurrent(sessionName.text)" in q
    assert 'page.ask("restore", modelData)' in q
    assert 'page.ask("remove", modelData)' in q
    assert "page.confirmName" in q and "page.answer(true)" in q
    assert "InfoBanner" in q and ("ListRow" in q or "SettingRow" in q) and "TextField" in q


def test_shell_instantiates_and_reports_sessions():
    q = read(SHELL)
    assert "Share, Automations, Reopen, Sessions, LockKeys" in q
    assert "function sessionSave(name: string)" in q
    assert "function sessionRestore(name: string)" in q
    assert "function sessionRemove(name: string)" in q
    assert "sessionsListed: Sessions.list" in q


# ---- name validation -------------------------------------------------------


def test_names_must_be_real_and_short():
    assert clean("  Work  ") == "Work"
    assert clean("") == ""
    assert clean("   ") == ""
    assert clean("a" * 60) == "a" * 60
    assert clean("a" * 61) == ""


def test_names_cannot_look_like_paths_or_control_the_object():
    for bad in [
        "one/two",
        "one\\two",
        "..",
        "a..b",
        "a\nb",
        "a\u0000b",
        "__proto__",
        "constructor",
        "toString",
    ]:
        assert clean(bad) == "", bad


# ---- dedupe and caps -------------------------------------------------------


def test_entries_are_trimmed_deduped_and_kept_in_order():
    assert capped([" a ", "a", "", "b", "a"]) == ["a", "b"]
    assert capped([]) == []
    assert capped("not a list") == []


def test_item_count_is_capped():
    assert len(capped([f"x{i}" for i in range(200)])) == 100


def test_saving_the_same_name_overwrites_instead_of_duplicating():
    first = call('put({}, "Work", ["a", "a", "b"], ["/home", "/home"], "2026-01-01")')
    second = call('put(%s, "Work", ["c"], ["/docs"], "2026-02-01")' % json.dumps(first))
    assert list(second) == ["Work"]
    assert second["Work"]["apps"] == ["c"]
    assert second["Work"]["paths"] == ["/docs"]
    assert second["Work"]["savedAt"] == "2026-02-01"


def test_invalid_names_are_refused_without_writing():
    assert call('put({}, "../nope", ["a"], [], "2026-01-01")') is None
    assert call('put({}, "", ["a"], [], "2026-01-01")') is None


def test_session_count_is_capped_and_the_oldest_goes():
    data = {}
    for i in range(30):
        data = call(
            "put(%s, %s, [], [], %s)"
            % (
                json.dumps(data),
                json.dumps(f"session {i}"),
                json.dumps(f"2026-01-{i + 1:02d}"),
            )
        )
    assert len(data) == 24
    assert "session 0" not in data and "session 5" not in data
    assert "session 29" in data and "session 6" in data


def test_loading_a_hand_edited_file_drops_bad_entries():
    raw = {
        "Good": {
            "apps": ["a", "a", 4],
            "paths": ["/a", "/a", ""],
            "savedAt": "2026-01-01",
        },
        "bad/name": {"apps": ["x"], "paths": [], "savedAt": "now"},
        "NoDate": {"apps": [], "paths": []},
        "broken": "not an object",
    }
    got = call("normalise(%s)" % json.dumps(raw))
    assert got == {
        "Good": {"apps": ["a", "4"], "paths": ["/a"], "savedAt": "2026-01-01"},
        "NoDate": {"apps": [], "paths": [], "savedAt": ""},
    }
    assert call("normalise(null)") == {}
    assert call("normalise([])") == {}


def test_list_is_newest_first_and_remove_forgets_one():
    data = call('put({}, "old", [], [], "2026-01-01")')
    data = call('put(%s, "new", [], [], "2026-02-01")' % json.dumps(data))
    assert [s["name"] for s in call("toList(%s)" % json.dumps(data))] == ["new", "old"]
    assert call('drop(%s, "old")' % json.dumps(data)) == {"new": data["new"]}
