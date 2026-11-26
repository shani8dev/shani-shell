"""The watch actions exposed by bridge/health.py and driven from the shell.

The bridge keeps one call to the watch's owner (or its stand-in) and returns
plain data; the QML only owns the words. The stand-in takes the same verbs and
values as bridge/phone/watch.py and refuses the same bad ones.
"""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "health.py"
FAKE = ROOT / "dev" / "fake-watch.py"
SERVICE = ROOT / "shani" / "Services" / "Health.qml"
WINDOW = ROOT / "shani" / "Modules" / "Health" / "HealthWindow.qml"


def module():
    spec = importlib.util.spec_from_file_location("health_watch_actions", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Recorder:
    def __init__(self):
        self.calls = []

    def run(self, arguments):
        self.calls.append(arguments)
        return "the watch answered"


def stand_in(tmp_path):
    watch = tmp_path / "fake-watch.json"
    log = tmp_path / "actions.jsonl"
    env = {
        **os.environ,
        "XDG_DATA_HOME": str(tmp_path),
        "SHANI_WATCH_FAKE": str(watch),
        "SHANI_WATCH_ACTION_TOOL": str(FAKE),
        "SHANI_WATCH_ACTION_LOG": str(log),
    }
    subprocess.run(
        [sys.executable, str(FAKE), "seed"],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    return env, watch, log


def cli(args, env):
    proc = subprocess.run(
        [sys.executable, str(BRIDGE)] + args,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


def fake(args, env):
    return subprocess.run(
        [sys.executable, str(FAKE)] + args,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


def rows(log):
    return [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()]


# ---- the plain functions pass the exact arguments to the one owner ----------


def test_plain_functions_call_the_watch_engine_with_exact_arguments(monkeypatch):
    h = module()
    recorder = Recorder()
    monkeypatch.setattr(h, "watch", recorder)
    monkeypatch.delenv("SHANI_WATCH_ACTION_TOOL", raising=False)

    assert h.cmd_sync_time() == {
        "ok": True,
        "error": "",
        "note": "the watch answered",
        "settings": {},
    }
    assert recorder.calls[-1] == {"action": "sync_time"}

    assert h.cmd_watch_settings()["ok"] is True
    assert recorder.calls[-1] == {"action": "settings"}

    assert h.cmd_watch_set("raise to wake", "ON")["ok"] is True
    assert recorder.calls[-1] == {
        "action": "set",
        "setting": "raise_to_wake",
        "value": "on",
    }

    assert h.cmd_watch_notify("Hello there")["ok"] is True
    assert recorder.calls[-1] == {
        "action": "notify",
        "text": "Hello there",
        "kind": "other",
        "sender": "Health",
    }

    assert h.cmd_watch_profile("170", "68", "41", "female")["ok"] is True
    assert recorder.calls[-1] == {
        "action": "profile",
        "height_cm": 170,
        "weight_kg": 68,
        "age": 41,
        "gender": "female",
    }
    assert len(recorder.calls) == 5


def test_bridge_refuses_incomplete_or_wrongly_typed_arguments(monkeypatch):
    h = module()
    recorder = Recorder()
    monkeypatch.setattr(h, "watch", recorder)
    monkeypatch.delenv("SHANI_WATCH_ACTION_TOOL", raising=False)

    assert h.cmd_watch_set("", "")["ok"] is False
    assert h.cmd_watch_notify("")["ok"] is False
    assert h.cmd_watch_profile("", "70", "40", "female")["ok"] is False
    assert h.cmd_watch_profile("abc", "70", "40", "female")["ok"] is False
    assert h.cmd_watch_profile("0", "70", "40", "female")["ok"] is False
    assert recorder.calls == []  # nothing was sent to the watch


def test_no_watch_reports_honestly_without_raising(monkeypatch):
    h = module()
    monkeypatch.setattr(h, "watch", None)
    monkeypatch.delenv("SHANI_WATCH_ACTION_TOOL", raising=False)
    for answer in (
        h.cmd_sync_time(),
        h.cmd_watch_settings(),
        h.cmd_watch_set("a", "b"),
    ):
        assert answer["ok"] is False and h.NOT_INSTALLED in answer["error"]
        assert answer["settings"] == {}


# ---- the stand-in answers deterministically and logs exact argv -------------


def test_stand_in_records_exact_argv_and_changes_state(tmp_path):
    env, watch, log = stand_in(tmp_path)

    assert cli(["sync-time"], env)["note"] == "The watch clock was set."
    assert rows(log)[0]["action"] == "sync_time" and rows(log)[0]["args"] == []

    saved = cli(["watch-set", "raise_to_wake", "on"], env)
    assert saved["ok"] is True
    assert rows(log)[-1] == {
        "action": "set",
        "args": ["raise_to_wake", "on"],
        "settings": {**json.loads(watch.read_text())["settings"]},
    }
    assert json.loads(watch.read_text())["settings"]["raise_to_wake"] == "on"

    read = cli(["watch-settings"], env)
    assert "raise_to_wake: on" in read["note"]
    assert read["settings"]["raise_to_wake"] == "on"

    assert cli(["watch-notify", "Hello from this computer"], env)["ok"] is True
    assert rows(log)[-1]["action"] == "notify"
    assert rows(log)[-1]["args"] == ["Hello from this computer", "other", "Health"]

    assert cli(["watch-profile", "170", "68", "41", "female"], env)["ok"] is True
    assert rows(log)[-1]["action"] == "profile"
    assert rows(log)[-1]["args"] == ["170", "68", "41", "female"]


def test_stand_in_refuses_the_same_verbs_and_values_as_the_engine(tmp_path):
    env, _watch, log = stand_in(tmp_path)
    for words, why in (
        (["sleep"], "action must be one of"),
        (["set", "raise_to_wake"], "set needs a setting and a value"),
        (["set", "raise_to_wake", "perhaps"], "must be on or off"),
        (["set", "time_format", "24-hour"], "must be one of"),
        (["set", "nonsense", "on"], "unknown setting"),
        (["notify"], "notify needs text"),
        (["profile", "170", "68", "40"], "profile needs"),
        (["profile", "a", "68", "40", "female"], "must be numbers"),
        (["measure", "temperature"], "what must be"),
    ):
        proc = fake(["action"] + words, env)
        assert proc.returncode == 2, words
        assert why in json.loads(proc.stdout)["error"], words
    assert not log.exists()  # nothing was recorded

    # the same refusal comes back through the bridge, as data not an exception
    got = cli(["watch-set", "raise_to_wake", "perhaps"], env)
    assert got["ok"] is False and "must be on or off" in got["error"]
    assert not log.exists()


# ---- the service and window wire every action -------------------------------


def test_service_wires_every_watch_action():
    s = SERVICE.read_text(encoding="utf-8")
    for fn in (
        "watchSyncTime",
        "watchSettings",
        "watchSet",
        "watchNotify",
        "watchProfile",
    ):
        assert "function %s(" % fn in s, fn
    for call in (
        'root.run("sync-time", [])',
        'root.run("watch-settings", [])',
        'root.run("watch-set", [String(setting || ""), String(value || "")])',
        'root.run("watch-notify", [String(text || "")])',
        'root.run("watch-profile"',
    ):
        assert call in s, call
    for branch in (
        'what === "watch-settings"',
        'what === "sync-time" || what === "watch-set"',
    ):
        assert branch in s, branch
    assert "property string watchNote" in s and "property var watchSettingsData" in s


def test_window_has_two_columns_and_keeps_every_named_card():
    w = WINDOW.read_text(encoding="utf-8")
    assert "GridLayout {" in w and "columns: 2" in w
    assert "columnSpacing: Theme.px(10)" in w and "rowSpacing: Theme.px(10)" in w
    # widths come from the grid, not from a content-sized Flow
    assert w.count("Layout.preferredWidth: 0") >= 10
    for name in (
        "health-watch-header",
        "health-activity",
        "health-stress",
        "health-loading",
        "health-no-watch",
        "health-error",
        "health-note",
    ):
        assert 'objectName: "%s"' % name in w, name
    assert w.count("Layout.columnSpan: 2") >= 6  # ring, week, spot, forms, controls
    assert 'objectName: "health-activity"' in w
    assert 'objectName: "health-stress"' in w


def test_window_offers_every_watch_action_with_plain_names():
    w = WINDOW.read_text(encoding="utf-8")
    for label in (
        "Set the watch's time",
        "Read watch settings",
        "Find my watch",
        "Send a test message",
        "Send my profile",
        "Raise to wake",
    ):
        assert 'Tr.t("%s")' % label in w, label
    for call in (
        "Health.watchSyncTime()",
        "Health.watchSettings()",
        "Health.watchSet(",
        "Health.watchNotify(",
        "Health.watchProfile(",
    ):
        assert call in w, call
    assert 'accessibleName: Tr.t("Set raise to wake %1", modelData[1])' in w
    assert 'Tr.t("Hello from this computer")' in w
    for banned in ("ShaniOS", "Da Fit", "Wear OS"):
        assert banned not in w, banned
