"""Hardware sensors in the System Monitor: the bridge and the two QML hooks.

The bridge is exercised for real against a fake hwmon tree (no live hardware,
no root): a subprocess with SHANI_HWMON_ROOT pointed at tmp_path reads exactly
the sysfs files it would read on a machine, so parsing, unit conversion,
labelling, severity and unreadable files are all covered here. The QML is
pinned statically because it needs a live shell to render.
"""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge/sensors.py"
SERVICE = "shani/Services/Sensors.qml"
PROCESSES = "shani/Modules/Processes/Processes.qml"
_spec = importlib.util.spec_from_file_location("sensors", BRIDGE)
sensors = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sensors)


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def run(root):
    """Run the real bridge with its sysfs root redirected to a test tree."""
    env = dict(os.environ, SHANI_HWMON_ROOT=str(root))
    out = subprocess.run(
        [sys.executable, str(BRIDGE)],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def fake_tree(tmp_path):
    """Two chips, a fallback name, a garbage input and an unreadable one."""
    a = tmp_path / "hwmon0"
    a.mkdir()
    (a / "name").write_text("coretemp\n")
    (a / "temp1_input").write_text("54000\n")
    (a / "temp1_label").write_text("Package id 0\n")
    (a / "temp1_max").write_text("85000\n")
    (a / "temp1_crit").write_text("95000\n")
    (a / "temp2_input").write_text("96000\n")
    (a / "temp2_max").write_text("85000\n")
    (a / "temp2_crit").write_text("95000\n")
    (a / "fan1_input").write_text("1200\n")
    (a / "fan1_label").write_text("CPU fan\n")
    b = tmp_path / "hwmon1"
    b.mkdir()
    (b / "name").write_text("atk0110\n")
    (b / "in0_input").write_text("1200\n")
    (b / "in0_max").write_text("1350\n")
    (b / "in0_crit_max").write_text("1400\n")
    (b / "in1_input").write_text("not-a-number\n")
    c = tmp_path / "hwmon2"  # no name file: chip name falls back to the dir
    c.mkdir()
    (c / "temp3_input").write_text("41000\n")
    (c / "temp4_input").mkdir()  # a directory cannot be read as a sysfs value
    return a, b, c


# ---- the bridge ------------------------------------------------------------


def test_parses_inputs_with_display_units_and_thresholds(tmp_path):
    fake_tree(tmp_path)
    got = run(tmp_path)
    by_label = {s["label"]: s for s in got}
    assert len(got) == 5  # temp1/temp2/fan1/in0/temp3; garbage and unreadable skipped

    t = by_label["Package id 0"]
    assert (t["name"], t["type"], t["unit"]) == ("coretemp", "temp", "°C")
    assert t["value"] == 54.0 and t["max"] == 85.0 and t["crit"] == 95.0
    assert t["level"] == 0

    v = by_label["Voltage 0"]  # no in0_label file: sysfs index is the fallback
    assert (v["name"], v["type"], v["unit"]) == ("atk0110", "in", "V")
    assert v["value"] == 1.2 and v["max"] == 1.35 and v["crit"] == 1.4

    f = by_label["CPU fan"]
    assert (f["type"], f["value"], f["unit"]) == ("fan", 1200, "RPM")
    assert f["max"] == 0 and f["crit"] == 0  # fan limits are not danger highs

    chip = by_label["Temperature 3"]  # no temp3_label file
    assert chip["name"] == "hwmon2"
    # chips with no limit files get conservative temperature defaults
    assert chip["max"] == 80.0 and chip["crit"] == 95.0


def test_severity_is_amber_at_max_and_red_at_crit(tmp_path):
    fake_tree(tmp_path)
    got = {s["label"]: s for s in run(tmp_path)}
    assert got["Package id 0"]["level"] == 0  # 54 < 85 < 95
    assert got["Temperature 3"]["level"] == 0  # 41 °C, below the fallback 80/95
    # 96 °C: past both the 85 °C max and the 95 °C crit
    assert got["Temperature 2"]["level"] == 2


def test_severity_function_boundaries():
    assert sensors.severity(84.9, 85, 95) == 0
    assert sensors.severity(85, 85, 95) == 1
    assert sensors.severity(94.9, 85, 95) == 1
    assert sensors.severity(95, 85, 95) == 2
    assert sensors.severity(120, 0, 0) == 0  # no advertised limit


def test_row_shape_is_exactly_what_the_qml_expects(tmp_path):
    fake_tree(tmp_path)
    row = run(tmp_path)[0]
    assert set(row) == {
        "name",
        "label",
        "value",
        "unit",
        "type",
        "max",
        "crit",
        "level",
    }


def test_missing_tree_and_empty_tree_are_honest_empty_lists(tmp_path):
    assert run(tmp_path / "does-not-exist") == []
    (tmp_path / "hwmon0").mkdir()
    (tmp_path / "hwmon0" / "name").write_text("empty\n")
    assert run(tmp_path) == []


def test_non_directory_hwmon_entry_is_skipped(tmp_path):
    a = tmp_path / "hwmon0"
    a.mkdir()
    (a / "name").write_text("good\n")
    (a / "temp1_input").write_text("42000\n")
    # a file where the hwmon directory should be: listdir-type failures are
    # swallowed, and one good chip still reports
    (tmp_path / "hwmon1").write_text("not a chip\n")
    got = run(tmp_path)
    assert len(got) == 1 and got[0]["value"] == 42.0


# ---- the QML hooks ---------------------------------------------------------


def test_service_is_gated_and_exposes_the_promised_api():
    q = read(SERVICE)
    assert "pragma Singleton" in q
    assert (
        'Quickshell.env("SHANI_SENSORS_TOOL") || "/usr/lib/shani-shell/sensors.py"' in q
    )
    assert "property bool wanted: Ui.processes" in q
    assert "property var sensors: []" in q
    assert "property bool loading: false" in q
    assert "property bool answered: false" in q
    assert 'property string error: ""' in q
    assert "function refresh()" in q
    assert 'command: ["python3", root.tool]' in q
    assert "JSON.parse(text)" in q
    # one bounded tick, only while wanted — no idle poller
    assert "readonly property int interval: 3000" in q
    assert "running: root.wanted" in q
    assert "triggeredOnStart: true" in q
    assert "Component.onCompleted" not in q


def test_processes_has_a_sensors_section_below_the_overview():
    p = read(PROCESSES)
    # the earlier overview / disk row and the concurrent network-usage section
    # must survive: this wave only adds a section below them
    # the overview label is translated (Tr.t) but the key stays the same
    assert "System overview" in p
    assert 'Tr.t("Disk I/O")' in p and "SysStats.diskReadRate" in p
    assert 'text: Tr.t("Network usage")' in p
    assert 'text: Tr.t("Sensors")' in p
    assert "model: Sensors.sensors" in p
    assert 'Tr.t("No hardware sensors found.")' in p
    assert "Sensors.answered && Sensors.error" in p
    assert 'Tr.t("Severity: %1"' in p
    assert 'Tr.t("Critical")' in p
    assert "°C · voltages in V · fans in RPM" in p
    # a long hwmon list must not push the process tree off the window
    assert "Theme.px(120)" in p and "contentHeight: sensorRows.implicitHeight" in p
    assert "Theme.red" in p and "Theme.amber" in p
    assert "Accessible.name" in p
    # no opaque card around the new rows
    assert "Sensors.surface" not in p


def test_every_sensor_string_has_a_template_key():
    template = json.loads(
        (ROOT / "shani/i18n/template.json").read_text(encoding="utf-8")
    )
    for key in (
        "Sensors",
        "Hardware sensors",
        "Sensor",
        "Sensor %1",
        "Severity: %1",
        "%1 %2, %3",
        "No hardware sensors found.",
        "Reading sensors…",
        "Critical",
        "Near maximum",
        "Temperatures in °C · voltages in V · fans in RPM · amber at maximum, red at critical",
    ):
        assert key in template, key
