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


def _when(arguments: dict, key: str = "datetime") -> str:
    """The timestamp a caller gave, normalised to UTC. No silent defaults."""
    value = str(arguments.get(key) or arguments.get("date") or "").strip()
    if not value:
        return ""
    if "T" not in value:
        return value + "T12:00:00Z"
    return value if value.endswith("Z") else value + "Z"


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


def compute(arguments: dict, astronomy) -> str:
    """Answer one kundali action with text or a JSON data object."""
    action = str(arguments.get("action") or "panchang").strip().lower()
    if action in SECTIONS:
        return json.dumps(
            compute_data(action, arguments, astronomy), ensure_ascii=False, default=str
        )

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
