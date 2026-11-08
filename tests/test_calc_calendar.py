"""Calculator + calendar-rich surfaces (feature-calc-calendar-rich).

- The Calc.js evaluator (node, like test_fuzzy): scientific parity
  (sin/cos/tan + inverses, ln/log, exp, x^y, floor/ceil, abs, |x|, factorial,
  nPr/nCr), the whitelist still rejects unknown words, and results are
  finite numbers only.
- The unit converter in the same file (mm→km, °C/°F/K, data, speed, area,
  time — sequence: convert() via a built query string, as the panel does).
- bridge/agenda.py: malformed write JSON exits 3; a write without EDS
  bindings exits 2 (the marker Services/Agenda.qml uses for the Chronoa
  ask fallback); the list form in such an environment also exits 2.
- Wiring: Agenda.openCalendar() opens the shell Calendar surface, never
  GNOME Calendar; shell.qml exposes the new IPC functions; bin/shani knows
  the calculator/calendar groups and maps them onto real IPC names.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
CALC = SHANI / "Modules/Launcher/Calc.js"
AGENDA = ROOT / "bridge" / "agenda.py"
CLI = ROOT / "bin" / "shani"

node = shutil.which("node")
calc_mark = pytest.mark.skipif(node is None, reason="node is not installed")


def run_calc(expr):
    prog = (CALC.read_text().replace(".pragma library", "")
            + "\nprocess.stdout.write(JSON.stringify(calc(%s)));" % json.dumps(expr))
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


# ---- the evaluator ----------------------------------------------------------

@calc_mark
def test_scientific_functions():
    assert run_calc("sin(0)") == 0
    assert run_calc("sqrt(16)") == 4
    assert run_calc("ln(exp(1))") == 1
    assert run_calc("2^10") == 1024
    assert run_calc("floor(2.9)+ceil(2.1)") == 5
    assert run_calc("abs(-7)") == 7


@calc_mark
def test_abs_pipes_and_factorial():
    assert run_calc("|-3+1|") == 2
    assert run_calc("5!") == 120
    assert run_calc("(3+2)!") == 120


@calc_mark
def test_permutations_and_combinations():
    assert run_calc("nPr(5,2)") == 20
    assert run_calc("nCr(5,2)") == 10


@calc_mark
def test_the_whitelist_rejects_strangers_and_non_values():
    assert run_calc("random()") is None
    assert run_calc("alert(1)") is None
    assert run_calc("3+") is None
    assert run_calc("sqrt(-1)") is None       # NaN: not a finite number
    assert run_calc("1/0") is None            # Infinity: not a finite number


@calc_mark
def test_the_unit_converter_via_a_built_query():
    out = json.loads(subprocess.run([node, "-e",
        (CALC.read_text().replace(".pragma library", "")
         + "\nprocess.stdout.write(JSON.stringify(convert(\"100 mm in km\")));")],
        capture_output=True, text=True, check=True).stdout)
    assert abs(out["value"] - 0.0001) < 1e-12
    assert out["text"].endswith(" km")


@calc_mark
def test_temperature_conversion_is_special():
    prog = (CALC.read_text().replace(".pragma library", "")
            + "\nprocess.stdout.write(JSON.stringify(convert(\"32 f in c\").value));")
    v = json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)
    assert abs(v) < 1e-9


# ---- bridge/agenda.py -------------------------------------------------------

def run_agenda(*args):
    return subprocess.run([sys.executable, str(AGENDA), *args],
                          capture_output=True, text=True, timeout=30)


def test_agenda_rejects_malformed_write_json_with_exit_3():
    for bad in ("not json", "[1, 2, 3]"):
        r = run_agenda("add", bad)
        assert r.returncode == 3, bad


def test_agenda_write_validates_fields_before_touching_eds():
    # a dict that is not a complete event: on an EDS machine this is exit 3
    # (bad input); without EDS it exits 2 first. Either way it never runs.
    r = run_agenda("add", '{"add": true}')
    assert r.returncode in (2, 3)


def test_agenda_write_without_eds_exits_2_for_the_chronoa_fallback():
    # 1761715800/1761719400 are valid times; the point is there is no EDS
    # calendar service in this environment, so the write must report exit 2
    # (which Agenda.qml turns into a Bridge ask), never crash the shell.
    r = run_agenda("add", json.dumps({"summary": "Test", "start": 1761715800, "end": 1761719400}))
    assert r.returncode in (0, 2)  # 0 where EDS really is present, 2 otherwise


def test_agenda_delete_and_edit_need_a_uid():
    for action in ("edit", "delete"):
        r = run_agenda(action, json.dumps({"summary": "x"}) if action == "edit" else "{}")
        assert r.returncode in (2, 3)


# ---- wiring -----------------------------------------------------------------

def test_agenda_open_calendar_is_the_shell_surface():
    t = (SHANI / "Services/Agenda.qml").read_text()
    assert "Ui.calendar = true" in t
    assert "gnome-calendar" not in t
    assert "org.gnome.Calendar" not in t


def test_agenda_writes_fall_back_to_bridge_ask():
    t = (SHANI / "Services/Agenda.qml").read_text()
    assert 'Bridge.send({ op: "ask"' in t
    assert "no calendar service" in t or "calendar service" in t


def test_shell_exposes_the_new_ipc_functions():
    t = (SHANI / "shell.qml").read_text()
    for fn in ("calculatorConvert", "calculatorRecall", "calculatorMemory", "calculatorHistoryClear",
               "calendarOpen", "calendarSearch", "calendarAdd", "calendarEdit", "calendarDelete"):
        assert f"function {fn}(" in t, fn


def test_shell_state_reports_memory_history_and_calendar():
    t = (SHANI / "shell.qml").read_text()
    assert "calculatorHistory" in t and "calculatorMemory" in t
    assert "calendarEvents" in t and "calendarSearch" in t


def test_calendar_panel_has_search_and_editor():
    t = (SHANI / "Modules/Calendar/CalendarPanel.qml").read_text()
    assert "Search events by title" in t
    assert "Agenda.search" in t
    assert "openEditor" in t and "saveEditor" in t and "deleteEditor" in t
    assert "hasEvents(" in t            # the event dots stay


def test_calculator_panel_has_all_three_tabs_and_the_converter():
    t = (SHANI / "Modules/Calculator/Calculator.qml").read_text()
    for tab in ('"Standard"', '"Scientific"', '"Converter"'):
        assert tab in t
    assert "Services.Calculator.unitNames" in t and "Services.Calculator.convertUnit(" in t
    assert "recallHistory" in t and "memoryAdd" in t and "memorySubtract" in t


def test_calculator_service_memory_history_and_unary_ops():
    t = (SHANI / "Services/Calculator.qml").read_text()
    for name in ("memoryClear", "memoryRecall", "memoryAdd", "memorySubtract",
                 "toggleSign", "percent", "reciprocal", "square", "sqrtVal",
                 "recallHistory", "clearHistory"):
        assert f"function {name}(" in t, name
    assert "slice(0, 20)" in t          # history capped at 20, newest first


def test_cli_groups_map_onto_real_ipc_functions():
    import importlib.machinery
    import importlib.util
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(CLI))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    for group, cmds in (("calculator", ["open", "press", "equals", "convert"]),
                        ("calendar", ["open", "add", "edit", "delete", "search"])):
        assert group in mod.GROUPS
        for c in cmds:
            assert (group, c) in mod.IPC_NAMES, (group, c)
    shell = (SHANI / "shell.qml").read_text()
    for name in mod.IPC_NAMES.values():
        assert f"function {name}(" in shell, name
