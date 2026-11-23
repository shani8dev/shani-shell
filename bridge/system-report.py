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
    """Run a read-only command; return {ok, output, error}, never a bare string.

    A missing tool, a timeout and a non-zero exit are failures, distinct from
    a command that succeeded with empty output.
    """
    if not shutil.which(cmd[0]):
        return {"ok": False, "output": "", "error": f"{cmd[0]} is not available"}
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {"ok": False, "output": "", "error": str(e)}
    output = (p.stdout or p.stderr).strip()
    if p.returncode != 0:
        return {
            "ok": False,
            "output": output,
            "error": (p.stderr or p.stdout).strip() or f"exit {p.returncode}",
        }
    return {"ok": True, "output": output, "error": ""}


def text(result):
    """Render a runner result as report text, marking failures visibly."""
    if isinstance(result, str):  # injected runners in the tests return plain strings
        return result.strip() or "(nothing)"
    body = (result.get("output") or "").strip()
    if result.get("ok"):
        return body or "(nothing)"
    err = (result.get("error") or "").strip() or "failed"
    return "[FAILED: " + err + "]" + ("\n" + body if body else "")


def section(title, body):
    return f"## {title}\n\n{text(body)}\n"


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
    host = text(runner(["hostnamectl", "hostname"]))
    kernel = text(runner(["uname", "-r"]))

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
                    f"Uptime: {text(runner(['uptime', '-p']))}",
                    f"Session: niri {text(runner(['niri', '--version']))} · Quickshell {text(runner(['qs', '--version']))}",
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
                    text(
                        runner(
                            [
                                "sh",
                                "-c",
                                'sed -n "s/^model name\\s*: //p" /proc/cpuinfo | head -1; nproc',
                            ]
                        )
                    ),
                    text(runner(["lspci", "-nn"])),
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
