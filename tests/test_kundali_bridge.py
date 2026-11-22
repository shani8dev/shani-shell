"""bridge/kundali.py: the panchang and birth-chart bridge.

The astronomy module it needs is shani-chronoa's and is not in the test image,
so what is pinned here is what the bridge does around it: it must say so
plainly rather than crash, and it must hand the module a timestamp it can
parse — a bare date becomes noon UTC, a date with a time gets a Z.
"""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import kundali  # noqa: E402


class FakeAstro:
    """Records what it was asked, and answers with something recognisable."""

    def __init__(self):
        self.asked = []

    def compute_panchang(self, date_str, lat, lon):
        self.asked.append(("panchang", date_str, lat, lon))
        return {"tithi": "Shukla Pratipada"}

    def compute_full_chart_v2(self, date_str, lat, lon):
        self.asked.append(("kundali", date_str, lat, lon))
        return {"houses": []}


@pytest.fixture
def astro(monkeypatch):
    fake = FakeAstro()
    monkeypatch.setattr(kundali, "_astro", lambda: fake)
    return fake


# ---- with no astronomy module ------------------------------------------------


def test_panchang_without_the_module_says_so(monkeypatch):
    monkeypatch.setattr(kundali, "_astro", lambda: None)
    assert "not available" in kundali.panchang("2024-01-01", 28.6, 77.2)["error"]


def test_a_chart_without_the_module_says_so(monkeypatch):
    monkeypatch.setattr(kundali, "_astro", lambda: None)
    assert (
        "not available" in kundali.kundali("1990-01-01T12:00:00Z", 28.6, 77.2)["error"]
    )


# ---- the timestamp handed to the module --------------------------------------


def test_a_bare_date_becomes_noon_utc(astro):
    kundali.panchang("2024-01-01", 28.6139, 77.2090)
    assert astro.asked[0][1] == "2024-01-01T12:00:00Z"


def test_a_time_without_a_zone_gets_a_z(astro):
    kundali.panchang("2024-01-01T06:30:00", 28.6139, 77.2090)
    assert astro.asked[0][1] == "2024-01-01T06:30:00Z"


def test_a_timestamp_that_is_already_utc_is_left_alone(astro):
    kundali.panchang("2024-01-01T06:30:00Z", 28.6139, 77.2090)
    assert astro.asked[0][1] == "2024-01-01T06:30:00Z"


def test_a_chart_gets_the_same_treatment(astro):
    kundali.kundali("1990-01-01", 19.0760, 72.8777)
    assert astro.asked[0][1] == "1990-01-01T12:00:00Z"


# ---- the coordinates are passed through --------------------------------------


def test_panchang_hands_over_the_coordinates(astro):
    kundali.panchang("2024-01-01", 19.076, 72.8777)
    assert astro.asked[0][2:] == (19.076, 72.8777)


def test_panchang_returns_what_the_module_said(astro):
    assert kundali.panchang("2024-01-01", 0, 0)["tithi"] == "Shukla Pratipada"


# ---- the command line --------------------------------------------------------


def test_the_command_line_answers_json_with_defaults(monkeypatch):
    import subprocess

    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/kundali.py"), "panchang", "2024-01-01"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 0
    # either the module answered or it said it was missing - never a traceback
    assert out.stdout.strip().startswith("{")
    assert "Traceback" not in out.stderr
