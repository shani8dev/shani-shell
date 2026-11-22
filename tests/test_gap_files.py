"""Gaps closed in the Files surface: Create Link (symlink), the sort keys Type
and Date Created, and the UI actions that reach them (Select Items Matching,
breadcrumb dropdowns). The bridge is run for real; the QML is checked as text.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "bridge" / "files.py"


def run(home, *args):
    env = dict(
        os.environ,
        HOME=str(home),
        XDG_DATA_HOME=str(home / ".local/share"),
        XDG_CONFIG_HOME=str(home / ".config"),
    )
    r = subprocess.run(
        [sys.executable, str(TOOL), *map(str, args)],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    return json.loads(r.stdout)


def test_symlink_uses_argv_slots_and_keeps_weird_names(tmp_path):
    target = tmp_path / 'a "weird" target.txt'
    target.write_text("x")
    link = tmp_path / 'Link to "weird".txt'
    r = run(tmp_path, "symlink", target, link)
    assert r["path"] == str(link)
    assert link.is_symlink() and os.readlink(link) == str(target)
    assert link.read_text() == "x"  # the link resolves


def test_symlink_refuses_to_overwrite(tmp_path):
    target = tmp_path / "t.txt"
    target.write_text("x")
    link = tmp_path / "Link.txt"
    link.write_text("do not clobber me")
    r = run(tmp_path, "symlink", target, link)
    assert r["code"] == "EEXIST" and link.read_text() == "do not clobber me"


def test_sort_by_type_and_date_created(tmp_path):
    (tmp_path / "b.pdf").write_text("p")
    (tmp_path / "a.JPG").write_text("j")
    (tmp_path / "c folder").mkdir()
    by_type = run(tmp_path, "list", tmp_path, "--sort=type")["entries"]
    assert [e["name"] for e in by_type][:2] == [
        "c folder",
        "a.JPG",
    ]  # folders first, then ext
    by_time = run(tmp_path, "list", tmp_path, "--sort=btime")["entries"]
    assert all("btime" in e for e in by_time)
    assert by_time[0]["isDir"]  # folders first
    files = [e["btime"] for e in by_time if not e["isDir"]]
    assert files == sorted(files, reverse=True)  # newest first


def test_files_ui_reaches_the_new_commands():
    svc = (ROOT / "shani/Services/Files.qml").read_text(encoding="utf-8")
    panel = (ROOT / "shani/Modules/Files/FilesPanel.qml").read_text(encoding="utf-8")
    assert 'import "../Common/FileFilter.js" as FileFilter' in svc
    assert "function selectMatching(pattern)" in svc and "FileFilter.compile" in svc
    assert (
        "function symlink(target, linkpath, cb)" in svc
        and '["symlink", target, linkpath]' in svc
    )
    assert "function openMatch()" in panel and "win.applyMatch()" in panel
    assert "Select Items Matching" in panel and "Create Link" in panel
    assert "Qt.Key_M" in panel  # Ctrl+M
    # sort order includes Type and Date Created
    assert '"btime"' in panel and '"type"' in panel and '"mtime"' in panel
    # breadcrumb dropdowns: the arrow lists a crumb's siblings
    assert "function openCrumbMenu(path, point)" in panel and "crumbMenuItems" in panel
    assert "▾" in panel and "openCrumbMenu(modelData.path" in panel
