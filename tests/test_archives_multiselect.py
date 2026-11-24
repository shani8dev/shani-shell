"""Archives: entry multi-select, batch extract and a changed indicator.

Quickshell needs a session, so the QML half is static - one test per behaviour.
The two algorithms worth exercising (building the selection set from a possibly
filtered/duplicated input, and summing per-entry failures into one report) are
also written out below as plain Python, mirroring setSelection()/finishBatch()
in Services/Archive.qml, and tested against the edge cases a GUI run would
miss: an entry that is not listed, a duplicate, a failed first entry, and a
wrong password that must not lose the entries already extracted.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW = "shani/Modules/Archives/ArchivesWindow.qml"
SERVICE = "shani/Services/Archive.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


# ---- pure logic (the same algorithms the QML uses) -------------------------


def set_selection(paths, visible):
    """Only listed paths, each held once, in visible-list order."""
    chosen = []
    for p in paths or []:
        if p in visible and p not in chosen:
            chosen.append(p)
    return chosen


def select_entry(selection, anchor, path, mode, visible):
    """single | toggle | range over the currently visible (filtered) list."""
    if path not in visible:
        return selection, anchor
    if mode == "range":
        a = visible.index(anchor) if anchor in visible else visible.index(path)
        b = visible.index(path)
        chosen = set_selection(visible[min(a, b) : max(a, b) + 1], visible)
        return chosen, chosen[-1] if chosen else ""
    if mode == "toggle":
        chosen = list(selection)
        if path in chosen:
            chosen.remove(path)
        else:
            chosen.append(path)
        # the anchor follows the last selected entry, even when one was removed
        chosen = set_selection(chosen, visible)
        return chosen, chosen[-1] if chosen else ""
    return set_selection([path], visible), path


def batch_report(done, failed):
    """One summary, one error line per failed entry, no abort on failure."""
    total = len(done) + len(failed)
    summary = f"{total} selected — Done: {len(done)}"
    if failed:
        summary += f"  ·  {len(failed)} failed"
    return {
        "total": total,
        "done": len(done),
        "failed": len(failed),
        "summary": summary,
        "error": "  ·  ".join(f"{p}: {e}" for p, e in failed),
    }


# ---- pure logic tests ------------------------------------------------------


def test_selection_drops_unlisted_paths_and_duplicates():
    visible = ["a.txt", "dir/", "dir/b.txt"]
    assert set_selection(
        ["dir/b.txt", "a.txt", "dir/b.txt", "../escape", ""], visible
    ) == [
        "dir/b.txt",
        "a.txt",
    ]
    assert set_selection([], visible) == []
    # a filter hiding an entry must make a previously selected path vanish
    assert set_selection(["dir/b.txt"], ["a.txt"]) == []


def test_single_toggle_and_shift_range_selection():
    visible = ["a", "b", "c", "d"]
    sel, anchor = select_entry([], "", "c", "single", visible)
    assert (sel, anchor) == (["c"], "c")

    sel, anchor = select_entry(sel, anchor, "a", "toggle", visible)
    assert (sel, anchor) == (["c", "a"], "a")
    sel, anchor = select_entry(sel, anchor, "c", "toggle", visible)
    assert sel == ["a"]  # toggled off, no duplicate left behind

    sel, anchor = select_entry(sel, anchor, "d", "range", visible)
    assert sel == ["a", "b", "c", "d"]  # from the last anchor, in list order
    # a range with no usable anchor starts at the clicked entry
    assert select_entry([], "", "b", "range", visible)[0] == ["b"]
    # a click on something not listed changes nothing
    assert select_entry(["a"], "a", "../escape", "toggle", visible) == (["a"], "a")


def test_batch_report_keeps_every_success_and_names_every_failure():
    report = batch_report(
        ["a.txt", "c.txt"], [("b.txt", "encrypted"), ("d/", "no space")]
    )
    assert report["total"] == 4
    assert report["done"] == 2
    assert report["failed"] == 2
    assert "2 failed" in report["summary"] and "Done: 2" in report["summary"]
    assert report["error"] == "b.txt: encrypted  ·  d/: no space"

    clean = batch_report(["a.txt", "b.txt"], [])
    assert clean["failed"] == 0 and "failed" not in clean["summary"]
    assert clean["error"] == ""


# ---- QML: the window -------------------------------------------------------


def test_delegate_has_a_checkbox_and_ctrl_shift_click():
    q = read(WINDOW)
    assert "readonly property bool chosen: Archive.isSelected(row.modelData.path)" in q
    assert "Accessible.role: Accessible.CheckBox" in q
    assert 'text: row.chosen ? "✓" : ""' in q
    assert (
        'onClicked: Archive.selectEntry(row.modelData.path, "toggle", win.visiblePaths)'
        in q
    )
    assert 'shift ? "range" : (ctrl ? "toggle" : "single")' in q
    assert "(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_A" in q
    assert "e.key === Qt.Key_Escape && Archive.selection.length" in q
    assert "property string entryFilter" in q
    assert "model: win.visibleEntries" in q


def test_extract_selected_chooses_a_destination_and_reports_a_summary():
    q = read(WINDOW)
    assert "function extractSelectedTo()" in q
    assert 'mode: "folder", title: Tr.t("Extract into")' in q
    assert "Archive.extractSelected(Archive.selection, paths[0])" in q
    assert 'Tr.t("%1 selected").arg(Archive.selection.length)' in q
    assert 'Archive.batchSummary !== ""' in q
    assert 'tone: Archive.batchFailed.length ? "warn" : "ok"' in q
    assert 'text: Tr.t("Show the folder")' in q
    # the visible count is not the selection count: both are shown
    assert 'win.visibleEntries.length + " / " + Archive.entries.length' in q


def test_modified_badge_and_reload_button():
    q = read(WINDOW)
    assert 'Archive.modified ? "  ·  " + Tr.t("Changed this session")' in q
    assert "visible: Archive.modified" in q
    assert 'text: Tr.t("Reload")' in q
    assert "onClicked: Archive.open(Archive.file)" in q


# ---- QML: the service ------------------------------------------------------


def test_service_builds_a_deduped_selection_over_visible_entries():
    q = read(SERVICE)
    assert "property var selection: []" in q
    assert "function isSelected(path)" in q
    assert "function setSelection(paths, visible)" in q
    assert "if (allowed.indexOf(p) >= 0 && chosen.indexOf(p) < 0) chosen.push(p);" in q
    assert "function selectAll(visible)" in q
    assert "function selectEntry(path, mode, visible)" in q
    assert "paths.slice(Math.min(a, b), Math.max(a, b) + 1)" in q
    assert "root.clearSelection()" in q


def test_batch_extract_is_a_queue_not_a_loop_of_extract_one():
    q = read(SERVICE)
    assert "function extractSelected(paths, where)" in q
    assert "function nextBatch()" in q
    assert "function finishBatch()" in q
    assert "root.batchPaths = wanted;" in q
    assert "root.batchIndex++;" in q
    assert "root.nextBatch();" in q
    # one entry through the hardened reader, password on stdin, free name in
    # the chosen destination (the same shape as extractOne)
    assert 'python3 "$2" extract "$3" "$t/x" "$4"' in q
    assert 'mktemp -d "$p/.shani-extract.XXXXXX"' in q
    assert 'batchOne.payload = root.pass + "\\n"' in q
    assert "if (batchOne.running) batchOne.running = false;" in q
    assert "if (root.batchIndex >= root.batchPaths.length) return;" in q


def test_failed_entry_is_recorded_and_the_rest_still_run():
    q = read(SERVICE)
    exited = q.split("id: batchOne", 1)[1].split("\n    }", 1)[0]
    assert "root.batchFailed.push(" in exited
    assert "root.batchDone.push(entry);" in exited
    assert "root.batchIndex++;" in exited
    assert 'root.retry = "batch";' in exited  # a wrong password pauses here
    assert "root.extracting = false;" in exited
    finish = q.split("function finishBatch() {", 1)[1].split("\n    }", 1)[0]
    assert "root.batchFailed.length" in finish
    assert 'Tr.t("%1 failed")' in finish
    assert "root.batchFailed.map(" in finish  # each error, in the report
    assert "root.extracting = false;" in finish


def test_unlock_resumes_the_batch_at_the_entry_that_asked():
    q = read(SERVICE)
    unlock = q.split("function unlock(pw) {", 1)[1].split("\n    }", 1)[0]
    assert 'root.retry === "batch"' in unlock
    assert "root.nextBatch();" in unlock
    assert "root.extracting = true;" in unlock


def test_free_space_preflight_covers_the_selected_entries_too():
    q = read(SERVICE)
    selected = q.split("function extractSelected(paths, where) {", 1)[1].split(
        "\n    }", 1
    )[0]
    assert "root.probeSize = bytes;" in selected
    assert 'root.probeKind = "batch";' in selected
    assert "root.probeThenExtract = true;" in selected
    guard = q.split("id: spaceProbe", 1)[1].split("function extractNow", 1)[0]
    assert 'root.probeKind === "batch" ? root.probeSize : root.totalSize' in guard
    assert "exp > free" in guard
    assert "root.batchRefused(why)" in guard
    assert "root.batchExtractNow()" in guard
    assert 'df -PB1 -- "$1"' in q


def test_modified_is_set_on_append_and_cleared_on_reload():
    q = read(SERVICE)
    assert "property bool modified: false" in q
    appender = q.split("id: appender", 1)[1].split("\n    }", 1)[0]
    assert "root.modified = true;" in appender
    opened = q.split("function open(arg) {", 1)[1].split("\n    }", 1)[0]
    assert "root.modified = false;" in opened
    assert "root.abortBatch();" in opened
    closed = q.split("function close() {", 1)[1].split("\n    }", 1)[0]
    assert "modified = false;" in closed
    cancel = q.split("function cancel() {", 1)[1].split("\n    }", 1)[0]
    assert "root.abortBatch();" in cancel


def test_removal_is_not_faked_without_a_safe_backend():
    """bsdtar cannot delete in place and zipadd.py (out of scope) has no delete
    command; a rebuild here would risk password/metadata loss and a half-written
    archive. There is deliberately no removal button or helper."""
    for rel in (WINDOW, SERVICE):
        q = read(rel)
        assert "removeEntry" not in q and "deleteEntry" not in q


def test_no_new_translation_keys_are_introduced():
    """The i18n template is owned by another agent; reuse existing keys."""
    template = json.loads(
        (ROOT / "shani/i18n/template.json").read_text(encoding="utf-8")
    )
    for rel in (WINDOW, SERVICE):
        keys = set(re.findall(r'Tr\.t\("((?:[^"\\]|\\.)*)"', read(rel)))
        assert keys <= set(template), (rel, sorted(keys - set(template)))
