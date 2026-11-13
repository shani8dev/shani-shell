#!/usr/bin/env python3
"""tidy — sort a folder (Downloads) into folders by what each file is, with an
undo; and read a file's words, for Chronoa to name it.

    tidy.py plan DIR          [{"from": path, "to": path, "group": "Pictures"}, ...]
    tidy.py apply DIR         do the plan; prints {"moved": n, "journal": file}
    tidy.py undo              put back what the last apply moved; {"restored": n}
    tidy.py text FILE         the words in it (a PDF's first pages, a picture's
                              text through tesseract, a text file's start), for naming

Sorting is by kind, not by guessing: pictures, videos, music, documents,
archives, installers (AppImages, packages, Flatpak refs, APKs) - each into a
folder of that name inside DIR. Nothing is ever written over (a name taken
gets " (2)"), only files directly in DIR move, hidden files and ones still
downloading (.part, .crdownload) stay. Every move is written to the journal
first, so `undo` can put back exactly those files, and only if nothing has
taken their old place since.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

GROUPS = {
    "Pictures": {"png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "heic", "heif", "tif", "tiff", "ico", "raw", "cr2", "nef"},
    "Videos": {"mp4", "mkv", "webm", "mov", "avi", "m4v", "mpg", "mpeg", "wmv", "flv", "3gp"},
    "Music": {"mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav", "wma", "aiff"},
    "Documents": {"pdf", "doc", "docx", "odt", "rtf", "txt", "md", "xls", "xlsx", "ods", "csv", "ppt", "pptx", "odp", "epub", "djvu"},
    "Archives": {"zip", "tar", "gz", "tgz", "xz", "txz", "bz2", "zst", "7z", "rar", "iso"},
    "Installers": {"appimage", "deb", "rpm", "flatpakref", "flatpak", "apk", "exe", "msi", "run", "pkg"},
}
UNFINISHED = {"part", "crdownload", "download", "tmp", "partial"}


def journal_file() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    return base / "shani-shell" / "tidy-journal.json"


def group_of(path: Path) -> str:
    ext = path.suffix.lower().lstrip(".")
    for group, exts in GROUPS.items():
        if ext in exts:
            return group
    return ""


def free(target: Path) -> Path:
    if not target.exists():
        return target
    n = 2
    while True:
        cand = target.with_name(f"{target.stem} ({n}){target.suffix}")
        if not cand.exists():
            return cand
        n += 1


def plan(folder: Path) -> list:
    out = []
    taken: set = set()
    for f in sorted(folder.iterdir(), key=lambda p: p.name.lower()):
        if not f.is_file() or f.is_symlink() or f.name.startswith(".") or f.suffix.lower().lstrip(".") in UNFINISHED:
            continue
        group = group_of(f)
        if not group:
            continue
        to = folder / group / f.name
        n = 2
        while to.exists() or str(to) in taken:
            to = folder / group / f"{f.stem} ({n}){f.suffix}"
            n += 1
        taken.add(str(to))
        out.append({"from": str(f), "to": str(to), "group": group})
    return out


def apply(folder: Path) -> dict:
    moves = plan(folder)
    done = []
    jf = journal_file()
    jf.parent.mkdir(parents=True, exist_ok=True)
    for m in moves:
        src, dst = Path(m["from"]), Path(m["to"])
        dst.parent.mkdir(exist_ok=True)
        if dst.exists():                       # taken since the plan was made: leave it
            continue
        shutil.move(str(src), str(dst))
        done.append(m)
        jf.write_text(json.dumps({"folder": str(folder), "moves": done}))
    return {"moved": len(done), "journal": str(jf)}


def undo() -> dict:
    jf = journal_file()
    try:
        data = json.loads(jf.read_text())
    except (OSError, ValueError):
        return {"restored": 0, "error": "nothing to undo"}
    restored, kept = 0, []
    for m in reversed(data.get("moves", [])):
        src, dst = Path(m["from"]), Path(m["to"])
        if dst.exists() and not src.exists():
            shutil.move(str(dst), str(src))
            restored += 1
        else:
            kept.append(m)
    folder = Path(data.get("folder", ""))
    for group in GROUPS:                       # the folders tidy made, when empty again
        d = folder / group
        try:
            d.rmdir()
        except OSError:
            pass
    if kept:
        jf.write_text(json.dumps({"folder": str(folder), "moves": kept}))
    else:
        jf.unlink(missing_ok=True)
    return {"restored": restored, "left": len(kept)}


def text_of(path: Path) -> str:
    """The words a person would use to name it: no more than ~3000 characters."""
    ext = path.suffix.lower().lstrip(".")
    try:
        if ext == "pdf":
            out = subprocess.run(["pdftotext", "-l", "2", "-q", str(path), "-"], capture_output=True, text=True, timeout=30).stdout
        elif group_of(path) == "Pictures":
            out = subprocess.run(["tesseract", str(path), "-", "--psm", "3"], capture_output=True, text=True, timeout=60).stdout
        else:
            with open(path, "rb") as f:
                raw = f.read(8000)
            if b"\0" in raw:
                return ""
            out = raw.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return " ".join(out.split())[:3000]


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "plan":
        print(json.dumps(plan(Path(argv[2]))))
        return 0
    if len(argv) >= 3 and argv[1] == "apply":
        print(json.dumps(apply(Path(argv[2]))))
        return 0
    if len(argv) >= 2 and argv[1] == "undo":
        print(json.dumps(undo()))
        return 0
    if len(argv) >= 3 and argv[1] == "text":
        print(text_of(Path(argv[2])))
        return 0
    print("usage: tidy.py plan DIR | apply DIR | undo | text FILE", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
