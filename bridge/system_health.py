#!/usr/bin/env python3
"""system_health — the read-only checks behind Settings › System › System health.

    system_health.py list     {"have", "checks": [{"key","title","status",
                               "detail"}], "error"}
    system_health.py storage  {"have", "error", "timestamp", "summary",
                               "subvolumes", "warnings"}
    system_health.py audit    {"have", "error", "active", "enabled",
                               "log_present", "log_size", "records",
                               "truncated", "verdict"}

`list` runs `shani-health --verify --json` as the person: no root. `storage`
reads the same tool's `--storage-info --json` through pkexec, because that mode
mounts the Btrfs root. `audit` reads ausearch through pkexec and asks systemd
about auditd without a password. A refusal is never reported as an empty
result. Every privileged vendor call lives in a `shanios_*` function; parsing
lives in plain functions that return data. An unusable report is said, never
filled in with invented values.

SHANI_SYSTEM_HEALTH / SHANI_SYSTEM_HEALTH_ARGS / SHANI_SYSTEM_PKEXEC /
SHANI_AUSEARCH / SHANI_SYSTEM_SYSTEMCTL / SHANI_AUDIT_LOG (tests, stand-ins).
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys

TOOL = shlex.split(os.environ.get("SHANI_SYSTEM_HEALTH", "shani-health"))
ARGS = shlex.split(os.environ.get("SHANI_SYSTEM_HEALTH_ARGS", "--verify --json"))
PKEXEC = shlex.split(os.environ.get("SHANI_SYSTEM_PKEXEC", "pkexec"))
AUSEARCH = shlex.split(os.environ.get("SHANI_AUSEARCH", "ausearch"))
SYSTEMCTL = shlex.split(os.environ.get("SHANI_SYSTEM_SYSTEMCTL", "systemctl"))
AUDIT_LOG = os.environ.get("SHANI_AUDIT_LOG", "/var/log/audit/audit.log")

MAX_RECORDS = 25
SUMMARY_KEYS = frozenset(
    {
        "Free",
        "Total",
        "Used",
        "Snapshots",
        "Quotas",
        "Scrub",
        "Scrub tmr",
        "Maint tmrs",
        "bees",
        "Dev errors",
        "Dedup",
    }
)
WARNING_STATUSES = frozenset({"warning", "critical", "fail"})
MALFORMED = "ausearch answered with something that is not a record list"

# The tool's own words, not a second opinion about their meaning. Anything
# unrecognised is info: never claim a check passed because we did not know its
# status word.
STATUS = {
    "pass": "pass",
    "passed": "pass",
    "ok": "pass",
    "good": "pass",
    "healthy": "pass",
    "success": "pass",
    "true": "pass",
    "warn": "warn",
    "warning": "warn",
    "degraded": "warn",
    "notice": "warn",
    "fail": "fail",
    "failed": "fail",
    "error": "fail",
    "critical": "fail",
    "bad": "fail",
    "false": "fail",
    "info": "info",
    "informational": "info",
    "unknown": "info",
    "skip": "info",
    "skipped": "info",
    "not run": "info",
    "none": "info",
}


def _text(check: dict, *names: str) -> str:
    for name in names:
        value = check.get(name)
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def _status(value) -> str:
    if isinstance(value, bool):
        return "pass" if value else "fail"
    word = str(value or "").strip().lower()
    return STATUS.get(word, "info")


def _rows(report):
    """Normalise a health report into check dicts; unknown shapes yield none."""
    if isinstance(report, dict):
        for key in ("checks", "report", "results"):
            if key in report:
                return _rows(report[key])
        if _text(report, "title", "name", "key", "id", "status"):
            return [report]
        return []
    if isinstance(report, list):
        return [c for c in report if isinstance(c, dict)]
    return []


def _check(check: dict) -> dict:
    title = _text(check, "title", "name", "label", "section")
    return {
        "key": _text(check, "key", "id", "name") or title,
        "title": title,
        "status": _status(
            check.get(
                "status", check.get("state", check.get("result", check.get("level")))
            )
        ),
        "detail": _text(check, "detail", "message", "description", "output", "note"),
    }


def _failure(r, fallback: str) -> str:
    """One line of why: a runner failure or the tool's own last error line."""
    if r is None:
        return fallback
    return (r.stderr.strip().splitlines() or [f"exit {r.returncode}"])[-1]


def _run_pkexec(args: list[str], timeout: int = 120):
    name = PKEXEC[0] if PKEXEC else "pkexec"
    if not PKEXEC or not shutil.which(name):
        return None, f"{name} is not available"
    try:
        return subprocess.run(
            PKEXEC + args, capture_output=True, text=True, timeout=timeout
        ), ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)


def shanios_verify() -> list[str]:
    """The unprivileged vendor health check, as the person."""
    return TOOL + ARGS


def shanios_storage_info() -> list[str]:
    """The Btrfs report, which needs root, behind the polkit prompt."""
    return PKEXEC + [*TOOL, "--storage-info", "--json"]


def _sizes(message: str) -> tuple[str, str]:
    """`960K (ratio: 16M)` -> used `960K`, uncompressed `16M`."""
    if " (ratio:" not in message:
        return "", ""
    used, _, rest = message.partition(" (ratio:")
    return used.strip(), rest.strip().rstrip(")").strip()


def storage_report(report) -> dict:
    """Split the tool's rows into capacity, subvolumes and the real warnings."""
    out: dict = {
        "have": False,
        "timestamp": "",
        "summary": {},
        "subvolumes": [],
        "warnings": [],
    }
    if not isinstance(report, dict):
        return out
    out["timestamp"] = str(report.get("timestamp") or "")
    checks = report.get("checks")
    if not isinstance(checks, list):
        return out
    out["have"] = True
    for check in checks:
        if not isinstance(check, dict):
            continue
        key = str(check.get("key") or "").strip()
        if not key:
            continue
        status = str(check.get("status") or "").strip().lower()
        message = str(check.get("message") or "").strip()
        used, uncompressed = _sizes(message)
        if status in WARNING_STATUSES:
            out["warnings"].append({"key": key, "status": status, "message": message})
        if key.startswith("@"):
            out["subvolumes"].append(
                {
                    "name": key,
                    "status": status,
                    "used": used,
                    "uncompressed": uncompressed,
                    "message": message,
                }
            )
        elif key in SUMMARY_KEYS:
            out["summary"][key] = {
                "status": status,
                "message": message,
                "used": used,
                "uncompressed": uncompressed,
            }
    return out


def listing() -> dict:
    out: dict = {"have": False, "checks": [], "error": ""}
    tool = TOOL[0] if TOOL else "shani-health"
    if not shutil.which(tool):
        out["error"] = f"{tool} is not available"
        return out
    argv = shanios_verify()
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        out["error"] = str(exc)
        return out
    # shani-health exits 1 when a check finds a problem and still prints its
    # JSON: the report on stdout wins over the exit code, or the fail rows are
    # lost just when they matter.
    try:
        report = json.loads(r.stdout or "")
    except ValueError as exc:
        out["error"] = _failure(r, f"could not read the health report: {exc}")
        return out
    out["have"] = True
    out["checks"] = [_check(c) for c in _rows(report)]
    return out


def storage() -> dict:
    out: dict = {
        "have": False,
        "error": "",
        "timestamp": "",
        "summary": {},
        "subvolumes": [],
        "warnings": [],
    }
    r, error = _run_pkexec(shanios_storage_info())
    if r is None:
        out["error"] = error
        return out
    # A cancelled prompt prints nothing at all; a failing check still prints
    # its JSON with exit 1 and must be read.
    try:
        report = json.loads(r.stdout or "")
    except ValueError as exc:
        out["error"] = _failure(r, f"could not read the storage report: {exc}")
        return out
    out.update(storage_report(report))
    return out


def _ausearch_argv() -> list[str]:
    return [
        *AUSEARCH,
        "--output=json",
        "-i",
        "-n",
        str(MAX_RECORDS),
        "--start",
        "recent",
    ]


def _systemctl_argv(verb: str) -> list[str]:
    return [*SYSTEMCTL, verb, "auditd"]


def _systemctl(verb: str) -> str:
    try:
        r = subprocess.run(
            _systemctl_argv(verb), capture_output=True, text=True, timeout=30
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return " ".join(r.stdout.split())


def _log_state() -> tuple[bool | None, int | None]:
    try:
        return True, os.stat(AUDIT_LOG).st_size
    except FileNotFoundError:
        return False, None
    except OSError:
        # Present or not, we cannot see it: not absent, not empty.
        return None, None


def _detail(record: dict) -> str:
    """The parsed fields of one record, or its raw line when unparsed."""
    fields: list[str] = []
    for item in record.get("items") or []:
        if not isinstance(item, dict):
            continue
        subs = item.get("sub")
        if isinstance(subs, list):
            for sub in subs:
                if isinstance(sub, dict) and sub.get("name"):
                    fields.append(f"{sub['name']}={sub.get('value', '')}")
        elif item.get("name"):
            fields.append(f"{item['name']}={item.get('value', '')}")
        if not fields and item.get("output"):
            fields.append(str(item["output"]))
    if not fields and record.get("output"):
        fields.append(str(record["output"]))
    return " ".join(fields)


def audit_records(document) -> tuple[list[dict], bool] | None:
    """Records from an ausearch document, None for a shape we do not read."""
    if not isinstance(document, dict):
        return None
    raw = document.get("records")
    if raw is None:
        raw = document.get("items")
    if not isinstance(raw, list):
        return None
    rows = []
    for record in raw:
        if not isinstance(record, dict):
            continue
        rows.append(
            {
                "type": str(record.get("type") or "record"),
                "time": str(record.get("time") or ""),
                "detail": _detail(record),
            }
        )
    return rows[:MAX_RECORDS], len(rows) > MAX_RECORDS


def audit_verdict(
    *,
    have: bool,
    active: str,
    log_present: bool | None,
    log_size: int | None,
    count: int,
) -> str:
    """Why an empty answer is empty; never a clean verdict without evidence."""
    if not have:
        return "unresolved"
    if count:
        return "genuine"
    if active in ("", "unknown"):
        return "unresolved"
    if active not in ("active", "activating"):
        return "not-running"
    if log_present is None:
        return "unresolved"
    if log_present is False:
        return "no-log"
    if log_size == 0:
        return "empty-log"
    return "genuine"


def audit() -> dict:
    out: dict = {
        "have": False,
        "error": "",
        "active": "",
        "enabled": "",
        "log_present": None,
        "log_size": None,
        "records": [],
        "truncated": False,
        "verdict": "unresolved",
    }
    out["active"] = _systemctl("is-active")
    out["enabled"] = _systemctl("is-enabled")
    out["log_present"], out["log_size"] = _log_state()
    r, error = _run_pkexec(_ausearch_argv())
    if r is None:
        out["error"] = error
    else:
        try:
            document = json.loads(r.stdout or "")
        except ValueError as exc:
            out["error"] = _failure(r, f"could not read audit records: {exc}")
        else:
            parsed = audit_records(document)
            if parsed is None:
                out["error"] = MALFORMED
            elif r.returncode != 0 and not parsed[0]:
                out["error"] = _failure(r, f"ausearch exit {r.returncode}")
            else:
                out["records"], out["truncated"] = parsed
                out["have"] = True
    out["verdict"] = audit_verdict(
        have=out["have"],
        active=out["active"],
        log_present=out["log_present"],
        log_size=out["log_size"],
        count=len(out["records"]),
    )
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in ("list", "storage", "audit"):
        print(
            json.dumps({"error": "usage: system_health.py list|storage|audit"}),
            file=sys.stderr,
        )
        return 2
    verb = argv[1]
    if verb == "list":
        result = listing()
    elif verb == "storage":
        result = storage()
    else:
        result = audit()
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
