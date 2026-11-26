#!/usr/bin/env python3
"""Deterministic FM tuner stand-in for dev/shell-parts/devices.sh and radio.sh.

No aerial, no rtl_fm: the radio's tuning state is one small JSON file. What is
asked is logged to $SHANI_FM_LOG, so a live check can see each verb. Reports
answer in the engine's own plain words, without doing any signal processing;
arguments the real engine refuses are refused here too.

  fake-fm.py state                  {"ok":true,"state":"stopped","frequency":0}
  fake-fm.py start [frequency]      state "running"; keeps the last frequency
  fake-fm.py tune <frequency>       change frequency; keep playing state
  fake-fm.py stop                   state "stopped"; frequency kept
  fake-fm.py bands                  the band report
  fake-fm.py volume <0-100[%]>      the radio's own volume
  fake-fm.py decode <capture.wav>   a recording's report
  fake-fm.py scan <capture.wav>     a whole-band recording's report

Env:
  SHANI_FM_STATE   state file (default /tmp/fake-fm-state.json)
  SHANI_FM_LOG     call log (default /tmp/fake-fm-calls)
"""

from __future__ import annotations

import json
import os
import sys
import wave
from pathlib import Path

DEFAULT_FREQUENCY = 98.5
ACTIONS = ("hardware", "bands", "scan", "tune", "stop", "volume", "decode")
BANDS = {
    "FM": (87.5, 108.0),
    "AM": (0.53, 1.71),
    "DAB": (174.0, 240.0),
    "Japan FM": (76.0, 90.0),
}


def state_path() -> Path:
    return Path(os.environ.get("SHANI_FM_STATE", "/tmp/fake-fm-state.json"))


def load() -> dict:
    try:
        data = json.loads(state_path().read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    return {"ok": True, "state": "stopped", "frequency": 0}


def save(row: dict) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(row), encoding="utf-8")


def refuse(why: str) -> int:
    print(why, file=sys.stderr)
    return 2


def volume(raw: str) -> tuple[float | None, str]:
    """The same 0-100 (or 0.0-1.0) percentage the real engine takes."""
    text = str(raw or "").strip().rstrip("%")
    try:
        value = float(text)
    except ValueError:
        return None, f"{raw!r} is not a volume; pass 0-100. Nothing was changed."
    if value > 1.0:
        value /= 100.0
    if not 0.0 <= value <= 1.0:
        return None, f"{raw!r} is outside 0-100. Nothing was changed."
    return value, ""


def capture(path: str) -> tuple[int, int, str]:
    """The WAV shape read_iq_wav demands, or the reason it cannot be read."""
    try:
        with wave.open(os.path.expanduser(path), "rb") as handle:
            channels = handle.getnchannels()
            width = handle.getsampwidth()
            rate = handle.getframerate()
            frames = handle.getnframes()
    except (OSError, wave.Error) as exc:
        raise ValueError(f"could not read {path}: {exc}") from exc
    if width != 2:
        raise ValueError(f"expected 16-bit samples, this file is {width * 8}-bit")
    if channels != 2:
        raise ValueError(
            "expected stereo IQ (real in one channel, imaginary in the other), "
            f"this file has {channels} channel(s)"
        )
    return frames, rate, os.path.expanduser(path)


def report(cmd: str, raw: str) -> int:
    if cmd == "bands":
        lines = ["What bands this can cover:"]
        for name, (low, high) in BANDS.items():
            lines.append(f"  {name}: {low:g}-{high:g} MHz")
        lines.append("")
        lines.append(
            "Only FM and AM are broadcast radio. DAB is digital and needs a "
            "decoder this skill does not have - it is listed so the absence "
            "is named rather than silent."
        )
        print("\n".join(lines))
        return 0
    if cmd == "volume":
        value, why = volume(raw)
        if value is None:
            return refuse(why)
        print(f"Radio volume {round(value * 100)}%.")
        return 0
    if cmd in ("decode", "scan"):
        if not raw.strip():
            first = "Decode what?" if cmd == "decode" else "Scan what?"
            thing = (
                "a recorded IQ capture"
                if cmd == "decode"
                else "a whole-band IQ capture to search"
            )
            return refuse(f"{first} Pass file, {thing}. Nothing was received.")
        try:
            frames, rate, path = capture(raw)
        except ValueError as exc:
            return refuse(f"{exc}. Nothing was received.")
        seconds = frames / rate if rate else 0.0
        if cmd == "decode":
            if frames < 8:
                return refuse(
                    f"{path} holds {frames} samples, which is too few to demodulate. Nothing was received."
                )
            print(
                f"Demodulated {frames:,} audio samples ({seconds:.2f}s at 32,000 Hz) "
                f"from {path}, which was captured at {rate:,} Hz.\n"
                "Peak audio level: 0.123\n"
                "No dominant tone, which is what speech sounds like here."
            )
        else:
            if frames < rate // 10:
                return refuse(
                    f"{path} holds only {seconds:.2f}s, too short to say anything about carriers. Nothing was received."
                )
            print(
                f"Searched {path} ({seconds:.2f}s).\n"
                "  No strong carrier tone found in the demodulated audio\n\n"
                "A wideband recording shows carriers; naming them needs a station "
                "list for your region, which this skill does not carry, and a wrong "
                "station name is worse than a frequency."
            )
        return 0
    return refuse(
        f"action must be one of {', '.join(ACTIONS)}, not {cmd!r}. Nothing was done."
    )


def main() -> int:
    argv = sys.argv[1:]
    try:
        path = Path(os.environ.get("SHANI_FM_LOG", "/tmp/fake-fm-calls"))
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(" ".join(argv) + "\n")
    except OSError:
        pass  # logging must never stop the radio answer

    cmd = (argv[0] if argv else "state").strip().lower()
    arg = argv[1] if len(argv) > 1 else ""
    if cmd not in (
        "state",
        "start",
        "tune",
        "stop",
        "bands",
        "volume",
        "decode",
        "scan",
    ):
        return report(cmd, arg)  # the same refusal the real engine gives
    if cmd in ("bands", "volume", "decode", "scan"):
        return report(cmd, arg)

    row = load()
    if cmd == "start":
        try:
            freq = float(arg) if arg else float(row.get("frequency") or 0)
        except ValueError:
            freq = float(row.get("frequency") or 0)
        if not freq:
            freq = DEFAULT_FREQUENCY
        row = {"ok": True, "state": "running", "frequency": freq}
        save(row)
    elif cmd == "tune" and arg:
        try:
            row["frequency"] = float(arg)
        except ValueError:
            pass
        row["ok"] = True
        save(row)
    elif cmd == "stop":
        row["ok"] = True
        row["state"] = "stopped"
        save(row)

    print(
        json.dumps(
            {
                "ok": bool(row.get("ok", True)),
                "state": str(row.get("state", "stopped")),
                "frequency": row.get("frequency", 0),
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
