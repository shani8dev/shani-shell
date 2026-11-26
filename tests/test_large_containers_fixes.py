"""The container-manager upgrade, as static invariants on the two files it touches.

1. stats: list rows carry CPU/mem, polled from `podman stats`;
2. the containers tab has All / Running / Stopped filters and a sorted list;
3. the log panel refreshes itself and reads again;
4. containers get an inspect panel;
5. the images list is sorted and has an empty state;
6. F5 re-reads the list;
7. empty and error states;
8. the new controls carry accessible names.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WIN = "shani/Modules/Containers/ContainersWindow.qml"


def read(p):
    return (ROOT / p).read_text()


def s():
    return read(WIN)


def test_stats_metrics_and_poll():
    s = read(WIN)
    assert "property var statsOf: []" in s
    assert '"stats", "--no-stream"' in s
    assert (
        'statsProc.command = [Quickshell.env("SHANI_PODMAN") || "podman", "stats", "--no-stream", "--all", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}"]'
        in s
    )
    assert "win.statsOf = m;" in s
    assert "function statsText(name)" in s
    assert "win.statsText(crow.modelData.name)" in s
    assert "Timer { id: statsTimer; interval: 20000" in s


def test_started_stopped_filters():
    s = read(WIN)
    assert 'property string filter: "all"' in s
    assert 'win.others.filter(c => win.filter === "all"' in s
    assert (
        '["all", Tr.t("All")], ["running", Tr.t("Running")], ["stopped", Tr.t("Stopped")]'
        in s
    )
    assert "onClicked: win.filter = modelData[0]" in s
    assert "No containers match the filter" in s


def test_sorted_models():
    s = read(WIN)
    assert "function cmpKey(a, b)" in s
    assert "model: win.sortedContainers" in s
    assert "model: win.sortedImages" in s
    assert (
        '["name", Tr.t("Name")], ["status", Tr.t("Status")]' in s
    )  # containers sort: status
    assert '["name", Tr.t("Name")], ["size", Tr.t("Size")]' in s  # images sort: size
    assert 'Choice { text: Tr.t("Descending")' in s


def test_live_log_panel():
    s = read(WIN)
    assert "function refreshLogs(name)" in s
    assert (
        'win.run(["logs", name], r => { if (win.logsOf === name) win.logsText = r.text || ""; })'
        in s
    )
    assert 'Timer { id: logTimer; interval: 10000; running: win.logsOf !== ""' in s
    # the panel header has its own refresh button
    assert (
        'IconButton { icon: "view-refresh"; size: Theme.px(20); tip: Tr.t("Read again"); onClicked: win.refreshLogs(crow.modelData.name) }'
        in s
    )


def test_quick_actions_inspect():
    s = read(WIN)
    assert (
        'IconButton { icon: "document-properties"; size: Theme.px(26); tip: Tr.t("Inspect"); onClicked: win.inspect(crow.modelData.name) }'
        in s
    )
    assert "function inspect(name)" in s
    # inspect now goes through the bridge, which returns a readable summary
    assert 'win.run(["container-inspect", name], r => { win.inspectData = [r]; })' in s
    assert "function inspectRows(name)" in s
    # start / stop / restart were there before and stay
    assert 'tip: crow.up ? Tr.t("Stop") : Tr.t("Start")' in s
    assert 'tip: Tr.t("Restart")' in s


def test_images_empty_state_and_prune():
    s = read(WIN)
    assert (
        'EmptyState {\n            visible: win.tab === "images" && win.images.length === 0'
        in s
    )
    assert 'title: Tr.t("No images yet")' in s
    assert 'win.run(["prune"]' in s
    assert (
        'text: [win.size(irow.modelData.size || 0), irow.modelData.used ? Tr.t("in use") : Tr.t("unused")].join("  ·  ")'
        in s
    )


def test_port_mapping():
    s = read(WIN)
    assert "crow.modelData.ports" in s


def test_refresh_hotkey():
    s = read(WIN)
    assert "Keys.onPressed: event => { if (event.key === Qt.Key_F5)" in s
    assert "event.accepted = true; win.refresh();" in s
    # the manual refresh button still exists
    assert 'tip: Tr.t("Read again"); onClicked: win.refresh()' in s


def test_accessible_names_on_new_controls():
    s = read(WIN)
    # the new buttons are IconButtons: they are named by their tip (Common/IconButton.qml)
    assert 'tip: Tr.t("Inspect")' in s
    assert 'tip: Tr.t("Read again")' in s
    # the new Choices are named by their text (Common/Choice.qml)
    assert 'Tr.t("All")' in s and 'Tr.t("Running")' in s and 'Tr.t("Stopped")' in s
    assert 'Choice { text: Tr.t("Descending"); selected: win.sortDesc' in s
    assert 'Text { text: Tr.t("Sort"); color: Theme.dim' in s


def test_empty_and_error_states():
    s = read(WIN)
    # the lister reports an error instead of failing silently
    assert "if (r.error) win.error = r.error;" in s
    assert 'text: !win.hasPodman ? Tr.t("Podman is not installed")' in s
    assert 'Tr.t("No toolboxes yet - pick a Linux above")' in s
    # logs now filter a snapshot or a followed stream through one helper
    assert (
        'text: win.logsOf === crow.modelData.name ? win.logText(crow.modelData.name) : ""'
        in s
    )
    assert "function logText(name)" in s and 'Tr.t("Nothing logged")' in s
