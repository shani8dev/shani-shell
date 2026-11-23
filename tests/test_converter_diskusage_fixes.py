"""Static checks for Converter/Job and DiskUsage panel fixes that the docs do
not list: retrying a failed job, stale running-index bookkeeping, and keyboard
/ AT access to the disk-usage views."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def converter():
    return read("shani/Modules/Converter/ConverterWindow.qml")


def diskusage():
    return read("shani/Modules/DiskUsage/DiskUsagePanel.qml")


def test_failed_job_can_be_retried():
    w = converter()
    assert 'text: Tr.t("Retry")' in w
    # A retry must clear the old failure and start from a clean, ready job so
    # convertAll()/startNext() can pick it up again.
    assert 'visible: row.modelData.state === "failed"' in w
    assert (
        'win.set(row.index, { state: "ready", progress: 0, error: "", out: "" })' in w
    )


def test_stray_worker_output_is_not_written_to_the_wrong_job():
    w = converter()
    # A cancelled/retried worker can emit one late line with running already -1;
    # jobs[-1] is not a job and must not be touched.
    assert "if (win.running < 0) return;" in w
    guard = w.index("if (win.running < 0) return;")
    first_set = w.index("e.progress !== undefined", guard)
    assert first_set > guard


def test_removing_an_earlier_job_keeps_the_running_index_on_its_job():
    w = converter()
    # splice() shifts every later job left; without adjusting, progress/done
    # would land on the job after the one actually being converted.
    assert "if (row.index < win.running) win.running--;" in w
    remove = w.index("if (row.index < win.running) win.running--;")
    splice = w.index("l.splice(row.index, 1)", remove)
    assert splice > remove


def test_duplicate_group_header_has_an_accessible_name():
    p = diskusage()
    # The flattened dupes model has header rows with no path; an AT checkbox
    # with an empty name is useless, so name the group.
    assert "Accessible.name: modelData.head ? Tr.t(" in p
    assert (
        'Tr.t("%1 copies of %2", modelData.n, DiskUsage.humanSize(modelData.size))' in p
    )


def test_back_and_refresh_keys_work_in_the_disk_usage_panel():
    p = diskusage()
    assert "Keys.onBackPressed: if (DiskUsage.history.length > 0) DiskUsage.back()" in p
    assert "event.key === Qt.Key_F5" in p
    assert "DiskUsage.refresh(); event.accepted = true;" in p
