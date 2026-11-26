"""Panchang times for one date and one place, as plain JSON data.

A thin bridge: parse ``DATE LAT LON ZONE``, call :func:`compute`, print JSON.
All astronomy is built on ``astronomy._sun_longitude`` and
``astronomy._moon_longitude``; the Moon's latitude (which astronomy.py lacks)
is added here from Meeus' main terms. No network, no packages beyond the
standard library, no default place and no traceback on bad input.
"""

from __future__ import annotations

import json
import math
import sys
from datetime import date as date_type, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

try:  # script (sys.path[0] = bridge/) and import (tests) both work
    import astronomy
    import kundali_engine
except ImportError:  # pragma: no cover - imported as bridge.panchang_times
    from . import astronomy, kundali_engine  # type: ignore[no-redef]

SUN_H0 = -0.833  # upper limb at the horizon, with standard refraction
MOON_H0 = 0.125  # Moon's centre: refraction - parallax + semi-diameter

_SIGNS = [
    "Aries",
    "Taurus",
    "Gemini",
    "Cancer",
    "Leo",
    "Virgo",
    "Libra",
    "Scorpio",
    "Sagittarius",
    "Capricorn",
    "Aquarius",
    "Pisces",
]
_MONTHS = [
    "Chaitra",
    "Vaisakha",
    "Jyeshtha",
    "Ashadha",
    "Shravana",
    "Bhadrapada",
    "Ashwina",
    "Kartika",
    "Margashirsha",
    "Pausha",
    "Magha",
    "Phalguna",
]
_TITHIS = astronomy.TITHIS
_YOGAS = astronomy.YOGAS
_NAKSHATRAS = astronomy.NAKSHATRAS
# The seven moving karanas; the four fixed ones are inserted at their slots.
_MOVING_KARANAS = ["Bava", "Balava", "Kaulava", "Taitila", "Gara", "Vanija", "Vishti"]
_FIXED_KARANAS = {0: "Kimstughna", 45: "Shakuni", 46: "Chatushpada", 47: "Naga"}
_NAK_SIZE = 360.0 / 27.0  # 13 degrees 20 minutes
_TITHI_NAMES = (
    [f"Shukla {name}" for name in _TITHIS[:14]]
    + ["Shukla Purnima"]
    + [f"Krishna {name}" for name in _TITHIS[:14]]
    + ["Krishna Amavasya"]
)
_LIMB_WIDTHS = {"tithi": 12.0, "nakshatra": _NAK_SIZE, "yoga": _NAK_SIZE, "karana": 6.0}

# Eighth-of-the-day tables, 1-based parts from sunrise, Sunday first.
_RAHU_PARTS = (8, 2, 7, 5, 6, 4, 3)
_YAMA_PARTS = (5, 4, 3, 2, 1, 7, 6)
_GULIKA_PARTS = (7, 6, 5, 4, 3, 2, 1)

_CHOG_CYCLE = ("Udveg", "Chal", "Labh", "Amrit", "Kaal", "Shubh", "Rog")
_CHOG_DAY_START = ("Udveg", "Amrit", "Rog", "Labh", "Shubh", "Chal", "Kaal")
_CHOG_NIGHT_START = ("Shubh", "Chal", "Kaal", "Udveg", "Amrit", "Rog", "Labh")
_CHOG_NATURE = {
    "Amrit": "good",
    "Shubh": "good",
    "Labh": "good",
    "Chal": "neutral",
    "Udveg": "bad",
    "Kaal": "bad",
    "Rog": "bad",
}

# Chaldean order, slowest first; each planetary hour moves one step on.
_CHALDEAN = ("Saturn", "Jupiter", "Mars", "Sun", "Venus", "Mercury", "Moon")
_DAY_LORD = {
    0: "Sun",
    1: "Moon",
    2: "Mars",
    3: "Mercury",
    4: "Jupiter",
    5: "Venus",
    6: "Saturday",
}  # Saturday fixed below
_DAY_LORD[6] = "Saturn"

# Meeus, Astronomical Algorithms, table 47.B: the largest terms of the
# Moon's ecliptic latitude (coefficient in degrees, D, M, M', F multiples).
_MOON_LAT_TERMS = (
    (5.128122, 0, 0, 0, 1),
    (0.280602, 0, 0, 1, 1),
    (0.277693, 0, 0, 1, -1),
    (0.173237, 2, 0, 0, -1),
    (0.055413, 2, 0, -1, 1),
    (0.046271, 2, 0, -1, -1),
    (0.032573, 2, 0, 0, 1),
    (0.017198, 0, 0, 2, 1),
    (0.009266, 2, 0, 1, -1),
    (0.008822, 0, 0, 2, -1),
    (0.008216, 2, 0, -2, -1),
    (0.004324, 2, 0, -1, -2),
    (0.004200, 0, 0, 1, -2),
    (0.003887, 0, 0, 1, 2),
    (0.003342, 2, 0, 1, 1),
)


def _norm(value: float) -> float:
    return value % 360.0


def _jd(moment: datetime) -> float:
    """Julian day of an aware UTC datetime (same formula as astronomy)."""
    moment = moment.astimezone(timezone.utc)
    y, m = moment.year, moment.month
    day = (
        moment.day
        + moment.hour / 24.0
        + moment.minute / 1440.0
        + moment.second / 86400.0
        + moment.microsecond / 86400e6
    )
    if m <= 2:
        y -= 1
        m += 12
    a = int(y / 100)
    b = 2 - a + int(a / 4)
    return int(365.25 * (y + 4716)) + int(30.6001 * (m + 1)) + day + b - 1524.5


def _utc_from_jd(jd: float) -> datetime:
    """Inverse of :func:`_jd`, built from the same Gregorian calendar rule."""
    z = int(jd + 0.5)
    f = jd + 0.5 - z
    if z < 2299161:
        a = z
    else:
        alpha = int((z - 1867216.25) / 36524.25)
        a = z + 1 + alpha - int(alpha / 4)
    b = a + 1524
    c = int((b - 122.1) / 365.25)
    d = int(365.25 * c)
    e = int((b - d) / 30.6001)
    day_frac = b - d - int(30.6001 * e) + f
    month = e - 1 if e < 14 else e - 13
    year = c - 4716 if month > 2 else c - 4715
    day = int(day_frac)
    frac = day_frac - day
    hour = int(frac * 24)
    minute = int((frac * 24 - hour) * 60)
    second = (frac * 24 - hour - minute / 60) * 3600
    micros = int(round(second * 1e6))
    whole, micros = divmod(micros, 1000000)
    return datetime(year, month, day, hour, minute, whole, micros, tzinfo=timezone.utc)


def _obliquity(jd: float) -> float:
    t = (jd - 2451545.0) / 36525.0
    return 23.439291 - 0.0130042 * t - 0.000000164 * t * t + 0.000000504 * t**3


def _gmst(jd: float) -> float:
    t = (jd - 2451545.0) / 36525.0
    return _norm(
        280.46061837
        + 360.98564736629 * (jd - 2451545.0)
        + 0.000387933 * t * t
        - t**3 / 38710000.0
    )


def _moon_arguments(jd: float) -> tuple[float, float, float, float]:
    t = (jd - 2451545.0) / 36525.0
    return (
        _norm(297.8501921 + 445267.1114034 * t - 0.0018819 * t * t + t**3 / 545868.0),
        _norm(357.5291092 + 35999.0502909 * t - 0.0001536 * t * t + t**3 / 24490000.0),
        _norm(134.9633964 + 477198.8675055 * t + 0.0087414 * t * t + t**3 / 69699.0),
        _norm(93.2720950 + 483202.0175233 * t - 0.0036539 * t * t - t**3 / 3526000.0),
    )


def _moon_latitude(jd: float) -> float:
    """Ecliptic latitude of the Moon, Meeus' main terms (about 0.01 degree)."""
    d, m, mp, f = _moon_arguments(jd)
    args = (math.radians(d), math.radians(m), math.radians(mp), math.radians(f))
    return sum(
        c * math.sin(sum(k * a for k, a in zip(coeffs, args)))
        for c, *coeffs in _MOON_LAT_TERMS
    )


def _equatorial(jd: float, body: str) -> tuple[float, float]:
    """Apparent right ascension and declination (radians) of Sun or Moon."""
    if body == "sun":
        lon, lat = astronomy._sun_longitude(jd), 0.0
    else:
        lon, lat = astronomy._moon_longitude(jd), _moon_latitude(jd)
    lam, beta, eps = math.radians(lon), math.radians(lat), math.radians(_obliquity(jd))
    ra = math.atan2(
        math.sin(lam) * math.cos(eps) - math.tan(beta) * math.sin(eps), math.cos(lam)
    )
    dec = math.asin(
        math.sin(beta) * math.cos(eps) + math.cos(beta) * math.sin(eps) * math.sin(lam)
    )
    return ra, dec


def altitude(jd: float, lat: float, lon: float, body: str) -> float:
    """Geometric altitude in degrees, no topocentric parallax correction."""
    ra, dec = _equatorial(jd, body)
    hour_angle = math.radians(_gmst(jd) + lon) - ra
    phi = math.radians(lat)
    return math.degrees(
        math.asin(
            math.sin(phi) * math.sin(dec)
            + math.cos(phi) * math.cos(dec) * math.cos(hour_angle)
        )
    )


def _crossing(
    left: datetime, right: datetime, lat: float, lon: float, h0: float, body: str
) -> datetime:
    """Bisect the altitude = h0 crossing between two UTC instants."""
    for _ in range(40):
        mid = left + (right - left) / 2
        value = altitude(_jd(mid), lat, lon, body) - h0
        if altitude(_jd(left), lat, lon, body) - h0 < 0:
            if value < 0:
                left = mid
            else:
                right = mid
        else:
            if value > 0:
                left = mid
            else:
                right = mid
    return left + (right - left) / 2


def _crossings(
    start: datetime, end: datetime, lat: float, lon: float, h0: float, body: str
) -> list[tuple[datetime, str]]:
    """All rise/set crossings in a UTC window, five-minute sampling."""
    found: list[tuple[datetime, str]] = []
    step = timedelta(minutes=5)
    previous = start
    previous_value = altitude(_jd(previous), lat, lon, body) - h0
    current = start + step
    while current <= end:
        value = altitude(_jd(current), lat, lon, body) - h0
        if previous_value < 0 <= value:
            found.append((_crossing(previous, current, lat, lon, h0, body), "rise"))
        elif previous_value > 0 >= value:
            found.append((_crossing(previous, current, lat, lon, h0, body), "set"))
        previous, previous_value = current, value
        current += step
    return found


def _local_window(day: date_type, zone: ZoneInfo) -> tuple[datetime, datetime]:
    """UTC instants of local midnight at the start and end of ``day``."""
    return (
        datetime.combine(day, time.min, tzinfo=zone).astimezone(timezone.utc),
        datetime.combine(day + timedelta(days=1), time.min, tzinfo=zone).astimezone(
            timezone.utc
        ),
    )


def _clock(moment: datetime, zone: ZoneInfo, base: date_type) -> str:
    """Wall-clock HH:MM with a +1/-1 day suffix when off the given date."""
    local = moment.astimezone(zone)
    shift = (local.date() - base).days
    text = local.strftime("%H:%M")
    if shift > 0:
        return f"{text}+{shift}"
    if shift < 0:
        return f"{text}{shift}"
    return text


def _minutes(left: datetime, right: datetime) -> str:
    total = int(round((right - left).total_seconds() / 60))
    return f"{total // 60:02d}:{total % 60:02d}"


def _sidereal_pair(jd: float) -> tuple[float, float]:
    """Sun and Moon sidereal (Lahiri) longitudes at a Julian day."""
    ayan = astronomy.ayanamsa_lahiri(jd)
    return (
        _norm(astronomy._sun_longitude(jd) - ayan),
        _norm(astronomy._moon_longitude(jd) - ayan),
    )


def _limb_angle(jd: float, kind: str) -> float:
    """The angle whose successive slices name a limb (degrees, 0..360)."""
    sun, moon = _sidereal_pair(jd)
    if kind in ("tithi", "karana"):
        return _norm(moon - sun)
    if kind == "nakshatra":
        return moon
    return _norm(moon + sun)


def _limb_name(kind: str, angle: float) -> str:
    if kind == "tithi":
        return _TITHI_NAMES[int(angle / 12.0) % 30]
    if kind == "nakshatra":
        return _NAKSHATRAS[int(angle / _NAK_SIZE) % 27]
    if kind == "yoga":
        return _YOGAS[int(angle / _NAK_SIZE) % 27]
    half = int(angle / 6.0) % 60
    if half in _FIXED_KARANAS:
        return _FIXED_KARANAS[half]
    moving = half - 1 if half <= 44 else half - 48 + 44
    return _MOVING_KARANAS[moving % 7]


def _limb_end(start: datetime, kind: str) -> tuple[datetime, float]:
    """Bisect the next boundary of a limb after ``start`` (UTC instant)."""
    width = _LIMB_WIDTHS[kind]
    jd0 = _jd(start)
    angle0 = _limb_angle(jd0, kind)
    target = (math.floor(angle0 / width) + 1) * width

    def progress(jd: float) -> float:
        return angle0 + (_limb_angle(jd, kind) - angle0) % 360.0

    left = jd0
    right = jd0 + 0.02  # about 29 minutes
    while progress(right) < target:
        right += 0.02
    for _ in range(40):
        middle = (left + right) / 2
        if progress(middle) < target:
            left = middle
        else:
            right = middle
    return _utc_from_jd((left + right) / 2), target


def _limbs(sunrise: datetime | None, zone: ZoneInfo, day: date_type) -> dict:
    if sunrise is None:
        return {
            kind: {
                "name": None,
                "ends_at": None,
                "next": None,
                "note": "No sunrise on this date",
            }
            for kind in _LIMB_WIDTHS
        }
    result = {}
    for kind in ("tithi", "nakshatra", "yoga", "karana"):
        end, boundary = _limb_end(sunrise, kind)
        result[kind] = {
            "name": _limb_name(kind, _limb_angle(_jd(sunrise), kind)),
            "ends_at": _clock(end, zone, day),
            "next": _limb_name(kind, boundary),
        }
    return result


def _rise_set(
    day: date_type, lat: float, lon: float, zone: ZoneInfo
) -> tuple[dict, dict, dict, dict]:
    """Return the sun and moon blocks plus the sunrise/sunset instants."""
    start, end = _local_window(day, zone)
    sun = _crossings(start, end, lat, lon, SUN_H0, "sun")
    moon = _crossings(start, end, lat, lon, MOON_H0, "moon")
    sunrise = next((t for t, kind in sun if kind == "rise"), None)
    sunset = next((t for t, kind in sun if kind == "set"), None)
    moonrise = next((t for t, kind in moon if kind == "rise"), None)
    moonset = next((t for t, kind in moon if kind == "set"), None)

    sun_block = {
        "sunrise": _clock(sunrise, zone, day) if sunrise else None,
        "sunset": _clock(sunset, zone, day) if sunset else None,
        "day_length": _minutes(sunrise, sunset) if sunrise and sunset else None,
        "night_length": _minutes(
            sunset, sunset + timedelta(days=1) - (sunset - sunrise)
        )
        if sunrise and sunset
        else None,
    }
    if not sunrise or not sunset:
        sun_block["note"] = "Sun does not both rise and set on this date"
    moon_block = {
        "moonrise": _clock(moonrise, zone, day) if moonrise else None,
        "moonset": _clock(moonset, zone, day) if moonset else None,
    }
    if not moonrise:
        moon_block["note"] = "Moon does not rise on this date"
    if not moonset:
        moon_block["note"] = (
            moon_block.get("note", "") + ";" if moon_block.get("note") else ""
        ) + "Moon does not set on this date"
    return sun_block, moon_block, sunrise, sunset


def compute(day: date_type, lat: float, lon: float, zone_name: str) -> dict:
    """All Panchang figures for ``day`` at (lat, lon) in the IANA zone."""
    zone = ZoneInfo(zone_name)
    if not -90 <= lat <= 90 or not -180 <= lon <= 180:
        raise ValueError("latitude must be -90..90 and longitude -180..180")
    sun, moon, sunrise, _sunset = _rise_set(day, lat, lon, zone)
    return {
        "date": day.isoformat(),
        "place": {"latitude": lat, "longitude": lon, "timezone": zone_name},
        "sun": sun,
        "moon": moon,
        "limbs": _limbs(sunrise, zone, day),
        "muhurtas": [],
        "choghadiya": {},
        "horas": [],
        "month": {},
        "illumination": {},
    }


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    try:
        if len(argv) != 4:
            raise ValueError("usage: panchang_times.py DATE LAT LON ZONE")
        day = date_type.fromisoformat(argv[0])
        lat, lon = float(argv[1]), float(argv[2])
        result = compute(day, lat, lon, argv[3])
    except Exception as exc:  # noqa: BLE001 - one JSON error, never a traceback
        result = {"error": str(exc)}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 1 if "error" in result else 0


if __name__ == "__main__":
    raise SystemExit(main())
