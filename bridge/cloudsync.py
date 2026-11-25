#!/usr/bin/env python3
"""cloudsync — background folder sync with rclone, driven by Shani's Cloud sync panel.

One process lives for the session (data/systemd/shani-cloudsync.service), so a
job keeps running after its window is closed and a schedule can fire on time.
Like bridge/mpris-player.py it speaks JSON lines:

stdin, one object a line, from Services/CloudSync:
    {"cmd":"list"}
    {"cmd":"add","id":"photos","remote":"drive:Photos","local":"/home/me/Pictures",
     "direction":"download"|"upload","conflict":"rename"|"keepboth"|"skip",
     "bandwidth":"2M","interval":3600}      # interval 0 = by hand
    {"cmd":"start"|"stop"|"pause"|"resume"|"remove","id":"photos"}
    {"cmd":"settings","id":"photos","conflict":"skip","bandwidth":"1M","interval":0}
    {"cmd":"quit"}

stdout, one object a line, read by the service:
    {"event":"jobs","jobs":[…]}             # on start and after "list"
    {"event":"job","job":{…}}               # one job changed
    {"event":"progress","id":…,"file":…,"transferred":n,"total":n,"progress":0..1}
    {"event":"notify","level":"info"|"error","title":…,"message":…}

The job list (settings, status, last runs) is persisted under $XDG_STATE_HOME
so the daemon can be restarted without losing the jobs. Nothing here touches
rclone's configuration: cloud.py owns the remotes, this only copies files.
"""

from __future__ import annotations

import json
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _-]{0,40}$")
BW_RE = re.compile(r"^(?:\d+(?:\.\d+)?[kKmMgG]|off)$")
TRANSFERRED_RE = re.compile(
    r"Transferred:\s*([\d.,]+\s*[KMGT]?i?B)\s*/\s*([\d.,]+\s*[KMGT]?i?B)"
)
PERCENT_RE = re.compile(r"(\d+(?:\.\d+)?)%")
INFO_RE = re.compile(r"INFO\s*:\s*(.+?):\s*(?:Copied|Checking|Updated|Deleted)")

CONFLICTS = ("rename", "keepboth", "skip")
DEFAULTS = {
    "direction": "download",
    "conflict": "rename",
    "bandwidth": "",
    "interval": 0,
    "state": "idle",
    "progress": 0.0,
    "file": "",
    "transferred": 0,
    "total": 0,
    "retries": 0,
    "nextRun": 0.0,
    "lastRun": 0.0,
    "error": "",
    "history": [],
}
UNITS = {
    "B": 1,
    "KB": 1000,
    "MB": 1000**2,
    "GB": 1000**3,
    "TB": 1000**4,
    "KIB": 1024,
    "MIB": 1024**2,
    "GIB": 1024**3,
    "TIB": 1024**4,
}


def state_path() -> str:
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return os.path.join(base, "shani", "cloudsync.json")


def size(text: str) -> int:
    m = re.match(r"^([\d.,]+)\s*([KMGT]?i?B)$", text.strip(), re.I)
    if not m:
        return 0
    return int(float(m.group(1).replace(",", "")) * UNITS.get(m.group(2).upper(), 1))


def load(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
    except (OSError, ValueError):
        return {}
    if not isinstance(raw, dict):
        return {}
    jobs = {}
    for jid, item in (raw.get("jobs") or {}).items():
        if (
            not isinstance(jid, str)
            or not NAME_RE.match(jid)
            or not isinstance(item, dict)
        ):
            continue
        job = dict(DEFAULTS)
        job.update({k: v for k, v in item.items() if k in DEFAULTS})
        # a job left "running" by a killed daemon cannot still be running
        if job["state"] in ("running", "paused"):
            job["state"] = "idle"
        history = job["history"]
        job["history"] = (
            [h for h in history if isinstance(h, dict)][-25:]
            if isinstance(history, list)
            else []
        )
        jobs[jid] = job
    return jobs


def save(path: str, jobs: dict) -> None:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".cloudsync-")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"jobs": jobs}, f)
        os.replace(tmp, path)
    except OSError:
        pass


class Daemon:
    def __init__(self, path: str | None = None):
        self.path = path or state_path()
        self.jobs = load(self.path)
        self.lock = threading.Lock()
        self.out_lock = threading.Lock()
        self.workers: dict[str, subprocess.Popen] = {}
        self.stopping: set[str] = set()

    # ---- events -----------------------------------------------------------------
    def emit(self, obj: dict) -> None:
        # workers emit from their own threads; one line at a time, flushed,
        # so the panel sees a progress update without waiting for the loop
        with self.out_lock:
            sys.stdout.write(json.dumps(obj) + "\n")
            sys.stdout.flush()

    def note(self, title: str, message: str, level: str = "info") -> None:
        self.emit(
            {"event": "notify", "level": level, "title": title, "message": message}
        )

    def public(self, jid: str, job: dict) -> dict:
        return dict(job, id=jid)

    def snapshot(self) -> dict:
        with self.lock:
            jobs = [self.public(jid, dict(j)) for jid, j in self.jobs.items()]
        return {"event": "jobs", "jobs": jobs}

    def changed(self, jid: str) -> None:
        with self.lock:
            job = self.jobs.get(jid)
            if job is None:
                return
            job["history"] = (
                job["history"]
                + [
                    {
                        "time": time.time(),
                        "state": job["state"],
                        "error": job["error"],
                    }
                ]
            )[-25:]
            snap = self.public(jid, dict(job))
        self.emit({"event": "job", "job": snap})
        save(self.path, self.jobs)

    # ---- commands ----------------------------------------------------------------
    def handle(self, msg: dict) -> None:
        cmd = msg.get("cmd")
        jid = msg.get("id", "")
        if cmd == "list":
            self.emit(self.snapshot())
        elif cmd == "add":
            self.add(msg)
        elif cmd == "settings":
            self.settings(jid, msg)
        elif cmd in ("start", "stop", "pause", "resume", "remove"):
            with self.lock:
                exists = jid in self.jobs
            if not exists:
                self.fail(jid, "no sync job called %s" % jid)
                return
            getattr(self, cmd)(jid)
        else:
            self.fail(jid, "unknown command")

    def fail(self, jid: str, error: str) -> None:
        self.emit({"event": "error", "id": jid, "error": error})

    def add(self, msg: dict) -> None:
        jid = msg.get("id", "")
        remote, local = msg.get("remote", ""), msg.get("local", "")
        direction, conflict = (
            msg.get("direction", "download"),
            msg.get("conflict", "rename"),
        )
        bw, interval = str(msg.get("bandwidth", "") or ""), msg.get("interval", 0)
        if not isinstance(jid, str) or not NAME_RE.match(jid):
            return self.fail(jid, "a name of letters, digits, spaces, - and _")
        with self.lock:
            if jid in self.jobs:
                return self.fail(jid, "%s is there already" % jid)
        if ":" not in remote or remote.endswith(":"):
            return self.fail(jid, "the remote is remote:path, e.g. drive:Photos")
        if not isinstance(local, str) or not os.path.isabs(local):
            return self.fail(jid, "the local folder needs an absolute path")
        if direction not in ("download", "upload"):
            return self.fail(jid, "the direction is download or upload")
        if conflict not in CONFLICTS:
            return self.fail(jid, "not a conflict policy this knows")
        if bw and not BW_RE.match(bw):
            return self.fail(jid, "the bandwidth limit is like 2M, or off")
        try:
            interval = max(0, int(interval))
        except (TypeError, ValueError):
            return self.fail(jid, "the interval is a number of seconds")
        job = dict(
            DEFAULTS,
            id=jid,
            remote=remote,
            local=local,
            direction=direction,
            conflict=conflict,
            bandwidth=bw,
            interval=interval,
        )
        with self.lock:
            self.jobs[jid] = job
        self.changed(jid)
        self.note(
            "Cloud sync added",
            "%s → %s" % (jid, local if direction == "download" else remote),
        )

    def settings(self, jid: str, msg: dict) -> None:
        with self.lock:
            job = self.jobs.get(jid)
            if job is None:
                return self.fail(jid, "no sync job called %s" % jid)
            changes = {
                k: msg[k] for k in ("conflict", "bandwidth", "interval") if k in msg
            }
            conflict = changes.get("conflict", job["conflict"])
            bw = str(changes.get("bandwidth", job["bandwidth"]) or "")
            if conflict not in CONFLICTS:
                return self.fail(jid, "not a conflict policy this knows")
            if bw and not BW_RE.match(bw):
                return self.fail(jid, "the bandwidth limit is like 2M, or off")
            try:
                interval = max(0, int(changes.get("interval", job["interval"])))
            except (TypeError, ValueError):
                return self.fail(jid, "the interval is a number of seconds")
            job.update(conflict=conflict, bandwidth=bw, interval=interval, error="")
            if interval and job["state"] in ("idle", "done", "error"):
                job["nextRun"] = time.time() + interval
        self.changed(jid)

    def start(self, jid: str) -> None:
        with self.lock:
            job = self.jobs.get(jid)
            if job is None or job["state"] in ("running", "paused"):
                return
            self.stopping.discard(jid)
            job["state"] = "running"
            job["error"] = ""
            job["progress"] = 0.0
            job["file"] = ""
        self.changed(jid)
        threading.Thread(target=self._run, args=(jid,), daemon=True).start()

    def stop(self, jid: str) -> None:
        with self.lock:
            job = self.jobs.get(jid)
            if job is None:
                return
            self.stopping.add(jid)
            job["state"] = "idle"
            job["nextRun"] = 0.0
            job["progress"] = 0.0
            job["file"] = ""
            proc = self.workers.get(jid)
        if proc:
            self._signal(proc, signal.SIGCONT)
            proc.terminate()
        self.changed(jid)

    def pause(self, jid: str) -> None:
        with self.lock:
            job = self.jobs.get(jid)
            proc = self.workers.get(jid)
            if job is None or job["state"] != "running":
                return
            job["state"] = "paused"
        if proc:
            self._signal(proc, signal.SIGSTOP)
        self.changed(jid)

    def resume(self, jid: str) -> None:
        with self.lock:
            job = self.jobs.get(jid)
            proc = self.workers.get(jid)
            if job is None or job["state"] != "paused":
                return
            job["state"] = "running"
        if proc:
            self._signal(proc, signal.SIGCONT)
        self.changed(jid)

    def remove(self, jid: str) -> None:
        self.stop(jid)
        with self.lock:
            self.jobs.pop(jid, None)
        save(self.path, self.jobs)
        self.emit({"event": "removed", "id": jid})

    @staticmethod
    def _signal(proc, sig) -> None:
        try:
            proc.send_signal(sig)
        except (OSError, ProcessLookupError):
            pass

    # ---- the copy ----------------------------------------------------------------
    @staticmethod
    def endpoints(job: dict) -> tuple[str, str]:
        remote = job["remote"] + ("" if job["remote"].endswith(":") else "") + "/"
        local = job["local"].rstrip("/") + "/"
        return (remote, local) if job["direction"] == "download" else (local, remote)

    def args(self, job: dict) -> list[str]:
        src, dst = self.endpoints(job)
        args = [
            shutil.which("rclone") or "rclone",
            "copy",
            src,
            dst,
            "--progress",
            "--stats",
            "1s",
        ]
        if job["bandwidth"] and job["bandwidth"] != "off":
            args.append("--bwlimit=" + str(job["bandwidth"]))
        if job["conflict"] == "skip":
            args.append("--ignore-existing")
        elif job["conflict"] == "rename":
            args.append("--suffix=-conflict")
        else:  # keep both: the overwritten copy is kept in a backup folder
            args += ["--backup-dir", dst + ".cloudsync-conflicts"]
        return args

    def _run(self, jid: str) -> None:
        with self.lock:
            job = self.jobs.get(jid)
            if job is None:
                return
            args, interval = self.args(job), job["interval"]
        self.note("Cloud sync started", "%s is copying" % jid)
        code, error = 0, ""
        try:
            proc = subprocess.Popen(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            with self.lock:
                self.workers[jid] = proc
            for line in proc.stdout:
                m = INFO_RE.search(line)
                if m:
                    with self.lock:
                        job["file"] = m.group(1).strip()
                t = TRANSFERRED_RE.search(line)
                p = PERCENT_RE.search(line)
                if t or p:
                    with self.lock:
                        job["transferred"] = (
                            size(t.group(1)) if t else job["transferred"]
                        )
                        job["total"] = size(t.group(2)) if t else job["total"]
                        job["progress"] = (
                            min(1.0, max(0.0, float(p.group(1)) / 100))
                            if p
                            else job["progress"]
                        )
                        snap = self.public(jid, dict(job))
                    self.emit(
                        {
                            "event": "progress",
                            "id": jid,
                            "file": snap["file"],
                            "transferred": snap["transferred"],
                            "total": snap["total"],
                            "progress": snap["progress"],
                        }
                    )
            code = proc.wait()
            if code != 0:
                error = "rclone stopped with an error"
        except OSError as e:
            code, error = 127, str(e)
        except Exception as e:  # a worker must never die without a state change
            code, error = 1, str(e)
        finally:
            with self.lock:
                self.workers.pop(jid, None)
        with self.lock:
            job = self.jobs.get(jid)
            if job is None or jid in self.stopping:
                return
            job["lastRun"] = time.time()
            if code == 0:
                job["state"] = "done"
                job["error"] = ""
                job["retries"] = 0
                job["progress"] = 1.0
                job["nextRun"] = time.time() + interval if interval else 0.0
            else:
                job["state"] = "error"
                job["error"] = error
                job["retries"] += 1
                job["progress"] = 0.0
                # retry with backoff: 5s, 10s, 20s … capped at 5 minutes
                job["nextRun"] = time.time() + min(300, 5 * 2 ** (job["retries"] - 1))
        self.changed(jid)
        if code == 0:
            self.note("Cloud sync finished", "%s is up to date" % jid)
        else:
            self.note("Cloud sync failed", "%s: %s" % (jid, error), "error")

    # ---- main loop ---------------------------------------------------------------
    def tick(self) -> None:
        now = time.time()
        with self.lock:
            due = [
                jid
                for jid, job in self.jobs.items()
                if job["nextRun"]
                and now >= job["nextRun"]
                and job["state"] not in ("running", "paused")
            ]
            for jid in due:
                self.jobs[jid]["nextRun"] = 0.0
        for jid in due:
            self.start(jid)

    def run(self) -> int:
        self.emit(self.snapshot())
        # Read raw bytes: select() watches the fd, while readline() would buffer
        # several lines at once and leave the rest unread until more arrives.
        buf, quitting = b"", False
        fd = sys.stdin.fileno()
        while not quitting:
            self.tick()
            with self.lock:
                waits = [j["nextRun"] for j in self.jobs.values() if j["nextRun"]]
            timeout = max(0.1, min(1.0, min(waits) - time.time())) if waits else 1.0
            try:
                ready, _, _ = select.select([fd], [], [], timeout)
            except (OSError, ValueError):
                break
            if ready:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    try:
                        msg = json.loads(raw)
                    except ValueError:
                        continue
                    if not isinstance(msg, dict):
                        continue
                    if msg.get("cmd") == "quit":
                        quitting = True
                        break
                    self.handle(msg)
        for jid in list(self.workers):
            self.stop(jid)
        save(self.path, self.jobs)
        return 0


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        print(
            "cloudsync is a session daemon; it reads JSON lines on stdin",
            file=sys.stderr,
        )
        return 2
    return Daemon().run()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
