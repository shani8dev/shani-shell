"""Static checks for the Housekeeping.qml scheduled-maintenance fixes.

There is no QML runtime in the dev container, so — as in the other gap tests —
each fix is verified by reading the source of the file that owns it.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = "shani/Services/Housekeeping.qml"


def load():
    s = (ROOT / SOURCE).read_text()
    assert s.count("{") == s.count("}"), "unbalanced braces in Housekeeping.qml"
    assert s.count("(") == s.count(")"), "unbalanced parens in Housekeeping.qml"
    return s


def test_trash_sweep_reports_failures():
    """A failed rm is no longer indistinguishable from 'nothing was old'."""
    s = load()
    assert "property bool sweepFailed: false" in s
    assert 'property string sweepError: ""' in s
    assert "property int sweepExitCode: 0" in s
    # the wc pipeline always exits 0, so failures are marked on stderr
    assert "stderr: StdioCollector { onStreamFinished: root._sweepErr = text }" in s
    assert 'echo "could not remove $b" >&2' in s
    assert "onExited: code => {" in s
    assert "root.sweepExitCode = code;" in s
    assert "root.sweepError = root._sweepErr.trim();" in s
    assert "root.sweepFailed = code !== 0 || root.sweepError.length > 0;" in s


def test_failed_health_probe_keeps_last_failing_drives():
    """A dead UDisks2 probe must not wipe a previously detected SMART warning."""
    s = load()
    # stdout is buffered; parsing happens only on a successful exit
    assert "stdout: StdioCollector { onStreamFinished: root._healthText = text }" in s
    assert "onStreamFinished: {\n                // per drive object" not in s
    assert "if (code !== 0) {" in s
    assert "root.healthFailed = true;" in s
    assert 'root.healthError = "gdbus exited " + code;' in s
    # the failing set is only committed after the exit code is known good
    assert s.index("onExited: code => {") < s.index("root.failing = out;")
    assert s.index("if (code !== 0) {") < s.index("root.failing = out;")
    assert "root.healthRetries = root.healthRetries + 1;" in s
    assert "if (root.healthRetries <= 3)" in s
    assert "id: healthRetry" in s
    assert "onTriggered: root.runHealthCheck()" in s


def test_schedule_transparency_run_now_and_disable():
    """Tasks, cadence, last attempt and per-task off switches are exposed."""
    s = load()
    assert "readonly property var schedule: [" in s
    assert '({ id: "trash", everyHours: 6 })' in s
    assert '({ id: "health", everyHours: 24 })' in s
    assert "property var disabled: ({})" in s
    assert "property real lastTrashRun: 0" in s
    assert "property real lastHealthRun: 0" in s
    assert "function runTrashSweep() {" in s
    assert "function runHealthCheck() {" in s
    assert "root.lastTrashRun = Date.now();" in s
    assert "root.lastHealthRun = Date.now();" in s
    assert "if (d.trashDays <= 0 || root.disabled.trash)" in s
    assert "if (root.disabled.health)" in s
    # both timers go through the run-now functions and honour the off switches
    assert "running: root.d.trashDays > 0 && !root.disabled.trash" in s
    assert "running: !root.disabled.health" in s
    assert s.count("onTriggered: root.runTrashSweep()") == 1
    assert s.count("onTriggered: root.runHealthCheck()") == 2  # daily + retry


def test_trash_cleanup_rejects_dot_names():
    """A crafted trashinfo name must never resolve rm -rf at the Trash dir."""
    s = load()
    cmd = s[s.index("sweep.command") : s.index("sweep.running = true")]
    guard = '[ -n "$b" ] && [ "$b" != "." ] && [ "$b" != ".." ] || continue;'
    assert guard in cmd
    assert cmd.index(guard) < cmd.index("rm -rf")
    assert "shortcut: a crafted ...trashinfo" in s
