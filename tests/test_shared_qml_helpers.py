"""Four identical QML bodies now live once in Common/*.js.

The helpers are plain logic, so node checks the behaviour the copies had; a
static check keeps every caller on the shared name.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shani" / "Common"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def ask(helper: str, body: str):
    src = (COMMON / helper).read_text(encoding="utf-8").replace(".pragma library", "")
    out = subprocess.run(
        ["node", "-e", src + "\n" + body], capture_output=True, text=True, check=True
    )
    return json.loads(out.stdout.strip().splitlines()[-1])


def test_service_run_starts_the_command():
    got = ask(
        "ServiceRun.js",
        """
var s = {};
var r = begin(s, "fetch");
console.log(JSON.stringify([r, s.what, s.busy, s.error]));
""",
    )
    assert got == [True, "fetch", True, ""]


def test_files_reveal_ignores_urls():
    got = ask(
        "FilesReveal.js",
        """
var seen = [];
var files = { show: p => seen.push("show:" + p), select: (p, m) => seen.push("select:" + p + ":" + m) };
var a = show("/home/me/a.txt", files);
var b = show("file:///home/me/a.txt", files);
console.log(JSON.stringify([a, seen, b]));
""",
    )
    assert got == [True, ["show:/home/me", "select:/home/me/a.txt:single"], False]


def test_job_queue_runs_one_job_at_a_time():
    got = ask(
        "JobQueue.js",
        """
var started = [];
var self = { busy: false, pending: [{ what: "a", args: [] }, { what: "b", args: ["x"] }],
             start: (w, a) => started.push(w + ":" + a.join(",")) };
var job = { running: false };
pump(self, job);
pump(self, job);
console.log(JSON.stringify(started));
""",
    )
    assert got == ["a:", "b:x"]


def test_net_tools_hand_off_and_empty_host():
    got = ask(
        "NetToolsOpen.js",
        """
var shell = {}, ui = { calls: [], closeAll: () => ui.calls.push("close"), netTools: false };
var a = open(" example.org ", shell, ui);
var b = open("", shell, ui);
console.log(JSON.stringify([a, shell.clipboardText, ui.netTools, ui.calls, b]));
""",
    )
    assert got == [True, "shani-nettools:example.org", True, ["close"], False]


GROUPS = {
    "ServiceRun": (
        "ServiceRun.begin(root, what)",
        [
            "shani/Services/PlayQueue.qml",
            "shani/Services/QuickNotes.qml",
            "shani/Services/Weather.qml",
            "shani/Services/Archive.qml",
        ],
    ),
    "FilesReveal": (
        "FilesReveal.show(path, Files)",
        [
            "shani/Modules/Viewer/Viewer.qml",
            "shani/Modules/Photos/PhotosWindow.qml",
            "shani/Modules/Archives/ArchivesWindow.qml",
            "shani/Modules/PdfReader/PdfReader.qml",
        ],
    ),
    "JobQueue": (
        "JobQueue.pump(root, job)",
        [
            "shani/Services/PhoneTools.qml",
            "shani/Services/Devices.qml",
            "shani/Services/Lines.qml",
        ],
    ),
    "NetToolsOpen": (
        "NetToolsOpen.open(host, Quickshell, Ui)",
        [
            "shani/Modules/Maps/MapsPanel.qml",
            "shani/Modules/Files/FilesPanel.qml",
            "shani/Modules/Terminal/TerminalAppWindow.qml",
        ],
    ),
}

OLD_BODIES = (
    "root.what = what;\n        root.busy = true;",
    'Files.select(p, "single");',
    "root.pending = root.pending.slice(1);",
    'Quickshell.clipboardText = "shani-nettools:" + h;',
)


def test_every_copy_calls_the_shared_helper():
    for helper, (call, files) in GROUPS.items():
        assert (COMMON / (helper + ".js")).exists(), helper
        for path in files:
            text = (ROOT / path).read_text(encoding="utf-8")
            assert call in text, (path, call)
            assert helper + ".js" in text, path
            for old in OLD_BODIES:
                assert old not in text, (path, old)
