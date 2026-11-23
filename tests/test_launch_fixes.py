"""Static checks for launch/launcher-entry gaps found by reading the two
Services singletons and their bridge (not listed in docs/GAPS*.md).

These singletons need a running shell to exercise, so each test asserts the
source carries the exact wiring rather than driving QML.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_launch_reports_bridge_failures():
    s = read("shani/Services/Launch.qml")
    # the bridge prints {"ok":false,"error":...}; execDetached dropped it
    assert "import Quickshell.Io" in s
    assert "id: runner" in s and "stdout: SplitParser" in s
    assert "d.ok === false" in s
    assert '"notify-send", "-a", "Shani", "-i", "dialog-warning"' in s
    assert "Quickshell.execDetached(argv.concat(o.files || []))" not in s


def test_launch_swallows_a_double_click():
    s = read("shani/Services/Launch.qml")
    assert "property var lastLaunch: ({})" in s
    assert "const key = id +" in s and "Date.now()" in s
    assert "now - root.lastLaunch[key] < 500" in s
    assert "a double click is not a second app" in s


def test_launch_options_are_validated_before_persisting():
    s = read("shani/Services/Launch.qml")
    assert '["auto", "discrete", "default"].indexOf(o.gpu) >= 0' in s
    assert 'typeof o.env === "string" && o.env.trim()' in s
    assert 'typeof o.args === "string" && o.args.trim()' in s
    assert "if (Object.keys(clean).length) all[id] = clean; else delete all[id];" in s


def test_launcher_entries_drop_stale_data_when_the_bridge_dies():
    s = read("shani/Services/LauncherEntries.qml")
    exit_block = s.split("onExited: {", 1)[1].split("\n        }", 1)[0]
    assert "root.ready = false" in exit_block
    assert "root.entries = {}" in exit_block
    assert "retry.start()" in exit_block
    assert exit_block.index("root.entries = {}") < exit_block.index("retry.start()")


def test_launcher_entries_ignore_malformed_and_unknown_fields():
    s = read("shani/Services/LauncherEntries.qml")
    assert 'if (!d || typeof d !== "object") return;' in s
    assert 'String(d.app || "").toLowerCase()' in s
    assert '"progressVisible", "urgent"' in s
    assert "Object.assign({}, m[k] || {}, d)" not in s
