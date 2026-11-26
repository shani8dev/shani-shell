#!/usr/bin/env python3
"""system_disks — a read-only view of the machine's software RAID, LVM, Btrfs,
compression and disk health for the Disks & filesystems page.

    system_disks.py raid          {"have", "arrays": [{"name", "state", "devices", "detail"}]}
    system_disks.py lvm           {"have", "pvs": [...], "vgs": [...], "lvs": [...], "error"}
    system_disks.py btrfs         {"have", "subvolumes": [...], "usage", "scrub", "error"}
    system_disks.py compression   {"have", "lines": [...], "error"}
    system_disks.py smart         {"have", "disks": [{"name", "health", "temp", "model"}]}

Every verb prints one JSON object and only reads: mdstat is a file, the tools are
asked for reports, and nothing is assembled, mounted or repaired. The commands
and paths can be pointed at stand-ins (dev/fake-system-disks.py) with
SHANI_MDSTAT, SHANI_MDADM, SHANI_PVS, SHANI_VGS, SHANI_LVS, SHANI_BTRFS,
SHANI_COMPSIZE, SHANI_SMARTCTL and SHANI_DISK_GLOB (space-separated globs).
A valid verb always exits 0; a tool failure is reported inside its JSON.
"""

from __future__ import annotations

import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

MDSTAT = os.environ.get("SHANI_MDSTAT", "/proc/mdstat")
MDADM = shlex.split(os.environ.get("SHANI_MDADM", "mdadm"))
PVS = shlex.split(os.environ.get("SHANI_PVS", "pvs"))
VGS = shlex.split(os.environ.get("SHANI_VGS", "vgs"))
LVS = shlex.split(os.environ.get("SHANI_LVS", "lvs"))
BTRFS = shlex.split(os.environ.get("SHANI_BTRFS", "btrfs"))
COMPSIZE = shlex.split(os.environ.get("SHANI_COMPSIZE", "compsize"))
SMARTCTL = shlex.split(os.environ.get("SHANI_SMARTCTL", "smartctl"))
DISK_GLOB = os.environ.get("SHANI_DISK_GLOB", "/dev/sd? /dev/nvme?n1")

_MD_ARRAY = re.compile(r"^(md\S+)\s*:\s*(\S+)\s+(.*)$")
_MD_DEVICE = re.compile(r"^([A-Za-z0-9_.-]+)\[\d+\]")
_MD_BITMAP = re.compile(r"\[([U_]{2,})\]")
_SUBVOL = re.compile(r"^ID\s+(\d+)\b")
_TOP = re.compile(r"\btop level\s+(\d+)")
_PATH = re.compile(r"\bpath\s+(.+?)\s*$")
_MODEL = re.compile(r"^(?:Device Model|Model Number)\s*:\s*(.+)$", re.I)
_HEALTH = re.compile(r"overall-health self-assessment test result\s*:\s*(\S+)", re.I)
_NVME_HEALTH = re.compile(r"Health Status\s*:\s*OK\b", re.I)


def _available(cmd: list[str]) -> bool:
    return bool(cmd) and shutil.which(cmd[0]) is not None


def _run(cmd: list[str], *args, timeout=20) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            cmd + list(args), capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 127, "", str(e))


def _failure(r: subprocess.CompletedProcess, fallback: str) -> str:
    lines = (r.stderr.strip() or r.stdout.strip()).splitlines()
    return (lines or [fallback])[-1]


def _short(text: str) -> str:
    """Keep the tool's own words, not the whole report."""
    return "\n".join(l.strip() for l in text.splitlines() if l.strip())[:600]


def raid() -> dict:
    """Arrays from /proc/mdstat, with the degraded bitmaps told apart.

    state is healthy/degraded from [UU] or [U_]; detail keeps the raid level
    and mdadm's own state line when mdadm is present. Nothing is assembled.
    """
    arrays = []
    try:
        with open(MDSTAT, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    for i, line in enumerate(lines):
        m = _MD_ARRAY.match(line.strip())
        if not m:
            continue
        name, mdstate, rest = m.groups()
        tokens = rest.split()
        devices = [_MD_DEVICE.match(t).group(1) for t in tokens if _MD_DEVICE.match(t)]
        bitmap = ""
        for follow in lines[i + 1 : i + 6]:
            b = _MD_BITMAP.search(follow)
            if b:
                bitmap = b.group(1)
                break
        if bitmap:
            state = "degraded" if "_" in bitmap else "healthy"
        else:
            state = "degraded" if mdstate == "inactive" else "unknown"
        detail = tokens[0] if tokens and tokens[0].startswith("raid") else ""
        if _available(MDADM):
            r = _run(MDADM, "--detail", "/dev/" + name)
            if r.returncode == 0:
                bits = [
                    l.strip()
                    for l in r.stdout.splitlines()
                    if re.match(
                        r"\s*(State|Raid Level|Failed Devices|Active Devices)\s*:", l
                    )
                ]
                detail = "; ".join(bits)[:300] or detail
        arrays.append(
            {"name": name, "state": state, "devices": devices, "detail": detail}
        )
    return {"have": bool(arrays), "arrays": arrays}


def _report(cmd: list[str], key: str, fields: dict) -> tuple[list[dict], str]:
    """One pvs/vgs/lvs JSON report, in the shape the caller asked for."""
    if not _available(cmd):
        return [], ""
    r = _run(cmd, "--reportformat", "json")
    if r.returncode != 0:
        return [], _failure(r, "%s failed" % cmd[0])
    try:
        rows = json.loads(r.stdout)["report"][0][key]
    except (ValueError, KeyError, IndexError, TypeError):
        return [], "could not read %s output" % cmd[0]
    out = []
    for row in rows if isinstance(rows, list) else []:
        if isinstance(row, dict):
            out.append(
                {
                    field: str(row.get(source, "") or "")
                    for field, source in fields.items()
                }
            )
    return out, ""


def lvm() -> dict:
    pvs, e1 = _report(
        PVS, "pv", {"name": "pv_name", "size": "pv_size", "vg": "vg_name"}
    )
    vgs, e2 = _report(
        VGS, "vg", {"name": "vg_name", "size": "vg_size", "free": "vg_free"}
    )
    lvs, e3 = _report(
        LVS,
        "lv",
        {"name": "lv_name", "vg": "vg_name", "size": "lv_size", "attr": "lv_attr"},
    )
    return {
        "have": bool(pvs or vgs or lvs),
        "pvs": pvs,
        "vgs": vgs,
        "lvs": lvs,
        "error": e1 or e2 or e3,
    }


def btrfs() -> dict:
    out = {"have": False, "subvolumes": [], "usage": "", "scrub": "", "error": ""}
    if not _available(BTRFS):
        return out
    errors = []
    r = _run(BTRFS, "subvolume", "list", "/")
    if r.returncode != 0:
        errors.append(_failure(r, "subvolume list failed"))
    else:
        for line in r.stdout.splitlines():
            m = _SUBVOL.match(line.strip())
            if not m:
                continue
            top = _TOP.search(line)
            path = _PATH.search(line)
            out["subvolumes"].append(
                {
                    "id": int(m.group(1)),
                    "path": path.group(1).strip() if path else "",
                    "parent": int(top.group(1)) if top else 0,
                }
            )
    r = _run(BTRFS, "filesystem", "usage", "/")
    if r.returncode != 0:
        errors.append(_failure(r, "filesystem usage failed"))
    else:
        out["usage"] = _short(r.stdout or r.stderr)
    r = _run(BTRFS, "filesystem", "scrub", "status", "/")
    if r.returncode != 0:
        errors.append(_failure(r, "scrub status failed"))
    else:
        out["scrub"] = _short(r.stdout or r.stderr)
    out["error"] = errors[0] if errors else ""
    out["have"] = bool(out["subvolumes"] or out["usage"] or out["scrub"])
    return out


def compression() -> dict:
    out = {"have": False, "lines": [], "error": ""}
    if not _available(COMPSIZE):
        return out
    out["have"] = True
    r = _run(COMPSIZE)
    out["lines"] = [l.strip() for l in r.stdout.splitlines() if l.strip()][:40]
    if r.returncode != 0:
        out["error"] = _failure(r, "compsize failed")
    return out


def _disk_paths() -> list[str]:
    names = []
    for pattern in DISK_GLOB.split():
        names.extend(glob.glob(pattern))
    return sorted(set(names))


def smart() -> dict:
    disks = []
    if _available(SMARTCTL):
        for path in _disk_paths():
            r = _run(SMARTCTL, "-H", "-A", path)
            text = r.stdout
            m = _HEALTH.search(text)
            if m:
                health = "healthy" if m.group(1).upper() == "PASSED" else "degraded"
            elif _NVME_HEALTH.search(text):
                health = "healthy"
            else:
                health = "unknown"
            temp = ""
            for line in text.splitlines():
                if "Temperature_Celsius" in line:
                    t = re.search(r"Temperature_Celsius\b.*\s(-?\d+)(?:\s|$)", line)
                    if t:
                        temp = t.group(1)
                elif not temp:
                    t = re.search(r"Temperature\s*:\s*(\d+)", line, re.I)
                    if t:
                        temp = t.group(1)
            model = ""
            for line in text.splitlines():
                m = _MODEL.match(line.strip())
                if m:
                    model = m.group(1).strip()
                    break
            disks.append(
                {
                    "name": os.path.basename(path.rstrip("/")),
                    "health": health,
                    "temp": temp,
                    "model": model,
                }
            )
    return {"have": bool(disks), "disks": disks}


VERBS = {
    "raid": raid,
    "lvm": lvm,
    "btrfs": btrfs,
    "compression": compression,
    "smart": smart,
}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if cmd not in VERBS or args:
        print(json.dumps({"error": "usage: system_disks.py " + "|".join(VERBS)}))
        return 2
    try:
        result = VERBS[cmd]()
    except (OSError, ValueError) as e:
        result = {"error": str(e)}
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
