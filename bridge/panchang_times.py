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
import os
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
_DAY_LORD = ("Sun", "Moon", "Mars", "Mercury", "Jupiter", "Venus", "Saturn")

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


def _interval(
    start: datetime,
    fraction: float,
    length: timedelta,
    zone: ZoneInfo,
    day: date_type,
    name: str,
    auspicious: bool,
) -> dict:
    begin = start + fraction * length
    return {
        "name": name,
        "start": _clock(begin, zone, day),
        "end": _clock(begin + length, zone, day),
        "auspicious": auspicious,
    }


# Amrit Kaal and Varjyam are left out: their per-nakshatra ghati offsets
# differ between printed panchangs, so there is no correct table to use here.


def _muhurtas(
    sunrise: datetime | None, sunset: datetime | None, zone: ZoneInfo, day: date_type
) -> list[dict]:
    if sunrise is None or sunset is None:
        return []
    weekday = (day.weekday() + 1) % 7  # Sunday = 0
    daylight = sunset - sunrise
    eighth = daylight / 8
    result = [
        _interval(
            sunrise, _RAHU_PARTS[weekday] - 1, eighth, zone, day, "Rahu Kaal", False
        ),
        _interval(
            sunrise, _YAMA_PARTS[weekday] - 1, eighth, zone, day, "Yamaganda", False
        ),
        _interval(
            sunrise,
            _GULIKA_PARTS[weekday] - 1,
            eighth,
            zone,
            day,
            "Gulika Kaal",
            False,
        ),
        _interval(sunrise, 7, daylight / 15, zone, day, "Abhijit", True),
    ]
    # Two muhurtas (2 x 48 minutes) before sunrise.
    brahma = sunrise - timedelta(minutes=96)
    result.append(
        {
            "name": "Brahma Muhurta",
            "start": _clock(brahma, zone, day),
            "end": _clock(brahma + timedelta(minutes=48), zone, day),
            "auspicious": True,
        }
    )
    return result


def _following_sunrise(sunset: datetime, lat: float, lon: float) -> datetime:
    """Next sunrise after sunset, for the night's length and its periods."""
    crossings = _crossings(
        sunset + timedelta(hours=1),
        sunset + timedelta(hours=30),
        lat,
        lon,
        SUN_H0,
        "sun",
    )
    return next(
        (t for t, kind in crossings if kind == "rise"), sunset + timedelta(days=1)
    )


def _choghadiya(
    sunrise: datetime,
    sunset: datetime,
    night_end: datetime,
    zone: ZoneInfo,
    day: date_type,
    weekday: int,
) -> dict:
    def periods(begin: datetime, end: datetime, first: str) -> list[dict]:
        index = _CHOG_CYCLE.index(first)
        length = (end - begin) / 8
        return [
            {
                "name": _CHOG_CYCLE[(index + i) % 7],
                "start": _clock(begin + i * length, zone, day),
                "end": _clock(begin + (i + 1) * length, zone, day),
                "nature": _CHOG_NATURE[_CHOG_CYCLE[(index + i) % 7]],
            }
            for i in range(8)
        ]

    return {
        "day": periods(sunrise, sunset, _CHOG_DAY_START[weekday]),
        "night": periods(sunset, night_end, _CHOG_NIGHT_START[weekday]),
    }


def _horas(
    sunrise: datetime,
    sunset: datetime,
    night_end: datetime,
    zone: ZoneInfo,
    day: date_type,
    weekday: int,
) -> list[dict]:
    day_length = (sunset - sunrise) / 12
    night_length = (night_end - sunset) / 12
    first = _CHALDEAN.index(_DAY_LORD[weekday])
    result = []
    for i in range(24):
        if i < 12:
            begin, length = sunrise + i * day_length, day_length
        else:
            begin, length = sunset + (i - 12) * night_length, night_length
        result.append(
            {
                "lord": _CHALDEAN[(first + i) % 7],
                "start": _clock(begin, zone, day),
                "end": _clock(begin + length, zone, day),
            }
        )
    return result


def _tithi_crossings(
    start_jd: float, end_jd: float, multiple: float, offset: float = 0.0
) -> list[float]:
    """Julian days where the Moon-Sun angle passes an offset + n * multiple."""
    target = (
        math.floor((_limb_angle(start_jd, "tithi") - offset) / multiple) + 1
    ) * multiple + offset
    found: list[float] = []
    left = start_jd
    unwrapped = _limb_angle(left, "tithi")
    while left < end_jd:
        right = min(left + 0.25, end_jd)
        angle_left = _limb_angle(left, "tithi")
        step = (_limb_angle(right, "tithi") - angle_left) % 360.0
        if step > 180:  # a backwards blip cannot be a real month
            step -= 360.0

        def progress(jd: float) -> float:
            return unwrapped + (_limb_angle(jd, "tithi") - angle_left) % 360.0

        if unwrapped + step >= target:
            low, high = left, right
            for _ in range(40):
                middle = (low + high) / 2
                if progress(middle) < target:
                    low = middle
                else:
                    high = middle
            found.append((low + high) / 2)
            target += multiple
        unwrapped += step
        left = right
    return found


def _new_moons(start: datetime, end: datetime) -> list[float]:
    return _tithi_crossings(_jd(start), _jd(end), 360.0)


def _amanta_index(jd: float) -> int:
    """A lunar month takes the sign the Sun enters during it (new moon + 1)."""
    return (int(_sidereal_pair(jd)[0] / 30.0) + 1) % 12


def _month(day: date_type, zone: ZoneInfo, zone_name: str) -> dict:
    midnight, next_midnight = _local_window(day, zone)
    moons = _new_moons(midnight - timedelta(days=40), next_midnight)
    if not moons:
        return {"error": "No new moon near this date"}
    last_new_moon = moons[-1]
    amanta = _amanta_index(last_new_moon)
    noon = kundali_engine.utc_instant(f"{day.isoformat()}T12:00@{zone_name}")
    tithi_angle = _limb_angle(astronomy.julian_day(noon), "tithi")
    shukla = tithi_angle < 180
    purnimanta = (amanta + (0 if shukla else 1)) % 12

    # The Vikram/Shaka year turns at the Chaitra new moon of this year.
    march = datetime(day.year, 3, 1, tzinfo=timezone.utc)
    june = datetime(day.year, 6, 1, tzinfo=timezone.utc)
    chaitra = next(
        (jd for jd in _new_moons(march, june) if _amanta_index(jd) == 0), None
    )
    before_chaitra = chaitra is not None and midnight < _utc_from_jd(chaitra)
    samvat = day.year - 1 if before_chaitra else day.year
    return {
        "amanta": _MONTHS[amanta],
        "purnimanta": _MONTHS[purnimanta],
        "paksha": "Shukla" if shukla else "Krishna",
        "vikram": samvat + 57,
        "shaka": samvat - 78,
    }


_PHASE_NAMES = (
    (11.25, "New Moon"),
    (78.75, "Waxing Crescent"),
    (101.25, "First Quarter"),
    (168.75, "Waxing Gibbous"),
    (191.25, "Full Moon"),
    (258.75, "Waning Gibbous"),
    (281.25, "Last Quarter"),
    (348.75, "Waning Crescent"),
    (360.0, "New Moon"),
)


def _illumination(day: date_type, zone_name: str) -> dict:
    noon = astronomy.julian_day(
        kundali_engine.utc_instant(f"{day.isoformat()}T12:00@{zone_name}")
    )
    status = astronomy.lunar_status(noon)
    angle = float(status["phase_angle"])
    phase = next(name for limit, name in _PHASE_NAMES if angle < limit)
    return {
        "percent": float(status["illumination"]),
        "phase": phase,
        "waxing": bool(status["waxing"]),
    }


def _rise_set(
    day: date_type, lat: float, lon: float, zone: ZoneInfo
) -> tuple[dict, dict, datetime | None, datetime | None, datetime | None]:
    """Return the sun and moon blocks plus the rise/set instants (UTC)."""
    start, end = _local_window(day, zone)
    sun = _crossings(start, end, lat, lon, SUN_H0, "sun")
    moon = _crossings(start, end, lat, lon, MOON_H0, "moon")
    sunrise = next((t for t, kind in sun if kind == "rise"), None)
    sunset = next((t for t, kind in sun if kind == "set"), None)
    moonrise = next((t for t, kind in moon if kind == "rise"), None)
    moonset = next((t for t, kind in moon if kind == "set"), None)

    night_end = _following_sunrise(sunset, lat, lon) if sunset else None
    sun_block = {
        "sunrise": _clock(sunrise, zone, day) if sunrise else None,
        "sunset": _clock(sunset, zone, day) if sunset else None,
        "day_length": _minutes(sunrise, sunset) if sunrise and sunset else None,
        "night_length": _minutes(sunset, night_end) if sunset and night_end else None,
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
    return sun_block, moon_block, sunrise, sunset, night_end


def _zone(name: str) -> ZoneInfo:
    """An IANA zone; an empty name means this computer's zone, not UTC."""
    if not name:
        name = os.environ.get("TZ", "").lstrip(":")
        if not name:
            parts = Path("/etc/localtime").resolve().parts
            name = (
                "/".join(parts[parts.index("zoneinfo") + 1 :])
                if "zoneinfo" in parts
                else "UTC"
            )
    return ZoneInfo(name)


def compute(day: date_type, lat: float, lon: float, zone_name: str) -> dict:
    """All Panchang figures for ``day`` at (lat, lon) in the IANA zone."""
    zone = _zone(zone_name)
    zone_name = str(zone)
    if not -90 <= lat <= 90 or not -180 <= lon <= 180:
        raise ValueError("latitude must be -90..90 and longitude -180..180")
    sun, moon, sunrise, sunset, night_end = _rise_set(day, lat, lon, zone)
    weekday = (day.weekday() + 1) % 7  # Sunday = 0
    if sunrise and sunset and night_end:
        choghadiya = _choghadiya(sunrise, sunset, night_end, zone, day, weekday)
        horas = _horas(sunrise, sunset, night_end, zone, day, weekday)
    else:
        choghadiya, horas = {}, []
    return {
        "date": day.isoformat(),
        "place": {"latitude": lat, "longitude": lon, "timezone": zone_name},
        "sun": sun,
        "moon": moon,
        "limbs": _limbs(sunrise, zone, day),
        "muhurtas": _muhurtas(sunrise, sunset, zone, day),
        "choghadiya": choghadiya,
        "horas": horas,
        "month": _month(day, zone, zone_name),
        "illumination": _illumination(day, zone_name),
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
