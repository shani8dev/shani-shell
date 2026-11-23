#!/usr/bin/env python3
"""security — read-only security posture: LSMs, AppArmor, password policy, audit.

    security.py status   JSON report. No changes, no root required for the basics;
    aa-status may be unreadable without privilege, reported as such.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

PWQUALITY = "/etc/security/pwquality.conf"
PAM_DIRS = ["/etc/pam.d", "/usr/lib/pam.d"]


def _lsm():
    try:
        return open("/sys/kernel/security/lsm", encoding="utf-8").read().strip().split(",")
    except OSError:
        return []


def _apparmor():
    out = {"active": None, "profiles": None, "enforcing": None, "note": ""}
    try:
        r = subprocess.run(["systemctl", "is-active", "apparmor"], capture_output=True, text=True, timeout=4)
        out["active"] = r.stdout.strip()
    except Exception:
        pass
    if shutil.which("aa-status") is None:
        out["note"] = "aa-status not installed"
        return out
    try:
        r = subprocess.run(["aa-status", "--json"], capture_output=True, text=True, timeout=6)
        if r.returncode == 0:
            d = json.loads(r.stdout)
            out["profiles"] = d.get("profiles")
            # enforcing = number of profiles in enforce mode
            if isinstance(out["profiles"], dict):
                out["enforcing"] = sum(1 for v in out["profiles"].values() if v == "enforce")
        else:
            out["note"] = (r.stderr or r.stdout).strip().splitlines()[0][:120] or "aa-status needs permission"
    except Exception as exc:
        out["note"] = str(exc)[:120]
    return out


def _pwquality():
    info = {"file": PWQUALITY, "present": os.path.exists(PWQUALITY), "settings": {}, "pam_wired": False}
    if info["present"]:
        try:
            for line in open(PWQUALITY, encoding="utf-8", errors="replace"):
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("["):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    info["settings"][k.strip()] = v.strip()
        except OSError:
            pass
    wired = False
    for d in PAM_DIRS:
        if not os.path.isdir(d):
            continue
        for name in os.listdir(d):
            p = os.path.join(d, name)
            try:
                t = open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            if "pam_pwquality" in t:
                wired = True; break
        if wired:
            break
    info["pam_wired"] = wired
    return info


def _audit():
    info = {"active": None, "enabled": None}
    for cmd, key in ((["systemctl", "is-active", "auditd"], "active"), (["systemctl", "is-enabled", "auditd"], "enabled")):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=4)
            info[key] = r.stdout.strip()
        except Exception:
            pass
    return info


def main():
    if len(sys.argv) < 2 or sys.argv[1] != "status":
        print(json.dumps({"error": "usage: security.py status"})); return 2
    print(json.dumps({
        "lsm": _lsm(),
        "apparmor": _apparmor(),
        "pwquality": _pwquality(),
        "audit": _audit(),
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
