#!/usr/bin/env python3
"""ups - the UPS this computer runs on, from NUT (shani-peripherals ships it,
shani-settings enables its server and monitor).

    ups.py                    {"present": false} or
                              {"present": true, "name", "model", "onBattery", "low",
                               "charge": 0-100, "minutes": n, "load": 0-100}
    ups.py policy             {"present", "file", "service", "monitored", "keys", "error"}
    ups.py policy-save        JSON on stdin with the seven keys; {"ok", "error", "keys"}
                              (also {"field"} when a value is refused)

UPower does not see a UPS behind NUT, so a desktop on a UPS showed nothing during a
power cut - the moment it matters most. `upsc` reads upsd's variables; the first
UPS on localhost is the one reported. SHANI_UPSC replaces `upsc` (the tests).

The policy half reads and writes the seven shutdown directives in upsmon.conf.
Writes go through shani-cassini-save with the new full content on stdin and a
sha256 the helper checks; the payload is never in argv, a log or this output.
SHANI_UPSMON_CONF, SHANI_SYSTEMCTL, SHANI_SYSTEM_PKEXEC and SHANI_CASSINI_SAVE
replace the paths and commands (the tests).
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

UPSC = os.environ.get("SHANI_UPSC", "upsc")
# SHANI_SYSTEM_* are the system pages' own harness overrides; the shorter
# names remain for callers and tests outside that harness.
UPSMON_CONF = os.environ.get(
    "SHANI_SYSTEM_UPSMON_CONF",
    os.environ.get("SHANI_UPSMON_CONF", "/etc/nut/upsmon.conf"),
)
SYSTEMCTL = shlex.split(
    os.environ.get(
        "SHANI_SYSTEM_UPS_SYSTEMCTL", os.environ.get("SHANI_SYSTEMCTL", "systemctl")
    )
)
PKEXEC = shlex.split(os.environ.get("SHANI_SYSTEM_PKEXEC", "pkexec"))
SAVE = os.environ.get(
    "SHANI_SYSTEM_CASSINI_SAVE",
    os.environ.get("SHANI_CASSINI_SAVE", "/usr/local/bin/shani-cassini-save"),
)
MAX_BYTES = 16384

# The seven directives the policy editor owns, in the order it shows them.
POLICY = {
    "MINSUPPLIES": "1",
    "SHUTDOWNCMD": '"/sbin/shutdown -h +0"',
    "POWERDOWNFLAG": "/etc/killpower",
    "DEADTIME": "15",
    "FINALDELAY": "0",
    "POLLFREQ": "5",
    "POLLFREQALERT": "5",
}
KEYS = tuple(POLICY)
# The bounds are the editor's, stricter than the deploy helper's validator: a
# value that cannot fire a shutdown is refused before asking for root.
BOUNDS = {
    "MINSUPPLIES": (1, 8),
    "DEADTIME": (1, 600),
    "FINALDELAY": (0, 600),
    "POLLFREQ": (1, 600),
    "POLLFREQALERT": (1, 600),
}
DIRECTIVE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)(?:\s+|=)(.*)$")


def run(*args: str) -> str:
    try:
        return subprocess.run(
            [UPSC, *args], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def number(v: str | None) -> float | None:
    try:
        return float(v) if v is not None else None
    except ValueError:
        return None


def read() -> dict:
    names = run("-l", "localhost").split()
    if not names:
        return {"present": False}
    name = names[0]
    var = {}
    for line in run(f"{name}@localhost").splitlines():
        k, sep, v = line.partition(":")
        if sep:
            var[k.strip()] = v.strip()
    status = var.get("ups.status", "").split()
    runtime = number(var.get("battery.runtime"))
    return {
        "present": True,
        "name": name,
        "model": " ".join(
            x
            for x in (
                var.get("device.mfr") or var.get("ups.mfr"),
                var.get("device.model") or var.get("ups.model"),
            )
            if x
        ),
        "onBattery": "OB" in status,
        "low": "LB" in status,
        "charge": number(var.get("battery.charge")),
        "minutes": round(runtime / 60) if runtime is not None else None,
        "load": number(var.get("ups.load")),
    }


# ---- upsmon.conf policy: plain functions returning data ---------------------


def read_conf() -> tuple[str | None, str]:
    try:
        with open(UPSMON_CONF, encoding="utf-8", errors="replace", newline="") as fh:
            return fh.read(), ""
    except FileNotFoundError:
        return None, "NUT is not configured (no upsmon.conf)"
    except OSError as exc:
        return None, f"could not read upsmon.conf: {exc}"[:200]


def split_directive(line: str) -> tuple[str, str]:
    """(KEY, value) for one upsmon.conf line, or ("", "") for prose and comments.

    upsmon.conf is a DIRECTIVE file (`KEY value`, no sections), not the
    INI-like ups.conf beside it. `KEY=value` is tolerated as well. Inline `#`
    comments are stripped, as the deploy helper's validator does.
    """
    body = line.split("#", 1)[0].strip()
    match = DIRECTIVE.match(body)
    if not match:
        return "", ""
    return match.group(1), match.group(2).strip()


def directives(text: str) -> tuple[dict[str, str], dict[str, int]]:
    """Last uncommented value per key, and how often each key appears."""
    found: dict[str, str] = {}
    counts: dict[str, int] = {}
    for line in text.splitlines():
        key, value = split_directive(line)
        if not key:
            continue
        counts[key] = counts.get(key, 0) + 1
        if value:
            found[key] = value
    return found, counts


def service_state() -> str:
    """systemd's own answer, as a stable code rather than a sentence."""
    try:
        result = subprocess.run(
            SYSTEMCTL + ["is-active", "nut-monitor.service"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    state = result.stdout.strip().lower()
    if state in ("active", "activating"):
        return "active"
    if state in ("inactive", "failed", "deactivating"):
        return "inactive"
    return "unknown"


def policy() -> dict:
    """The seven values, the monitor and the service state, as plain data."""
    text, error = read_conf()
    values: dict[str, str] = {}
    monitored = ""
    if text is not None:
        found, _ = directives(text)
        values = {key: found.get(key, "") for key in KEYS}
        monitored = found.get("MONITOR", "").split("@", 1)[0]
    return {
        "present": text is not None,
        "file": UPSMON_CONF,
        "service": service_state(),
        "monitored": monitored,
        "keys": values,
        "error": error,
    }


def unquote(value: str) -> str:
    if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def validate(values: dict, counts: dict[str, int]) -> tuple[str, str]:
    """First bad (field, short reason), or ("", ""). No command runs before this."""
    for key in KEYS:
        raw = values[key]
        if type(raw) is not str:
            return key, "must be text"
        if counts.get(key, 0) > 1:
            return key, "duplicate"
        if not raw:
            continue  # empty means remove/comment the directive
        if key in BOUNDS:
            low, high = BOUNDS[key]
            if not raw.isdigit():
                return key, "must be a whole number"
            if not low <= int(raw) <= high:
                return key, f"must be between {low} and {high}"
        elif key == "SHUTDOWNCMD":
            if len(raw) < 2 or not (raw.startswith('"') and raw.endswith('"')):
                return key, "must be a quoted command"
        elif key == "POWERDOWNFLAG":
            if not unquote(raw).startswith("/"):
                return key, "must be an absolute path"
    return "", ""


def line_ending(line: str) -> str:
    for ending in ("\r\n", "\n", "\r"):
        if line.endswith(ending):
            return ending
    return ""


def stage(text: str, values: dict) -> str:
    """New full content: replace the last occurrence, leave all else byte-for-byte."""
    lines = text.splitlines(keepends=True)
    last = {}
    for index, line in enumerate(lines):
        key, _ = split_directive(line)
        if key in POLICY:
            last[key] = index
    for key in KEYS:
        value = values[key]
        if key in last:
            index = last[key]
            ending = line_ending(lines[index])
            body = lines[index][: -len(ending)] if ending else lines[index]
            lines[index] = (f"{key} {value}" if value else "# " + body) + ending
        elif value:
            if lines and not line_ending(lines[-1]):
                lines[-1] += "\n"
            lines.append(f"{key} {value}\n")
    return "".join(lines)


def shanios_upsmon_save(content: bytes, digest: str) -> dict:
    """The only ShaniOS-only call: install upsmon.conf as root, content on stdin.

    The caller proposes; the helper validates and commits. Neither the content
    nor any value from it reaches argv, a log or the JSON this bridge prints.
    """
    if not PKEXEC or not shutil.which(PKEXEC[0]):
        return {
            "ok": False,
            "error": f"{PKEXEC[0] if PKEXEC else 'pkexec'} is not available",
        }
    try:
        result = subprocess.run(
            PKEXEC + [SAVE, "--target", "nut_upsmon_conf", "--expect-sha256", digest],
            input=content,
            capture_output=True,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)[:300]}
    if result.returncode != 0:
        lines = (result.stderr or b"").decode("utf-8", "replace").splitlines()
        error = lines[-1].strip() if lines else f"exit {result.returncode}"
        return {"ok": False, "error": error[:300]}
    return {"ok": True, "error": ""}


def policy_save(body: bytes) -> dict:
    try:
        values = json.loads(body or b"")
    except (ValueError, UnicodeDecodeError):
        return {"ok": False, "error": "expected a JSON object", "field": ""}
    if not isinstance(values, dict) or set(values) != set(KEYS):
        return {
            "ok": False,
            "error": "expected exactly the seven upsmon keys",
            "field": "",
        }
    text, _ = read_conf()
    _, counts = directives(text) if text is not None else ({}, {})
    field, error = validate(values, counts)
    if error:
        return {"ok": False, "error": error, "field": field}
    if text is not None:
        found, _ = directives(text)
        current = {key: found.get(key, "") for key in KEYS}
        if current == values:
            return {"ok": True, "error": "unchanged", "keys": current}
    content = stage(text or "", values).encode("utf-8")
    if len(content) > MAX_BYTES:
        return {"ok": False, "error": "content too large", "field": ""}
    saved = shanios_upsmon_save(content, hashlib.sha256(content).hexdigest())
    if not saved["ok"]:
        return {"ok": False, "error": saved["error"], "keys": {}}
    after, read_error = read_conf()
    if after is None:
        return {"ok": False, "error": read_error, "keys": {}}
    found, _ = directives(after)
    keys = {key: found.get(key, "") for key in KEYS}
    if any(keys[key] != values[key] for key in KEYS):
        return {"ok": False, "error": "verification failed", "keys": keys}
    return {"ok": True, "error": "", "keys": keys}


def main(argv: list[str]) -> int:
    if len(argv) == 1:
        print(json.dumps(read()))
        return 0
    verb = argv[1] if len(argv) > 1 else ""
    if len(argv) != 2 or verb not in ("policy", "policy-save"):
        print(json.dumps({"error": "usage: ups.py [policy|policy-save]"}))
        return 2
    result = policy() if verb == "policy" else policy_save(sys.stdin.buffer.read())
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
