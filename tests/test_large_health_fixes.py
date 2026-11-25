"""The large Health ("local-first fitness") upgrade.

No QML runtime exists in this container, so the shipped bindings and branches
are pinned as static assertions, as the other app-window suites do. The bridge
is driven for real: a log/import/history round trip on a temporary
XDG_DATA_HOME proves the journal survives on disk, and a fake shani_link proves
both the watch read and the no-watch degradation path.
"""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "health.py"
SERVICE = ROOT / "shani/Services/Health.qml"
WINDOW = ROOT / "shani/Modules/Health/HealthWindow.qml"
UI = ROOT / "shani/Common/Ui.qml"
SHELL = ROOT / "shani/shell.qml"
IDS_JS = ROOT / "shani/Services/ShellApps.js"
CLI = ROOT / "bin/shani"


def read(path):
    return Path(path).read_text(encoding="utf-8")


def bridge_module():
    spec = importlib.util.spec_from_file_location("health_bridge", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def cli(args, tmp_path):
    env = {**os.environ, "XDG_DATA_HOME": str(tmp_path)}
    return subprocess.run(
        [sys.executable, str(BRIDGE)] + args,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )


def answer(args, tmp_path):
    return json.loads(cli(args, tmp_path).stdout)


class FakeWatch:
    """Enough of shani_link for one summary and one measurement."""

    @staticmethod
    def health_summary(mac):
        return {
            "steps_today": {"steps": 9100, "distance_m": 6200, "calories": 410},
            "steps_yesterday": {"steps": 7100},
            "battery": 61,
            "step_goal": 12000,
            "device": {},
            "sleep_summary": {
                "asleep_minutes": 420,
                "deep_minutes": 90,
                "light_minutes": 330,
                "awake_minutes": 20,
            },
            "stress_today": [],
            "training": [
                {
                    "start": None,
                    "type": "Walk",
                    "active_seconds": 1500,
                    "steps": 2200,
                    "calories": 120,
                }
            ],
        }

    @staticmethod
    def measure(mac, what):
        return (72,) if what == "heart_rate" else (98,)


class FakeGatt:
    @staticmethod
    def paired():
        return [("AA:BB:CC:DD:EE:FF", "Fake Band")]

    @staticmethod
    def looks_like_low_energy(mac):
        return True


class FakePhones:
    @staticmethod
    def phones():
        return []


# ---- 1. graceful degradation is a real answer, not a crash ------------------


def test_no_shani_link_still_answers_with_the_local_journal(tmp_path, monkeypatch):
    h = bridge_module()
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    h.watch = h.moyoung = h.gatt = h.phone_bluez = None
    out = h.cmd_summary()
    assert h.NOT_INSTALLED in out["error"]
    assert out["steps_today"] == 0
    assert out["steps_week"] == [0] * 7
    assert out["sleep"] == {"deep": 0, "light": 0, "awake": 0, "rem": 0, "asleep": 0}
    assert out["workouts"] == [] and out["measures"] == []
    spot = h.cmd_spot("hr")
    assert spot["ok"] is False and h.NOT_INSTALLED in spot["error"]
    assert spot["value"] == []


def test_bridge_is_stdlib_only_and_uses_an_optional_import(tmp_path):
    source = read(BRIDGE)
    assert "import sqlite3" in source and "import json" in source
    assert "def _module(name: str):" in source
    assert '__import__(name, fromlist=["*"])' in source
    assert "XDG_DATA_HOME" in source and "health.sqlite3" in source
    for banned in ("import requests", "import urllib.request", "http://", "https://"):
        assert banned not in source, banned
    assert cli(["log"], tmp_path).returncode == 0


# ---- 2. log, history and workouts round trip through sqlite -----------------


def test_log_step_sleep_and_workout_persist_under_xdg_data_home(tmp_path):
    for args in (
        ["log", "step", "8123"],
        ["log", "sleep", "95", "260", "25"],
        ["log", "workout", "Run", "32", "4100", "300"],
    ):
        assert answer(args, tmp_path)["ok"] is True
    db = tmp_path / "shani-shell" / "health.sqlite3"
    assert db.is_file(), "the journal must be a local file, not a service"

    today = answer(["summary"], tmp_path)
    assert today["steps_today"] == 8123
    assert today["steps_week"][-1] == 8123
    assert today["sleep"]["deep"] == 95 and today["sleep"]["asleep"] == 355
    workouts = answer(["workouts"], tmp_path)
    assert workouts[0]["kind"] == "Run" and workouts[0]["minutes"] == 32
    assert workouts[0]["steps"] == 4100 and workouts[0]["source"] == "local"


def test_history_is_seven_zero_filled_days_oldest_first(tmp_path):
    rows = answer(["history", "7"], tmp_path)
    assert len(rows) == 7
    assert rows[-1]["day"] > rows[0]["day"]
    for key in ("day", "steps", "deep_min", "light_min", "awake_min", "rem_min"):
        assert key in rows[0]
    assert rows[0]["steps"] == 0
    assert answer(["log", "step", "5000"], tmp_path)["ok"]
    assert answer(["history", "7"], tmp_path)[-1]["steps"] == 5000


def test_invalid_logs_are_answered_not_exceptions(tmp_path):
    for args in (
        ["log"],
        ["log", "unknown"],
        ["log", "step"],
        ["log", "sleep", "1"],
        ["log", "workout", "Run"],
    ):
        out = answer(args, tmp_path)
        assert out["ok"] is False and out["error"]


# ---- 3. CSV / JSON import ---------------------------------------------------


def test_import_csv_and_json_into_the_same_journal(tmp_path):
    # days relative to today: "history 7" is the last week, so fixed dates rot
    import datetime
    d1 = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
    d2 = (datetime.date.today() - datetime.timedelta(days=2)).isoformat()
    csv = tmp_path / "days.csv"
    csv.write_text(
        "date,steps,deep,light,awake\n%s,6000,60,200,20\n" % d1, encoding="utf-8"
    )
    got = answer(["import", str(csv)], tmp_path)
    assert got["ok"] is True and got["imported"] == 1

    js = tmp_path / "health.json"
    js.write_text(
        json.dumps(
            {
                "days": [{"day": d2, "steps": 7000, "rem": 15}],
                "workouts": [{"day": d2, "kind": "Yoga", "minutes": 20}],
            }
        ),
        encoding="utf-8",
    )
    got = answer(["import", str(js)], tmp_path)
    assert got["ok"] is True and got["imported"] == 2

    by_day = {row["day"]: row for row in answer(["history", "7"], tmp_path)}
    assert by_day[d1]["steps"] == 6000
    assert by_day[d1]["deep_min"] == 60
    assert (
        by_day[d2]["steps"] == 7000 and by_day[d2]["rem_min"] == 15
    )
    assert any(w["kind"] == "Yoga" for w in answer(["workouts"], tmp_path))


def test_import_reports_bad_files_without_losing_data(tmp_path):
    assert answer(["import", str(tmp_path / "missing.json")], tmp_path)["ok"] is False
    bad = tmp_path / "bad.txt"
    bad.write_text("steps\n10\n", encoding="utf-8")
    assert "csv or .json" in answer(["import", str(bad)], tmp_path)["error"]
    broken = tmp_path / "broken.json"
    broken.write_text("{not json", encoding="utf-8")
    assert "bad JSON" in answer(["import", str(broken)], tmp_path)["error"]
    assert answer(["import"], tmp_path)["ok"] is False


# ---- 4. watch reads, when shani-link is there -------------------------------


def test_watch_summary_overrides_steps_and_merges_workouts(tmp_path, monkeypatch):
    h = bridge_module()
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    h.watch, h.moyoung, h.gatt, h.phone_bluez = (
        object(),
        FakeWatch,
        FakeGatt,
        FakePhones,
    )
    out = h.cmd_summary()
    assert out["error"] == "" and out["device"] == "Fake Band"
    assert out["steps_today"] == 9100 and out["steps_yesterday"] == 7100
    assert out["step_goal"] == 12000 and out["battery"] == 61
    assert out["sleep"]["deep"] == 90 and out["sleep"]["asleep"] == 420
    assert out["steps_week"][-1] == 9100 and out["steps_week"][-2] == 7100
    assert any(w["source"] == "watch" and w["kind"] == "Walk" for w in out["workouts"])


def test_spot_measurement_is_stored_locally(tmp_path, monkeypatch):
    h = bridge_module()
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    h.watch, h.moyoung, h.gatt, h.phone_bluez = (
        object(),
        FakeWatch,
        FakeGatt,
        FakePhones,
    )
    got = h.cmd_spot("hr")
    assert got["ok"] is True and got["value"] == [72] and got["unit"] == "bpm"
    assert h.cmd_measures()[0]["kind"] == "heart_rate"
    assert h.cmd_spot("nonsense")["ok"] is False


# ---- 5. service: every read and write goes through the bridge ---------------


def test_service_owns_the_bridge_and_queues_its_calls():
    s = read(SERVICE)
    assert "pragma Singleton" in s
    assert 'Quickshell.env("SHANI_HEALTH_TOOL")' in s
    assert 'ToolPath.of(Quickshell.env("SHANI_HEALTH_TOOL"), "health.py")' in s
    assert "function refresh() {" in s
    assert 'root.run("summary", []);' in s and 'root.run("history", ["7"]);' in s
    for fn in ("logStep", "logSleep", "logWorkout", "importFile", "spot"):
        assert "function %s(" % fn in s
    assert 'root.run("log", ["step"' in s
    assert 'root.run("log", ["sleep"' in s
    assert 'root.run("log", ["workout"' in s
    assert 'root.run("import", [String(path)])' in s
    assert 'root.run("spot", [String(kind || "hr")])' in s
    assert "job.running || root.busy" in s and "root.pending = root.pending.concat" in s
    assert 'job.command = ["python3", root.tool, what].concat(args);' in s
    assert "Component.onCompleted: refresh()" in s


def test_service_parses_each_answer_and_formats_readouts():
    s = read(SERVICE)
    for branch in (
        'what === "summary"',
        'what === "history"',
        'what === "log"',
        'what === "import"',
        'what === "spot"',
    ):
        assert branch in s
    assert "root.stepsWeek = Array.isArray(data && data.steps_week)" in s
    assert "root.history = Array.isArray(data) ? data : [];" in s
    assert 'Tr.t("Imported %1 entries", (data && data.imported) || 0)' in s
    assert "function dayLabel(day) {" in s
    assert "function duration(minutes) {" in s
    assert "function reading(item) {" in s
    assert 'root.error = (data && data.error) || "";' in s
    assert "root.loaded = true;" in s


# ---- 6. window: all the views, controls, states and AT names ----------------


def test_window_is_a_named_shell_app_bound_to_the_flag():
    w = read(WINDOW)
    assert 'appName: "Health"' in w
    assert "visible: Ui.health" in w and "onGone: Ui.health = false" in w
    assert "onVisibleChanged: if (visible) Health.refresh()" in w
    assert "Keys.onEscapePressed: Ui.health = false" in w


def test_window_shows_steps_sleep_workouts_trends_and_spot_checks():
    w = read(WINDOW)
    assert "Sparkline {" in w and "values: Health.stepsWeek" in w
    for label in (
        'Tr.t("Steps today")',
        'Tr.t("Steps this week")',
        'Tr.t("Sleep stages")',
        'Tr.t("Daily trend")',
        'Tr.t("Workouts")',
    ):
        assert label in w
    assert "model: win.hasJournal ? Health.history.slice().reverse() : []" in w
    assert "model: Health.workouts" in w
    assert 'Health.spot("hr")' in w and 'Health.spot("spo2")' in w
    assert "Health.reading(Health.measures[0])" in w
    assert "Health.duration(" in w


def test_window_logs_and_imports_without_a_watch():
    w = read(WINDOW)
    assert "Health.logStep(win.stepText)" in w
    assert "Health.logSleep(win.deepText, win.lightText, win.awakeText)" in w
    assert "Health.logWorkout(win.workoutKind, win.workoutMinutes)" in w
    assert 'filters: ["csv", "json"]' in w
    assert "Health.importFile(paths[0])" in w
    assert 'Tr.t("Log %1", modelData[1])' in w


def test_window_states_privacy_note_and_accessibility_names():
    w = read(WINDOW)
    assert (
        'Tr.t("Stays on this computer — no account, no cloud, nothing uploaded.")' in w
    )
    assert 'visible: Health.error !== ""' in w
    assert "visible: !win.hasJournal && !Health.busy" in w
    assert "visible: Health.workouts.length === 0" in w
    assert 'Tr.t("No history yet")' in w and 'Tr.t("No workouts yet")' in w
    assert "Accessible.role: Accessible.List" in w
    assert 'Accessible.name: Tr.t("Workouts")' in w
    assert w.count("Accessible.name:") >= 8
    assert w.count("Accessible.role: Accessible.StatusBar") >= 2


# ---- 7. full shell wiring ---------------------------------------------------


def test_one_ui_flag_and_a_lazy_window():
    u, sh = read(UI), read(SHELL)
    assert u.count("property bool health: false") == 1
    assert (
        'LazyLoader { active: Ui.health; source: "Modules/Health/HealthWindow.qml" }'
        in sh
    )
    assert WINDOW.is_file() and SERVICE.is_file()


def test_shell_ipc_and_state_key():
    sh = read(SHELL)
    assert "function healthOpen() { Ui.closeAll(); Ui.health = true; }" in sh
    assert "function healthClose() { Ui.health = false; }" in sh
    assert "healthShown: Ui.health" in sh
    assert "healthSteps: Health.stepsToday" in sh


def test_desktop_entry_and_window_title_id_agree():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(CLI))
    cli_mod = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("shani_cli", loader)
    )
    loader.exec_module(cli_mod)
    spec = cli_mod.APPS["health"]
    assert spec[0] == "dev.shani.Health"
    assert spec[1] == "Health"
    assert spec[6] == ["healthOpen"] and spec[8] == "healthShown"
    import re

    ids = json.loads(re.search(r"var ids = (\{.*?\});", read(IDS_JS), re.S).group(1))
    assert ids["Health"] == "dev.shani.Health"
    assert ids == {v[1]: v[0] for v in cli_mod.APPS.values()}
