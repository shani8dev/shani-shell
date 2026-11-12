#!/usr/bin/env python3
"""cleanup — what takes room in the person's own space, and making it free.

    cleanup.py scan          {"trash": {...}, "thumbnails": {...}, "caches": [...],
                              "downloads": {...}, "flatpak": bool}
    cleanup.py clean trash             empty the Trash (gio trash --empty)
    cleanup.py clean thumbnails        the thumbnail cache (made again when needed)
    cleanup.py clean cache NAME        one folder of ~/.cache
    cleanup.py clean downloads         old downloads (DAYS, 90) into the Trash - not deleted
    cleanup.py clean flatpak           Flatpak runtimes no app uses any more

Only the person's own files: the system's (update images, old snapshots, the
journal) is Cassini's Maintenance page, which runs as root with a reason.

Some caches are not offered: the ones that cost a download to make again
(Chronoa's models, the shell's own music and map caches) - they are listed,
marked "keep", with why. A cache folder is named, never a path: a NAME with a
"/" or "..", or one that is not a folder of ~/.cache, is refused (exit 3).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache")
DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
TRASH = DATA / "Trash"
DAYS = int(os.environ.get("SHANI_CLEANUP_DOWNLOAD_DAYS", "90"))
# made again only by downloading, or the shell's own work: not offered
KEEP = {
    "shani-chronoa": "Chronoa's models: gigabytes to download again",
    "huggingface": "AI models: gigabytes to download again",
    "shani-shell": "the shell's music, map and photo caches",
    "flatpak": "Flatpak's own bookkeeping",
    "cliphist": "your clipboard history (clear it from the clipboard menu)",
}
GIO = os.environ.get("SHANI_GIO", "gio")


def size_of(path: Path) -> int:
    total = 0
    try:
        if path.is_symlink() or path.is_file():
            return path.lstat().st_size
    except OSError:
        return 0
    for dirpath, _dirs, files in os.walk(path, followlinks=False):
        for name in files:
            try:
                total += os.lstat(os.path.join(dirpath, name)).st_size
            except OSError:
                pass
    return total


def downloads_dir() -> Path:
    env = os.environ.get("XDG_DOWNLOAD_DIR")
    if env:
        return Path(env)
    try:
        for line in (Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "user-dirs.dirs").read_text().splitlines():
            if line.startswith("XDG_DOWNLOAD_DIR="):
                return Path(line.split("=", 1)[1].strip().strip('"').replace("$HOME", str(HOME)))
    except OSError:
        pass
    return HOME / "Downloads"


def old_downloads() -> list[Path]:
    root = downloads_dir()
    cutoff = time.time() - DAYS * 86400
    out = []
    try:
        for p in root.iterdir():
            try:
                st = p.lstat()
            except OSError:
                continue
            # the newer of changed and last opened: a file read last week is not old
            if max(st.st_mtime, st.st_atime) < cutoff and not p.name.startswith("."):
                out.append(p)
    except OSError:
        pass
    return sorted(out)


def scan() -> dict:
    trash_files = TRASH / "files"
    try:
        trash_count = sum(1 for _ in trash_files.iterdir())
    except OSError:
        trash_count = 0
    caches = []
    try:
        for p in sorted(CACHE.iterdir()):
            if not p.is_dir() or p.name == "thumbnails":
                continue
            caches.append({"name": p.name, "size": size_of(p), "keep": KEEP.get(p.name, "")})
    except OSError:
        pass
    caches.sort(key=lambda c: -c["size"])
    olds = old_downloads()
    return {
        "trash": {"size": size_of(TRASH), "count": trash_count},
        "thumbnails": {"size": size_of(CACHE / "thumbnails")},
        "caches": caches,
        "downloads": {"size": sum(size_of(p) for p in olds), "count": len(olds), "days": DAYS,
                      "folder": str(downloads_dir()), "items": [p.name for p in olds[:50]]},
        "flatpak": shutil.which("flatpak") is not None,
    }


def clean(what: str, arg: str = "") -> dict:
    if what == "trash":
        r = subprocess.run([GIO, "trash", "--empty"], capture_output=True, text=True)
        return {"ok": r.returncode == 0, "error": r.stderr.strip()}
    if what == "thumbnails":
        shutil.rmtree(CACHE / "thumbnails", ignore_errors=True)
        return {"ok": True}
    if what == "cache":
        if not arg or "/" in arg or arg in (".", "..") or arg == "thumbnails":
            raise ValueError(f"not a cache folder: {arg!r}")
        if arg in KEEP:
            raise ValueError(f"{arg} is kept: {KEEP[arg]}")
        target = CACHE / arg
        if not target.is_dir() or target.is_symlink():
            raise ValueError(f"no such cache folder: {arg}")
        shutil.rmtree(target, ignore_errors=True)
        return {"ok": not target.exists()}
    if what == "downloads":
        moved = 0
        for p in old_downloads():
            if subprocess.run([GIO, "trash", "--", str(p)], capture_output=True).returncode == 0:
                moved += 1
        return {"ok": True, "moved": moved}
    if what == "flatpak":
        if not shutil.which("flatpak"):
            raise ValueError("flatpak is not installed")
        r = subprocess.run(["flatpak", "uninstall", "--unused", "-y", "--noninteractive"], capture_output=True, text=True)
        return {"ok": r.returncode == 0, "error": r.stderr.strip()[-300:]}
    raise ValueError(f"nothing called {what!r} to clean")


def main(argv: list[str]) -> int:
    try:
        if len(argv) > 1 and argv[1] == "clean" and len(argv) > 2:
            print(json.dumps(clean(argv[2], argv[3] if len(argv) > 3 else "")))
            return 0
        if len(argv) == 1 or argv[1] == "scan":
            print(json.dumps(scan()))
            return 0
    except ValueError as exc:
        print(f"cleanup: {exc}", file=sys.stderr)
        return 3
    print("usage: cleanup.py scan | clean trash|thumbnails|downloads|flatpak | clean cache NAME", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
