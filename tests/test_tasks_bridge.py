"""bridge/tasks.py: the to-do list behind the Tasks app.

Evolution Data Server is not in the test image, so what is pinned here is the
part that does not need it: the repeat sidecar (which rule each task has, and
how a rule is stopped), and the command line's answers when there is no task
service at all — an empty list and exit 2, never a traceback.
"""

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import tasks  # noqa: E402


@pytest.fixture
def repeats(tmp_path, monkeypatch):
    """A sidecar of its own, so a test never reads the machine's."""
    path = tmp_path / "state" / "shani-task-repeats.json"
    monkeypatch.setattr(tasks, "REPEATS", path)
    return path


# ---- the sidecar -----------------------------------------------------------


def test_a_missing_sidecar_is_no_rules(repeats):
    assert tasks._load_repeats() == {}


def test_a_corrupt_sidecar_is_no_rules(repeats):
    repeats.parent.mkdir(parents=True, exist_ok=True)
    repeats.write_text("{not json")
    assert tasks._load_repeats() == {}


def test_a_sidecar_that_is_not_an_object_is_no_rules(repeats):
    repeats.parent.mkdir(parents=True, exist_ok=True)
    repeats.write_text("[1, 2]")
    assert tasks._load_repeats() == {}


def test_a_rule_survives_a_round_trip(repeats):
    tasks._save_repeats({"abc": "weekly"})
    assert tasks._load_repeats() == {"abc": "weekly"}


def test_the_intervals_are_the_three_documented_ones():
    assert set(tasks._INTERVALS) == {"daily", "weekly", "monthly"}
    # daily is one day, monthly thirty: the recurrence is a fixed step
    assert tasks._INTERVALS["daily"] == 1
    assert tasks._INTERVALS["monthly"] == 30


# ---- setting and stopping a repeat -----------------------------------------


def test_repeat_records_the_rule_without_touching_eds(repeats):
    got = tasks.write("repeat", {"uid": "abc", "rule": "weekly"})
    assert got == {"ok": True, "uid": "abc", "rule": "weekly"}
    assert tasks._load_repeats() == {"abc": "weekly"}


def test_repeat_is_case_insensitive(repeats):
    tasks.write("repeat", {"uid": "abc", "rule": "Daily"})
    assert tasks._load_repeats() == {"abc": "daily"}


def test_an_empty_rule_stops_the_repeat(repeats):
    tasks.write("repeat", {"uid": "abc", "rule": "daily"})
    got = tasks.write("repeat", {"uid": "abc", "rule": ""})
    assert got["ok"] is True and tasks._load_repeats() == {}


def test_an_unknown_rule_is_refused(repeats):
    with pytest.raises(ValueError) as caught:
        tasks.write("repeat", {"uid": "abc", "rule": "hourly"})
    assert "daily" in str(caught.value)
    assert tasks._load_repeats() == {}  # nothing was written


def test_repeat_needs_to_know_which_task(repeats):
    with pytest.raises(ValueError):
        tasks.write("repeat", {"rule": "daily"})


# ---- the command line ------------------------------------------------------


def run_cli(*args):
    import subprocess

    return subprocess.run(
        [sys.executable, str(ROOT / "bridge/tasks.py"), *args],
        capture_output=True,
        text=True,
        timeout=60,
    )


def test_no_task_service_is_exit_2_with_a_sentence(monkeypatch):
    """The container has no EDS registry: the caller gets a sentence, not a
    traceback, and the exit code says "nothing here" rather than "bad input"."""
    monkeypatch.setattr(
        tasks, "tasks", lambda: (_ for _ in ()).throw(RuntimeError("no registry"))
    )
    out = run_cli()
    assert out.returncode == 2
    assert "no task service" in out.stderr


def test_a_payload_that_is_not_json_is_exit_3():
    out = run_cli("add", "{oops")
    assert out.returncode == 3


def test_a_payload_that_is_not_an_object_is_exit_3():
    out = run_cli("add", "[1,2]")
    assert out.returncode == 3


def test_a_repeat_command_answers_json(monkeypatch, repeats, tmp_path):
    # the sidecar is in the repository's path; the test points it at tmp
    import subprocess

    script = ROOT / "bridge/tasks.py"
    out = subprocess.run(
        [
            sys.executable,
            "-c",
            "import sys; sys.path.insert(0, sys.argv[1]);"
            "import tasks; tasks.REPEATS = __import__('pathlib').Path(sys.argv[2]);"
            'sys.exit(tasks.main([\'tasks.py\', \'repeat\', \'{"uid": "abc", "rule": "monthly"}\']))',
            str(ROOT / "bridge"),
            str(repeats),
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 0
    assert json.loads(out.stdout)["rule"] == "monthly"
    assert tasks._load_repeats() == {"abc": "monthly"}
