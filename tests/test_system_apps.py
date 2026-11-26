"""bridge/system_apps.py against one stand-in (dev/fake-system-info.py): flatpak's
tab-separated apps, snap's table and an ostree deployment, the os-release fallback,
and honest "have: false" when a tool is not there. No total is invented across
managers that number their versions differently.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_apps.py"
FAKE = ROOT / "dev" / "fake-system-info.py"
TOOLS = ("flatpak", "snap", "ostree")
MISSING = "/nonexistent/no-such-tool"


def run(tmp_path, *args, tools=TOOLS, os_release=True, env_extra=None):
    for name in TOOLS:
        p = tmp_path / name
        if name in tools and not p.exists():
            p.symlink_to(FAKE)
    env = dict(
        os.environ,
        FAKE_SYSTEM_INFO=str(tmp_path),
        PATH="%s:%s" % (tmp_path, os.environ["PATH"]),
    )
    for k in (
        "SHANI_SYSTEM_FLATPAK",
        "SHANI_SYSTEM_SNAP",
        "SHANI_OSTREE",
        "SHANI_OS_RELEASE",
        "FAKE_SYSTEM_INFO_FAIL",
    ):
        env.pop(k, None)
    env["SHANI_SYSTEM_FLATPAK"] = str(tmp_path / "flatpak") if "flatpak" in tools else MISSING
    env["SHANI_SYSTEM_SNAP"] = str(tmp_path / "snap") if "snap" in tools else MISSING
    env["SHANI_OSTREE"] = str(tmp_path / "ostree") if "ostree" in tools else MISSING
    release = tmp_path / "os-release"
    if os_release:
        release.write_text(
            'NAME="ShaniOS"\nPRETTY_NAME="ShaniOS 26"\nVERSION_ID="26.2026.11"\n',
            encoding="utf-8",
        )
    env["SHANI_OS_RELEASE"] = str(release) if os_release else MISSING
    if env_extra:
        env.update(env_extra)
    r = subprocess.run(
        [sys.executable, str(BRIDGE), "list", *args],
        capture_output=True,
        text=True,
        env=env,
    )
    return json.loads(r.stdout), r.returncode


def calls(tmp_path):
    p = tmp_path / "calls"
    return p.read_text(encoding="utf-8").splitlines() if p.exists() else []


def test_list_parses_all_three_managers(tmp_path):
    got, rc = run(tmp_path)
    assert rc == 0
    assert got == {
        "flatpak": [
            {"id": "org.gnome.TextEditor", "name": "Text Editor", "version": "46.2"},
            {"id": "com.example.Notes", "name": "Notes", "version": "1.8.1"},
        ],
        "snap": [
            {"id": "core22", "name": "core22", "version": "20241001"},
            {"id": "firefox", "name": "firefox", "version": "141.0"},
            {"id": "code", "name": "code", "version": "1.95"},
        ],
        "os": [{"id": "shani/stable", "version": "26.2026.11"}],
        "have": {"flatpak": True, "snap": True, "os": True},
    }
    assert calls(tmp_path) == [
        "flatpak list --app --columns=application,application-name,version",
        "snap list",
        "ostree admin deploy --json",
    ]


def test_missing_tools_are_empty_and_not_claimed(tmp_path):
    got, _ = run(tmp_path, tools=(), os_release=False)
    assert got == {
        "flatpak": [],
        "snap": [],
        "os": [],
        "have": {"flatpak": False, "snap": False, "os": False},
    }
    assert calls(tmp_path) == []


def test_os_release_fallback_when_ostree_is_absent(tmp_path):
    got, _ = run(tmp_path, tools=("flatpak", "snap"))
    assert got["os"] == [{"id": "ShaniOS 26", "version": "26.2026.11"}]
    assert got["have"]["os"] is True
    assert "ostree" not in " ".join(calls(tmp_path))


def test_failed_tool_has_no_invented_rows(tmp_path):
    got, _ = run(tmp_path, env_extra={"FAKE_SYSTEM_INFO_FAIL": "flatpak"})
    assert got["flatpak"] == [] and got["have"]["flatpak"] is True
    assert len(got["snap"]) == 3 and got["os"] == [
        {"id": "shani/stable", "version": "26.2026.11"}
    ]
