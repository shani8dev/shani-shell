"""Static checks for the pass-22 loading-state fixes.

These are QML surfaces driven by live processes (journalctl, curl, a file
watcher), so the assertions pin the wiring that makes each failure honest
without a running shell.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_file_directory_reload_drops_the_previous_folder():
    q = read("shani/Common/FileDirectory.qml")
    assert "readonly property ListModel entries: ListModel {}" in q
    assert "property var _all: []" in q
    reload = q.split("function reload() {")[1].split("function refresh()")[0]
    assert "root._all = []" in reload
    assert "root.entries.clear()" in reload
    assert "root.total = 0" in reload
    # stale rows must be gone before the watcher is started for the new path
    assert reload.index("root._all = []") < reload.index("root.watcher.running = true")


def test_logs_panel_does_not_claim_no_logs_while_reading():
    q = read("shani/Modules/Logs/LogsPanel.qml")
    assert "property bool loading: false" in q
    read_journal = q.split("function readJournal() {")[1].split("onVisibleChanged")[0]
    assert "win.loading = true" in read_journal
    stdout = q.split("stdout: StdioCollector {")[1].split("stderr:")[0]
    assert "win.loading = false" in stdout
    exited = q.split("onExited: code => {")[1].split("Item { anchors.fill")[0]
    assert "win.loading = false" in exited
    assert "visible: win.entries.length === 0 && !win.loading" in q


def test_weather_failure_replaces_the_permanent_loading_line():
    svc = read("shani/Services/Weather.qml")
    win = read("shani/Modules/Weather/WeatherWindow.qml")
    assert 'property string error: ""' in svc
    assert 'root.error = Tr.t("Could not look up that place' in svc
    assert 'root.error = Tr.t("Could not get the weather' in svc
    assert svc.count('root.error = ""') >= 2  # cleared on both success paths
    empty = win.split("EmptyState {")[1].split("// ---- now ----")[0]
    assert 'Weather.error !== "" ? Weather.error' in empty
    assert 'Tr.t("Weather unavailable")' in empty
    assert 'Tr.t("Getting the weather…")' in empty
