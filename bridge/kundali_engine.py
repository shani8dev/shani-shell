"""Kundali (birth chart) and Panchang engine, moved from shani-chronoa.

Computes Vedic birth charts (Rasi, Navamsha) and Panchang (Tithi, Vara,
Nakshatra, Yoga, Karana) entirely offline with Meeus algorithms. No network,
no API keys, no pip packages: only the standard library and the astronomy
module injected by bridge/kundali.py.

One calculation per consumer. ``panchang`` and ``kundali`` render the text the
bridge returns; the six sections the Kundali window shows (dasha periods,
ashtakavarga, dignity, aspects, nakshatra, eclipses) return plain data through
:func:`compute_data`, so the window owns the words. Calculations that had no
window and only repeated another one were removed.
"""

from __future__ import annotations

import json

NAKSHATRAS = [
    "Ashwini",
    "Bharani",
    "Krittika",
    "Rohini",
    "Mrigashira",
    "Ardra",
    "Punarvasu",
    "Pushya",
    "Ashlesha",
    "Magha",
    "Purva Phalguni",
    "Uttara Phalguni",
    "Hasta",
    "Chitra",
    "Swati",
    "Vishakha",
    "Anuradha",
    "Jyeshtha",
    "Mula",
    "Purva Ashadha",
    "Uttara Ashadha",
    "Shravana",
    "Dhanishta",
    "Shatabhisha",
    "Purva Bhadrapada",
    "Uttara Bhadrapada",
    "Revati",
]

#: The chart sections the window draws. Everything else was a duplicate or
#: had no surface to show its answer.
SECTIONS = ("dasha", "ashtakavarga", "dignity", "aspects", "nakshatra", "eclipse")

#: Every calculation compute() answers for a birth, in the groups the Kundali
#: window shows them (kundali.py run ACTION …). Labels are the window's to
#: translate; the keys are stable.
ACTION_GROUPS = (
    (
        "chart",
        (
            "fullchart",
            "bhava",
            "drishti",
            "aspects",
            "nakshatra",
            "lunarmansion",
            "nodes",
        ),
    ),
    ("dashas", ("yoginidasha", "ashtottaridasha", "charadasha", "timelords")),
    (
        "strength",
        (
            "shadbala",
            "shadbala_full",
            "vimshopaka",
            "ashtakavarga",
            "cheshta",
            "dignity",
            "combustion",
            "grahayuddha",
        ),
    ),
    (
        "points",
        (
            "arudha",
            "upagrahas",
            "upagrahas_full",
            "charakarakas",
            "karakas_full",
            "arabicparts",
            "arabicparts_full",
            "fixedstars",
        ),
    ),
    ("yogas", ("yogas", "vishesha", "vishesha_yogas")),
    ("timing", ("gochara", "muhurta", "horary", "fullpanchang", "kalamana")),
    ("sky", ("grahana", "eclipse", "meanmotion")),
    ("traditions", ("bazi", "ziwei", "chinese", "temperament")),
    ("matching", ("ashtakoota",)),
)
ACTIONS = tuple(a for _, group in ACTION_GROUPS for a in group)

#: The new calculations answer both ``compute`` (text) and ``compute_data``
#: (plain data). Every one is also in ACTION_GROUPS above.
_NEW_GROUPS = ("matching", "doshas", "kp", "annual", "lalkitab")
NEW_ACTIONS = tuple(
    a for group, names in ACTION_GROUPS if group in _NEW_GROUPS for a in names
)


def utc_instant(value: str) -> str:
    """A time as given, as a UTC ISO stamp. "1990-01-01T10:00@Asia/Kolkata" is a
    clock time in that place's zone (its offset that day, summer time and all);
    a stamp with Z or an offset is already an instant; a bare time is UTC."""
    value = str(value or "").strip()
    if not value:
        return ""
    if "@" in value:
        from datetime import datetime, timezone
        from zoneinfo import ZoneInfo

        local, zone = value.split("@", 1)
        if "T" not in local:
            local += "T12:00"
        dt = datetime.fromisoformat(local).replace(tzinfo=ZoneInfo(zone.strip()))
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if "T" not in value:
        return value + "T12:00:00Z"
    if value.endswith("Z") or "+" in value[10:] or value[10:].count("-") > 0:
        return value
    return value + "Z"


def local_parts(value: str) -> dict:
    """The birth's own wall-clock year, month, day and hour (for the Chinese
    systems, which count from local time)."""
    from datetime import datetime

    value = str(value or "").strip()
    local = value.split("@", 1)[0] if "@" in value else value.rstrip("Z")
    if "T" not in local:
        local += "T12:00"
    dt = datetime.fromisoformat(local[:19])
    return {"year": dt.year, "month": dt.month, "day": dt.day, "hour": dt.hour}


def _when(arguments: dict, key: str = "datetime") -> str:
    """The timestamp a caller gave, normalised to UTC. No silent defaults."""
    return utc_instant(arguments.get(key) or arguments.get("date") or "")


def _chart(arguments: dict, astronomy):
    """The chart behind a section, or an error string when inputs are missing."""
    when = _when(arguments)
    if not when:
        return None, "Provide a date and time"
    try:
        lat = float(arguments["latitude"])
        lon = float(arguments["longitude"])
        return astronomy.compute_full_chart_v2(when, lat, lon), ""
    except (KeyError, TypeError, ValueError) as exc:
        return None, f"Bad place or time: {exc}"
    except Exception as exc:  # noqa: BLE001 - one engine failure is one answer
        return None, f"Calculation failed: {exc}"


def compute_data(action: str, arguments: dict, astronomy) -> dict:
    """One chart section as data (stable keys, no sentences for the UI)."""
    action = str(action or "").strip().lower()
    if action in NEW_ACTIONS:
        try:
            return new_data(action, arguments, astronomy)
        except Exception as exc:  # noqa: BLE001 - one honest error for the window
            return {"error": str(exc)[:160]}
    if action not in SECTIONS:
        return {"error": f"Unknown section: {action}"}
    chart, error = _chart(arguments, astronomy)
    if error:
        return {"error": error}
    try:
        if action == "dasha":
            dasha = chart.get("dasha") or {}
            periods = [
                {
                    "lord": str(d.get("lord") or ""),
                    "years": d.get("years", 0),
                    "start_offset": d.get("start_offset", 0),
                }
                for d in (dasha.get("mahadashas") or [])
            ]
            return {"system": "Vimshottari", "periods": periods[:16]}

        if action == "ashtakavarga":
            av = chart.get("ashtakavarga") or {}
            points = av.get("sarva") or []
            signs = getattr(astronomy, "SIGNS", [])
            return {
                "rows": [
                    {
                        "sign": signs[i] if i < len(signs) else str(i),
                        "points": points[i],
                    }
                    for i in range(len(points))
                ]
            }

        if action == "dignity":
            return {
                "planets": [
                    {
                        "name": p.get("name", ""),
                        "sign": p.get("sign", ""),
                        "dignity": p.get("dignity") or "",
                    }
                    for p in chart.get("planets", [])
                ]
            }

        if action == "aspects":
            return {
                "aspects": [
                    {
                        "planet1": a.get("planet1", ""),
                        "aspect": a.get("aspect", ""),
                        "planet2": a.get("planet2", ""),
                        "orb": a.get("orb", 0),
                    }
                    for a in (chart.get("aspects") or [])
                ]
            }

        if action == "nakshatra":
            moon = next(
                (p for p in chart.get("planets", []) if p.get("name") == "Moon"), {}
            )
            lon = float(moon.get("sidereal_longitude") or 0)
            info = (
                astronomy.nakshatra_details(lon)
                if hasattr(astronomy, "nakshatra_details")
                else {}
            )
            return {
                "nakshatra": str(info.get("nakshatra") or ""),
                "pada": info.get("pada", 0),
                "lord": str(info.get("lord") or ""),
                "moon": {
                    "sign": str(moon.get("sign") or ""),
                    "degree": moon.get("degree", 0),
                    "minute": moon.get("minute", 0),
                },
            }

        # eclipse
        jd = astronomy.julian_day(_when(arguments))
        sun = astronomy._sun_longitude(jd)
        moon_lon = astronomy._moon_longitude(jd)
        info = astronomy.eclipse_details(sun, moon_lon, jd)
        return {
            "solar_eclipse": bool(info.get("solar_eclipse")),
            "lunar_eclipse": bool(info.get("lunar_eclipse")),
            "angular_separation": info.get("angular_separation", 0),
            "magnitude": info.get("magnitude", 0),
            "type": str(info.get("type") or ""),
        }
    except Exception as exc:  # noqa: BLE001 - the window shows one honest error
        return {"error": str(exc)[:160]}


def _new_chart(arguments: dict, astronomy):
    """The sidereal chart behind a new calculation (positions from compute_chart)."""
    return astronomy.compute_chart(
        _need_when(arguments),
        _need(arguments, "latitude"),
        _need(arguments, "longitude"),
    )


def _second_chart(arguments: dict, astronomy):
    """An optional second birth, for matching. Missing means self-match."""
    if arguments.get("datetime2") in (None, ""):
        return None
    when2 = utc_instant(arguments["datetime2"])
    return astronomy.compute_chart(
        when2, float(arguments["latitude2"]), float(arguments["longitude2"])
    )


def new_data(action: str, arguments: dict, astronomy) -> dict:
    """Plain data for the new calculations; no words and no UI sentences."""
    action = str(action or "").strip().lower()
    if action not in NEW_ACTIONS:
        return {"error": f"Unknown calculation: {action}"}
    chart = _new_chart(arguments, astronomy)
    if action == "ashtakoota":
        other = _second_chart(arguments, astronomy) or chart
        return astronomy.ashtakoota_guna_milan(chart, other)
    return {"error": f"Unknown calculation: {action}"}


def render_new(action: str, data: dict) -> str:
    """Readable text for one new calculation, from its plain data."""
    if "error" in data:
        return f"Calculation failed: {data['error']}"
    if action == "ashtakoota":
        lines = ["Ashtakoota Guna Milan (out of 36):"]
        for k in data["kootas"]:
            lines.append(
                f"  {k['number']}. {k['name']}: {k['score']}/{k['max']} ({k['reason']})"
            )
        lines += [
            f"  Total: {data['total']}/36 - {data['verdict']}",
            f"  Nadi dosha: {data['nadi_dosha']['present']}",
            f"  Bhakoot dosha: {data['bhakoot_dosha']['present']}",
        ]
        return "\n".join(lines)
    return "Calculation failed: no renderer"


def _need(arguments: dict, key: str) -> float:
    """A required number (latitude, longitude): missing is an error, never a default place."""
    if arguments.get(key) in (None, ""):
        raise ValueError(f"missing {key}")
    return float(arguments[key])


def _need_when(arguments: dict) -> str:
    """A required time, in UTC: missing is an error, never a default date."""
    when = _when(arguments)
    if not when:
        raise ValueError("missing date and time")
    return when


def compute(arguments: dict, astronomy) -> str:
    """Answer one kundali action with text or a JSON data object."""
    action = str(arguments.get("action") or "panchang").strip().lower()
    if action in SECTIONS:
        return json.dumps(
            compute_data(action, arguments, astronomy), ensure_ascii=False, default=str
        )

    # ---- new calculations: plain data rendered as text ----
    if action == "ashtakoota":
        try:
            return render_new(
                "ashtakoota", new_data("ashtakoota", arguments, astronomy)
            )
        except Exception as exc:  # noqa: BLE001
            return f"Calculation failed: {exc}"

    # ---- every calculation the engine offers (restored from 98075ba) ----

    if action == "nakshatra":
        lon = _need(arguments, "longitude")
        try:
            info = astronomy.nakshatra_details(lon)
            return f"Nakshatra: {info['nakshatra']} (Pada {info['pada']}, Lord: {info['lord']})"
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "dignity":
        planet = arguments.get("planet", "Sun")
        sign = arguments.get("sign", "Aries")
        try:
            info = astronomy.planet_info(planet, sign)
            return f"{planet} in {sign}: {info['dignity']}"
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "bazi":
        year = int(arguments.get("year", 2024))
        month = int(arguments.get("month", 1))
        day = int(arguments.get("day", 1))
        hour = int(arguments.get("hour", 12))
        try:
            pillars = astronomy.bazi_pillars(year, month, day, hour)
            lines = [f"BaZi for {year}-{month:02d}-{day:02d} {hour:02d}:00:"]
            for name in ["year", "month", "day", "hour"]:
                p = pillars[name]
                lines.append(
                    f"  {name.capitalize()}: {p['stem']}{p['branch']} ({p['element']})"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "aspects":
        date_str = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not date_str:
            return "Provide a date."
        if "T" not in date_str:
            date_str = date_str + "T12:00:00Z"
        elif not date_str.endswith("Z"):
            date_str = date_str + "Z"
        try:
            chart = astronomy.compute_chart(date_str, lat, lon)
            aspects = astronomy.compute_aspects(chart["planets"])
            if not aspects:
                return "No major aspects found."
            lines = ["Aspects:"]
            for a in aspects:
                lines.append(
                    f"  {a['planet1']} {a['aspect']} {a['planet2']} (orb {a['orb']}°)"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "timelords":
        date_str = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not date_str:
            return "Provide a birth datetime."
        if "T" not in date_str:
            date_str = date_str + "T12:00:00Z"
        elif not date_str.endswith("Z"):
            date_str = date_str + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(date_str, lat, lon)
            asc = chart["ascendant"]
            tl = astronomy.time_lords(date_str, asc, 0, 10)
            lines = ["Time Lords (first 10 years):", "Profections:"]
            for p in tl.get("profections", []):
                lines.append(
                    f"  Age {p['age']}: {p['sign']} (lord: {p['lord']}, house {p['house']})"
                )
            lines.append("Firdaria:")
            for f in tl.get("firdaria", []):
                lines.append(f"  {f['lord']}: {f['start']}-{f['end']} years")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "arabicparts":
        date_str = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not date_str:
            return "Provide a datetime."
        if "T" not in date_str:
            date_str = date_str + "T12:00:00Z"
        elif not date_str.endswith("Z"):
            date_str = date_str + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(date_str, lat, lon)
            asc = chart["ascendant"]
            sun = next((p for p in chart["planets"] if p["name"] == "Sun"), {})
            moon = next((p for p in chart["planets"] if p["name"] == "Moon"), {})
            venus = next((p for p in chart["planets"] if p["name"] == "Venus"), {})
            parts = astronomy.arabic_parts(
                asc, sun.get("sidereal_longitude", 0), moon.get("sidereal_longitude", 0)
            )
            lines = ["Arabic Parts (Lots):"]
            for name, val in parts.items():
                sign_idx = int(val / 30) % 12
                lines.append(f"  {name}: {astronomy.SIGNS[sign_idx]} {val % 30:.2f}°")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "temperament":
        date_str = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not date_str:
            return "Provide a datetime."
        if "T" not in date_str:
            date_str = date_str + "T12:00:00Z"
        elif not date_str.endswith("Z"):
            date_str = date_str + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(date_str, lat, lon)
            temp = astronomy.temperament(chart["planets"])
            lines = [f"Temperament: {temp['primary_temperament']}"]
            for elem, pct in temp["percentages"].items():
                lines.append(f"  {elem}: {pct}%")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "lunarmansion":
        lon = _need(arguments, "longitude")
        try:
            return f"Lunar Mansion: {astronomy.lunar_mansion(lon)}"
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "charakarakas":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            karakas = astronomy.chara_karakas(chart["planets"])
            lines = ["Chara Karakas (Jaimini):"]
            for name, planet in karakas.items():
                lines.append(f"  {name}: {planet}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "shadbala":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            lines = ["Shadbala (Simplified):"]
            for p in chart["planets"][:7]:
                sb = astronomy.shadbala(p["name"], p["sign"], p.get("house", 1))
                lines.append(
                    f"  {p['name']}: Uchcha={sb['uchcha_bala']} Kendra={sb['kendra_bala']} Ojh={sb['ojhayugma_bala']} Total={sb['total']}"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "combustion":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            sun = next((p for p in chart["planets"] if p["name"] == "Sun"), {})
            sun_lon = sun.get("sidereal_longitude", 0)
            lines = ["Combustion Check:"]
            for p in chart["planets"]:
                if p["name"] in (
                    "Moon",
                    "Mercury",
                    "Venus",
                    "Mars",
                    "Jupiter",
                    "Saturn",
                ):
                    comb = astronomy.is_combust(
                        p["name"], p["sidereal_longitude"], sun_lon
                    )
                    lines.append(
                        f"  {p['name']}: {'Combust' if comb else 'Not combust'}"
                    )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "horary":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        qh = int(arguments.get("quesited_house", 7))
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            h = astronomy.horary_chart(dt, lat, lon, qh)
            lines = [f"Horary Chart for {dt}:"]
            lines.append(f"  Querent significator: {h['querent_significator']}")
            lines.append(
                f"  Quesited significator (House {qh}): {h['quesited_lord'] if 'quesited_lord' in h else h.get('quesited_significator', '')}"
            )
            lines.append(f"  Same significator: {h['same_significator']}")
            lines.append(f"  Moon void of course: {h['moon_void_of_course']}")
            lines.append(f"  Planetary hour ruler: {h['planetary_hour_ruler']}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "upagrahas":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            sun = next((p for p in chart["planets"] if p["name"] == "Sun"), {})
            sun_lon = sun.get("sidereal_longitude", 0)
            kala = astronomy.upagraha_kala(sun_lon)
            mrityu = astronomy.upagraha_mrityu(sun_lon)
            lines = ["Upagrahas:"]
            lines.append(
                f"  Kala: {astronomy.SIGNS[int(kala / 30) % 12]} {kala % 30:.2f}°"
            )
            lines.append(
                f"  Mrityu: {astronomy.SIGNS[int(mrityu / 30) % 12]} {mrityu % 30:.2f}°"
            )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "fullchart":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            # Return full chart as JSON
            return json.dumps(chart, indent=2, default=str)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "arudha":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            arudhas = astronomy.all_arudhas(chart["planets"], chart["houses"])
            lines = ["Arudha Padas:"]
            for name, sign in arudhas.items():
                lines.append(f"  {name}: {sign}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "drishti":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            asc_idx = int(chart["ascendant"] / 30) % 12
            drishtis = astronomy.find_vedic_aspects(chart["planets"], asc_idx)
            if not drishtis:
                return "No Vedic aspects found."
            lines = ["Vedic Drishti (Aspects):"]
            for d in drishtis[:20]:
                lines.append(
                    f"  {d['from']} -> {d['to']}: {d['houses_away']} houses ({d['strength']}%)"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "vishesha":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            sun = next((p for p in chart["planets"] if p["name"] == "Sun"), {})
            sun_sid = sun.get("sidereal_longitude", 0)
            lines = ["Vishesha (Special) Lagnas:"]
            lines.append(
                f"  Hora Lagna: {astronomy.SIGNS[int(astronomy.hora_lagna_full(sun_sid, astronomy.julian_day(dt)) / 30) % 12]}"
            )
            lines.append(
                f"  Ghati Lagna: {astronomy.SIGNS[int(astronomy.ghati_lagna_full(sun_sid) / 30) % 12]}"
            )
            lines.append(
                f"  Bhava Lagna: {astronomy.SIGNS[int(astronomy.bhava_lagna_full(sun_sid) / 30) % 12]}"
            )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "muhurta":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            result = astronomy.muhurta_score(dt, lat, lon)
            lines = [f"Muhurta Score: {result['score']} ({result['verdict']})"]
            lines.append(f"  Vara: {result['vara']}")
            for f in result.get("factors", []):
                lines.append(f"  {f['code']}: {f['weight']}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "vimshopaka":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            lines = ["Vimshopaka Bala (Shadvarga):"]
            for p in chart["planets"][:7]:
                vb = astronomy.vimshopaka_bala(p["name"], p["sign"], "shadvarga")
                lines.append(f"  {p['name']}: {vb}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "cheshta":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            lines = ["Cheshta (Motion States):"]
            for p in chart["planets"][:7]:
                state = astronomy.cheshta_state(1.0, 1.0)  # simplified
                lines.append(f"  {p['name']}: {state}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "grahayuddha":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            planets = chart["planets"]
            results = []
            for i in range(len(planets)):
                for j in range(i + 1, len(planets)):
                    gy = astronomy.graha_yuddha(
                        planets[i]["name"],
                        planets[i]["sidereal_longitude"],
                        planets[j]["name"],
                        planets[j]["sidereal_longitude"],
                    )
                    if gy["in_war"]:
                        results.append(gy)
            if not results:
                return "No planetary wars found."
            lines = ["Graha Yuddha (Planetary Wars):"]
            for r in results:
                lines.append(
                    f"  {r['planet1']} vs {r['planet2']}: sep {r['separation']}° (winner: {r['winner']})"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "upagrahas_full":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            sun = next((p for p in chart["planets"] if p["name"] == "Sun"), {})
            sun_sid = sun.get("sidereal_longitude", 0)
            upags = astronomy.all_upagrahas(sun_sid, True)
            lines = ["Upagrahas:"]
            for name, val in upags.items():
                sign_idx = int(val / 30) % 12
                lines.append(f"  {name}: {astronomy.SIGNS[sign_idx]} {val % 30:.2f}°")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "ashtakavarga":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            asc_sign = int(chart["ascendant"] / 30) % 12
            av = astronomy.ashtakavarga_full(chart["planets"], asc_sign)
            lines = ["Ashtakavarga (Sarva):"]
            for i, v in enumerate(av["sarva"]):
                lines.append(f"  {astronomy.SIGNS[i]}: {v}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "gochara":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            natal_moon = next((p for p in chart["planets"] if p["name"] == "Moon"), {})
            natal_moon_sign = int(natal_moon.get("sidereal_longitude", 0) / 30) % 12
            goch = astronomy.gochara(natal_moon_sign, chart["planets"])
            lines = ["Gochara (Transit from Moon):"]
            for planet, info in goch.items():
                fav = "Favorable" if info["favorable"] else "Unfavorable"
                lines.append(f"  {planet}: House {info['house_from_moon']} ({fav})")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "bhava":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            bh = astronomy.bhava_analysis(chart["planets"], chart["houses"])
            lines = ["Bhava (House) Analysis:"]
            for name, info in bh.items():
                tags = []
                if info["is_kendra"]:
                    tags.append("Kendra")
                if info["is_trikona"]:
                    tags.append("Trikona")
                if info["is_dusthana"]:
                    tags.append("Dusthana")
                if info["is_upachaya"]:
                    tags.append("Upachaya")
                planets = ", ".join(info["planets"]) if info["planets"] else "empty"
                lines.append(
                    f"  {name}: {info['sign']} [{', '.join(tags)}] planets: {planets}"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "kalamana":
        dt = _when(arguments)
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            jd = astronomy.julian_day(dt)
            km = astronomy.kala_mana(jd)
            kh = astronomy.kala_khanda(jd)
            lines = ["Kala Mana (Time):"]
            lines.append(f"  Julian Day: {km['julian_day']}")
            lines.append(f"  Day number: {km['day_number']}")
            lines.append(f"  Hour of day: {kh['hour_of_day']}")
            lines.append(f"  Ghati: {kh['ghati']}")
            lines.append(f"  Vighati: {kh['vighati']}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "chinese":
        dt = _when(arguments)
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            cc = astronomy.chinese_calendar(dt)
            lines = ["Chinese Calendar:"]
            for k, v in cc.items():
                lines.append(f"  {k}: {v}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "grahana":
        dt = _when(arguments)
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            jd = astronomy.julian_day(dt)
            sun = astronomy._sun_longitude(jd)
            moon = astronomy._moon_longitude(jd)
            g = astronomy.khagola_grahana(sun, moon)
            lines = ["Grahana (Eclipse) Check:"]
            lines.append(f"  Solar eclipse: {g['solar_eclipse']}")
            lines.append(f"  Lunar eclipse: {g['lunar_eclipse']}")
            lines.append(f"  Angular separation: {g['angular_separation']}°")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "shadbala_full":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            jd = astronomy.julian_day(dt)
            lines = ["Shadbala (Complete):"]
            for p in chart["planets"][:7]:
                sb = astronomy.shadbala_complete(
                    p["name"],
                    p["sign"],
                    p.get("house", 1),
                    True,
                    chart["planets"][1]["sidereal_longitude"]
                    if len(chart["planets"]) > 1
                    else 0,
                    chart["planets"][0]["sidereal_longitude"],
                    jd,
                )
                lines.append(
                    f"  {p['name']}: Nais={sb['naisargika']} Kendra={sb['kendra']} Dig={sb['dig']} Cheshta={sb['cheshta']} Total={sb['total']}"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "karakas_full":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            karakas = astronomy.chara_karakas_full(chart["planets"])
            lines = ["Chara Karakas (Full, with Rahu reflection):"]
            for name, info in karakas.items():
                lines.append(f"  {name}: {info['planet']} ({info['degree']}°)")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "fixedstars":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            jd = astronomy.julian_day(dt)
            points = [p["sidereal_longitude"] for p in chart["planets"]]
            ayan = chart["ayanamsa"]
            stars = astronomy.fixed_stars_conjunct(jd, points, 2.0, True, ayan)
            if not stars:
                return "No fixed stars conjunct chart points."
            lines = ["Fixed Stars:"]
            for s in stars[:20]:
                lines.append(
                    f"  {s['star']}: conjunct point at {s['point']}° (orb {s['orb']}°)"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "arabicparts_full":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            asc = chart["ascendant"]
            sun = next((p for p in chart["planets"] if p["name"] == "Sun"), {})
            moon = next((p for p in chart["planets"] if p["name"] == "Moon"), {})
            venus = next((p for p in chart["planets"] if p["name"] == "Venus"), {})
            mars = next((p for p in chart["planets"] if p["name"] == "Mars"), {})
            mercury = next((p for p in chart["planets"] if p["name"] == "Mercury"), {})
            jupiter = next((p for p in chart["planets"] if p["name"] == "Jupiter"), {})
            saturn = next((p for p in chart["planets"] if p["name"] == "Saturn"), {})
            parts = astronomy.arabic_parts_full(
                asc,
                sun.get("sidereal_longitude", 0),
                moon.get("sidereal_longitude", 0),
                venus.get("sidereal_longitude", 0),
                mars.get("sidereal_longitude", 0),
                mercury.get("sidereal_longitude", 0),
                jupiter.get("sidereal_longitude", 0),
                saturn.get("sidereal_longitude", 0),
            )
            lines = ["Arabic Parts (Full):"]
            for name, val in parts.items():
                sign_idx = int(val / 30) % 12
                lines.append(f"  {name}: {astronomy.SIGNS[sign_idx]} {val % 30:.2f}°")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "fullpanchang":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a date."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            pc = astronomy.compute_full_panchang(dt, lat, lon)
            lines = [f"Full Panchang for {dt}:"]
            for k, v in pc.items():
                lines.append(f"  {k}: {v}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "yogas":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            yogas = astronomy.vishesha_yogas_full(chart["planets"])
            return "Vishesha Yogas:\n" + "\n".join(f"  {y}" for y in yogas)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "nodes":
        dt = _when(arguments)
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            jd = astronomy.julian_day(dt)
            mean = astronomy.node_mean(jd)
            true = astronomy.node_true(jd)
            osc = astronomy.node_osculating(jd)
            return f"Nodes:\n  Mean (Rahu): {mean:.4f}\n  True (Rahu): {true:.4f}\n  Osculating (Rahu): {osc:.4f}\n  Ketu: {(mean + 180) % 360:.4f}"
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "eclipse":
        dt = _when(arguments)
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            jd = astronomy.julian_day(dt)
            sun = astronomy._sun_longitude(jd)
            moon = astronomy._moon_longitude(jd)
            e = astronomy.eclipse_details(sun, moon, jd)
            lines = ["Eclipse Check:"]
            lines.append(f"  Solar eclipse: {e['solar_eclipse']}")
            lines.append(f"  Lunar eclipse: {e['lunar_eclipse']}")
            lines.append(f"  Angular separation: {e['angular_separation']}°")
            lines.append(f"  Magnitude: {e['magnitude']}")
            lines.append(f"  Type: {e['type']}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "charadasha":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            asc_sign = int(chart["ascendant"] / 30) % 12
            positions = {
                p["name"]: int(p["sidereal_longitude"] / 30) % 12
                for p in chart["planets"]
            }
            dashas = astronomy.chara_dasha(asc_sign, positions)
            lines = ["Chara Dasha (Jaimini):"]
            for d in dashas[:6]:
                lines.append(f"  {d['sign']}: {d['years']} years")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "yoginidasha":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            moon = next((p for p in chart["planets"] if p["name"] == "Moon"), {})
            dashas = astronomy.yogini_dasha(
                moon.get("sidereal_longitude", 0), astronomy.julian_day(dt)
            )
            lines = ["Yogini Dasha:"]
            for d in dashas[:8]:
                lines.append(
                    f"  {d['lord']}: {d['years']} years (from +{d['start_offset']})"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "ashtottaridasha":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            moon = next((p for p in chart["planets"] if p["name"] == "Moon"), {})
            dashas = astronomy.ashtottari_dasha(moon.get("sidereal_longitude", 0))
            lines = ["Ashtottari Dasha:"]
            for d in dashas:
                lines.append(
                    f"  {d['lord']}: {d['years']} years (from +{d['start_offset']})"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "ziwei":
        year = int(arguments.get("year", 2024))
        month = int(arguments.get("month", 1))
        day = int(arguments.get("day", 1))
        hour = int(arguments.get("hour", 12))
        try:
            zw = astronomy.zi_wei_basic(year, month, day, hour)
            lines = [f"Zi Wei Dou Shu for {year}-{month:02d}-{day:02d} {hour:02d}:00:"]
            lines.append(f"  Life Palace: {zw['life_palace']}")
            lines.append(f"  Bureau: {zw['bureau']}")
            lines.append("  Palaces:")
            for name, info in zw["palaces"].items():
                lines.append(f"    {name}: Palace {info['palace']}")
            return "\n".join(lines)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "vishesha_yogas":
        dt = _when(arguments)
        lat = _need(arguments, "latitude")
        lon = _need(arguments, "longitude")
        if not dt:
            return "Provide a datetime."
        if "T" not in dt:
            dt = dt + "T12:00:00Z"
        elif not dt.endswith("Z"):
            dt = dt + "Z"
        try:
            chart = astronomy.compute_full_chart_v2(dt, lat, lon)
            yogas = astronomy.vishesha_yogas_comprehensive(chart["planets"])
            return "Vishesha Yogas:\n" + "\n".join(f"  {y}" for y in yogas)
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "meanmotion":
        planet = arguments.get("planet", "Sun")
        try:
            mm = astronomy.mean_motion_full(planet)
            return f"{mm['planet']}: {mm['degrees_per_day']}°/day ({mm['degrees_per_year']}°/year)"
        except Exception as exc:
            return f"Failed: {exc}"

    if action == "panchang":
        date_str = _when(arguments, "date")
        if not date_str:
            return "Provide a date."
        try:
            p = astronomy.compute_panchang(
                date_str,
                float(arguments.get("latitude", 0)),
                float(arguments.get("longitude", 0)),
            )
            return "\n".join(
                [
                    f"Panchang for {date_str} ({arguments.get('latitude', 0)}, {arguments.get('longitude', 0)}):",
                    f"  Tithi: {p['tithi']}",
                    f"  Vara: {p['vara']}",
                    f"  Nakshatra: {p['nakshatra']}",
                    f"  Yoga: {p['yoga']}",
                    f"  Karana: {p['karana']}",
                    f"  Sun: {p['sun_longitude']}°  Moon: {p['moon_longitude']}°",
                    f"  Ayanamsa (Lahiri): {p['ayanamsa']}°",
                ]
            )
        except Exception as exc:  # noqa: BLE001
            return f"Panchang calculation failed: {exc}"

    if action in ("kundali", "chart"):
        date_str = _when(arguments)
        if not date_str:
            return "Provide a birth datetime."
        try:
            chart = astronomy.compute_full_chart_v2(
                date_str,
                float(arguments.get("latitude", 0)),
                float(arguments.get("longitude", 0)),
            )
            lines = [
                f"Kundali (Sidereal, Lahiri) for {date_str} ({arguments.get('latitude', 0)}, {arguments.get('longitude', 0)}):",
                "",
                f"Ascendant: {chart['ascendant_sign']} {int(chart['ascendant'] % 30)}°",
                f"Ayanamsa (Lahiri): {chart['ayanamsa']}°",
                "",
                "Planets:",
            ]
            for p in chart.get("planets", []):
                retro = " (R)" if p.get("retrograde") else ""
                dig = p.get("dignity", "")
                lines.append(
                    f"  {p['name']}: {p['sign']} {p['degree']}°{p['minute']:02d}'{retro} ({dig})"
                )
            lines += ["", "Houses (Whole Sign):"]
            for h in chart.get("houses", []):
                lines.append(
                    f"  House {h['house_number']}: {h['sign']} {h['degree']}°{h['minute']:02d}'"
                )
            lines += ["", "Navamsha (D9):"]
            for p in chart.get("planets", []):
                v = astronomy.varga_longitude(p["sidereal_longitude"], "D9")
                sign_idx = int(v / 30) % 12
                lines.append(
                    f"  {p['name']}: {astronomy.SIGNS[sign_idx]} {int(v % 30)}°"
                )
            return "\n".join(lines)
        except Exception as exc:  # noqa: BLE001
            return f"Kundali calculation failed: {exc}"

    return "Unknown action. Use 'panchang', 'kundali' or a chart section."
