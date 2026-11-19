#!/usr/bin/env python3
"""A short, read-only health check, in the spirit of Ananta Maintenance.

One JSON object per run: [{"id", "title", "ok", "detail"}]. Nothing is changed,
nothing privileged is touched, and a check that cannot be read says so instead
of inventing a pass. The shell shows the score as a ring and the checks as a list.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys

MIN_FREE = 2 * 1000**3  # 2 GB, below which installs and updates get risky
SHELL_TOOLS = ["niri", "qs", "wpctl", "grim", "notify-send"]


def run(cmd, timeout=8):
    """stdout on success ('' when there is nothing to say); None on failure."""
    if not shutil.which(cmd[0]):
        return None
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return p.stdout.strip() if p.returncode == 0 else None


def check(cid, title, ok, detail):
    return {"id": cid, "title": title, "ok": bool(ok), "detail": detail}


def checks():
    out = []

    # A successful df ends in one number; a failed one gives None.
    free_text = run(["df", "-B1", "--output=avail", "/"])
    lines = [l.strip() for l in (free_text or "").splitlines() if l.strip()]
    free = int(lines[-1]) if lines and lines[-1].isdigit() else None
    out.append(
        check(
            "space",
            "Free space on the system disk",
            free is not None and free >= MIN_FREE,
            f"{free / 1e9:.1f} GB free" if free is not None else "could not be read",
        )
    )

    # No output from `systemctl --failed` means no failed units — a pass, not an error.
    failed = run(["systemctl", "--failed", "--no-legend", "--plain"])
    services_ok = failed is not None and not failed.splitlines()
    out.append(
        check(
            "services",
            "System services",
            services_ok,
            "none failed"
            if services_ok
            else (
                "; ".join(failed.splitlines()[:3])
                if failed is not None
                else "could not be read"
            ),
        )
    )

    opts = run(["findmnt", "-no", "OPTIONS", "/"])
    writable_ok = opts is not None and "ro" not in opts.split(",")
    out.append(
        check(
            "writable",
            "System files can be written",
            writable_ok,
            "read and write"
            if writable_ok
            else ("read-only" if opts is not None else "could not be read"),
        )
    )

    missing = [t for t in SHELL_TOOLS if not shutil.which(t)]
    out.append(
        check(
            "tools",
            "Desktop tools present",
            not missing,
            "all present" if not missing else "missing: " + ", ".join(missing),
        )
    )

    return out


def main():
    json.dump(checks(), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
