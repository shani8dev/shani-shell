"""bridge/files.py search: by name, and by what a file says (rg, else grep),
within the folder searched - a match outside it is not listed, a hidden folder
is skipped unless hidden files are shown, a name match is not listed twice."""
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "files.py"


def run(path):
    return json.loads(subprocess.run([sys.executable, str(BRIDGE), "list", path], capture_output=True, text=True).stdout)


def test_by_name_and_by_text(tmp_path):
    root = tmp_path / "docs"; (root / "sub").mkdir(parents=True); (root / ".hid").mkdir()
    (root / "sub" / "report.txt").write_text("the quarterly BUDGET is here")
    (root / ".hid" / "x.txt").write_text("budget")
    (root / "budget-notes.txt").write_text("budget twice: name and text")
    (tmp_path / "elsewhere.txt").write_text("budget")
    got = {e["name"]: e.get("inside", False) for e in run(f"search:budget\t{root}")["entries"]}
    assert got == {"budget-notes.txt": False, "report.txt": True}


def test_short_words_are_names_only(tmp_path):
    (tmp_path / "a.txt").write_text("ab ab ab")
    assert run(f"search:ab\t{tmp_path}")["entries"] == []
