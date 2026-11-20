#!/usr/bin/env python3
"""copyjob — Files' copies and moves, the way TeraCopy does them. Run by
`files.py job`; one job per process, so a big copy never holds up anything else.

    files.py job <dest> <copy|move|auto> [--opts=JSON] <path>...
    files.py job - hash  --opts={"out": "x.sha256"} <path>...   checksums made
    files.py job - check <file.sha256|.md5|.sha1|.sha512>       checksums tested

Options ({"verify", "conflict", "pairs"}):
  verify     each file read back after it is written and compared with the hash
             taken of the source as it was read (BLAKE2) - a move removes a source
             only once its copy is proven whole
  conflict   what a name already there gets: rename (default - "name (2)"), skip,
             replace, older (replaced when the source is newer), differs (replaced
             when size or time differ). With anything but rename, folders merge.
             A replaced file goes to the trash (it can be put back), never deleted
  pairs      [[source, target], ...] instead of <path>s: Retry, for exactly the
             files that failed

What it says, one JSON line each: {"total", "items"} first; {"done", "total",
"file", "rate"} at most four times a second (rate: bytes a second, over the
last few seconds); {"paused": bool} when paused or resumed; {"phase": "verifying"};
and last the result: {"mode", "pairs": [[src, dst, how]], "failed": [{"path",
"target", "error"}], "skipped", "replaced", "verified", "cancelled"?, "error"?}.

SIGUSR1 pauses and resumes it; SIGTERM stops it (the file half-written is
removed, everything finished stays). A bad file does not stop the rest: it is
listed in "failed", and the job goes on. Each job is written down in
$XDG_STATE_HOME/shani-shell/copy-history.jsonl (Files > Copy history).
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import signal
import stat
import subprocess
import sys
import time


class Cancelled(Exception):
    pass


def free_name(directory, name):
    """name, or "name (2).ext", "name (3).ext" ... - the first not taken."""
    if not os.path.lexists(os.path.join(directory, name)):
        return os.path.join(directory, name)
    stem, ext = os.path.splitext(name)
    if stem.endswith(".tar"):
        stem, ext = stem[:-4], ".tar" + ext
    n = 2
    while os.path.lexists(os.path.join(directory, f"{stem} ({n}){ext}")):
        n += 1
    return os.path.join(directory, f"{stem} ({n}){ext}")


def history_file():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "shani-shell", "copy-history.jsonl")


def history(n=100):
    try:
        with open(history_file(), encoding="utf-8") as f:
            lines = f.readlines()[-n:]
    except OSError:
        return []
    out = []
    for line in reversed(lines):
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def _note_history(entry):
    p = history_file()
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
        # kept short: the last 500 jobs
        with open(p, encoding="utf-8") as f:
            lines = f.readlines()
        if len(lines) > 600:
            with open(p + ".new", "w", encoding="utf-8") as f:
                f.writelines(lines[-500:])
            os.replace(p + ".new", p)
    except OSError:
        pass


class Job:
    def __init__(self, out=sys.stdout, chunk=1 << 20, opts=None):
        self.out, self.chunk, self.opts = out, chunk, opts or {}
        self.cancel = False
        self.paused = False
        self.total = 0
        self.bytes = 0
        self.said = 0.0
        self.window = []                       # (time, bytes) for the rate
        self.delay = 0.0
        if os.environ.get("SHANI_FILES_JOB_DELAY_FILE"):
            try:
                self.delay = float(open(os.environ["SHANI_FILES_JOB_DELAY_FILE"]).read().strip() or 0)
            except (OSError, ValueError):
                self.delay = 0.0
        self.pairs, self.failed = [], []
        self.made, self.copied = [], []
        self.skipped = self.replaced = self.verified = 0
        signal.signal(signal.SIGTERM, lambda *_: setattr(self, "cancel", True))
        signal.signal(signal.SIGUSR1, lambda *_: self._toggle())

    # ---- saying how far it is ------------------------------------------------------
    def say(self, obj):
        self.out.write(json.dumps(obj) + "\n")
        self.out.flush()

    def _toggle(self):
        self.paused = not self.paused

    def tick(self, name, n):
        if self.delay:
            time.sleep(self.delay)
        self.bytes += n
        now = time.monotonic()
        self.window.append((now, self.bytes))
        while self.window and now - self.window[0][0] > 3:
            self.window.pop(0)
        if self.paused:
            self.say({"paused": True, "done": self.bytes, "total": self.total, "file": name})
            while self.paused and not self.cancel:
                time.sleep(0.2)
            self.window = [(time.monotonic(), self.bytes)]
            self.say({"paused": False})
        if now - self.said >= 0.25:
            self.said = now
            t0, b0 = self.window[0]
            rate = int((self.bytes - b0) / (now - t0)) if now - t0 > 0.2 else 0
            self.say({"done": self.bytes, "total": self.total, "file": name, "rate": rate})
        if self.cancel:
            raise Cancelled()

    # ---- one file -----------------------------------------------------------------
    def copy_file(self, src, dst):
        """src's bytes into dst (written beside it first, then renamed in: a reader
        never sees half a file under the real name); verified when asked. A name
        already there was settled by the caller (place())."""
        if os.path.islink(src):
            os.symlink(os.readlink(src), dst)
            return
        part = os.path.join(os.path.dirname(dst), ".%s.shani-part" % os.path.basename(dst))
        h = hashlib.blake2b(digest_size=32) if self.opts.get("verify") else None
        try:
            with open(src, "rb") as a, open(part, "xb") as b:
                while True:
                    buf = a.read(self.chunk)
                    if not buf:
                        break
                    b.write(buf)
                    if h:
                        h.update(buf)
                    self.tick(os.path.basename(src), len(buf))
                if h:
                    b.flush()
                    os.fsync(b.fileno())
            shutil.copystat(src, part, follow_symlinks=False)
            if h:
                self.say({"phase": "verifying", "file": os.path.basename(src)})
                if self._digest(part) != h.hexdigest():
                    raise OSError("the copy does not match the original (verify)")
                self.verified += 1
            if os.path.lexists(dst):
                self._to_trash(dst)              # replace: the old one can be put back
                self.replaced += 1
            os.rename(part, dst)
        except BaseException:
            if os.path.lexists(part):
                os.remove(part)                  # the half-written one only
            raise

    def _digest(self, p):
        h = hashlib.blake2b(digest_size=32)
        with open(p, "rb") as f:
            while chunk := f.read(self.chunk):
                h.update(chunk)
        return h.hexdigest()

    @staticmethod
    def _to_trash(p):
        r = subprocess.run(["gio", "trash", "--", p], capture_output=True, text=True)
        if r.returncode != 0:
            raise OSError((r.stderr.strip().splitlines() or ["the one there could not be moved to the trash"])[-1])

    # ---- the rule for a name already there ----------------------------------------
    def decide(self, src, dst):
        """"copy" (nothing there, or it is to be replaced), "skip", or "merge"."""
        if not os.path.lexists(dst):
            return "copy"
        rule = self.opts.get("conflict", "rename")
        if os.path.isdir(dst) and not os.path.islink(dst) and os.path.isdir(src) and not os.path.islink(src):
            return "merge"
        if os.path.isdir(dst) != os.path.isdir(src):
            return "skip"                        # a folder never replaces a file, nor the other way
        if rule == "skip":
            return "skip"
        if rule == "replace":
            return "copy"
        try:
            s, d = os.lstat(src), os.lstat(dst)
        except OSError:
            return "skip"
        if rule == "older":
            return "copy" if int(s.st_mtime) > int(d.st_mtime) else "skip"
        if rule == "differs":
            return "copy" if (s.st_size != d.st_size or int(s.st_mtime) != int(d.st_mtime)) else "skip"
        return "skip"

    # ---- a tree: each file on its own, a bad one listed and passed over ------------
    def copy_tree(self, src, dst):
        """Copies; what it made is in self.made (Stop takes exactly that back), the
        sources copied whole in self.copied (a move removes those once the item is
        done)."""
        if os.path.islink(src) or not os.path.isdir(src):
            what = self.decide(src, dst)
            if what == "skip":
                self.skipped += 1
                self.bytes += self._size(src)
                return
            existed = os.path.lexists(dst)
            try:
                self.copy_file(src, dst)
            except Cancelled:
                raise
            except OSError as e:
                self.failed.append({"path": src, "target": dst, "error": e.strerror or str(e)})
                return
            if not existed:
                self.made.append(dst)
            self.copied.append(src)
            return
        if not os.path.isdir(dst):
            try:
                os.mkdir(dst)
                self.made.append(dst)
            except OSError as e:
                self.failed.append({"path": src, "target": dst, "error": e.strerror or str(e)})
                return
        for e in sorted(os.scandir(src), key=lambda e: e.name):
            self.copy_tree(e.path, os.path.join(dst, e.name))
        try:
            shutil.copystat(src, dst, follow_symlinks=False)
        except OSError:
            pass
        self.copied.append(src)

    def take_back(self):
        """Stop: what this item made, newest first - its files, then its folders
        (emptied by then); nothing it did not make."""
        for p in reversed(self.made):
            try:
                if os.path.isdir(p) and not os.path.islink(p):
                    os.rmdir(p)
                else:
                    os.remove(p)
            except OSError:
                pass

    def finish_move(self):
        """A move across drives, once its item is copied: the sources copied whole
        removed - files first, then folders that are empty by then (one with a
        file that failed keeps it, and so stays)."""
        for p in self.copied:
            if os.path.islink(p) or not os.path.isdir(p):
                try:
                    os.remove(p)
                except OSError:
                    pass
        for p in sorted((p for p in self.copied if os.path.isdir(p) and not os.path.islink(p)), key=len, reverse=True):
            try:
                os.rmdir(p)
            except OSError:
                pass

    @staticmethod
    def _size(p):
        if os.path.islink(p) or not os.path.isdir(p):
            try:
                return os.lstat(p).st_size
            except OSError:
                return 0
        total = 0
        for r, _, files in os.walk(p):
            for n in files:
                try:
                    total += os.lstat(os.path.join(r, n)).st_size
                except OSError:
                    pass
        return total

    # ---- a copy or a move ---------------------------------------------------------
    def run(self, dest, mode, paths):
        started = time.time()
        dest = os.path.abspath(dest) if dest != "-" else dest
        explicit = self.opts.get("pairs")
        if explicit:
            work = [(os.path.abspath(s), os.path.abspath(t)) for s, t in explicit]
        else:
            work = [(os.path.abspath(p), None) for p in paths]

        def same_drive(p, d):
            try:
                return os.stat(os.path.dirname(p) or "/").st_dev == os.stat(d).st_dev
            except OSError:
                return False

        def moving(p, d):
            return mode == "move" or (mode == "auto" and same_drive(p, d))

        self.total = sum(self._size(p) for p, t in work
                         if not (moving(p, t and os.path.dirname(t) or dest) and same_drive(p, t and os.path.dirname(t) or dest)))
        self.say({"total": self.total, "items": len(work)})
        cancelled = False
        for p, target in work:
            d = os.path.dirname(target) if target else dest
            if d == p or d.startswith(p + os.sep):
                self.failed.append({"path": p, "target": d, "error": "a folder cannot go inside itself"})
                continue
            if not target and mode in ("move", "auto") and os.path.dirname(p) == dest:
                continue                                  # already here
            if not target:
                name = os.path.join(dest, os.path.basename(p))
                target = free_name(dest, os.path.basename(p)) if self.opts.get("conflict", "rename") == "rename" else name
            how = "moved" if moving(p, d) else "copied"
            try:
                if moving(p, d) and same_drive(p, d) and self.decide(p, target) == "copy" and not os.path.lexists(target):
                    os.rename(p, target)                  # same drive, nothing in the way: instant
                    self.pairs.append([p, target, how])
                    continue
                before = len(self.failed)
                self.made, self.copied = [], []
                self.copy_tree(p, target)
                if how == "moved":
                    self.finish_move()
                if len(self.failed) == before and os.path.lexists(target):
                    self.pairs.append([p, target, how])
                elif os.path.lexists(target):
                    self.pairs.append([p, target, how + "-partly"])
            except Cancelled:
                self.take_back()                          # the source is untouched: a move removes only at the end
                cancelled = True
                break
        result = {"mode": mode, "pairs": self.pairs, "failed": self.failed, "skipped": self.skipped,
                  "replaced": self.replaced, "verified": self.verified}
        if cancelled:
            result["cancelled"] = True
        if self.failed:
            result["error"] = self.failed[0]["error"] if len(self.failed) == 1 else \
                "%d could not be %s: %s" % (len(self.failed), "moved" if mode == "move" else "copied", self.failed[0]["error"])
        _note_history({"time": int(started), "seconds": round(time.time() - started, 1), "mode": mode, "dest": dest,
                       "items": len(work), "bytes": self.bytes, "done": len(self.pairs), "failed": len(self.failed),
                       "skipped": self.skipped, "replaced": self.replaced, "verified": self.verified,
                       "cancelled": cancelled, "names": [os.path.basename(p) for p, _ in work][:5]})
        self.say(result)
        return 0

    # ---- checksums: made (sha256sum's own format) and tested ----------------------
    def make_sums(self, out, paths):
        files = []
        for p in paths:
            p = os.path.abspath(p)
            if os.path.isdir(p):
                for r, dirs, names in os.walk(p):
                    dirs.sort()
                    files += [os.path.join(r, n) for n in sorted(names) if os.path.isfile(os.path.join(r, n))]
            elif os.path.isfile(p):
                files.append(p)
        out = os.path.abspath(out)
        base = os.path.dirname(out)
        files = [f for f in files if f != out]
        self.total = sum(os.path.getsize(f) for f in files)
        self.say({"total": self.total, "items": len(files)})
        lines = []
        try:
            for f in files:
                h = hashlib.sha256()
                with open(f, "rb") as fh:
                    while chunk := fh.read(self.chunk):
                        h.update(chunk)
                        self.tick(os.path.basename(f), len(chunk))
                lines.append("%s  %s\n" % (h.hexdigest(), os.path.relpath(f, base)))
        except Cancelled:
            self.say({"mode": "hash", "pairs": [], "cancelled": True})
            return 0
        target = free_name(base, os.path.basename(out))
        with open(target, "x", encoding="utf-8") as fh:
            fh.writelines(lines)
        self.say({"mode": "hash", "pairs": [[target, target, "made"]], "count": len(lines), "saved": target})
        return 0

    def check_sums(self, sums):
        alg = {"md5": "md5", "sha1": "sha1", "sha256": "sha256", "sha512": "sha512"}.get(sums.rsplit(".", 1)[-1].lower(), "")
        base = os.path.dirname(os.path.abspath(sums))
        entries = []
        with open(sums, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.startswith("#") or "  " not in line and " *" not in line:
                    continue
                digest, _, name = line.partition(" ")
                name = name.lstrip(" *")
                if not alg:
                    alg = {32: "md5", 40: "sha1", 64: "sha256", 128: "sha512"}.get(len(digest), "sha256")
                entries.append((digest.lower(), os.path.join(base, name)))
        self.total = sum(os.path.getsize(p) for _, p in entries if os.path.isfile(p))
        self.say({"total": self.total, "items": len(entries)})
        good, bad, missing = 0, [], []
        try:
            for digest, p in entries:
                if not os.path.isfile(p):
                    missing.append(p)
                    continue
                h = hashlib.new(alg)
                with open(p, "rb") as fh:
                    while chunk := fh.read(self.chunk):
                        h.update(chunk)
                        self.tick(os.path.basename(p), len(chunk))
                if h.hexdigest() == digest:
                    good += 1
                else:
                    bad.append(p)
        except Cancelled:
            self.say({"mode": "check", "pairs": [], "cancelled": True})
            return 0
        r = {"mode": "check", "pairs": [], "good": good, "bad": bad, "missing": missing}
        if bad or missing:
            r["error"] = "%d do not match, %d missing" % (len(bad), len(missing))
        self.say(r)
        return 0


def main(dest, mode, args, out=sys.stdout):
    opts = {}
    rest = []
    for a in args:
        if a.startswith("--opts="):
            try:
                opts = json.loads(a[7:]) or {}
            except ValueError:
                opts = {}
        else:
            rest.append(a)
    j = Job(out=out, opts=opts)
    if mode in ("hash", "check"):
        started = time.time()
        rc = j.make_sums(opts.get("out") or os.path.join(os.path.dirname(os.path.abspath(rest[0])), "checksums.sha256"), rest) \
            if mode == "hash" else j.check_sums(rest[0])
        _note_history({"time": int(started), "seconds": round(time.time() - started, 1), "mode": mode, "dest": "-",
                       "items": len(rest), "bytes": j.bytes, "done": len(rest), "failed": 0, "skipped": 0, "replaced": 0,
                       "verified": 0, "cancelled": j.cancel, "names": [os.path.basename(p.rstrip("/")) for p in rest][:5]})
        return rc
    return j.run(dest, mode, rest)
