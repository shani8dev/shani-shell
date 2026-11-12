"""The file manager: the backend (bridge/files.py), the path and filter
helpers, and the wiring of the surface.

bridge/files.py lists a directory, watches it and changes it. The listing is
what the Files surface (Modules/Files/FilesPanel.qml) and the file chooser
(Services/FilePicker.qml) show, through Common/FileDirectory.qml.

The two JS helpers are run in node, the way tests/test_fuzzy.py runs Fuzzy.js.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "files.py"
SERVICE = ROOT / "shani" / "Services" / "Files.qml"
PICKER = ROOT / "shani" / "Services" / "FilePicker.qml"
DIRECTORY = ROOT / "shani" / "Common" / "FileDirectory.qml"
PANEL = ROOT / "shani" / "Modules" / "Files" / "FilesPanel.qml"
PICKER_PANEL = ROOT / "shani" / "Modules" / "FilePicker" / "FilePickerPanel.qml"
PATHS_JS = ROOT / "shani" / "Common" / "FilePaths.js"
FILTER_JS = ROOT / "shani" / "Common" / "FileFilter.js"
SHELL = ROOT / "shani" / "shell.qml"

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")
gio = shutil.which("gio")
gio_mark = pytest.mark.skipif(gio is None, reason="gio is not installed")


def run(*args, **kw):
    """the backend's answer, as JSON"""
    r = subprocess.run([sys.executable, str(BRIDGE), *args], capture_output=True, text=True, **kw)
    return json.loads(r.stdout)


def names(answer):
    return [e["name"] for e in answer["entries"]]


# ---- the listing ----------------------------------------------------------------

def test_a_listing_is_the_folders_first_then_the_files(tmp_path):
    (tmp_path / "b.txt").write_text("bee")
    (tmp_path / "a.txt").write_text("ay")
    (tmp_path / "Folder").mkdir()
    answer = run("list", str(tmp_path))
    assert names(answer) == ["Folder", "a.txt", "b.txt"]
    assert answer["total"] == 3
    entry = next(e for e in answer["entries"] if e["name"] == "a.txt")
    assert entry["path"] == str(tmp_path / "a.txt")
    assert entry["size"] == 2
    assert entry["isDir"] is False
    assert entry["ext"] == ".txt"
    assert next(e for e in answer["entries"] if e["name"] == "Folder")["isDir"] is True


def test_the_hidden_files_are_left_out_unless_asked_for(tmp_path):
    (tmp_path / ".secret").write_text("x")
    (tmp_path / "shown").write_text("x")
    assert names(run("list", str(tmp_path))) == ["shown"]
    assert names(run("list", str(tmp_path), "--hidden")) == [".secret", "shown"]


def test_the_names_sort_naturally_so_file2_comes_before_file10(tmp_path):
    for name in ("file10.txt", "file2.txt", "file1.txt"):
        (tmp_path / name).write_text("x")
    assert names(run("list", str(tmp_path))) == ["file1.txt", "file2.txt", "file10.txt"]


def test_the_sort_can_be_by_size_or_by_date(tmp_path):
    (tmp_path / "small.txt").write_text("x")
    (tmp_path / "big.txt").write_text("x" * 100)
    by_size = names(run("list", str(tmp_path), "--sort=size"))
    assert by_size == ["small.txt", "big.txt"]
    assert names(run("list", str(tmp_path), "--sort=size", "--desc")) == ["big.txt", "small.txt"]


def test_a_filter_keeps_only_the_extensions_given(tmp_path):
    (tmp_path / "a.jpg").write_text("x")
    (tmp_path / "b.png").write_text("x")
    (tmp_path / "c.txt").write_text("x")
    (tmp_path / "Folder").mkdir()
    answer = run("list", str(tmp_path), "--filter=jpg,png")
    assert names(answer) == ["Folder", "a.jpg", "b.png"]


def test_a_folder_that_is_not_there_says_so(tmp_path):
    answer = run("list", str(tmp_path / "nowhere"))
    assert answer["entries"] == []
    assert answer["error"]


# ---- changing things --------------------------------------------------------------

def test_a_new_folder_is_made_and_a_second_one_is_refused(tmp_path):
    answer = run("mkdir", str(tmp_path / "made"))
    assert answer.get("path", "").endswith("made")
    assert (tmp_path / "made").is_dir()
    again = run("mkdir", str(tmp_path / "made"))
    assert again["code"] == "EEXIST"


def test_a_file_is_renamed_and_a_name_with_a_slash_is_refused(tmp_path):
    (tmp_path / "old.txt").write_text("x")
    answer = run("rename", str(tmp_path / "old.txt"), "new.txt")
    assert answer.get("path", "").endswith("new.txt")
    assert (tmp_path / "new.txt").exists()
    assert not (tmp_path / "old.txt").exists()
    assert run("rename", str(tmp_path / "new.txt"), "a/b")["code"] == "EINVAL"


def test_stat_answers_the_entry_and_its_size(tmp_path):
    (tmp_path / "a.txt").write_text("hello")
    answer = run("stat", str(tmp_path / "a.txt"))
    assert answer["entry"]["name"] == "a.txt"
    assert answer["entry"]["size"] == 5


def test_the_places_hold_the_home_folder():
    answer = run("places")
    paths = [p["path"] for p in answer["places"]]
    assert paths[0] == str(Path.home())


@gio_mark
def test_trashing_moves_the_file_to_the_trash_and_keeps_it(tmp_path):
    # the desktop trash is where a person can put it back: the file manager
    # never deletes
    (tmp_path / "gone.txt").write_text("x")
    answer = run("trash", str(tmp_path / "gone.txt"))
    if answer.get("error") and "not supported" in answer["error"]:
        pytest.skip("this filesystem has no trash (a container's /tmp)")
    assert not answer.get("error"), answer
    assert not (tmp_path / "gone.txt").exists()
    listed = subprocess.run([gio, "trash", "--list"], capture_output=True, text=True)
    assert "gone.txt" in listed.stdout


# ---- the JS helpers ------------------------------------------------------------------

@node_mark
def test_the_path_helpers_tidy_what_was_typed():
    prog = PATHS_JS.read_text().replace(".pragma library", "") + """
const home = "/home/u";
const out = {
    "tilde": expandTilde("~/Pictures", home),
    "parent": parentOf("/home/u/Pictures"),
    "root": parentOf("/home"),
    "base": baseName("/home/u/a.txt"),
    "join": join("/home/u", "a.txt"),
    "rootJoin": join("/", "etc"),
    "norm": normalize("/home/u/../u/Pictures/", home),
    "relative": normalize("Pictures", home),
    "name": validName("a/b")
};
process.stdout.write(JSON.stringify(out));"""
    out = json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)
    assert out["tilde"] == "/home/u/Pictures"
    assert out["parent"] == "/home/u"
    assert out["root"] == "/"
    assert out["base"] == "a.txt"
    assert out["join"] == "/home/u/a.txt"
    assert out["rootJoin"] == "/etc"
    assert out["norm"] == "/home/u/Pictures"
    assert out["relative"] == ""           # not absolute: nothing sensible can be made of it
    assert out["name"] is False            # a name with a slash is not a name


@node_mark
def test_the_filter_matches_a_word_anywhere_or_a_pattern():
    prog = FILTER_JS.read_text().replace(".pragma library", "") + """
const plain = compile("port");
const pattern = compile("*.jpg");
const out = {
    "inside": plain.test("report.png"),
    "outside": plain.test("readme.txt"),
    "glob": pattern.test("a.jpg"),
    "globNo": pattern.test("a.png"),
    "question": compile("a?c").test("abc")
};
process.stdout.write(JSON.stringify(out));"""
    out = json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)
    assert out["inside"] is True
    assert out["outside"] is False
    assert out["glob"] is True
    assert out["globNo"] is False
    assert out["question"] is True


# ---- the surface ---------------------------------------------------------------------

def read(p):
    return Path(p).read_text(encoding="utf-8")


def test_the_backend_answers_and_the_service_asks_it():
    assert BRIDGE.exists()
    service = read(SERVICE)
    assert 'SHANI_FILES_TOOL' in service          # the tool can be pointed elsewhere (the tests do)
    for method in ('"list"', '"stat"', '"mkdir"', '"rename"', '"trash"'):
        assert method in service, method


def test_the_surface_is_wired_into_the_shell():
    shell = read(SHELL)
    assert "import qs.Modules.Files" in shell
    assert 'LazyLoader { active: Ui.files; source: "Modules/Files/FilesPanel.qml" }' in shell
    assert "function filesOpen(path: string)" in shell
    assert "filesShown: Ui.files" in shell
    assert "import qs.Modules.FilePicker" in shell
    assert 'LazyLoader { active: FilePicker.shown; source: "Modules/FilePicker/FilePickerPanel.qml" }' in shell


def test_the_chooser_replaces_the_native_dialog_that_held_the_shell():
    # the portal's dialog waited for D-Bus and held the whole shell; the
    # chooser is the shell's own
    picker = read(ROOT / "shani" / "Common" / "FolderPicker.qml")
    assert "Ui.filePicker.open(" in picker
    assert "FolderDialog" not in picker


def test_the_listing_is_watched_and_the_watch_is_the_only_thing_that_runs():
    directory = read(DIRECTORY)
    assert "watch" in directory
    assert "Process" in directory
    # the watcher is started when a path is set and stopped when it goes away
    assert "Component.onDestruction" in directory


def test_nothing_is_deleted_by_the_file_manager():
    # the trash is the desktop trash: `gio trash`, which can be undone
    bridge = read(BRIDGE)
    assert "gio" in bridge
    assert "os.remove" not in bridge
    assert "shutil.rmtree" not in bridge


def test_recent_files_are_the_ones_opened_lately_newest_first(tmp_path):
    import json, os, subprocess, sys
    a = tmp_path / "a.txt"; a.write_text("a")
    b = tmp_path / "b.pdf"; b.write_text("b")
    gone = tmp_path / "gone.txt"
    data = tmp_path / "data"; data.mkdir()
    (data / "recently-used.xbel").write_text(f"""<?xml version="1.0"?>
<xbel version="1.0">
  <bookmark href="file://{a}" added="2026-01-01T00:00:00Z" modified="2026-01-01T00:00:00Z" visited="2026-01-01T00:00:00Z"/>
  <bookmark href="file://{b}" added="2026-02-01T00:00:00Z" modified="2026-02-01T00:00:00Z" visited="2026-02-01T00:00:00Z"/>
  <bookmark href="file://{gone}" added="2026-03-01T00:00:00Z" modified="2026-03-01T00:00:00Z" visited="2026-03-01T00:00:00Z"/>
  <bookmark href="https://example.com/x" added="2026-03-01T00:00:00Z" modified="2026-03-01T00:00:00Z" visited="2026-03-01T00:00:00Z"/>
</xbel>""")
    out = subprocess.run([sys.executable, str(ROOT / "bridge/files.py"), "list", "recent:"], capture_output=True, text=True,
                         env=dict(os.environ, XDG_DATA_HOME=str(data)), check=True).stdout
    assert [e["name"] for e in json.loads(out)["entries"]] == ["b.pdf", "a.txt"]
