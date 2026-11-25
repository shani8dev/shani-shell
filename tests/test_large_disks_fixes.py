"""Static guards for the large-disk manager upgrades: selectivity search/filter,
partition list, tools, smart details expansion, performance view, large-file
finder with preview, by-fs filter, units, AT names, and empty/error states.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW = ROOT / "shani" / "Modules" / "Disks" / "DisksWindow.qml"
w = WINDOW.read_text()


def test_selectivity_search_and_by_fs_filter():
    for token in (
        'property string filterText: ""',
        'property string fsFilter: ""',
        "function diskMatch(d)",
        "function filteredDisks()",
        'placeholder: Tr.t("Search disks…")',
        "fsChoices",
        '["", Tr.t("By fs: All")]',
        "onClicked: win.fsFilter = modelData[0]",
        "model: win.filteredDisks()",
    ):
        assert token in w, token
    # the disk list honours the filter, and the model keeps loop devices
    assert 'd.type !== "disk"' in w and 'win.showLoops && d.type === "loop"' in w


def test_units_selector_and_human_honors_unit_scale():
    assert 'property string unitScale: "auto"' in w
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        assert 's === "%s"' % unit in w, unit
    assert 'Math.round(n) + " B"' in w and '(n / 1e12).toFixed(1) + " TB"' in w
    assert (
        '["auto", Tr.t("Auto")], ["bytes", "B"], ["KB", "KB"], ["MB", "MB"], ["GB", "GB"], ["TB", "TB"]'
        in w
    )


def test_partition_list_dialog():
    assert "function partList(d)" in w
    assert "id: partDialog" in w and 'Tr.t("Partitions · %1"' in w
    assert "win.partList(win.selectedDisk)" in w and 'Tr.t("Partitions…")' in w
    assert "visible: win.partList(win.selectedDisk).length === 0" in w
    assert 'Tr.t("(unmounted)")' in w and "win.human(modelData.size || 0)" in w
    assert 'title: Tr.t("No partitions")' in w


def test_smart_details_expansion_at_names_capacity_refresh():
    assert "function attrName(a)" in w
    assert "win.attrName(modelData)" in w
    assert (
        'text: Tr.t("Capacity: %1", smartCol.info.capacity ? win.human(smartCol.info.capacity) : "—")'
        in w
    )
    assert 'Tr.t("Health: %1", (healthRow.curHealth && healthRow.curHealth.overall) || "—")' in w
    assert (
        'Tr.t("Refresh health")' in w
        and 'onClicked: Disks.checkHealth(win.selectedDisk ? win.selectedDisk.path : "")'
        in w
    )


def test_performance_view():
    assert "id: perfDialog" and "win.benchHistory" in w
    assert "function runBench()" in w and "onClicked: win.runBench()" in w
    assert "win.benchHistory.slice(-9)" in w
    assert 'text: modelData.at + "  " + modelData.mbps.toFixed(1) + Tr.t(" MB/s")' in w
    assert 'Tr.t("Performance…")' in w and 'visible: modelData.type === "disk"' in w


def test_large_files_finder_with_time_machine_like_preview():
    assert "function scanBigFiles()" in w and '["find", d.path, "-xdev"' in w
    assert "-printf" in w and "win.bigFiles = out.slice(0, 20)" in w
    assert (
        "id: bigDialog"
        and 'text: modelData.when + "  " + win.human(modelData.size || 0) + "\\n" + modelData.path'
        in w
    )
    assert 'Tr.t("Large files…")' in w and "bigFinder.running" in w


def test_tools_dialog_wipe_with_two_click_confirm():
    assert "id: toolsDialog" and 'Tr.t("Tools · %1"' in w
    assert "Disks.eraseQuick(win.selectedDisk.path)" in w
    assert "Disks.eraseSecure(win.selectedDisk.path)" in w
    assert (
        'win.confirmAction === "wipe-quick"' in w
        and 'win.confirmAction === "wipe-secure"' in w
    )


def test_empty_and_error_states():
    assert 'title: Disks.error !== "" ? Tr.t("Could not read the disks")' in w
    assert 'Tr.t("No matching disks")' in w and 'Tr.t("No disks found")' in w
    assert "actionText: list.count === 0 && Disks.disks.length > 0" in w
    assert "onAction: win.clearFilter()" in w
    assert "visible: win.partList(win.selectedDisk).length === 0" in w
    assert "visible: win.benchHistory.length === 0" in w
