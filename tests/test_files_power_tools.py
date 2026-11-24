"""Files power tools from the CuboCore research: batch-rename case transforms and
regex find/replace with a live preview, Save folder tree as text, search category
chips, and last-query suggestions backed by the one Settings store.

The QML bits are asserted statically (the shell has no unit-test harness); the
bridge's tree rendering is pure Python and tested directly and over argv.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "files.py"
sys.path.insert(0, str(ROOT / "bridge"))
import files  # noqa: E402

PANEL = "shani/Modules/Files/FilesPanel.qml"
SERVICE = "shani/Services/Files.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def bridge(*args):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *map(str, args)],
        capture_output=True,
        text=True,
    )
    return json.loads(r.stdout)


# ---- batch rename: transforms are shared by preview and commit -----------------


def test_batch_case_and_regex_are_wired_into_preview_and_commit():
    q = read(PANEL)
    assert "function batchTransform(text)" in q
    assert 'win.batchCase === "upper"' in q and "out.toUpperCase()" in q
    assert 'win.batchCase === "lower"' in q and "out.toLowerCase()" in q
    assert 'win.batchCase === "title"' in q
    assert 'Tr.t("UPPER")' in q and 'Tr.t("lower")' in q
    assert 'Tr.t("Capitalize Each Word")' in q
    assert 'new RegExp(win.batchFind, "g")' in q
    assert "out.split(win.batchFind).join(win.batchReplace)" in q
    assert "readonly property bool batchRegexInvalid" in q
    # the preview still runs on every keystroke, and the commit gets the same text
    assert "model: win.batchPreview(batchField.text)" in q
    assert "Files.batchRename(win.batchTransform(pattern), win.batchPaths)" in q
    assert "function commitBatchRename(pattern)" in q


def test_batch_dialog_resets_transforms_between_uses():
    q = read(PANEL)
    for line in (
        'win.batchCase = "";',
        'win.batchFind = "";',
        'win.batchReplace = "";',
        "win.batchRegex = false;",
    ):
        assert line in q
    assert q.index("function beginBatchRename") < q.index("function commitBatchRename")


# ---- Save folder tree as text --------------------------------------------------


def test_tree_command_renders_ascii_tree_with_counts(tmp_path):
    root = tmp_path / "root"
    (root / "dir2").mkdir(parents=True)
    (root / "dir1").mkdir()
    (root / "dir2" / "z.txt").write_text("z")
    (root / "dir1" / "y.txt").write_text("y")
    (root / "b.txt").write_text("b")
    (root / "a.txt").write_text("a")
    r = files.tree_lines(str(root))
    assert r["lines"][0] == str(root.resolve())
    assert r["lines"][1:-2] == [
        "├── dir1",
        "│   └── y.txt",
        "├── dir2",
        "│   └── z.txt",
        "├── a.txt",
        "└── b.txt",
    ]
    assert r["text"].endswith("2 folders, 4 files\n")
    assert (r["folders"], r["files"], r["truncated"]) == (2, 4, False)


def test_tree_dedupes_symlink_loops_and_caps_depth_and_entries(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    chain = root / "one"
    chain.mkdir()
    (chain / "two").mkdir()
    (chain / "two" / "three").mkdir()
    try:
        os.symlink(str(root), str(root / "back"))
    except (OSError, NotImplementedError):
        pass  # some filesystems refuse symlinks
    r = files.tree_lines(str(root))
    assert any("[loop]" in line for line in r["lines"])
    assert sum("[loop]" in line for line in r["lines"]) == 1

    shallow = files.tree_lines(str(root), max_depth=2)
    assert shallow["truncated"] is True
    assert not any("three" in line for line in shallow["lines"])

    for i in range(12):
        (root / ("f%02d.txt" % i)).write_text("x")
    capped = files.tree_lines(str(root), max_entries=5)
    assert capped["truncated"] is True
    assert capped["files"] + capped["folders"] == 5
    assert "… (truncated)" in capped["text"]


def test_save_tree_writes_file_and_reports_bad_destination(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "a.txt").write_text("x")
    out = tmp_path / "tree.txt"
    r = files.save_tree(str(root), str(out))
    assert r["saved"] == str(out.resolve())
    assert out.read_text(encoding="utf-8").endswith("a.txt\n\n0 folders, 1 file\n")
    assert "error" in files.save_tree(str(root), str(tmp_path / "missing" / "x.txt"))
    assert "error" in files.save_tree(str(root), str(tmp_path))
    assert "error" in files.save_tree(str(root), "")


def test_tree_accepts_subcommand_and_flag_forms_over_argv(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "note.txt").write_text("x")
    one, two, three = (tmp_path / n for n in ("one.txt", "two.txt", "three.txt"))
    assert bridge("tree", str(root), "--out", str(one))["saved"] == str(one.resolve())
    assert bridge("--tree", str(root), "--out", str(two))["saved"] == str(two.resolve())
    assert bridge("tree", str(root), "--out=" + str(three))["saved"] == str(
        three.resolve()
    )
    assert one.read_text() == two.read_text() == three.read_text()
    assert "error" in bridge("tree", str(root))


def test_tree_action_uses_a_save_picker_and_a_process_not_a_shell():
    q = read(PANEL)
    s = read(SERVICE)
    assert "import QtQuick.Dialogs" in q
    assert "fileMode: FileDialog.SaveFile" in q
    assert 'Tr.t("Save folder tree as text…")' in q
    assert "Files.saveTree(win.treeSaveDir, path)" in q
    assert "onAccepted:" in q
    assert '["python3", root.tool, "tree", dir, "--out", out]' in s
    assert "id: treeProc" in s and "StdioCollector" in s
    assert 'root.note = Tr.t("Folder tree saved: %1"' in s


# ---- search category chips -----------------------------------------------------


def test_chips_feed_backend_filters_and_a_folders_only_predicate():
    q = read(PANEL)
    s = read(SERVICE)
    for cid in ("all", "folders", "images", "media", "documents", "text"):
        assert '{ id: "%s"' % cid in q
    assert "filters: Files.activeFilters" in q
    assert "function visibleFrom(model)" in q
    assert "model: win.visibleEntries" in q
    assert "model: win.splitVisibleEntries" in q
    assert "Files.setSearchCategory(cat.id, cat.filters, cat.foldersOnly)" in q
    assert "function setSearchCategory(id, filters, foldersOnly)" in s
    assert "property bool foldersOnly" in s
    # deep search and type-to-search survive: neither was replaced, only narrowed
    assert "onTriggered: win.deepWords" not in q  # settled in the timer body now
    assert "Files.rememberSearch(words)" in q
    assert "win.typed += event.text.toLowerCase()" in q
    assert "Files.searchPath(win.deepWords)" in q


# ---- search history ------------------------------------------------------------


def test_history_is_deduped_capped_and_persisted_in_one_store():
    s = read(SERVICE)
    assert "filesSearchHistory" in s
    assert "function rememberSearch(words)" in s
    assert "x.toLowerCase() !== q.toLowerCase()" in s
    assert ".slice(0, root.searchHistoryMax)" in s
    assert "readonly property int searchHistoryMax: 8" in s
    assert "function clearSearchHistory()" in s
    assert "Settings.data.filesSearchHistory = []" in s
    assert "q.length < 2" in s
    # no second store was introduced
    assert s.count("filesSearchHistory") == 3


def test_history_shows_as_suggestions_with_a_clear_action():
    q = read(PANEL)
    assert "id: searchHistoryBox" in q
    assert "searchBox.activeFocus" in q
    assert "model: Files.searchHistory.slice(0, Files.searchHistoryMax)" in q
    assert 'Tr.t("Clear search history")' in q
    assert "Files.clearSearchHistory()" in q
    assert "searchBox.text = modelData" in q
