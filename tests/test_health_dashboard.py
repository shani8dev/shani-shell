"""The watch dashboard: structured data from a stand-in watch, all local.

The bridge is run for real against a temporary XDG_DATA_HOME and a fake watch
file. The QML has no runtime here, so its bindings are pinned as static
assertions, the way the other Health and app-window suites pin theirs.
"""

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


def module():
    spec = importlib.util.spec_from_file_location("health_dashboard_bridge", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def cli(args, tmp_path, watch_file=None):
    env = {**os.environ, "XDG_DATA_HOME": str(tmp_path)}
    env.pop("SHANI_WATCH_FAKE", None)
    if watch_file is not None:
        env["SHANI_WATCH_FAKE"] = str(watch_file)
    return subprocess.run(
        [sys.executable, str(BRIDGE)] + args,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )


def answer(args, tmp_path, watch_file=None):
    proc = cli(args, tmp_path, watch_file)
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


FAKE = {
    "device": "FB BGS002",
    "device_model": "MOYOU-BGS2",
    "device_firmware": "1.7.4",
    "last_read": "2026-11-26T09:32:00+05:30",
    "connected": True,
    "distance_m": 4380,
    "calories": 231,
    "battery": 64,
    "sleep_stages": [
        {"stage": "light", "minutes": 217},
        {"stage": "deep", "minutes": 103},
        {"stage": "light", "minutes": 60},
        {"stage": "awake", "minutes": 10},
    ],
    "stress_series": [
        {"when": "2026-11-26T09:00:00", "value": 18},
        {"when": "2026-11-26T09:30:00", "value": 29},
    ],
}


# ---- the bridge: structured fields, no upload -------------------------------


def test_summary_merges_a_stand_in_watch_without_touching_the_journal(tmp_path):
    watch = tmp_path / "fake-watch.json"
    watch.write_text(json.dumps(FAKE), encoding="utf-8")
    assert answer(["log", "step", "6240"], tmp_path, watch)["ok"] is True

    out = answer(["summary"], tmp_path, watch)
    for key in (
        "device_model",
        "device_firmware",
        "last_read",
        "connected",
        "distance_m",
        "calories",
        "sleep_stages",
        "stress_series",
    ):
        assert key in out, key
    assert out["device_model"] == "MOYOU-BGS2"
    assert out["device_firmware"] == "1.7.4"
    assert out["last_read"] == FAKE["last_read"]
    assert out["connected"] is True
    assert out["distance_m"] == 4380 and out["calories"] == 231
    assert out["sleep_stages"][1] == {"stage": "deep", "minutes": 103}
    assert out["stress_series"][-1] == {"when": "2026-11-26T09:30:00", "value": 29}
    # the local journal and every older field survive the overlay
    assert out["steps_today"] == 6240
    assert len(out["steps_week"]) == 7 and len(out["history"]) == 7
    assert "workouts" in out and "measures" in out and "sleep" in out

    source = BRIDGE.read_text(encoding="utf-8")
    for banned in ("requests", "urllib", "http://", "https://"):
        assert banned not in source, banned


def test_summary_without_a_fake_reports_honest_empty_values(tmp_path, monkeypatch):
    h = module()
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    monkeypatch.delenv("SHANI_WATCH_FAKE", raising=False)
    h.watch = h.moyoung = h.gatt = h.phone_bluez = None
    out = h.cmd_summary()
    assert out["connected"] is False
    assert out["device_model"] == "" and out["device_firmware"] == ""
    assert out["last_read"] == ""
    assert out["distance_m"] == 0 and out["calories"] == 0
    assert out["sleep_stages"] == [] and out["stress_series"] == []


def test_an_unreadable_fake_is_ignored_not_raised(tmp_path, monkeypatch):
    h = module()
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    h.watch = h.moyoung = h.gatt = h.phone_bluez = None
    broken = tmp_path / "watch.json"
    broken.write_text("{not json", encoding="utf-8")
    monkeypatch.setenv("SHANI_WATCH_FAKE", str(broken))
    out = h.cmd_summary()
    assert out["connected"] is False and out["device_model"] == ""
    monkeypatch.setenv("SHANI_WATCH_FAKE", str(tmp_path / "missing.json"))
    assert h.cmd_summary()["connected"] is False


def test_watch_connect_writes_the_fake_and_the_phone_setting(tmp_path, monkeypatch):
    watch = tmp_path / "fake-watch.json"
    watch.write_text(json.dumps(FAKE), encoding="utf-8")
    saved = []
    settings = type(
        "Settings",
        (),
        {"set_bool": staticmethod(lambda key, value: saved.append((key, value)))},
    )

    h = module()
    monkeypatch.setenv("SHANI_WATCH_FAKE", str(watch))
    monkeypatch.setattr(
        h, "_module", lambda name: type("Mod", (), {"Settings": settings})
    )

    assert h.cmd_watch_connect("off") == {"ok": True, "error": "", "connected": False}
    assert json.loads(watch.read_text())["connected"] is False
    assert saved == [("watch-companion-enabled", False)]

    assert h.cmd_watch_connect("state")["connected"] is False
    assert h.cmd_watch_connect("on")["connected"] is True
    assert json.loads(watch.read_text())["connected"] is True
    assert saved[-1] == ("watch-companion-enabled", True)
    assert h.cmd_watch_connect("perhaps")["ok"] is False


def test_watch_connect_works_without_a_fake_or_a_phone(tmp_path, monkeypatch):
    h = module()
    monkeypatch.delenv("SHANI_WATCH_FAKE", raising=False)
    monkeypatch.setattr(h, "_module", lambda name: None)
    assert h.cmd_watch_connect("on") == {"ok": True, "error": "", "connected": True}
    assert h.cmd_watch_connect("state")["connected"] is False


# ---- the service: the window never reads a bridge itself --------------------


def test_service_parses_the_new_fields_and_runs_watch_connect():
    s = SERVICE.read_text(encoding="utf-8")
    assert 'Quickshell.env("SHANI_FITNESS_TOOL")' in s
    for name in (
        "deviceModel",
        "deviceFirmware",
        "lastRead",
        "connected",
        "distanceM",
        "calories",
        "sleepStages",
        "stressSeries",
    ):
        assert "property" in s and name in s, name
    for key in (
        "device_model",
        "device_firmware",
        "last_read",
        "connected",
        "distance_m",
        "calories",
        "sleep_stages",
        "stress_series",
    ):
        assert key in s, key
    assert "function watchConnect(on) {" in s
    assert 'root.run("watch-connect", [on ? "on" : "off"]);' in s
    assert 'what === "watch-connect"' in s
    assert "watch-companion-enabled" not in s  # the bridge owns that key


# ---- the window: a dashboard, a switch and a way forward --------------------


def test_window_draws_the_watch_header_activity_sleep_and_stress():
    w = WINDOW.read_text(encoding="utf-8")
    assert 'objectName: "health-watch-header"' in w
    assert "Health.deviceModel" in w and "Health.deviceFirmware" in w
    assert "Health.lastRead" in w and "Health.battery" in w
    assert "activityRing" in w and "ctx.arc" in w and "Theme.success" in w
    assert 'Tr.t("Activity")' in w
    assert "2 days ago" in w and "Yesterday" in w and "Today" in w
    assert "Health.sleepStages" in w and "Theme.blue" in w and "Theme.amber" in w
    assert "Health.stressSeries" in w and "Sparkline {" in w
    assert 'objectName: "health-stress"' in w


def test_window_offers_a_switch_and_an_empty_state_without_a_watch():
    w = WINDOW.read_text(encoding="utf-8")
    assert "SwitchRow {" in w
    assert 'Tr.t("Keep my watch connected to this computer")' in w
    assert "Health.watchConnect(value)" in w
    assert 'objectName: "health-no-watch"' in w
    assert 'Tr.t("No watch yet")' in w
    assert "Connect a watch" in w
    assert "health-no-watch" in w and "!win.hasWatch && !win.hasJournal" in w


def test_window_keeps_the_existing_log_checks_and_privacy_words():
    w = WINDOW.read_text(encoding="utf-8")
    assert (
        'Tr.t("Stays on this computer — no account, no cloud, nothing uploaded.")' in w
    )
    assert 'Tr.t("Find my watch")' in w and "Health.findWatch()" in w
    assert 'Health.spot("hr")' in w and 'Health.spot("spo2")' in w
    assert "Health.logStep(win.stepText)" in w
    assert "Health.logSleep(win.deepText, win.lightText, win.awakeText)" in w
    assert "Health.logWorkout(win.workoutKind, win.workoutMinutes)" in w
    assert w.count("Accessible.name:") >= 8
    # labels are plain words: no other product's app name
    for banned in ("Da Fit", "Wear OS", "Google Fit", "Health Connect"):
        assert banned not in w, banned
