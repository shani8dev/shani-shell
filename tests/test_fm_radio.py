"""The radio's extra actions: bridge -> one FM engine, with a rejecting stand-in.

Bands, volume, decode and scan used to stop at the bridge's four FM verbs. The
engine already has them; these tests pin the exact arguments sent to it, the
shape of the JSON sent to the UI, and the stand-in's negative controls.
"""

import ast
import importlib.util
import json
import os
import subprocess
import sys
import wave
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
FAKE = ROOT / "dev" / "fake-fm.py"
ENGINE = ROOT / "bridge" / "phone" / "fm_radio.py"


@pytest.fixture
def bridge(monkeypatch, tmp_path):
    spec = importlib.util.spec_from_file_location(
        "devices_fm_under_test", ROOT / "bridge" / "devices.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    monkeypatch.delenv("SHANI_FM", raising=False)
    modules = {}
    monkeypatch.setattr(mod, "_module", lambda name: modules.get(name))
    return mod, modules


class Engine:
    def __init__(self):
        self.calls = []

    def run(self, arguments):
        self.calls.append(arguments)
        return "The radio answered"


def engine_actions() -> set:
    tree = ast.parse(ENGINE.read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "_ACTIONS" for t in node.targets
        ):
            return set(ast.literal_eval(node.value))
    raise AssertionError("fm_radio.py has no _ACTIONS list")


def fake(tmp_path, *args) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["SHANI_FM_STATE"] = str(tmp_path / "state.json")
    env["SHANI_FM_LOG"] = str(tmp_path / "calls")
    return subprocess.run(
        [sys.executable, str(FAKE), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )


def capture(tmp_path, frames=40000, rate=200000, channels=2, width=2) -> Path:
    path = tmp_path / "capture.wav"
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(width)
        handle.setframerate(rate)
        handle.writeframes(b"\x00" * frames * channels * width)
    return path


# ---- the pass-through arguments are ones fm_radio.run really accepts ----------


def test_bridge_verbs_are_real_engine_actions(bridge):
    mod, _ = bridge
    assert set(mod.FM_REPORT_ACTIONS) <= engine_actions()
    source = ENGINE.read_text(encoding="utf-8")
    assert 'arguments.get("file")' in source
    assert 'arguments.get("volume")' in source


@pytest.mark.parametrize(
    "verb,value,key",
    [
        ("bands", "", None),
        ("volume", "75", "volume"),
        ("decode", "/tmp/capture.wav", "file"),
        ("scan", "/tmp/capture.wav", "file"),
    ],
)
def test_arguments_passed_to_the_engine(bridge, verb, value, key):
    mod, modules = bridge
    engine = Engine()
    modules["phone.fm_radio"] = engine
    got = mod.fm_report(verb, value)
    assert got == {"ok": True, "error": "", "text": "The radio answered"}
    wanted = {"action": verb}
    if key:
        wanted[key] = value
    assert engine.calls == [wanted]
    assert set(engine.calls[0]) <= {"action", "volume", "file"}


# ---- the stand-in sees the same argv, and the UI gets one JSON shape -----------


@pytest.mark.parametrize(
    "verb,value,argv",
    [
        ("bands", "", ["bands"]),
        ("volume", "75", ["volume", "75"]),
        ("decode", "/tmp/capture.wav", ["decode", "/tmp/capture.wav"]),
        ("scan", "/tmp/capture.wav", ["scan", "/tmp/capture.wav"]),
    ],
)
def test_exact_argv_sent_to_the_stand_in(bridge, monkeypatch, verb, value, argv):
    mod, _ = bridge
    monkeypatch.setenv("SHANI_FM", "python3 /work/dev/fake-fm.py")
    seen = []

    def stand_in(binary, args):
        seen.append((binary, args))
        return {"out": "The radio answered"}

    monkeypatch.setattr(mod, "_standalone", stand_in)
    got = mod.fm_report(verb, value)
    assert seen == [(["python3", "/work/dev/fake-fm.py"], argv)]
    assert got == {"ok": True, "error": "", "text": "The radio answered"}


def test_main_prints_one_json_answer(bridge, monkeypatch, capsys):
    mod, _ = bridge
    monkeypatch.setenv("SHANI_FM", str(FAKE))
    monkeypatch.setattr(mod.sys, "argv", ["devices.py", "fm", "bands"])
    assert mod.main() == 0
    got = json.loads(capsys.readouterr().out)
    assert set(got) == {"ok", "error", "text"}
    assert got["ok"] is True and "What bands this can cover:" in got["text"]


def test_engine_failure_is_an_error_in_plain_words(bridge):
    mod, modules = bridge
    modules["phone.fm_radio"] = type(
        "Fm",
        (),
        {
            "run": staticmethod(
                lambda _args: "The radio is not playing; tune a station first."
            )
        },
    )
    got = mod.fm_report("volume", "75")
    assert got["ok"] is False and got["error"].startswith("The radio is not playing")


def test_start_still_uses_the_stand_in_unchanged(bridge, monkeypatch):
    mod, _ = bridge
    monkeypatch.setenv("SHANI_FM", str(FAKE))
    seen = []

    def stand_in(_binary, args):
        seen.append(args)
        return {"out": json.dumps({"state": "running", "frequency": 98.6})}

    monkeypatch.setattr(mod, "_standalone", stand_in)
    got = mod.cmd_fm("start", "98.6")
    assert seen == [["start", "98.6"]]
    assert got["state"] == "on" and got["frequency"] == "98.6"


# ---- the bridge refuses bad requests before the engine is called --------------


def test_bridge_rejects_unknown_verb_and_bad_arguments(bridge):
    mod, modules = bridge
    engine = Engine()
    modules["phone.fm_radio"] = engine
    assert mod.fm_report("record")["error"] == "fm needs bands, volume, decode or scan"
    assert mod.fm_report("decode")["error"] == "pick a recording first"
    assert mod.fm_report("scan", "")["error"] == "pick a recording first"
    assert "0 to 100" in mod.fm_report("volume", "loud")["error"]
    assert "0 to 100" in mod.fm_report("volume", "150")["error"]
    assert all(
        not mod.fm_report(v, a)["ok"]
        for v, a in (("record", ""), ("decode", ""), ("volume", "loud"))
    )
    assert engine.calls == []


# ---- the stand-in rejects what the engine rejects ------------------------------


@pytest.mark.parametrize(
    "argv",
    [
        ("plays",),
        ("decode",),
        ("scan",),
        ("volume",),
        ("volume", "loud"),
        ("volume", "150"),
        ("decode", "/no/such/capture.wav"),
        ("scan", "/no/such/capture.wav"),
    ],
)
def test_fake_rejects_bad_verbs_and_arguments(tmp_path, argv):
    got = fake(tmp_path, *argv)
    assert got.returncode != 0
    assert got.stderr.strip()


def test_fake_rejects_a_capture_that_is_not_stereo_iq(tmp_path):
    path = capture(tmp_path, channels=1)
    got = fake(tmp_path, "decode", str(path))
    assert got.returncode != 0 and "stereo IQ" in got.stderr


def test_fake_reports_bands_volume_and_captures(tmp_path):
    path = capture(tmp_path)
    bands = fake(tmp_path, "bands")
    assert bands.returncode == 0 and "FM: 87.5-108 MHz" in bands.stdout
    volume = fake(tmp_path, "volume", "75%")
    assert volume.returncode == 0 and "Radio volume 75%." in volume.stdout
    decoded = fake(tmp_path, "decode", str(path))
    assert decoded.returncode == 0 and "Demodulated" in decoded.stdout
    assert str(path) in decoded.stdout
    scanned = fake(tmp_path, "scan", str(path))
    assert scanned.returncode == 0 and "Searched" in scanned.stdout
    assert str(path) in scanned.stdout
    assert (tmp_path / "calls").read_text(encoding="utf-8").splitlines() == [
        "bands",
        "volume 75%",
        f"decode {path}",
        f"scan {path}",
    ]
