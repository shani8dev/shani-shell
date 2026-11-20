#!/usr/bin/env python3
"""dupes — what to clear out of a folder: its biggest files, and files that are
the same as another (the cleaner of ES File Explorer and its like).

    dupes.py big <dir>       [{"path", "size", "mtime"}] the 200 biggest files
    dupes.py dupes <dir>     [{"size", "paths": [...oldest first]}] groups of files
                             with the same bytes, the most space wasted first

Not looked in: hidden folders (apps' own data - clearing those breaks apps),
caches and build output, other drives mounted inside. Files of the same size are
compared by their first 64 KB, then whole (BLAKE2) - so two files are only called
the same when every byte is. Empty files are not duplicates of anything. Nothing
is deleted here: Disk Usage marks, the person reviews, gio trash moves.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys

SKIP = {"node_modules", "__pycache__", "target", "build", "dist", "venv", ".venv", "site-packages"}


def files(root: str):
    dev = os.stat(root).st_dev
    for d, dirs, names in os.walk(root):
        keep = []
        for x in dirs:
            if x.startswith(".") or x in SKIP:
                continue
            try:
                if os.stat(os.path.join(d, x), follow_symlinks=False).st_dev != dev:
                    continue                           # another drive mounted here
            except OSError:
                continue
            keep.append(x)
        dirs[:] = keep
        for n in names:
            if n.startswith("."):
                continue
            p = os.path.join(d, n)
            try:
                st = os.lstat(p)
            except OSError:
                continue
            if os.path.stat.S_ISREG(st.st_mode):
                yield p, st


def biggest(root: str, n: int = 200) -> list[dict]:
    import heapq
    top = heapq.nlargest(n, ((st.st_size, p, st.st_mtime) for p, st in files(root)))
    return [{"path": p, "size": s, "mtime": int(m * 1000)} for s, p, m in top]


def _digest(p: str, limit: int = 0) -> str | None:
    h = hashlib.blake2b(digest_size=20)
    try:
        with open(p, "rb") as f:
            if limit:
                h.update(f.read(limit))
            else:
                while chunk := f.read(1 << 20):
                    h.update(chunk)
    except OSError:
        return None
    return h.hexdigest()


def duplicates(root: str, groups_max: int = 200) -> list[dict]:
    by_size: dict[int, list] = {}
    seen_inodes = set()
    for p, st in files(root):
        if st.st_size == 0 or (st.st_dev, st.st_ino) in seen_inodes:
            continue                                   # empty, or a hard link to one seen
        seen_inodes.add((st.st_dev, st.st_ino))
        by_size.setdefault(st.st_size, []).append((p, st.st_mtime))
    out = []
    for size, ps in by_size.items():
        if len(ps) < 2:
            continue
        for stage in (65536, 0):                       # the first 64 KB, then all of it
            if stage and size <= stage and len(ps) > 1:
                continue                               # small: the whole file is the first pass
            buckets: dict[str, list] = {}
            for p, m in ps:
                k = _digest(p, stage)
                if k:
                    buckets.setdefault(k, []).append((p, m))
            groups = [g for g in buckets.values() if len(g) > 1]
            if stage:
                ps = [x for g in groups for x in g]
                if not ps:
                    break
                continue
            for g in groups:
                g.sort(key=lambda x: x[1])
                out.append({"size": size, "paths": [p for p, _ in g]})
    out.sort(key=lambda g: -g["size"] * (len(g["paths"]) - 1))
    return out[:groups_max]


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[1] in ("big", "dupes") and os.path.isdir(argv[2]):
        print(json.dumps(biggest(argv[2]) if argv[1] == "big" else duplicates(argv[2])))
        return 0
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
