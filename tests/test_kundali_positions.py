"""The Kundali engine's positions agree with the references.

Two errors went into every chart until 2026-11-26:
- Mercury to Pluto were their *mean heliocentric* longitudes taken as seen
  from the Earth - no orbit, no step to the Earth's centre - so Venus was up
  to ~60 degrees off, Mars ~28, and no planet was ever retrograde
  ("retrograde": False was written into every chart);
- the ascendant formula had both signs flipped: every chart rose in the
  opposite sign, and every house was the opposite one.

References (tests/data): JPL Horizons geocentric longitudes for 12 dates
1950-2045, and the Swiss Ephemeris' ascendant, Lahiri ayanamsa and mean node
for the same dates at three latitudes. Limits are what the pure-Python model
achieves, with a little room; a regression of a degree fails loudly.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import astronomy as a  # noqa: E402

JPL = json.loads((ROOT / "tests/data/jpl_geocentric.json").read_text())
SWE = json.loads((ROOT / "tests/data/swisseph_reference.json").read_text())
LIMIT_ARCMIN = {"Sun": 1, "Moon": 4, "Mercury": 2, "Venus": 2, "Mars": 2,
                "Jupiter": 7, "Saturn": 11, "Uranus": 3, "Neptune": 2}


def _jd(utc):
    return a.julian_day(utc.replace(" ", "T") + ":00Z")


def _arcmin(x, y):
    return abs((x - y + 180) % 360 - 180) * 60


def _ours(name, jd):
    k = name.lower()
    if k == "sun":
        return a._sun_longitude(jd)
    if k == "moon":
        return a._moon_longitude(jd)
    return a._planet_longitude(k, jd)


@pytest.mark.parametrize("name", sorted(LIMIT_ARCMIN))
def test_geocentric_longitude_matches_jpl(name):
    worst = max(_arcmin(_ours(name, _jd(u)), v) for u, v in zip(JPL["utc"], JPL["longitude"][name]))
    assert worst <= LIMIT_ARCMIN[name], f"{name} off by {worst:.1f}'"


@pytest.mark.parametrize("place", SWE["places"], ids=lambda p: p[0])
def test_ascendant_matches_swiss_ephemeris(place):
    name, lat, lon = place
    worst = max(_arcmin(a.ascendant(_jd(u), lat, lon), v) for u, v in zip(JPL["utc"], SWE["ascendant"][name]))
    assert worst <= 2, f"ascendant at {name} off by {worst:.1f}'"


def test_ayanamsa_and_mean_node_match():
    for u, ay, node in zip(JPL["utc"], SWE["ayanamsa"], SWE["mean_node"]):
        assert _arcmin(a.ayanamsa_lahiri(_jd(u)), ay) <= 1
        assert _arcmin(a._planet_longitude("rahu", _jd(u)), node) <= 1


def test_retrograde_follows_the_sky():
    # Saturn was retrograde on 2000-01-01; Jupiter direct on 2000-01-01;
    # Mercury retrograde 2020-10-14..11-03; the nodes always are
    assert a.is_retrograde("Saturn", _jd("2000-01-01 12:00"))
    assert not a.is_retrograde("Jupiter", _jd("2000-03-01 12:00"))
    assert a.is_retrograde("Mercury", _jd("2020-10-25 12:00"))
    assert not a.is_retrograde("Mercury", _jd("2020-12-01 12:00"))
    assert a.is_retrograde("Rahu", _jd("2020-12-01 12:00"))
    assert not a.is_retrograde("Sun", _jd("2020-12-01 12:00"))
    chart = a.compute_chart("2020-10-25T12:00:00Z", 28.6139, 77.2090)
    assert next(p for p in chart["planets"] if p["name"] == "Mercury")["retrograde"] is True


def test_the_window_reads_the_birth_time_as_local_time():
    """The window appended "Z" to the typed time: an Indian birth at 10:00
    was computed as 10:00 UTC (15:30 IST) - the rising sign about three signs
    off. A searched place sends its clock time with its zone ("@Asia/Kolkata",
    converted by the bridge with that day's rules); this computer's place
    sends the local Date's UTC instant. The zone is shown."""
    qml = (ROOT / "shani/Modules/Kundali/KundaliPanel.qml").read_text()
    fn = qml[qml.index("function birthArg()"):]
    fn = fn[:fn.index("\n    }")]
    assert '"@" + win.place.timezone' in fn
    assert 'new Date(win.dateInput + "T" + time + ":00")' in fn and "toISOString()" in fn
    assert qml.count("win.birthArg()") >= 4 and '":00Z"' not in qml.replace('time + ":00Z"', "")
    assert 'Tr.t("Local time, %1"' in qml


@pytest.mark.parametrize("when", ["1990-01-01T06:30:00Z", "1975-07-21T18:00:00Z", "2020-12-21T18:20:00Z"])
def test_ashtakavarga_has_every_planets_bindus(when):
    """Only the Sun's and the Moon's tables were there: the Sarvashtakavarga
    summed to ~97. Each planet's Bhinnashtakavarga has a fixed total whatever
    the chart (Sun 48, Moon 49, Mars 39, Mercury 54, Jupiter 56, Venus 52,
    Saturn 39), and the Sarvashtakavarga 337."""
    c = a.compute_full_chart_v2(when, 18.5204, 73.8567)
    av = a.ashtakavarga_full(c["planets"], int(c["ascendant"] / 30) % 12)
    totals = {k: sum(v) for k, v in av["bhinna"].items()}
    assert totals == {"Sun": 48, "Moon": 49, "Mars": 39, "Mercury": 54, "Jupiter": 56, "Venus": 52, "Saturn": 39}
    assert sum(av["sarva"]) == 337 and sum(c["ashtakavarga"]["sarva"]) == 337
