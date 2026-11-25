"""The background cloud-sync feature: bridge/cloudsync.py against a fake rclone,
the two QML files as text (the shell has no QML runner here), and the user unit.

The daemon is driven exactly as Services/CloudSync drives it — JSON lines on
stdin, JSON events on stdout — so the protocol, the state file, the retry and
the progress events are really exercised, not just grepped. The panel's form
validation is lifted out and run in node with small stand-ins, like the other
large-feature tests do.
"""

import importlib.util
import json
import os
import queue
import re
import select
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "cloudsync.py"
SERVICE = (ROOT / "shani/Services/CloudSync.qml").read_text(encoding="utf-8")
PANEL = (ROOT / "shani/Modules/Cloud/CloudPanel.qml").read_text(encoding="utf-8")
UNIT = (ROOT / "data/systemd/shani-cloudsync.service").read_text(encoding="utf-8")

FAKE = r"""#!/bin/sh
echo "$*" >> "$T/args"
[ -e "$T/fail" ] && { echo "rclone: always fails" >&2; exit 9; }
if [ -e "$T/failonce" ] && [ ! -e "$T/recovered" ]; then : > "$T/recovered"; echo "rclone: once" >&2; exit 9; fi
if [ "$1" = copy ]; then
  echo "2026/01/01 00:00:00 INFO  : one.txt: Copied (new)"
  echo "Transferred:   1.000 KiB / 2.000 KiB, 50%, 1 KiB/s, ETA 1s"
  echo "2026/01/01 00:00:01 INFO  : two.txt: Copied (new)"
  echo "Transferred:   2.000 KiB / 2.000 KiB, 100%, 2 KiB/s, ETA 0s"
fi
"""


def setup(tmp_path):
    (tmp_path / "bin").mkdir(exist_ok=True)
    fake = tmp_path / "bin" / "rclone"
    fake.write_text(FAKE)
    fake.chmod(0o755)
    return dict(
        os.environ,
        PATH="%s:%s" % (tmp_path / "bin", os.environ["PATH"]),
        T=str(tmp_path),
        XDG_STATE_HOME=str(tmp_path / "state"),
    )


class Driver:
    def __init__(self, env):
        self.env = env
        self.events = []
        self.buf = b""
        self.p = subprocess.Popen(
            [sys.executable, str(BRIDGE)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
            env=env,
        )

    def send(self, **msg):
        self.p.stdin.write((json.dumps(msg) + "\n").encode())
        self.p.stdin.flush()

    def _read(self, timeout):
        # Raw bytes: select() watches the fd, while readline() could buffer two
        # events in one read and leave the second invisible to the next select.
        deadline = time.monotonic() + timeout
        while True:
            while b"\n" in self.buf:
                raw, self.buf = self.buf.split(b"\n", 1)
                if not raw.strip():
                    continue
                e = json.loads(raw)
                self.events.append(e)
                yield e
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return
            r, _, _ = select.select([self.p.stdout.fileno()], [], [], remaining)
            if not r:
                return
            chunk = os.read(self.p.stdout.fileno(), 65536)
            if not chunk:
                return
            self.buf += chunk

    def wait(self, pred, timeout=8):
        for e in self._read(timeout):
            if pred(e):
                return e
        raise AssertionError(
            "no matching event; saw %s" % [e.get("event") for e in self.events[-12:]]
        )

    def job(self, jid, state=None, timeout=8):
        return self.wait(
            lambda e: (
                e.get("event") == "job"
                and e["job"]["id"] == jid
                and (state is None or e["job"]["state"] == state)
            ),
            timeout,
        )

    def close(self):
        try:
            self.send(cmd="quit")
        except (BrokenPipeError, OSError):
            pass
        try:
            self.p.stdin.close()
            self.p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.p.kill()
        self.buf += self.p.stdout.read()
        self.events += [json.loads(x) for x in self.buf.splitlines() if x.strip()]
        self.buf = b""
        return self.p.stderr.read().decode()


def new_job(tmp_path, env, **overrides):
    d = Driver(env)
    try:
        msg = dict(
            cmd="add",
            id="photos",
            remote="drive:Photos",
            local=str(tmp_path / "Pictures"),
            direction="download",
            conflict="rename",
            bandwidth="",
            interval=0,
        )
        msg.update(overrides)
        d.send(**msg)
        d.job(msg["id"])
        return d
    except Exception:
        d.close()
        raise


# ---- the daemon: protocol, state, copy -------------------------------------------


def test_job_added_and_persisted_across_restart(tmp_path):
    env = setup(tmp_path)
    d = new_job(tmp_path, env)
    assert d.close() == ""
    state = json.loads((tmp_path / "state" / "shani" / "cloudsync.json").read_text())
    assert state["jobs"]["photos"]["remote"] == "drive:Photos"
    assert state["jobs"]["photos"]["state"] == "idle"

    d = Driver(env)
    jobs = d.wait(lambda e: e.get("event") == "jobs")["jobs"]
    assert [j["id"] for j in jobs] == ["photos"]
    d.close()


def test_copy_emits_per_file_progress_and_notifications(tmp_path):
    env = setup(tmp_path)
    d = new_job(tmp_path, env, bandwidth="2M", conflict="skip")
    d.send(cmd="start", id="photos")
    d.job("photos", "running")
    done = d.job("photos", "done")
    d.wait(lambda e: e.get("event") == "notify" and e["title"] == "Cloud sync finished")
    assert done["job"]["progress"] == 1.0 and done["job"]["retries"] == 0
    assert [e["file"] for e in d.events if e.get("event") == "progress"][-2:] == [
        "one.txt",
        "two.txt",
    ]
    assert any(
        e.get("progress") == 0.5 for e in d.events if e.get("event") == "progress"
    )
    notes = [e for e in d.events if e.get("event") == "notify"]
    assert [n["title"] for n in notes] == [
        "Cloud sync added",
        "Cloud sync started",
        "Cloud sync finished",
    ]
    args = (tmp_path / "args").read_text()
    assert "--bwlimit=2M" in args and "--ignore-existing" in args
    assert "drive:Photos/ %s/ --progress --stats 1s" % (tmp_path / "Pictures") in args
    d.close()


def test_direction_and_conflict_policies_reach_rclone(tmp_path):
    env = setup(tmp_path)
    d = new_job(tmp_path, env, direction="upload", conflict="keepboth", id="up")
    d.send(cmd="start", id="up")
    d.job("up", "done")
    d.close()
    args = (tmp_path / "args").read_text()
    assert "%s/ drive:Photos/" % (tmp_path / "Pictures") in args
    assert "--backup-dir drive:Photos/.cloudsync-conflicts" in args

    env = setup(tmp_path)
    d = new_job(tmp_path, env, conflict="rename", id="ren")
    d.send(cmd="start", id="ren")
    d.job("ren", "done")
    d.close()
    assert "--suffix=-conflict" in (tmp_path / "args").read_text()


def test_failure_retries_with_backoff_and_a_later_success_resets_it(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "failonce").touch()
    d = new_job(tmp_path, env)
    d.send(cmd="start", id="photos")
    failed = d.job("photos", "error")
    d.wait(lambda e: e.get("event") == "notify" and e["title"] == "Cloud sync failed")
    j = failed["job"]
    assert j["retries"] == 1 and 3.5 <= j["nextRun"] - time.time() <= 5.5
    assert any(
        e.get("event") == "notify"
        and e.get("level") == "error"
        and e["title"] == "Cloud sync failed"
        for e in d.events
    )
    d.send(cmd="start", id="photos")
    ok = d.job("photos", "done")
    assert ok["job"]["retries"] == 0 and ok["job"]["nextRun"] == 0.0
    d.close()


def test_validation_and_errors(tmp_path):
    env = setup(tmp_path)
    d = Driver(env)
    for bad in (
        dict(id="bad/name", remote="drive:Photos", local="/tmp"),
        dict(id="x", remote="no-colon", local="/tmp"),
        dict(id="x", remote="drive:", local="/tmp"),
        dict(id="x", remote="drive:P", local="relative"),
        dict(id="x", remote="drive:P", local="/tmp", direction="sideways"),
        dict(id="x", remote="drive:P", local="/tmp", conflict="delete"),
        dict(id="x", remote="drive:P", local="/tmp", bandwidth="fast"),
        dict(id="x", remote="drive:P", local="/tmp", interval="soon"),
    ):
        d.send(cmd="add", **bad)
        d.wait(lambda e: e.get("event") == "error")
    assert len([e for e in d.events if e.get("event") == "error"]) == 8
    d.send(cmd="start", id="missing")
    assert d.wait(lambda e: e.get("event") == "error")["error"].startswith(
        "no sync job"
    )
    d.send(cmd="nope")
    assert d.wait(lambda e: e.get("event") == "error")["error"] == "unknown command"
    d.close()


def test_settings_remove_and_list(tmp_path):
    env = setup(tmp_path)
    d = new_job(tmp_path, env)
    d.send(cmd="settings", id="photos", conflict="skip", bandwidth="1M", interval=3600)
    j = d.wait(
        lambda e: e.get("event") == "job" and e["job"].get("conflict") == "skip"
    )["job"]
    assert (j["conflict"], j["bandwidth"], j["interval"]) == ("skip", "1M", 3600)
    assert j["nextRun"] > time.time()
    d.send(cmd="list")
    assert [x["id"] for x in d.wait(lambda e: e.get("event") == "jobs")["jobs"]] == [
        "photos"
    ]
    d.send(cmd="remove", id="photos")
    d.wait(lambda e: e.get("event") == "removed" and e["id"] == "photos")
    assert (
        json.loads((tmp_path / "state" / "shani" / "cloudsync.json").read_text())[
            "jobs"
        ]
        == {}
    )
    d.close()


# ---- pause / resume and the schedule (in-process, deterministic) -----------------


def load_module():
    spec = importlib.util.spec_from_file_location("cloudsync", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Lines:
    def __init__(self):
        self.q = queue.Queue()

    def __iter__(self):
        return self

    def __next__(self):
        value = self.q.get()
        if value is None:
            raise StopIteration
        return value


class FakeProc:
    def __init__(self, signals):
        self.stdout = Lines()
        self.signals = signals
        self.terminated = False

    def send_signal(self, sig):
        self.signals.append(sig)

    def terminate(self):
        self.terminated = True
        self.stdout.q.put(None)

    def wait(self):
        return 0


def test_pause_resume_and_schedule(tmp_path, monkeypatch):
    mod = load_module()
    signals = []
    procs = []

    def popen(*args, **kw):
        p = FakeProc(signals)
        procs.append(p)
        return p

    monkeypatch.setattr(mod.subprocess, "Popen", popen)
    d = mod.Daemon(str(tmp_path / "state.json"))
    events = []
    d.emit = lambda e: events.append(e)
    d.handle(
        {
            "cmd": "add",
            "id": "p",
            "remote": "drive:P",
            "local": str(tmp_path),
            "direction": "download",
            "conflict": "rename",
            "bandwidth": "",
            "interval": 3600,
        }
    )
    # a past due job is picked up by tick(), not by the UI
    d.jobs["p"]["nextRun"] = time.time() - 1
    d.tick()
    assert d.jobs["p"]["nextRun"] == 0.0
    deadline = time.monotonic() + 3
    while not d.workers.get("p") and time.monotonic() < deadline:
        time.sleep(0.01)
    assert d.workers["p"] in procs
    d.pause("p")
    assert d.jobs["p"]["state"] == "paused" and signal.SIGSTOP in signals
    d.resume("p")
    assert d.jobs["p"]["state"] == "running" and signal.SIGCONT in signals
    procs[0].stdout.q.put("Transferred:   1 / 2 Bytes, 50%\n")
    procs[0].stdout.q.put(None)
    deadline = time.monotonic() + 3
    while d.jobs["p"]["state"] == "running" and time.monotonic() < deadline:
        time.sleep(0.01)
    assert d.jobs["p"]["state"] == "done"
    assert any(e.get("event") == "progress" and e["progress"] == 0.5 for e in events)
    assert d.jobs["p"]["nextRun"] > time.time()  # the repeat was scheduled again


def test_stop_terminates_the_worker(tmp_path, monkeypatch):
    mod = load_module()
    procs = []

    def popen(*args, **kw):
        p = FakeProc([])
        procs.append(p)
        return p

    monkeypatch.setattr(mod.subprocess, "Popen", popen)
    d = mod.Daemon(str(tmp_path / "state.json"))
    d.emit = lambda e: None
    d.jobs["p"] = dict(mod.DEFAULTS, id="p", remote="drive:P", local=str(tmp_path))
    d.start("p")
    deadline = time.monotonic() + 3
    while not d.workers.get("p") and time.monotonic() < deadline:
        time.sleep(0.01)
    d.stop("p")
    assert procs[0].terminated and d.jobs["p"]["state"] == "idle"
    assert d.jobs["p"]["nextRun"] == 0.0


# ---- systemd ---------------------------------------------------------------------


def test_service_follows_the_shell_and_restarts():
    assert "PartOf=shani-shell.service" in UNIT
    assert "After=shani-shell.service" in UNIT
    assert "Restart=on-failure" in UNIT
    assert "WantedBy=default.target" in UNIT
    assert "Type=simple" in UNIT
    assert "/usr/lib/shani-shell/cloudsync.py" in UNIT


# ---- QML -------------------------------------------------------------------------


def test_service_is_the_daemons_only_channel():
    assert SERVICE.startswith("pragma Singleton")
    assert "SHANI_CLOUDSYNC_TOOL" in SERVICE
    assert 'command: ["python3", root.tool]' in SERVICE
    assert "stdinEnabled: true" in SERVICE
    assert "stdout: SplitParser" in SERVICE
    for event in ("jobs", "job", "progress", "removed", "error", "notify"):
        assert 'e.event === "%s"' % event in SERVICE, event
    for fn in (
        "refresh",
        "add",
        "settings",
        "start",
        "stop",
        "pause",
        "resume",
        "remove",
    ):
        assert "function %s(" % fn in SERVICE, fn
    assert (
        'cmd: "start"' in SERVICE
        and 'cmd: "pause"' in SERVICE
        and 'cmd: "resume"' in SERVICE
    )
    assert 'cmd: "stop"' in SERVICE
    assert "notify-send" in SERVICE
    assert "cloud.py" in SERVICE  # the remotes picker, never a config write here


def test_panel_has_every_control_and_accessible_names():
    # a Ui-driven surface is bound to Ui.cloudSync, not hardcoded true
    assert "AppWindow {" in PANEL and "visible: Ui.cloudSync" in PANEL
    # appName is optional; a self-registering window may carry a title used by
    # the app launcher. Either form is valid — only require it not be duplicated.
    assert PANEL.count("appName:") <= 1
    assert not re.search(r"^\s*Ui\.", PANEL, re.M)  # no new Ui flag
    for text in (
        "No sync jobs yet",
        "Start %1",
        "Pause %1",
        "Resume %1",
        "Stop %1",
        "Remove %1",
        "Bandwidth limit",
        "Repeat interval",
        "Keep both",
        "If a file exists there already",
    ):
        assert text in PANEL, text
    assert "FolderPicker {" in PANEL
    assert "model: CloudSync.remotes" in PANEL
    assert "Accessible.role: Accessible.ProgressBar" in PANEL
    assert 'Accessible.name: Tr.t("Progress of %1")' in PANEL
    assert "row.modelData.file" in PANEL
    assert "(row.modelData.history || []).slice().reverse()" in PANEL
    assert "CloudSync.error" in PANEL and "!CloudSync.available" in PANEL
    assert "EmptyState {" in PANEL
    for icon in (
        "media-playback-start",
        "media-playback-pause",
        "media-playback-stop",
        "list-remove",
    ):
        assert 'icon: "%s"' % icon in PANEL, icon


node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")


def js_func(src, name):
    m = re.search(r"(?m)^[ \t]*function %s\(" % re.escape(name), src)
    assert m, name
    i = src.index("{", m.start())
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[m.start() : j + 1]
    raise AssertionError("unbalanced " + name)


PRELUDE = r"""
const Tr = { t: (s, ...a) => s.replace(/%1/, String(a[0] ?? '')) };
const CloudSync = { added: null, add: (...a) => { CloudSync.added = a; } };
const idField = { text: '' }, remoteField = { text: '' }, localPicker = { value: '' };
const bandwidthField = { text: '' }, intervalField = { text: '' };
const win = { notice: '', directionChoice: 'download', conflictChoice: 'rename' };
"""


def run_form(call, result="({notice:win.notice, added:CloudSync.added})"):
    parts = [js_func(PANEL, n) for n in ("add", "bytes")]
    prog = (
        PRELUDE
        + "\n"
        + "\n".join(parts)
        + "\nwin.add = add; win.bytes = bytes;\n"
        + call
        + "\nprocess.stdout.write(JSON.stringify("
        + result
        + "));\n"
    )
    r = subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


@node_mark
def test_panel_form_validates_before_sending():
    out = run_form(
        "idField.text='bad/name'; remoteField.text='drive:P'; localPicker.value='/tmp'; win.add();"
    )
    assert out["added"] is None and "name" in out["notice"]

    out = run_form(
        "idField.text='p'; remoteField.text='nodrive'; localPicker.value='/tmp'; win.add();"
    )
    assert out["added"] is None and "remote:path" in out["notice"]

    out = run_form(
        "idField.text='p'; remoteField.text='drive:P'; localPicker.value='relative'; win.add();"
    )
    assert out["added"] is None and "local folder" in out["notice"]

    out = run_form(
        "idField.text=' p '; remoteField.text=' drive:P '; localPicker.value='/tmp/Pics';"
        " win.directionChoice='upload'; win.conflictChoice='skip';"
        " bandwidthField.text='1M'; intervalField.text='3600'; win.add();"
    )
    assert out["added"] == ["p", "drive:P", "/tmp/Pics", "upload", "skip", "1M", 3600]
    assert out["notice"] == ""


@node_mark
def test_panel_formats_progress_bytes():
    out = run_form("", "[bytes(0), bytes(2048), bytes(2*1024*1024), bytes(1073741824)]")
    assert out == ["0 B", "2 KB", "2.0 MB", "1.0 GB"]


@pytest.mark.parametrize("text", (SERVICE, PANEL))
def test_new_qml_is_clean(text):
    assert text.endswith("\n")
    assert "\t" not in text
    assert "console.log" not in text
    assert re.search(r"^FloatingWindow \{", text, re.M) is None
