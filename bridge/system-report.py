#!/usr/bin/env python3
"""A plain-text problem report, collected on this computer only.

Ported from Ananta OS's problem report (ananta-maintenanced/src/report.rs):
the same sections, the same rule that nothing secret goes in, and the same
contract that a person reads and edits it before saving or copying it. The
shell opens the result in its own Text Editor; this script only prints it.

Read-only: no state is changed, no home files are read, no passwords, keys or
recovery keys are collected. Logs can contain a computer's or an account's
name, so the report says so at the top.
"""

from __future__ import annotations

import shutil
import subprocess
import sys

JOURNAL_LINES = "100"


def run(cmd, timeout=10):
    """Run a read-only command; say plainly when it is missing or fails."""
    if not shutil.which(cmd[0]):
        return f"({cmd[0]} is not available)"
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"({e})"
    return (p.stdout or p.stderr).strip() or "(nothing)"


def section(title, body):
    return f"## {title}\n\n{body.strip() or '(nothing)'}\n"


def report(runner=run):
    """Build the report. `runner` is injected so the sections can be tested."""
    os_release = {}
    try:
        with open("/etc/os-release", encoding="utf-8", errors="replace") as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    os_release[k] = v.strip().strip('"')
    except OSError:
        pass

    version = os_release.get("PRETTY_NAME") or os_release.get("VERSION_ID") or "unknown"
    host = runner(["hostnamectl", "hostname"])
    kernel = runner(["uname", "-r"])

    out = [
        "# Shani Shell problem report\n",
        f"Version {version} · Kernel {kernel}\n",
        "Review this before sharing: logs can contain a computer's or an account's name.\n",
    ]

    out.append(
        section(
            "System",
            "\n".join(
                [
                    f"Computer: {host}",
                    f"Uptime: {runner(['uptime', '-p'])}",
                    f"Session: niri {runner(['niri', '--version'])} · Quickshell {runner(['qs', '--version'])}",
                ]
            ),
        )
    )
    out.append(
        section(
            "Storage",
            runner(["df", "-h", "--output=target,size,used,avail", "/", "/home"]),
        )
    )
    out.append(
        section(
            "Hardware",
            "\n".join(
                [
                    runner(
                        [
                            "sh",
                            "-c",
                            'sed -n "s/^model name\\s*: //p" /proc/cpuinfo | head -1; nproc',
                        ]
                    ),
                    runner(["lspci", "-nn"]),
                ]
            ),
        )
    )
    out.append(
        section(
            "Services that failed",
            runner(["systemctl", "--failed", "--no-legend", "--plain"]),
        )
    )
    out.append(
        section(
            "Errors since this start",
            runner(
                [
                    "journalctl",
                    "-b",
                    "-p",
                    "3",
                    "-o",
                    "short-monotonic",
                    "--no-pager",
                    "-n",
                    JOURNAL_LINES,
                ]
            ),
        )
    )
    out.append(
        section(
            "Errors of the previous start",
            runner(
                [
                    "journalctl",
                    "-b",
                    "-1",
                    "-p",
                    "3",
                    "-o",
                    "short-monotonic",
                    "--no-pager",
                    "-n",
                    JOURNAL_LINES,
                ]
            ),
        )
    )
    return "\n".join(out)


def main():
    sys.stdout.write(report())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
