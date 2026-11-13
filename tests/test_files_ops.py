"""bridge/files.py: what the file manager does to files, run for real in a
temporary home - copy/cut/paste never over anything, the trash and putting things
back, undo as the moves made backwards, search through folders, Properties,
batch rename and bookmarks."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parent.parent / "bridge" / "files.py"


@pytest.fixture
def home(tmp_path, monkeypatch):
    h = tmp_path / "home"
    (h / ".local" / "share").mkdir(parents=True)
    (h / ".config").mkdir()
    return h


def run(home, *args):
    env = dict(os.environ, HOME=str(home), XDG_DATA_HOME=str(home / ".local" / "share"),
               XDG_CONFIG_HOME=str(home / ".config"))
    r = subprocess.run([sys.executable, str(TOOL), *map(str, args)], capture_output=True, text=True, env=env, timeout=60)
    return json.loads(r.stdout)


def test_paste_copies_and_never_writes_over(home):
    (home / "a").mkdir(); (home / "b").mkdir()
    (home / "a" / "note.txt").write_text("one")
    (home / "b" / "note.txt").write_text("already here")
    r = run(home, "paste", home / "b", "copy", home / "a" / "note.txt")
    assert r["pairs"] == [[str(home / "a" / "note.txt"), str(home / "b" / "note (2).txt")]]
    assert (home / "b" / "note.txt").read_text() == "already here"
    assert (home / "b" / "note (2).txt").read_text() == "one" and (home / "a" / "note.txt").exists()


def test_cut_moves_and_undo_moves_back(home):
    (home / "a").mkdir(); (home / "b").mkdir()
    (home / "a" / "photo.jpg").write_text("x")
    r = run(home, "paste", home / "b", "move", home / "a" / "photo.jpg")
    assert not (home / "a" / "photo.jpg").exists() and (home / "b" / "photo.jpg").exists()
    back = [[to, frm] for frm, to in r["pairs"]]
    u = run(home, "move-pairs", json.dumps(back))
    assert (home / "a" / "photo.jpg").exists() and not u.get("error")


def test_undo_never_writes_over_something_new(home):
    (home / "x.txt").write_text("new one")
    (home / "y.txt").write_text("moved")
    u = run(home, "move-pairs", json.dumps([[str(home / "y.txt"), str(home / "x.txt")]]))
    assert u["error"] and (home / "x.txt").read_text() == "new one"


def test_a_folder_cannot_go_inside_itself(home):
    (home / "f" / "sub").mkdir(parents=True)
    r = run(home, "paste", home / "f" / "sub", "copy", home / "f")
    assert r["pairs"] == [] and "inside itself" in r["error"]


def test_trash_and_put_back(home):
    (home / "docs").mkdir()
    (home / "docs" / "report.pdf").write_text("r")
    t = run(home, "trash", home / "docs" / "report.pdf")
    assert t["trashed"] == 1 and not (home / "docs" / "report.pdf").exists()
    items = run(home, "trash-list")["items"]
    assert items[0]["original"] == str(home / "docs" / "report.pdf")
    # something new took its name meanwhile: it comes back beside it
    (home / "docs" / "report.pdf").write_text("new")
    r = run(home, "restore", items[0]["name"])
    assert r["pairs"][0][1] == str(home / "docs" / "report (2).pdf")
    assert (home / "docs" / "report.pdf").read_text() == "new" and run(home, "trash-list")["items"] == []


def test_empty_trash(home):
    for n in ("a.txt", "b.txt"):
        (home / n).write_text(n)
        run(home, "trash", home / n)
    assert len(run(home, "trash-list")["items"]) == 2
    assert run(home, "empty-trash")["removed"] == 2 and run(home, "trash-list")["items"] == []


def test_search_goes_through_folders_and_skips_hidden(home):
    (home / "Work" / "2026" / "March").mkdir(parents=True)
    (home / "Work" / "2026" / "March" / "electricity bill.pdf").write_text("x")
    (home / ".cache").mkdir()
    (home / ".cache" / "electricity bill.pdf").write_text("x")
    found = run(home, "search", home, "bill electricity")["entries"]
    assert [e["path"] for e in found] == [str(home / "Work" / "2026" / "March" / "electricity bill.pdf")]


def test_properties_count_through_folders(home):
    (home / "p" / "q").mkdir(parents=True)
    (home / "p" / "a.bin").write_bytes(b"x" * 1000)
    (home / "p" / "q" / "b.bin").write_bytes(b"x" * 500)
    r = run(home, "props", home / "p")
    assert r["size"] == 1500 and r["files"] == 2 and r["dirs"] == 2 and r["mode"].startswith("d") and r["type"] == "folder"


def test_batch_rename_keeps_extensions_and_order(home):
    for n in ("IMG_9.jpg", "IMG_10.png", "IMG_11.jpg"):
        (home / n).write_text(n)
    r = run(home, "batch-rename", "Holiday #", home / "IMG_9.jpg", home / "IMG_10.png", home / "IMG_11.jpg")
    assert sorted(p.name for p in home.iterdir() if not p.name.startswith(".")) == ["Holiday 1.jpg", "Holiday 2.png", "Holiday 3.jpg"]
    assert (home / "Holiday 2.png").read_text() == "IMG_10.png" and len(r["pairs"]) == 3


def test_batch_rename_onto_each_others_names_works(home):
    # "#" numbering that lands on a name another of them has now: through temporary names
    (home / "2.txt").write_text("was two"); (home / "1.txt").write_text("was one")
    run(home, "batch-rename", "#", home / "2.txt", home / "1.txt")
    assert (home / "1.txt").read_text() == "was two" and (home / "2.txt").read_text() == "was one"


def test_batch_rename_refuses_to_write_over_another_file(home):
    (home / "a.txt").write_text("a"); (home / "Note 1.txt").write_text("keep")
    r = run(home, "batch-rename", "Note #", home / "a.txt")
    assert r["error"] and (home / "Note 1.txt").read_text() == "keep" and (home / "a.txt").exists()


def test_bookmarks_in_places(home):
    (home / "Projects").mkdir()
    run(home, "bookmark-add", home / "Projects")
    assert any(p.get("bookmark") and p["path"] == str(home / "Projects") for p in run(home, "places")["places"])
    assert (home / ".config" / "gtk-3.0" / "bookmarks").read_text().startswith("file://")
    run(home, "bookmark-remove", home / "Projects")
    assert not any(p.get("bookmark") for p in run(home, "places")["places"])
