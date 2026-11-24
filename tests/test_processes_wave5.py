"""Wave 5 System Monitor: persisted sorting and the System pressure row.

The QML needs a live shell to render, so its wiring is pinned here as static
invariants. The two pieces of logic that can be wrong without ever showing a
QML error -- the sibling comparator and the meter thresholds -- are mirrored
in Python and replayed on small process/sample tables.
"""

import re
from functools import cmp_to_key
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROCESSES = ROOT / "shani/Modules/Processes/Processes.qml"


def source():
    return PROCESSES.read_text(encoding="utf-8")


def function_body(text, name):
    """The body of `function name(...) { ... }`, braces balanced."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", text)
    assert m, f"function {name}() is missing"
    start = m.end() - 1
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : i]
    raise AssertionError(f"unbalanced function {name}()")


def section(text, start_marker, end_marker):
    return text[text.index(start_marker) : text.index(end_marker)]


# ---- persisted sort ---------------------------------------------------------


def test_sort_choice_lives_in_a_sibling_json_file():
    p = source()
    assert "import Quickshell.Io" in p
    assert 'path: win.prefsDir + "/processes-sort.json"' in p
    assert "Settings.path" in p  # config dir of the shell, not a new one
    assert "atomicWrites: true" in p
    assert "JsonAdapter {" in p
    assert 'property string key: "cpu"' in p
    assert "property bool desc: true" in p
    assert "writeAdapter()" in p
    assert "mkdir" in p
    assert "function loadSort()" in p and "function saveSort()" in p
    assert "onLoadFailed" in p  # missing file keeps the defaults
    load = function_body(p, "loadSort")
    assert "win.sortApplied" in load and "win.sortKeys.indexOf(k) >= 0" in load
    save = function_body(p, "saveSort")
    assert "sortPrefs.key = win.sortKey" in save
    assert "sortPrefs.desc = win.sortDesc" in save
    assert "win.sortKeys" in p


def test_clicking_a_header_saves_the_new_choice():
    p = source()
    body = function_body(p, "setSort")
    assert "win.sortKey = key" in body
    assert 'key !== "pid" && key !== "name"' in body  # text sorts ascending first
    assert "win.treeList = win.buildTree()" in body
    assert "win.saveSort()" in body


def test_headers_are_named_keyboard_buttons_with_an_indicator():
    p = source()
    header = section(p, "// clickable column headers", "// the processes, a row each")
    for key in ("name", "pid", "cpu", "mem", "disk"):
        assert f'key: "{key}"' in header, key
    for needle in (
        "Accessible.role: Accessible.Button",
        'Accessible.name: Tr.t("Sort by %1", modelData.label)',
        "Accessible.onPressAction: win.setSort(modelData.key)",
        'KeyFocus { name: Tr.t("Sort by %1", modelData.label)',
        'win.sortDesc ? " ↓" : " ↑"',
        "cursorShape: Qt.PointingHandCursor",
    ):
        assert needle in header, needle


# ---- the sort comparator, replayed ------------------------------------------

SORT_KEYS = ["name", "pid", "cpu", "mem", "disk"]


def metric(p, key, disk_io):
    """Mirror of win.metric(): the disk column reads TopProcesses.diskIo by pid."""
    if key == "pid":
        return p["pid"]
    if key == "name":
        return str(p.get("name") or "")
    if key == "mem":
        return p["mem"]
    if key == "disk":
        return disk_io.get(p["pid"], 0)
    return p["cpu"]


def sort_rows(rows, key, desc, disk_io=None):
    """Mirror of win.sortRows(), including JS localeCompare's string branch."""
    disk_io = disk_io or {}
    direction = -1 if desc else 1

    def compare(a, b):
        x, y = metric(a, key, disk_io), metric(b, key, disk_io)
        if isinstance(x, str) or isinstance(y, str):
            xs, ys = str(x).lower(), str(y).lower()
            return ((xs > ys) - (xs < ys)) * direction
        return (x - y) * direction

    return sorted(rows, key=cmp_to_key(compare))


def set_sort(key, current_key, current_desc):
    """Mirror of the first-click direction in win.setSort()."""
    if key == current_key:
        return key, not current_desc
    return key, key not in ("pid", "name")


def build_tree(procs, key, desc, disk_io=None):
    """Mirror of win.buildTree(): compare siblings, keep parents above children."""
    disk_io = disk_io or {}
    by_pid = {p["pid"]: p for p in procs}
    kids = {}
    for p in procs:
        kids.setdefault(p["ppid"], []).append(p)
    out = []

    def walk(indent, ppid):
        for p in sort_rows(kids.get(ppid, []), key, desc, disk_io):
            out.append((p, indent))
            walk(indent + 1, p["pid"])

    roots = [p for p in procs if p["ppid"] <= 1 or p["ppid"] not in by_pid]
    for p in sort_rows(roots, key, desc, disk_io):
        out.append((p, 0))
        walk(1, p["pid"])
    return out


def proc(pid, name, cpu, mem, ppid=1):
    return {"pid": pid, "name": name, "cpu": cpu, "mem": mem, "ppid": ppid}


def test_sort_rows_uses_the_clicked_key_and_direction():
    p = source()
    body = function_body(p, "sortRows")
    assert "const key = win.sortKey, dir = win.sortDesc ? -1 : 1" in body
    assert "localeCompare" in body
    assert "win.metric(a, key)" in body and "win.metric(b, key)" in body

    rows = [
        proc(1, "zeta", 12, 4),
        proc(2, "alpha", 75, 2),
        proc(3, "mid", 40, 9),
    ]
    assert [r["pid"] for r in sort_rows(rows, "cpu", True)] == [2, 3, 1]
    assert [r["pid"] for r in sort_rows(rows, "cpu", False)] == [1, 3, 2]
    assert [r["pid"] for r in sort_rows(rows, "mem", True)] == [3, 1, 2]
    assert [r["name"] for r in sort_rows(rows, "name", False)] == [
        "alpha",
        "mid",
        "zeta",
    ]
    assert [r["pid"] for r in sort_rows(rows, "pid", False)] == [1, 2, 3]


def test_disk_sort_reads_the_sample_and_first_click_directions_are_right():
    rows = [proc(10, "a", 1, 1), proc(11, "b", 1, 1), proc(12, "c", 1, 1)]
    io = {10: 500, 12: 9000}  # pid 11 has no sample at all
    assert [r["pid"] for r in sort_rows(rows, "disk", True, io)] == [12, 10, 11]
    assert [r["pid"] for r in sort_rows(rows, "disk", False, io)] == [11, 10, 12]
    assert set_sort("name", "cpu", True) == ("name", False)
    assert set_sort("cpu", "cpu", True) == ("cpu", False)
    assert set_sort("disk", "name", True) == ("disk", True)
    assert set_sort("pid", "cpu", True) == ("pid", False)


def test_tree_sorts_only_siblings():
    rows = [
        proc(10, "parent", 1, 1, ppid=0),
        proc(11, "low", 5, 1, ppid=10),
        proc(12, "high", 90, 1, ppid=10),
        proc(20, "other", 50, 1, ppid=0),
    ]
    out = build_tree(rows, "cpu", True)
    pids = [p["pid"] for p, _ in out]
    assert pids == [20, 10, 12, 11]
    # the parent stays above its own children even when a child uses more CPU
    assert pids.index(10) < pids.index(12)
    assert [p["pid"] for p, indent in out if indent == 1] == [12, 11]


# ---- System pressure meters -------------------------------------------------

PRESSURE = section(source(), "// ---- System pressure", "// ---- Hardware sensors")


def thresholds(text, name):
    """Read the >= cut-offs out of a QML level function, high then medium."""
    body = function_body(text, name)
    return [float(x) for x in re.findall(r">=\s*(\d+(?:\.\d+)?)", body)]


def level(value, cutoffs):
    hi, mid = cutoffs
    return 2 if value >= hi else 1 if value >= mid else 0


def test_pressure_row_uses_only_the_existing_sysstats_samples():
    for needle in (
        'Tr.t("System pressure")',
        "SysStats.load1.toFixed(2)",
        "SysStats.load5.toFixed(2)",
        "SysStats.load15.toFixed(2)",
        "SysStats.swapUsedMb",
        "SysStats.swapTotalMb",
        "SysStats.psiCpu",
        "SysStats.psiMem",
        "SysStats.psiIo",
        "win.pressureColor",
    ):
        assert needle in PRESSURE, needle
    # no opaque card, no extra poller or history series
    assert "Theme.surface1" not in PRESSURE and "Theme.card" not in PRESSURE
    assert PRESSURE.count("Accessible.name") >= 4
    p = source()
    assert p.count("Timer {") == 1
    assert p.count("Sparkline {") == 3
    assert "StdioCollector" not in p and "Process {" not in p


def test_meter_thresholds_have_testable_boundaries():
    p = source()
    load = thresholds(p, "loadLevel")
    swap = thresholds(p, "swapLevel")
    psi = thresholds(p, "psiLevel")
    assert load == [1, 0.7] and swap == [0.9, 0.7] and psi == [40, 20]
    # load is per core, so four cores need a load of four to saturate
    assert level(2.6 / 4, load) == 0
    assert level(3.2 / 4, load) == 1
    assert level(4 / 4, load) == 2
    assert level(0.7, load) == 1  # no core count: the raw load is used
    # swap is a share of the total; no swap configured is never a warning
    assert level(0.69, swap) == 0
    assert level(0.7, swap) == 1
    assert level(0.9, swap) == 2
    assert level(0, swap) == 0
    # PSI is already a percentage of stalled time
    assert level(19.9, psi) == 0
    assert level(20, psi) == 1
    assert level(40, psi) == 2


def test_meter_colours_are_theme_tokens():
    p = source()
    body = function_body(p, "pressureColor")
    for token in ("Theme.red", "Theme.amber", "Theme.accent"):
        assert token in body
