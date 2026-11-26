"""Every calculation the Kundali engine has is there, and reachable.

a01edd0 cut kundali_engine.py from ~1000 lines to ~250, dropping ~40
calculations (shadbala, vimshopaka, the other dashas, arudhas, upagrahas,
yogas, muhurta, horary, BaZi, Zi Wei, ...) because the window had no place
for them. They are back (from 98075ba), every one is in ACTIONS, and
kundali.py run ACTION answers each for a birth.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import kundali_engine as k  # noqa: E402

BRIDGE = ROOT / "bridge/kundali.py"
BIRTH = ("1990-01-01T12:00@Asia/Kolkata", "18.5204", "73.8567")   # Pune, local time


def test_none_of_the_restored_calculations_is_missing():
    restored = {"shadbala", "shadbala_full", "vimshopaka", "yoginidasha", "ashtottaridasha", "charadasha",
                "arudha", "upagrahas", "charakarakas", "yogas", "vishesha_yogas", "muhurta", "horary",
                "gochara", "bazi", "ziwei", "chinese", "fixedstars", "arabicparts", "grahayuddha",
                "cheshta", "combustion", "timelords", "temperament", "kalamana", "grahana", "nodes"}
    assert restored <= set(k.ACTIONS)
    assert len(k.ACTIONS) >= 42


def test_the_catalogue_and_the_engine_agree():
    src = (ROOT / "bridge/kundali_engine.py").read_text()
    handled = set(re.findall(r'    if action == "([a-z_]+)"', src)) - {"panchang", "dasha"}
    assert handled == set(k.ACTIONS)


@pytest.mark.parametrize("action", k.ACTIONS)
def test_each_answers_for_a_birth(action):
    r = subprocess.run([sys.executable, str(BRIDGE), "run", action, *BIRTH],
                       capture_output=True, text=True, timeout=60)
    data = json.loads(r.stdout)
    text = data.get("text", "")
    assert r.returncode == 0 and text, data
    assert not any(w in text[:120] for w in ("Failed", "failed", "Unknown", "Provide", "rror")), text[:200]


def test_a_birth_time_is_converted_with_its_places_rules():
    assert k.utc_instant("1990-01-01T12:00@Asia/Kolkata") == "1990-01-01T06:30:00Z"
    # New York in July: summer time (UTC-4), not standard (UTC-5)
    assert k.utc_instant("1990-07-01T12:00@America/New_York") == "1990-07-01T16:00:00Z"
    assert k.utc_instant("1990-01-01T12:00@America/New_York") == "1990-01-01T17:00:00Z"
    assert k.utc_instant("1990-01-01T06:30:00Z") == "1990-01-01T06:30:00Z"
    assert k.local_parts("1990-07-01T23:15@America/New_York") == {"year": 1990, "month": 7, "day": 1, "hour": 23}


def test_the_chart_carries_every_planets_navamsa():
    r = subprocess.run([sys.executable, str(BRIDGE), "kundali", *BIRTH], capture_output=True, text=True, timeout=60)
    data = json.loads(r.stdout)
    assert data["datetime"] == "1990-01-01T06:30:00Z"
    assert {p["name"] for p in data["navamsa"]} == {p["name"] for p in data["planets"]}
    assert data["navamsa_ascendant"]
