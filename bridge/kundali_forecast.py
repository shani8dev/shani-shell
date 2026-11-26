#!/usr/bin/env python3
"""The days ahead for a saved birth: the indications a Kundali reader looks at
first, as data (the window and the notifications word them).

    kundali_forecast.py BIRTH LAT LON [START] [DAYS]
        BIRTH  "1990-01-01T12:00@Asia/Kolkata" (or a UTC stamp)
        START  the first day, YYYY-MM-DD (default: today, this computer's date)
        DAYS   how many days (default 7, at most 60)

Per day (four looks a day, so a condition that holds for part of it counts):
- chandrashtama: the Moon in the 8th sign from the birth Moon - a hard day
- tara: the Moon's nakshatra counted from the birth nakshatra; Vipat (3),
  Pratyak (5) and Naidhana (7) are unfavourable, Janma (1) is a day for care,
  Sampat (2), Kshema (4), Sadhana (6), Mitra (8), Parama mitra (9) favourable
Across the days:
- the Vimshottari mahadasha and antardasha that begin
- Saturn's and Jupiter's sign changes
And now: the running mahadasha / antardasha; Saturn's place from the birth
Moon (Sade Sati: 12th, 1st, 2nd; kantaka: 4th; ashtama: 8th); Jupiter in the
8th or 12th from the Moon.

These are the traditional indications, not certainties; the wording that
reaches a person says so.
"""
from __future__ import annotations

import json
import sys
from datetime import date, datetime, timedelta, timezone

import astronomy
import kundali_engine

TARAS = ["janma", "sampat", "vipat", "kshema", "pratyak", "sadhana", "naidhana", "mitra", "parama_mitra"]
HARD_TARAS = {"vipat", "pratyak", "naidhana"}
GOOD_TARAS = {"sampat", "kshema", "sadhana", "mitra", "parama_mitra"}


def _sid(name: str, jd: float) -> float:
    k = name.lower()
    trop = astronomy._moon_longitude(jd) if k == "moon" else astronomy._sun_longitude(jd) if k == "sun" \
        else astronomy._planet_longitude(k, jd)
    return (trop - astronomy.ayanamsa_lahiri(jd)) % 360


def _jd(dt: datetime) -> float:
    return astronomy.julian_day(dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))


def _periods(chart: dict, born: datetime) -> list:
    """Every mahadasha and antardasha with its start and end as dates."""
    out = []
    for md in (chart.get("dasha") or {}).get("mahadashas", []):
        md_start = born + timedelta(days=md["start_offset"] * 365.25)
        out.append({"level": "mahadasha", "lord": md["lord"], "start": md_start,
                    "end": md_start + timedelta(days=md["years"] * 365.25)})
        for ad in md.get("antardashas", []):
            ad_start = born + timedelta(days=(md["start_offset"] + ad["start_offset"]) * 365.25)
            out.append({"level": "antardasha", "lord": ad["lord"], "within": md["lord"], "start": ad_start,
                        "end": ad_start + timedelta(days=ad["years"] * 365.25)})
    return out


def forecast(birth: str, lat: float, lon: float, start: date | None = None, days: int = 7) -> dict:
    stamp = kundali_engine.utc_instant(birth)
    if not stamp:
        return {"error": "missing birth date and time"}
    born = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    chart = astronomy.compute_full_chart_v2(stamp, lat, lon)
    moon = next(p for p in chart["planets"] if p["name"] == "Moon")
    moon_sign = int(moon["sidereal_longitude"] // 30) % 12
    birth_nak = int(moon["sidereal_longitude"] // (360 / 27)) % 27
    start = start or date.today()
    days = max(1, min(60, int(days)))

    out_days = []
    for i in range(days):
        d = start + timedelta(days=i)
        reasons, tone = [], ""
        looks = [datetime(d.year, d.month, d.day, h, tzinfo=timezone.utc) for h in (0, 6, 12, 18)]
        signs = {int(_sid("moon", _jd(t)) // 30) % 12 for t in looks}
        if (moon_sign + 7) % 12 in signs:
            reasons.append({"code": "chandrashtama"})
        naks = [int(_sid("moon", _jd(t)) // (360 / 27)) % 27 for t in looks]
        taras = [TARAS[((n - birth_nak) % 27) % 9] for n in naks]
        tara = max(set(taras), key=taras.count)      # the one that holds most of the day
        if tara in HARD_TARAS:
            reasons.append({"code": "tara", "tara": tara})
        elif tara == "janma":
            reasons.append({"code": "tara", "tara": tara})
        if any(r["code"] == "chandrashtama" for r in reasons) or (tara in HARD_TARAS and tara == "naidhana"):
            tone = "difficult"
        elif reasons:
            tone = "caution"
        elif tara in GOOD_TARAS:
            tone = "good"
        out_days.append({"date": d.isoformat(), "tone": tone, "tara": tara, "reasons": reasons})

    # what changes across the days: a period beginning, Saturn or Jupiter changing sign
    first = datetime(start.year, start.month, start.day, tzinfo=timezone.utc)
    last = first + timedelta(days=days)
    periods = _periods(chart, born)
    changes = [{"date": p["start"].date().isoformat(), "kind": p["level"], "lord": p["lord"],
                "within": p.get("within", "")}
               for p in periods if first <= p["start"] < last]
    for planet in ("saturn", "jupiter"):
        prev = int(_sid(planet, _jd(first)) // 30) % 12
        for i in range(1, days + 1):
            s = int(_sid(planet, _jd(first + timedelta(days=i))) // 30) % 12
            if s != prev:
                changes.append({"date": (first + timedelta(days=i)).date().isoformat(), "kind": "ingress",
                                "planet": planet.capitalize(), "sign": astronomy.SIGNS[s],
                                "from_moon": (s - moon_sign) % 12 + 1})
                prev = s
    # Sade Sati: a phase that begins inside the days; and the phases, with dates
    sati = {}
    try:
        sati = astronomy.sade_sati(chart, first.strftime("%Y-%m-%dT%H:%M:%SZ"))
        for ph in sati.get("phases", []):
            begins = datetime.fromisoformat(ph["start"].replace("Z", "+00:00"))
            if first <= begins < last:
                changes.append({"date": begins.date().isoformat(), "kind": "sade_sati", "phase": ph.get("name", "")})
    except Exception:  # noqa: BLE001 - the rest of the forecast stands without it
        sati = {}
    changes.sort(key=lambda c: c["date"])

    # now: the running periods, Saturn and Jupiter from the birth Moon
    now = datetime.now(timezone.utc)
    running = {p["level"]: {"lord": p["lord"], "until": p["end"].date().isoformat()}
               for p in periods if p["start"] <= now < p["end"]}
    sat = (int(_sid("saturn", _jd(now)) // 30) % 12 - moon_sign) % 12 + 1
    jup = (int(_sid("jupiter", _jd(now)) // 30) % 12 - moon_sign) % 12 + 1
    saturn = {12: "sade_sati_rising", 1: "sade_sati_peak", 2: "sade_sati_setting", 4: "kantaka", 8: "ashtama"}.get(sat, "")
    status = {
        "mahadasha": running.get("mahadasha"),
        "antardasha": running.get("antardasha"),
        "saturn_from_moon": sat, "saturn": saturn,
        "jupiter_from_moon": jup, "jupiter": "hard" if jup in (8, 12) else ("good" if jup in (2, 5, 7, 9, 11) else ""),
        "sade_sati": {"running": bool(sati.get("running")), "phase": sati.get("phase_name"),
                      "phases": [{"name": p.get("name"), "start": p["start"][:10], "end": p["end"][:10]}
                                 for p in sati.get("phases", [])]},
        "moon_sign": astronomy.SIGNS[moon_sign],
        "nakshatra": (moon.get("nakshatra") or {}).get("nakshatra", ""),
    }
    return {"birth": stamp, "start": start.isoformat(), "days": out_days, "changes": changes, "now": status}


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(json.dumps({"error": "usage: kundali_forecast.py BIRTH LAT LON [START] [DAYS]"}))
        return 2
    try:
        start = date.fromisoformat(argv[4]) if len(argv) > 4 and argv[4] else None
        result = forecast(argv[1], float(argv[2]), float(argv[3]), start, int(argv[5]) if len(argv) > 5 else 7)
    except Exception as exc:  # noqa: BLE001 - never a traceback to the UI
        result = {"error": f"{type(exc).__name__}: {exc}"}
    print(json.dumps(result, ensure_ascii=False))
    return 1 if result.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
