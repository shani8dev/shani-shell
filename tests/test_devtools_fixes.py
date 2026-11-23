"""Static/unit checks for the pass-22 developer & logging fixes."""

import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parent.parent

# the report generator
REPORT = ROOT / "bridge" / "system-report.py"
_spec = importlib.util.spec_from_file_location("system_report", REPORT)
report_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(report_mod)

# the CLI (no .py extension, so load it by path)
BIN = ROOT / "bin" / "shani"
_loader = importlib.machinery.SourceFileLoader("shani_cli", str(BIN))
_spec = importlib.util.spec_from_loader(_loader.name, _loader)
shani_mod = importlib.util.module_from_spec(_spec)
_loader.exec_module(shani_mod)


def test_report_run_is_structured_and_failures_are_visible(monkeypatch):
    monkeypatch.setattr(report_mod.shutil, "which", lambda cmd: None)
    missing = report_mod.run(["nope"])
    assert missing["ok"] is False and "not available" in missing["error"]

    monkeypatch.setattr(report_mod.shutil, "which", lambda cmd: "/bin/x")

    def boom(*a, **k):
        raise subprocess.TimeoutExpired(a[0], 1)

    monkeypatch.setattr(report_mod.subprocess, "run", boom)
    timed = report_mod.run(["x"])
    assert timed["ok"] is False and "timed out" in timed["error"]

    assert (
        report_mod.text({"ok": False, "output": "", "error": "boom"})
        == "[FAILED: boom]"
    )
    out = report_mod.report(lambda cmd: {"ok": False, "output": "", "error": "broken"})
    assert "[FAILED: broken]" in out


def test_shani_report_command_runs_the_report_script(monkeypatch):
    assert shani_mod.build_parser().parse_args(["report"]).func is shani_mod._cmd_report
    monkeypatch.setattr(shutil, "which", lambda name: None)
    monkeypatch.setattr(os.path, "isfile", lambda path: True)
    seen = []

    def fake_run(cmd, **kw):
        seen.append(cmd)
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    assert shani_mod._cmd_report(None) == 0
    assert seen and seen[0][-1].endswith("system-report.py")


def test_log_timestamps_carry_a_date():
    src = (ROOT / "shani" / "Common" / "Log.qml").read_text()
    assert "MM-dd HH:mm:ss" in src
    assert "fmtTime" in src and "Qt.formatDateTime" in src


def test_report_doc_has_dated_title_and_save_action():
    src = (ROOT / "shani" / "Modules" / "Settings" / "SettingsAbout.qml").read_text()
    assert "shani-report-" in src
    assert 'Tr.t("Save report…")' in src
    assert 'mode: "save"' in src and "TextDocs.saveAs(paths[0])" in src
    # still opens the generated text in our own editor
    assert "TextDocs.newDoc()" in src and "TextDocs.setText(text)" in src
    assert "Ui.textEditor = true" in src
