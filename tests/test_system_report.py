"""The problem report borrowed from Ananta OS: sections, honesty, no secrets.

The generator only prints text; the shell opens it in its own editor so it can
be read and edited before anyone saves or copies it.
"""

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "bridge" / "system-report.py"
spec = importlib.util.spec_from_file_location("system_report", SOURCE)
report_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report_mod)


def test_report_has_all_the_sections():
    r = report_mod.report(lambda cmd: "sample output")
    for title in (
        "System",
        "Storage",
        "Hardware",
        "Services that failed",
        "Errors since this start",
        "Errors of the previous start",
    ):
        assert "## " + title in r
    assert "# Shani Shell problem report" in r
    assert "Review this before sharing" in r


def test_report_says_when_a_tool_is_missing():
    r = report_mod.report(lambda cmd: "(niri is not available)")
    assert "(niri is not available)" in r  # never invent data for a missing tool


def test_report_reads_no_home_files_or_environment():
    source = SOURCE.read_text()
    assert "expanduser" not in source
    assert "environ" not in source
    assert source.count("open(") == 1  # only /etc/os-release
