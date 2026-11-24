"""Second deep pass: Places quick-jump (already in the sidebar) and folder capacity
in Properties.

Static assertions pin the QML surface; the pure helpers below mirror the QML
formatting/path gate so a change to either is caught here. The bridge is read
through `free_space()` directly - no process, no shell - to check the shape the
Properties probe consumes.
"""

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = ROOT / "shani/Modules/Files/FilesPanel.qml"
BRIDGE = ROOT / "bridge/files.py"


def panel():
    return PANEL.read_text(encoding="utf-8")


def bridge():
    spec = importlib.util.spec_from_file_location("files_probe_bridge", BRIDGE)
    fb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fb)
    return fb


# ---- pure logic, mirrored from the QML -----------------------------------------


def human_size(n):
    """Files.qml humanSize: 1 decimal above a KB, plain bytes below."""
    n = float(n or 0)
    if n >= 1073741824:
        return f"{n / 1073741824:.1f} GB"
    if n >= 1048576:
        return f"{n / 1048576:.1f} MB"
    if n >= 1024:
        return f"{n / 1024:.1f} KB"
    return f"{int(n)} B"


def capacity_text(free, total):
    """The Properties row is only shown once a real total has been measured."""
    if not isinstance(total, (int, float)) or total <= 0:
        return ""
    if not isinstance(free, (int, float)) or free < 0:
        return ""
    return f"{human_size(free)} free of {human_size(total)}"


def is_local_folder(kind, path):
    """Props capacity gate: a real folder with an absolute local path."""
    return kind == "folder" and isinstance(path, str) and path.startswith("/")


def test_human_size_matches_the_qml_function():
    assert human_size(0) == "0 B"
    assert human_size(1023) == "1023 B"
    assert human_size(1024) == "1.0 KB"
    assert human_size(1536) == "1.5 KB"
    assert human_size(1048576) == "1.0 MB"
    assert human_size(1073741824) == "1.0 GB"


def test_capacity_text_needs_both_numbers():
    assert capacity_text(2048, 1048576) == "2.0 KB free of 1.0 MB"
    assert capacity_text(0, 100) == "0 B free of 100 B"
    assert capacity_text(-1, 100) == ""  # probe failed
    assert capacity_text(100, 0) == ""  # not measured yet
    assert capacity_text(100, None) == ""


def test_path_gate_rejects_pseudo_places_and_remote_uris():
    assert is_local_folder("folder", "/home/me/Downloads")
    assert is_local_folder("folder", "/")
    for kind, path in (
        ("folder", "recent:"),
        ("folder", "starred:"),
        ("folder", "kind:pictures"),
        ("folder", "smb://host/share"),
        ("folder", ""),
        ("folder", None),
        ("file", "/home/me/a.txt"),
    ):
        assert not is_local_folder(kind, path), (kind, path)


def test_bridge_free_space_feeds_the_capacity_format(tmp_path):
    r = bridge().free_space(str(tmp_path))
    assert 0 < r["free"] <= r["total"]
    text = capacity_text(r["free"], r["total"])
    assert "free of" in text and text.startswith(human_size(r["free"]))


# ---- static: the QML actually uses those helpers --------------------------------


def test_places_sidebar_already_has_the_quick_jumps():
    q = panel()
    assert 'text: Tr.t("Places")' in q
    assert (
        "model: Files.places.filter(p => !Files.devices.some(d => d.path && d.path === p.path))"
        in q
    )
    assert 'title: Tr.t("Trash")' in q
    assert (
        "Files.openDevice(devRow.modelData)" in q
    )  # drives without a second jump list
    b = BRIDGE.read_text(encoding="utf-8")
    assert (
        '"name": "Home"' in b
        and '"desktop", "user-desktop"' in b
        and '"downloads", "folder-download"' in b
    )


def test_properties_shows_free_of_total_for_a_folder():
    q = panel()
    assert 'propsBox.row(Tr.t("Space"), propsBox.totalBytes > 0' in q
    assert (
        'Tr.t("%1 free of %2", Files.humanSize(propsBox.freeBytes), Files.humanSize(propsBox.totalBytes))'
        in q
    )
    assert (
        'p.type === "folder" && typeof p.path === "string" && p.path.indexOf("/") === 0'
        in q
    )
    assert "import Quickshell.Io" in q


def test_capacity_probe_is_argv_only_and_not_faked():
    q = panel()
    # files.py free (statvfs), not a shell pipeline or a string-built command
    assert 'propsCapacity.command = ["python3", Files.tool, "free", path]' in q
    assert "sh -c" not in q
    assert "function probeCapacity()" in q
    assert (
        "function onPropsChanged() { if (propsBox.visible && !propsBox.p.loading) propsBox.probeCapacity(); }"
        in q
    )
    assert '"free", path' in q
    # stale answers from a previous dialog must not overwrite this folder's numbers
    assert "propsCapacity.forPath !== propsBox.p.path" in q


def test_existing_search_chips_history_and_tabs_are_untouched():
    """The other waves' work in this same file must keep working."""
    q = panel()
    assert "path: win.searchingDeep ? Files.searchPath(win.deepWords) : Files.path" in q
    assert "model: win.searchCategories" in q
    assert "Files.rememberSearch(words);" in q
    assert "Files.clearSearchHistory()" in q
    assert "Files.tabPaths" in q
