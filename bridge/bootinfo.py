#!/usr/bin/env python3
"""bootinfo — the boot slots, secure boot and boot health, for Settings.

Every call to a ShaniOS-only tool or file lives in one ``shanios_*`` function;
the rest of this bridge only parses the data those functions return. Bridges
stay thin: parse argv, call a plain function, print JSON.

    bootinfo.py status       {"available", "rows", "note"}   (free)
    bootinfo.py secureboot   {"available", "sbctl_present", ...}  (free)
    bootinfo.py verify       {"available", "passed", "issues", "checks", ...}
    bootinfo.py backups      {"available", "slots", "error"}

``--status`` needs no root and no deploy lock. ``verify`` and ``backups`` use
pkexec: the calling page says why before asking for a password. No secret is
ever passed on argv; these reads need none.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

TIMEOUT = 12
PRIVILEGED_TIMEOUT = 90

# ShaniOS-only tools and files. Keep the command lists below as literals:
# tests/test_os_cli_contract.py reads them to check every option against the
# real parser in ../shani-deploy.
# The SHANI_SYSTEM_* names are the system pages' own harness overrides; the
# shorter ones stay as fallbacks for callers and tests outside that harness.
DEPLOY = os.environ.get(
    "SHANI_SYSTEM_DEPLOY", os.environ.get("SHANI_DEPLOY", "shani-deploy")
)
PKEXEC = shlex.split(os.environ.get("SHANI_SYSTEM_PKEXEC", "pkexec"))
SBCTL = os.environ.get("SHANI_SYSTEM_SBCTL", os.environ.get("SHANI_SBCTL", "sbctl"))
MOKUTIL = os.environ.get(
    "SHANI_SYSTEM_MOKUTIL", os.environ.get("SHANI_MOKUTIL", "mokutil")
)
EFI_DIR = Path(os.environ.get("SHANI_EFI_DIR", "/sys/firmware/efi"))

# what the deploy script reports, and what a person needs to see
FIELDS = [
    ("version", "Version"),
    ("profile", "Profile"),
    ("channel", "Channel"),
    ("booted_slot", "Running from"),
    ("current_slot", "Current slot"),
    ("previous_slot", "Previous slot"),
    ("candidate_boot", "Still a candidate boot"),
    ("update_available", "Update waiting"),
    ("boot_failure", "Boot failure marker"),
    ("auto_rollback_done", "Rolled back on its own"),
]


# --- ShaniOS-only calls -----------------------------------------------------


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def shanios_release_file() -> str:
    """The release file this system booted from."""
    return _read("/etc/shani-version")


def shanios_selected_slot() -> str:
    """The slot this system selected on the last boot."""
    return _read("/data/current-slot")


def shanios_status(check: bool = False):
    """The free deploy status document; (doc | None, error)."""
    if shutil.which(DEPLOY) is None:
        return None, "shani-deploy is not installed, so the slots cannot be read."
    args = (
        [DEPLOY, "--status", "--check", "--json"]
        if check
        else [DEPLOY, "--status", "--json"]
    )
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=TIMEOUT)
    except Exception as exc:  # noqa: BLE001
        return None, f"Could not ask shani-deploy: {exc}"
    try:
        doc = json.loads(proc.stdout) or {}
    except Exception:  # noqa: BLE001
        return None, "shani-deploy did not answer with JSON."
    return doc, ""


def shanios_verify_existing():
    """Raw ``--verify-existing`` output (SGR colour kept), or (None, error).

    Severity is carried only by the SGR colour, so the output is returned
    unstripped. Cancelled authorisation becomes the stable code ``cancelled``;
    the UI owns the sentence.
    """
    if not PKEXEC or shutil.which(PKEXEC[0]) is None:
        return None, "no-pkexec"
    args = PKEXEC + [DEPLOY, "--verify-existing"]
    try:
        proc = subprocess.run(
            args, capture_output=True, text=True, timeout=PRIVILEGED_TIMEOUT
        )
    except Exception as exc:  # noqa: BLE001
        return None, str(exc)
    if getattr(proc, "returncode", 0) in (126, 127):
        return None, "cancelled"
    out = (
        (getattr(proc, "stdout", "") or "") + "\n" + (getattr(proc, "stderr", "") or "")
    )
    return out, ""


def shanios_list_backups():
    """The ``--list-backups --json`` document, or (None, error)."""
    if not PKEXEC or shutil.which(PKEXEC[0]) is None:
        return None, "no-pkexec"
    args = PKEXEC + [DEPLOY, "--list-backups", "--json"]
    try:
        proc = subprocess.run(
            args, capture_output=True, text=True, timeout=PRIVILEGED_TIMEOUT
        )
    except Exception as exc:  # noqa: BLE001
        return None, str(exc)
    if getattr(proc, "returncode", 0) in (126, 127):
        return None, "cancelled"
    try:
        doc = json.loads(getattr(proc, "stdout", "") or "") or {}
    except Exception:  # noqa: BLE001
        return None, "bad-json"
    return doc, ""


# --- plain helpers ----------------------------------------------------------


def _yes(v):
    if isinstance(v, bool):
        return "yes" if v else "no"
    return str(v) if v not in (None, "") else ""


def _efi_flag(name: str):
    """Read a boolean EFI variable (SecureBoot / SetupMode), byte 4 == 1."""
    if not EFI_DIR.is_dir():
        return None
    matches = sorted((EFI_DIR / "efivars").glob(f"{name}-*"))
    if not matches:
        return None
    try:
        data = matches[0].read_bytes()
    except OSError:
        return None
    if len(data) < 5:
        return None
    return data[4] == 1


def _sbctl_probe():
    """``sbctl status --json`` as a dict, or None when it cannot be read."""
    if shutil.which(SBCTL) is None:
        return None
    try:
        proc = subprocess.run(
            [SBCTL, "status", "--json"], capture_output=True, text=True, timeout=8
        )
    except Exception:  # noqa: BLE001
        return None
    if (
        getattr(proc, "returncode", 0) != 0
        or not (getattr(proc, "stdout", "") or "").strip()
    ):
        return None
    try:
        doc = json.loads(proc.stdout)
    except Exception:  # noqa: BLE001
        return None
    return doc if isinstance(doc, dict) else None


def _mokutil_sb_state():
    """True / False from ``mokutil --sb-state``; None when unreadable."""
    if shutil.which(MOKUTIL) is None:
        return None
    try:
        proc = subprocess.run(
            [MOKUTIL, "--sb-state"], capture_output=True, text=True, timeout=8
        )
    except Exception:  # noqa: BLE001
        return None
    if getattr(proc, "returncode", 0) != 0:
        return None
    text = (
        (getattr(proc, "stdout", "") or "") + " " + (getattr(proc, "stderr", "") or "")
    ).lower()
    if "enabled" in text:
        return True
    if "disabled" in text:
        return False
    return None


def _mokutil_key_count():
    """Enrolled MOK keys; None when the count could not be read (never 0)."""
    if shutil.which(MOKUTIL) is None:
        return None
    try:
        proc = subprocess.run(
            [MOKUTIL, "--list-enrolled"], capture_output=True, text=True, timeout=8
        )
    except Exception:  # noqa: BLE001
        return None
    if getattr(proc, "returncode", 0) != 0:
        return None
    out = getattr(proc, "stdout", "") or ""
    return sum(1 for line in out.splitlines() if line.strip().startswith("[key"))


def _secure_boot():
    """The one Secure Boot row on the status page, in its old wording."""
    sb = _mokutil_sb_state()
    if sb is True:
        return "enabled"
    if sb is False:
        return "disabled"
    return ""


def _encryption():
    # LUKS devices currently present; read-only, no root.
    if shutil.which("lsblk") is None:
        return []
    try:
        proc = subprocess.run(
            ["lsblk", "-J", "-o", "NAME,TYPE,FSTYPE"],
            capture_output=True,
            text=True,
            timeout=4,
        )
        doc = json.loads(proc.stdout or "{}")
    except Exception:  # noqa: BLE001
        return []
    found = []

    def walk(nodes):
        for node in nodes or []:
            if node.get("fstype") == "crypto_LUKS" or node.get("type") == "crypt":
                found.append(node.get("name", ""))
            walk(node.get("children"))

    walk(doc.get("blockdevices"))
    return found


# --- verify-existing output -------------------------------------------------

_ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
_VERIFY_RULE = re.compile(r"^={10,}$")
_VERIFY_CHECK = re.compile(r"^  (?P<key>.{16}) (?P<body>.*)$")
_VERIFY_ADVICE = re.compile(r"^\s+\x1b\[0;33m-> (?P<text>.*)$")
_VERIFY_SUMMARY = re.compile(
    r"^\x1b\[0;3(?P<tone>[123])m(?P<stamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) "
    r"\[(?P<tag>[A-Z]+)\] (?P<message>.*)$"
)
# The only three codes the deploy script's _row() emits. Anything else is
# information, not a guess.
_VERIFY_TONE = {"1": "bad", "2": "ok", "3": "warn"}
_VERIFY_ISSUES = re.compile(r"found (\d+) issue")
_VERIFY_TITLE = "Verify Existing Deployment"


def _strip_ansi(text: str) -> str:
    return _ANSI.sub("", text)


def parse_verify_existing(text: str) -> dict:
    """The tool's own rows, advice and summary as plain data.

    Unrecognised lines are kept in ``unread``: dropping them would look the
    same as the tool saying nothing, and on this page that difference matters.
    """
    checks, advice, unread = [], [], []
    issues = None
    passed = None
    for raw in (text or "").splitlines():
        line = raw.rstrip("\n")
        if (
            not line.strip()
            or _VERIFY_RULE.match(line)
            or line.strip() == _VERIFY_TITLE
        ):
            continue
        found = _VERIFY_ADVICE.match(line)
        if found:
            advice.append(_strip_ansi(found.group("text")).strip())
            continue
        found = _VERIFY_SUMMARY.match(line)
        if found:
            passed = found.group("tag") == "SUCCESS"
            count = _VERIFY_ISSUES.search(found.group("message"))
            if count:
                issues = int(count.group(1))
            continue
        found = _VERIFY_CHECK.match(line)
        if found:
            body = found.group("body")
            tone = re.match(r"^\x1b\[0;3(?P<tone>[123])m", body)
            checks.append(
                {
                    "key": found.group("key").strip(),
                    "severity": _VERIFY_TONE[tone.group("tone")] if tone else "info",
                    "text": _strip_ansi(body).strip(),
                }
            )
            continue
        unread.append(_strip_ansi(line).strip())
    return {
        "checks": checks,
        "advice": advice,
        "unread": unread,
        "issues": issues,
        "passed": passed,
    }


# --- verbs ------------------------------------------------------------------


def cmd_status() -> dict:
    doc, error = shanios_status()
    rows = []
    if doc is None:
        note = error
    else:
        note = ""
        for key, label in FIELDS:
            v = doc.get(key)
            if v in (None, "", False, [], {}):
                continue
            status = ""
            if key == "booted_slot" and v:
                status = "ok"
            if key == "boot_failure" and v:
                status = "fail"
            if key == "auto_rollback_done" and v is True:
                status = "warn"
            rows.append(
                {"label": label, "value": _yes(v), "detail": key, "status": status}
            )
    rows.append(
        {
            "label": "Release file",
            "value": shanios_release_file(),
            "detail": "/etc/shani-version",
            "status": "",
        }
    )
    rows.append(
        {
            "label": "Selected slot",
            "value": shanios_selected_slot(),
            "detail": "/data/current-slot",
            "status": "",
        }
    )
    sb = _secure_boot()
    if sb:
        rows.append(
            {
                "label": "Secure Boot",
                "value": sb,
                "detail": "mokutil --sb-state",
                "status": "ok" if sb == "enabled" else "warn",
            }
        )
    enc = _encryption()
    if enc:
        rows.append(
            {
                "label": "Encrypted volumes",
                "value": ", ".join(enc),
                "detail": "lsblk",
                "status": "ok",
            }
        )
    return {"available": doc is not None, "rows": rows, "note": note}


def cmd_secureboot() -> dict:
    uefi = EFI_DIR.is_dir()
    sbctl_present = shutil.which(SBCTL) is not None
    doc = _sbctl_probe()
    if doc is None:
        doc = {}
        error = "sbctl-no-answer" if sbctl_present else ""
    else:
        error = ""

    sb_state = _mokutil_sb_state()
    secure_boot = bool(doc["secure_boot"]) if "secure_boot" in doc else sb_state
    if secure_boot is None:
        secure_boot = _efi_flag("SecureBoot")
    setup_mode = (
        bool(doc["setup_mode"]) if "setup_mode" in doc else _efi_flag("SetupMode")
    )

    if not uefi:
        verdict = "legacy"
    elif setup_mode is True:
        verdict = "setup"
    elif secure_boot is True:
        verdict = "on"
    elif secure_boot is False:
        verdict = "off"
    else:
        verdict = "unknown"

    installed = bool(doc["installed"]) if "installed" in doc else None
    guid = str(doc.get("guid") or "")
    vendors = [str(v) for v in (doc.get("vendors") or []) if v]
    return {
        "available": bool(doc) or sb_state is not None or uefi,
        "sbctl_present": sbctl_present,
        "installed": installed,
        "secure_boot": verdict,
        "setup_mode": setup_mode,
        "enrolled": (installed and bool(guid)) if doc else None,
        "enrolled_keys": _mokutil_key_count(),
        "microsoft_keys": any("microsoft" in v.lower() for v in vendors),
        "guid": guid,
        "vendors": vendors,
        "error": error,
    }


def cmd_verify() -> dict:
    empty = {
        "available": False,
        "passed": None,
        "issues": None,
        "checks": [],
        "advice": [],
        "unread": [],
        "error": "",
    }
    text, error = shanios_verify_existing()
    if text is None:
        return {**empty, "error": error}
    report = parse_verify_existing(text)
    if not report["checks"] and not report["unread"]:
        return {**empty, "error": "no-answer"}
    return {"available": True, **report, "error": ""}


def cmd_backups() -> dict:
    empty = {"available": False, "slots": [], "error": ""}
    doc, error = shanios_list_backups()
    if doc is None:
        return {**empty, "error": error}
    slots = doc.get("slots")
    if not isinstance(slots, list):
        return {**empty, "error": "no-slots"}
    return {
        "available": True,
        "slots": [slot for slot in slots if isinstance(slot, dict)],
        "error": "",
    }


VERBS = {
    "status": cmd_status,
    "secureboot": cmd_secureboot,
    "verify": cmd_verify,
    "backups": cmd_backups,
}


def main(argv=None) -> int:
    argv = sys.argv if argv is None else argv
    verb = argv[1] if len(argv) > 1 else "status"
    if verb not in VERBS or len(argv) > 2:
        print(
            json.dumps({"error": "usage: bootinfo.py status|secureboot|verify|backups"})
        )
        return 2
    print(json.dumps(VERBS[verb](), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
