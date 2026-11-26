"""Lal Kitab basics: fixed houses with Aries as house 1, the permanent
(pakka) house of each planet, and its sign-based strength.

The pakka ghar table is the standard one: Sun 9, Moon 2, Mars 3, Mercury 6,
Jupiter 12, Venus 7, Saturn 8, Rahu 6, Ketu 12. Own/exalted/debilitated
uses the usual sign dignities that Lal Kitab assumes.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import astronomy as a  # noqa: E402


@pytest.fixture
def chart():
    positions = {
        "Sun": 10,  # Aries, house 1, exalted, pakka 9
        "Moon": 40,  # Taurus, house 2, exalted, pakka 2
        "Mars": 280,  # Capricorn, house 10, exalted, pakka 3
        "Mercury": 165,  # Virgo, house 6, exalted, pakka 6
        "Jupiter": 240,  # Sagittarius, house 9, own sign, pakka 12
        "Venus": 340,  # Pisces, house 12, exalted, pakka 7
        "Saturn": 180,  # Libra, house 7, exalted, pakka 8
        "Rahu": 150,  # Virgo, house 6, pakka 6
        "Ketu": 310,  # Aquarius, house 11, pakka 12
    }
    return {
        "planets": [
            {"name": name, "sidereal_longitude": value}
            for name, value in positions.items()
        ]
    }


def test_houses_are_fixed_with_aries_first(chart):
    result = a.lal_kitab_chart(chart)
    assert result["house_1_sign"] == "Aries"
    assert len(result["houses"]) == 12
    assert result["houses"][0]["sign"] == "Aries"
    assert result["houses"][11]["sign"] == "Pisces"
    assert result["houses"][0]["planets"] == ["Sun"]
    assert result["houses"][1]["planets"] == ["Moon"]
    assert result["houses"][5]["planets"] == ["Mercury", "Rahu"]
    assert result["houses"][9]["planets"] == ["Mars"]


def test_pakka_ghar_and_dignity_per_planet(chart):
    by_name = {p["name"]: p for p in a.lal_kitab_chart(chart)["planets"]}
    assert by_name["Sun"]["pakka_ghar"] == 9
    assert by_name["Sun"]["in_pakka_ghar"] is False
    assert by_name["Sun"]["dignity"] == "Exalted"
    assert by_name["Moon"]["pakka_ghar"] == 2
    assert by_name["Moon"]["in_pakka_ghar"] is True
    assert by_name["Mars"]["house"] == 10
    assert by_name["Mercury"]["in_pakka_ghar"] is True
    assert by_name["Mercury"]["dignity"] == "Exalted"
    assert by_name["Rahu"]["pakka_ghar"] == 6
    assert by_name["Rahu"]["in_pakka_ghar"] is True
    assert by_name["Ketu"]["pakka_ghar"] == 12
    assert by_name["Ketu"]["house"] == 11


def test_the_bridge_returns_lal_kitab_as_data():
    import json
    import subprocess as sp

    out = sp.run(
        [
            sys.executable,
            str(ROOT / "bridge/kundali.py"),
            "data",
            "lalkitab",
            "1990-01-01T12:00@Asia/Kolkata",
            "18.5204",
            "73.8567",
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 0
    data = json.loads(out.stdout)
    assert data["system"] == "lal_kitab"
    assert len(data["houses"]) == 12 and len(data["planets"]) == 12
    assert "text" not in data
