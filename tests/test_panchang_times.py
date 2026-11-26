"""Panchang times: rise/set, limbs, muhurtas, choghadiya, months.

Published references: sunrise-sunset.org (Pune 2026-10-19, Delhi equinox,
Stockholm solstice) and phasesmoon.com (Pune moonrise 2026-10-19). The
prompt's "about 06:37 / 18:17 / 13:01" for Pune are rough; the published
figures for those coordinates are 06:29 / 18:09 / 13:40 IST.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import date
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import astronomy as a  # noqa: E402
import panchang_times as pt  # noqa: E402


def compute(d, lat, lon, zone):
    return pt.compute(date.fromisoformat(d), lat, lon, zone)


def minutes(text):
    """Minutes past local midnight, with +1/-1 day suffixes."""
    shift = 0
    if text.endswith("+1"):
        text, shift = text[:-2], 1440
    elif text.endswith("-1"):
        text, shift = text[:-2], -1440
    hour, minute = (int(v) for v in text.split(":"))
    return hour * 60 + minute + shift


def delta(left, right):
    return abs(minutes(left) - minutes(right))


@pytest.mark.parametrize(
    "place",
    [
        ("2026-10-19", 18.5204, 73.8567, "Asia/Kolkata", "06:29", "18:09", "13:40"),
        ("2026-09-23", 28.6139, 77.2090, "Asia/Kolkata", "06:09", "18:17", None),
        ("2026-06-21", 59.3293, 18.0686, "Europe/Stockholm", "03:30", "22:08", None),
    ],
    ids=["pune", "delhi-equinox", "stockholm-solstice"],
)
def test_rise_set_match_published_times(place):
    d, lat, lon, zone, sunrise, sunset, moonrise = place
    result = compute(d, lat, lon, zone)
    assert delta(result["sun"]["sunrise"], sunrise) <= 2
    assert delta(result["sun"]["sunset"], sunset) <= 2
    if moonrise:
        assert delta(result["moon"]["moonrise"], moonrise) <= 2


def test_day_and_night_lengths_cover_the_whole_day():
    result = compute("2026-10-19", 18.5204, 73.8567, "Asia/Kolkata")
    day = minutes(result["sun"]["day_length"])
    night = minutes(result["sun"]["night_length"])
    assert day + night == 1440
    assert delta(result["sun"]["sunset"], result["sun"]["sunrise"]) == day


def test_polar_day_says_the_sun_does_not_set():
    result = compute("2026-06-21", 69.6492, 18.9553, "Europe/Oslo")
    assert result["sun"]["sunset"] is None
    assert "note" in result["sun"]


def test_cli_prints_one_json_object_and_errors_without_traceback():
    script = str(ROOT / "bridge" / "panchang_times.py")
    good = subprocess.run(
        [sys.executable, script, "2026-10-19", "18.5204", "73.8567", "Asia/Kolkata"],
        capture_output=True,
        text=True,
    )
    assert good.returncode == 0 and good.stderr == ""
    assert set(json.loads(good.stdout)) >= {
        "sun",
        "moon",
        "limbs",
        "muhurtas",
        "choghadiya",
        "horas",
        "month",
        "illumination",
    }
    bad = subprocess.run(
        [sys.executable, script, "not-a-date", "0", "0", "UTC"],
        capture_output=True,
        text=True,
    )
    assert bad.returncode == 1 and "Traceback" not in bad.stderr
    assert "error" in json.loads(bad.stdout)
