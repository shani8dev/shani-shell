#!/usr/bin/env python3
"""Stand-in for the boot tools used by bridge/bootinfo.py.

Invoked by basename through copies named ``shani-deploy``, ``sbctl``,
``mokutil`` and ``pkexec``. It accepts only the exact forms the bridge uses;
anything else is usage on stderr and exit 2. Every call is logged (argv only)
to $FAKE_BOOT_TOOLS_DIR/calls (default /tmp/fake-boot-tools/calls). No secret
is ever accepted, logged or printed.

Fixture overrides, all optional:
  FAKE_BOOT_TOOLS_STATUS       JSON text | fail | bad-json
  FAKE_BOOT_TOOLS_BACKUPS      JSON text | fail | bad-json
  FAKE_BOOT_TOOLS_SBCTL        JSON text | fail | bad-json | empty
  FAKE_BOOT_TOOLS_SB_STATE     enabled (default) | disabled | unknown | fail
  FAKE_BOOT_TOOLS_KEYS         number of [key N] blocks (default 2) | fail
  FAKE_BOOT_TOOLS_VERIFY       ok (default) | issues | unread | noanswer | empty | cancelled
  FAKE_BOOT_TOOLS_PKEXEC_RC    exit code for the pkexec shim, before any output
"""

from __future__ import annotations

import json
import os
import sys

D = os.environ.get("FAKE_BOOT_TOOLS_DIR", "/tmp/fake-boot-tools")
CALLS = os.path.join(D, "calls")

STATUS = {
    "version": "20261121",
    "profile": "niri",
    "channel": "stable",
    "booted_slot": "green",
    "current_slot": "green",
    "previous_slot": "blue",
    "candidate_boot": False,
    "update_available": None,
    "boot_failure": "",
    "auto_rollback_done": False,
}
BACKUPS = {
    "slots": [
        {
            "slot": "green",
            "version": "20261121",
            "backups": [
                {
                    "name": "green-pre-update",
                    "created": "2026-11-21 08:30",
                    "size": "1.2G",
                }
            ],
        },
        {
            "slot": "blue",
            "version": "20261109",
            "backups": [
                {
                    "name": "blue-pre-update",
                    "created": "2026-11-09 09:10",
                    "size": "1.1G",
                }
            ],
        },
    ]
}
SBCTL = {
    "vendors": ["Microsoft", "Custom Key"],
    "guid": "a1b2c3d4",
    "installed": True,
    "secure_boot": True,
    "setup_mode": False,
}

USAGE = (
    "usage: fake-boot-tools.py: shani-deploy --status --json|"
    "--status --check --json|--verify-existing|--list-backups --json; "
    "sbctl status --json; mokutil --sb-state|--list-enrolled; "
    "pkexec <command>"
)


def usage() -> None:
    print(USAGE, file=sys.stderr)


def log_call(name: str, args: list[str]) -> None:
    os.makedirs(D, exist_ok=True)
    with open(CALLS, "a", encoding="utf-8") as handle:
        handle.write(" ".join([name] + args) + "\n")


def json_fixture(env: str, default: dict) -> int:
    """Print a JSON fixture, or honour a failure mode."""
    value = os.environ.get(env)
    if value == "fail":
        print("fake-boot-tools: command failed", file=sys.stderr)
        return 1
    if value == "bad-json":
        print("not json at all")
        return 0
    if value == "empty":
        return 0
    doc = default
    if value:
        try:
            doc = json.loads(value)
        except ValueError:
            print("fake-boot-tools: bad fixture in " + env, file=sys.stderr)
            return 2
    print(json.dumps(doc))
    return 0


def verify_text(mode: str) -> str:
    """The tool's own lines: SGR colour is the only severity signal."""

    def row(key: str, tone: int | None, text: str) -> str:
        pad = f"  {key:<16} "
        if tone is None:
            return pad + text + "\x1b[0m"
        return pad + f"\x1b[0;3{tone}m" + text + "\x1b[0m"

    lines = ["=" * 48, "Verify Existing Deployment", "=" * 48]
    if mode == "empty":
        return ""
    if mode == "noanswer":
        return "\n".join(lines) + "\n"  # a title and rules, but no rows
    if mode == "cancelled":
        return ""  # the caller exits 126 before printing
    if mode == "issues":
        lines += [
            row("UKI Booted", 2, "both slots verify against the MOK certificate"),
            row("UKI Candidate", 1, "candidate image is not signed"),
            row("Loader default", 1, "points at a slot with no signed image"),
            row("Rollback backups", 2, "both slots hold a rollback backup"),
            row("Booted slot", 3, "booted (@green) matches current-slot"),
            row("Deploy State", 2, "no pending deployment"),
            row("Reboot Status", None, "no reboot needed"),
            "    \x1b[0;33m-> Re-sign the candidate image before restarting\x1b[0m",
            "\x1b[0;31m2026-11-26 10:00:00 [ERROR] found 2 issues\x1b[0m",
        ]
    else:
        lines += [
            row("UKI Booted", 2, "both slots verify against the MOK certificate"),
            row("UKI Candidate", 2, "candidate image is signed"),
            row("Loader default", 2, "points at the booted slot"),
            row("Rollback backups", 2, "both slots hold a rollback backup"),
            row("Booted slot", 3, "booted (@green) matches current-slot"),
            row("Deploy State", 2, "no pending deployment"),
            row("Reboot Status", None, "no reboot needed"),
            "    \x1b[0;33m-> A yellow row is worth a look, not a failure\x1b[0m",
            "\x1b[0;32m2026-11-26 10:00:00 [SUCCESS] all checks passed\x1b[0m",
        ]
    if mode == "unread":
        lines.insert(3, "a line this build added that no page reads")
    return "\n".join(lines) + "\n"


def deploy(args: list[str]) -> int:
    if args in (["--status", "--json"], ["--status", "--check", "--json"]):
        return json_fixture("FAKE_BOOT_TOOLS_STATUS", STATUS)
    if args == ["--verify-existing"]:
        mode = os.environ.get("FAKE_BOOT_TOOLS_VERIFY", "ok")
        if mode not in ("ok", "issues", "unread", "noanswer", "empty", "cancelled"):
            usage()
            return 2
        if mode == "cancelled":
            return int(os.environ.get("FAKE_BOOT_TOOLS_PKEXEC_RC", "126"))
        sys.stdout.write(verify_text(mode))
        return 0
    if args == ["--list-backups", "--json"]:
        return json_fixture("FAKE_BOOT_TOOLS_BACKUPS", BACKUPS)
    usage()
    return 2


def sbctl(args: list[str]) -> int:
    if args != ["status", "--json"]:
        usage()
        return 2
    return json_fixture("FAKE_BOOT_TOOLS_SBCTL", SBCTL)


def mokutil(args: list[str]) -> int:
    if args == ["--sb-state"]:
        state = os.environ.get("FAKE_BOOT_TOOLS_SB_STATE", "enabled")
        if state not in ("enabled", "disabled", "unknown", "fail"):
            usage()
            return 2
        if state == "fail":
            print("mokutil: command failed", file=sys.stderr)
            return 1
        if state != "unknown":
            print(f"SecureBoot {state}")
        return 0
    if args == ["--list-enrolled"]:
        count = os.environ.get("FAKE_BOOT_TOOLS_KEYS", "2")
        if count == "fail":
            print("mokutil: command failed", file=sys.stderr)
            return 1
        if not count.isdigit():
            usage()
            return 2
        for number in range(1, int(count) + 1):
            print(f"[key {number}]")
            print("  Subject: CN=Shani MOK")
        return 0
    usage()
    return 2


def main(args: list[str]) -> int:
    name = os.path.basename(sys.argv[0])
    log_call(name, args)
    if name == "pkexec":
        override = os.environ.get("FAKE_BOOT_TOOLS_PKEXEC_RC")
        if override is not None:
            return int(override)
        if not args:
            usage()
            return 2
        name = os.path.basename(args[0])
        if name != "shani-deploy":
            usage()
            return 2
        args = args[1:]
    if name == "shani-deploy":
        return deploy(args)
    if name == "sbctl":
        return sbctl(args)
    if name == "mokutil":
        return mokutil(args)
    usage()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
