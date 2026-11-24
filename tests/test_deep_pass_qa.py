"""Second deep pass: QA regressions for the CuboCore-inspired features.

The QML surfaces cannot be instantiated in pytest here, so these tests either
run the very same QML functions in node with tiny stubs, exercise the Python
bridge directly, or pin a guard that must stay in the source. Every test in the
"Bugs" section FAILS on the code as it stands; each names the file and line it
catches. The "Guards" section documents fixes that are already in place so a
later edit cannot silently undo them.

This file is deliberately test-only: no QML or bridge source is changed here.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

NODE = shutil.which("node") or shutil.which("nodejs")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def source_of(src: str, name: str) -> str:
    """One `function name(...) { ... }` verbatim, braces matched."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", src)
    assert m, name
    start = m.start()
    i = m.end() - 1
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[start : j + 1]
    raise AssertionError(f"unterminated function {name}")


def node(prog: str) -> object:
    out = subprocess.run(
        [NODE, "-e", prog], capture_output=True, text=True, timeout=30, check=True
    )
    return json.loads(out.stdout.strip().splitlines()[-1])


# ---------------------------------------------------------------------------
# Bugs — each of these fails on the current source.
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_insert_datetime_works_with_one_cursor():
    """TextEditorPanel.qml:205-210 / :163 / :209-210.

    insertDateTime() delegates to insertAtCursors(), which returns immediately
    when multiCursor is false. multiCursor is `extraCursors.length > 0`, so in
    ordinary single-cursor editing the new "Insert date and time" button does
    nothing at all. Run the two real QML functions with one cursor: the text
    must change. Fix: let insertAtCursors handle the primary cursor on its own
    (`if (str === "") return false;`), or give insertDateTime a non-multi path.
    """
    src = read("shani/Modules/TextEditor/TextEditorPanel.qml")
    prog = """
var win = {};
var edit = { cursorPosition: 6, text: "abcdef", forceActiveFocus: function () {} };
var extraCursors = [];
var multiCursor = extraCursors.length > 0;
var loading = false;
var Qt = { formatDateTime: function (d, f) { return "2026-01-01 00:00"; } };
var TextDocs = { setText: function (t) { edit.text = t; } };
var repaint = { restart: function () {} };
%s
%s
win.insertDateTime = insertDateTime;
win.insertAtCursors = insertAtCursors;
win.insertDateTime();
console.log(JSON.stringify({ text: edit.text, cursor: edit.cursorPosition }));
""" % (
        source_of(src, "insertDateTime"),
        source_of(src, "insertAtCursors"),
    )
    got = node(prog)
    assert "2026-01-01" in got["text"], (
        "insertDateTime is a no-op with a single cursor (the normal case): " + repr(got)
    )
    assert got["cursor"] > 6


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_ctrl_shift_f2_reaches_batch_rename_with_one_selection():
    """FilesPanel.qml:234-238 before :245-249.

    The plain-F2 handler has no modifier guard, so Ctrl+Shift+F2 with exactly
    one file selected matches it first and opens the single-rename dialog; the
    batch-rename handler below is never reached. Evaluate both real conditions
    with a Ctrl+Shift+F2 event and one selected path. Fix: guard the F2 branch
    with `!control && !(event.modifiers & Qt.ShiftModifier)` or move the batch
    branch above it.
    """
    lines = [
        line.strip()
        for line in read("shani/Modules/Files/FilesPanel.qml").splitlines()
        if "Qt.Key_F2" in line and line.strip().startswith("if (")
    ]
    assert len(lines) == 2, lines
    # the plain-F2 branch is the one guarded with `!control`; the batch one
    # requires ControlModifier. Both now mention ShiftModifier (the fix).
    single = next(c for c in lines if "!control" in c)
    batch = next(c for c in lines if c is not single)
    cond = lambda line: re.match(r"if \((.*)\) \{", line).group(1)
    prog = """
var Qt = { Key_F2: 1, ShiftModifier: 2, ControlModifier: 4 };
var event = { key: Qt.Key_F2, modifiers: Qt.ShiftModifier | Qt.ControlModifier };
var control = true, alt = false;
var Files = { selected: ['/home/a.txt'] };
console.log(JSON.stringify({ single: !!(%s), batch: !!(%s) }));
""" % (
        cond(single),
        cond(batch),
    )
    got = node(prog)
    assert not got["single"], (
        "plain F2 branch swallows Ctrl+Shift+F2 before batch rename: " + repr(got)
    )
    assert got["batch"]


def test_batch_rename_pattern_cannot_escape_the_folder(tmp_path):
    """Bridge/files.py:1724-1735 + Services/Files.qml:1433-1436.

    batch_rename() joins the user-typed pattern straight onto the source
    folder. A pattern with `../` or an absolute path moves files out of that
    folder (verified: ../escaped # moves the file into the parent). The QML
    service does not call FilePaths.validName(), unlike renameEntry/makeFolder.
    Fix: reject names containing '/' or '\\\\', absolute names and '.' / '..'
    in files.py (and/or validate the pattern in Files.batchRename).
    """
    import files  # noqa: E402  (conftest puts bridge/ on sys.path)

    inner = tmp_path / "inner"
    inner.mkdir()
    source = inner / "a.txt"
    source.write_text("x", encoding="utf-8")

    result = files.batch_rename("../escaped #", [str(source)])
    assert result.get("error"), "batch_rename accepted a traversing pattern: " + repr(
        result
    )
    assert (inner / "a.txt").exists(), "the file was moved out of its folder"
    assert not (tmp_path / "escaped 1.txt").exists()


def test_batch_rename_service_validates_the_pattern():
    """Services/Files.qml:1433-1436.

    The single-file rename guards with FilePaths.validName(); the batch path
    must do the same, since the bridge trusts the pattern as a file name.
    """
    body = source_of(read("shani/Services/Files.qml"), "batchRename")
    assert "FilePaths.validName" in body or "validName(" in body, (
        "Files.batchRename forwards an unvalidated pattern to the bridge"
    )


def test_split_selection_does_not_mutate_the_property_array():
    """Services/Files.qml:514-533.

    `const s = root._splitPaths` aliases the property's array; splice/push on
    it mutates the value in place and assigning the same object back does not
    emit a change notification, so delegates bound to isSplitSelected() go
    stale. Fix: `const s = root._splitPaths.slice()` before splicing.
    """
    body = source_of(read("shani/Services/Files.qml"), "selectSplit")
    aliased = re.search(r"const\s+s\s*=\s*root\._splitPaths\s*;", body)
    assert not (aliased and re.search(r"\bs\.(?:splice|push|sort|reverse)\(", body)), (
        "selectSplit mutates root._splitPaths through an alias instead of a copy"
    )


def test_batch_results_are_reassigned_not_mutated():
    """Services/Archive.qml:447-448.

    root.batchDone.push() / root.batchFailed.push() mutate a `property var`
    array in place. The UI bindings on batchFailed.length only recover because
    finishBatch() happens to reassign batchSummary afterwards; that coupling is
    invisible and breaks as soon as a result is shown mid-queue. Fix: assign a
    new array (`root.batchFailed = root.batchFailed.concat([...])`).
    """
    src = read("shani/Services/Archive.qml")
    assert "root.batchDone.push(" not in src
    assert "root.batchFailed.push(" not in src


# ---------------------------------------------------------------------------
# Guards — already fixed once; these keep them fixed.
# ---------------------------------------------------------------------------


def test_logind_values_still_guarded_against_a_missing_object():
    """SettingsPowerKeys.qml:222,229 — the page.logind deref was fixed once."""
    src = read("shani/Modules/Settings/SettingsPowerKeys.qml")
    assert "(page.logind && page.logind[modelData])" in src
    assert '(page.logind && page.logind["IdleActionSec"])' in src


def test_read_only_status_does_not_use_pkexec():
    """SettingsStorage.qml:46/47 and SettingsPrinters.qml:35/36 (fixed twice).

    adminCmd is for writes and may hold pkexec; the *status* read must not use
    it, or the toggle waits on a password prompt just to show its current value.
    """
    for rel, proc in (
        ("shani/Modules/Settings/SettingsStorage.qml", "fstrimGet"),
        ("shani/Modules/Settings/SettingsPrinters.qml", "cbGet"),
    ):
        src = read(rel)
        assert "// read-only status: no pkexec" in src, rel
        line = next(l for l in src.splitlines() if "id: " + proc in l)
        assert "pkexec" not in line and "adminCmd" not in line, (rel, line.strip())


def test_stats_timers_are_gated_by_wanted():
    """SysStats.qml:114,257 — no polling when no surface shows the numbers."""
    src = read("shani/Services/SysStats.qml")
    assert src.count("running: root.wanted") >= 2
    assert "if (!wanted)" in src
    assert "root.lastDisk = null" in src


def test_filemeta_and_sessions_pass_paths_as_argv():
    """FileMeta.qml:50, Sessions.qml:109 — paths never go through a shell."""
    meta = read("shani/Services/FileMeta.qml")
    assert 'meta.command = ["python3", root.tool, p]' in meta
    assert "sh -c" not in meta and "shell: true" not in meta
    sessions = read("shani/Services/Sessions.qml")
    assert (
        'probe.command = ["sh", "-c", \'[ -d "$1" ] && echo dir || echo file\', "sh", p]'
        in sessions
    )


def test_playback_clamps_are_not_bypassed():
    """PlayQueue.qml:48-55 — a second copy of the formula is not allowed."""
    src = read("shani/Services/PlayQueue.qml")
    assert "function clampVolume(v)" in src
    assert "function clampSeek(seconds, length)" in src
    assert "Math.max(0, Math.min(1, Number(c.value)))" not in src
    assert "root.seekRequested(clampSeek(c.to, root.duration))" in src
