#!/usr/bin/env python3
"""One stand-in for the six read-only tools behind the system pages.

Symlink this file by tool name (flatpak, snap, ostree, lspci, glxinfo and
shani-etc-changes) and point the bridge's SHANI_* variable at the symlink. Every
call is logged to $FAKE_SYSTEM_INFO/calls as "<tool> <args>" so a test can check
the exact argv. The outputs are fixed and realistic; lspci includes a display
controller with no kernel driver, and the etc helper hides a secret file's diff.

$FAKE_SYSTEM_ETC_DIR may hold list.json, diff.json, restore.json and cancel.json
to replace the etc helper's answers. $FAKE_SYSTEM_ETC_FAIL=1 makes the helper
fail, and $FAKE_SYSTEM_INFO_FAIL=<comma-separated tool names> makes any listed
tool fail. Mountinfo and data-dir fixtures go straight to the bridge through
SHANI_MOUNTINFO, SHANI_DATA_DIR and SHANI_DATA_SIZE (tests/test_system_machine.py).
"""

from __future__ import annotations

import json
import os
import sys

D = os.environ.get("FAKE_SYSTEM_INFO", "/tmp")
os.makedirs(D, exist_ok=True)
PROG = os.path.basename(sys.argv[0])
ARGS = sys.argv[1:]
with open(os.path.join(D, "calls"), "a", encoding="utf-8") as log:
    log.write(PROG + " " + " ".join(ARGS) + "\n")

FAILING = {
    x.strip()
    for x in os.environ.get("FAKE_SYSTEM_INFO_FAIL", "").split(",")
    if x.strip()
}
if PROG in FAILING or (
    PROG == "shani-etc-changes" and os.environ.get("FAKE_SYSTEM_ETC_FAIL")
):
    print("tool failed on purpose", file=sys.stderr)
    sys.exit(1)


def from_fixture(name: str, default: str) -> str:
    base = os.environ.get("FAKE_SYSTEM_ETC_DIR", "")
    path = os.path.join(base, name) if base else ""
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            return f.read()
    return default


if PROG == "flatpak":
    print("org.gnome.TextEditor\tText Editor\t46.2")
    print("com.example.Notes\tNotes\t1.8.1")
elif PROG == "snap":
    print("Name  Version  Rev  Tracking       Publisher     Notes")
    print("core22  20241001  1663  latest/stable  canonical✓    base")
    print("firefox  141.0  312  latest/stable  mozilla✓      -")
    print("code  1.95  142  latest/stable  vscode✓       classic")
elif PROG == "ostree":
    print(
        json.dumps(
            [
                {
                    "id": "shani/stable",
                    "version": "26.2026.11",
                    "checksum": "e2f7a91d4b6c0f8a3d5e7b9c1a2f4d6e8b0c2a4f6d8e0b2c4a6f8d0e2c4a6f8",
                    "booted": True,
                }
            ]
        )
    )
elif PROG == "lspci":
    # Blank-line separated blocks, as lspci -nnk prints them. The last display
    # controller has modules but no bound driver: never guess one from modules.
    print("""00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics] [8086:9a49] (rev 01)
\tSubsystem: Lenovo Device [17aa:3f8e]
\tKernel driver in use: i915
\tKernel modules: i915

00:14.0 USB controller [0c03]: Intel Corporation Tiger Lake-LP USB 3.2 Gen 2x1 xHCI Host Controller [8086:a0ed] (rev 20)
\tKernel driver in use: xhci_hcd

01:00.0 3D controller [0302]: NVIDIA Corporation TU117M [GeForce GTX 1650 Mobile] [10de:1f91] (rev a1)
\tKernel driver in use: nvidia
\tKernel modules: nouveau, nvidia_drm, nvidia

02:00.0 Display controller [0380]: Advanced Micro Devices, Inc. [AMD/ATI] Topaz XT [Radeon R7 M260] [1002:690f] (rev ff)
\tKernel modules: radeon""")
elif PROG == "glxinfo":
    print("name of display: :0")
    print("direct rendering: Yes")
    print("OpenGL renderer string: Mesa Intel(R) Xe Graphics (TGL GT2)")
    print("OpenGL version string: 4.6 (Compatibility Profile) Mesa 24.2.8")
elif PROG == "shani-etc-changes":
    verb = ARGS[0] if ARGS else ""
    if verb == "list":
        print(
            from_fixture(
                "list.json",
                json.dumps(
                    {
                        "ok": True,
                        "changes": [
                            {
                                "path": "/etc/hosts",
                                "kind": "edited file",
                                "protected": False,
                                "secret": False,
                                "pending": True,
                            },
                            {
                                "path": "/etc/ssh/sshd_config",
                                "kind": "settings",
                                "protected": True,
                                "secret": False,
                                "pending": True,
                            },
                            {
                                "path": "/etc/shadow",
                                "kind": "password file",
                                "protected": True,
                                "secret": True,
                                "pending": False,
                            },
                        ],
                        "pending": ["/etc/hosts", "/etc/ssh/sshd_config"],
                        "done": ["/etc/shadow"],
                    }
                ),
            )
        )
    elif verb == "diff":
        path = ARGS[1] if len(ARGS) > 1 else ""
        if path == "/etc/shadow":
            answer = {"ok": True, "diff": "", "hidden": True, "binary": False}
        elif path.endswith(".png"):
            answer = {"ok": True, "diff": "", "hidden": False, "binary": True}
        else:
            answer = {
                "ok": True,
                "diff": "--- a%s\n+++ b%s\n@@ -1 +1 @@\n-old line\n+new line\n"
                % (path, path),
                "hidden": False,
                "binary": False,
            }
        print(from_fixture("diff.json", json.dumps(answer)))
    elif verb == "restore":
        print(from_fixture("restore.json", json.dumps({"ok": True, "queued": True})))
    elif verb == "cancel":
        print(from_fixture("cancel.json", json.dumps({"ok": True, "queued": False})))
    else:
        print("unknown verb", file=sys.stderr)
        sys.exit(2)
