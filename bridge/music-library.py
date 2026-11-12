#!/usr/bin/env python3
"""music-library — the songs in ~/Music, by artist and album, as JSON.

    music-library.py videos [DIR]   every video under DIR (~/Videos, or XDG_VIDEOS_DIR):
        {"videos": [{"path", "title", "folder", "duration", "thumb", "time"}], "scanned": n, "read": n}
        newest first; "thumb" is a frame from a tenth of the way in, made once
        with ffmpeg into the cache ("" when it could not be made)
    music-library.py scan [DIR]     every song under DIR (~/Music, or XDG_MUSIC_DIR):
        {"songs": [{"path", "title", "artist", "album", "albumArtist", "track",
                    "disc", "year", "duration", "cover"}], "scanned": n, "read": n}

Tags come from ffprobe (ffmpeg is in the image), read only for a file that is
new or changed since the last scan: the answers are kept in
~/.cache/shani-shell/music/library.json by path, size and mtime, so a second
scan of a big library reads nothing. A song without tags is named by its file
and its folders (Artist/Album/01 Title.flac, the usual layout).

The cover is the album folder's own picture (cover.jpg, folder.png, …) or the
picture inside the first song that has one, taken out once with ffmpeg into
the cache; "cover" is "" when there is none.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

AUDIO = {".mp3", ".flac", ".ogg", ".oga", ".opus", ".m4a", ".aac", ".wav", ".wma", ".aiff", ".aif", ".mka", ".ape", ".wv"}
COVER_NAMES = ("cover", "folder", "front", "album", "albumart")
COVER_EXT = (".jpg", ".jpeg", ".png", ".webp")
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "shani-shell" / "music"
FFPROBE = os.environ.get("SHANI_FFPROBE", "ffprobe")
FFMPEG = os.environ.get("SHANI_FFMPEG", "ffmpeg")


VIDEO = {".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".mpg", ".mpeg", ".ogv", ".wmv", ".flv", ".3gp", ".ts"}


def user_dir(kind: str, fallback: str) -> Path:
    env = os.environ.get(f"XDG_{kind}_DIR")
    if env:
        return Path(env)
    dirs = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "user-dirs.dirs"
    try:
        for line in dirs.read_text().splitlines():
            m = re.match(rf'XDG_{kind}_DIR="(.*)"', line.strip())
            if m:
                return Path(m.group(1).replace("$HOME", str(Path.home())))
    except OSError:
        pass
    return Path.home() / fallback


def music_dir() -> Path:
    return user_dir("MUSIC", "Music")


def number(v) -> int:
    m = re.match(r"\s*(\d+)", str(v or ""))
    return int(m.group(1)) if m else 0


def probe(path: Path) -> dict:
    try:
        out = subprocess.run([FFPROBE, "-v", "error", "-show_entries", "format=duration:format_tags:stream=codec_type:stream_tags:stream_disposition=attached_pic",
                              "-of", "json", str(path)], capture_output=True, text=True, timeout=20).stdout
        data = json.loads(out or "{}")
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        data = {}
    fmt = data.get("format", {})
    # Ogg and Opus keep their tags on the audio stream, MP3 and FLAC on the container
    tags = {}
    for st in data.get("streams", []):
        if st.get("codec_type") == "audio":
            tags.update({k.lower(): v for k, v in (st.get("tags") or {}).items()})
    tags.update({k.lower(): v for k, v in (fmt.get("tags") or {}).items()})
    has_pic = any(s.get("codec_type") == "video" and (s.get("disposition") or {}).get("attached_pic") == 1 for s in data.get("streams", []))
    # the usual layout, for a song without tags: Artist/Album/01 - Title.ext
    parts = path.parts
    stem = re.sub(r"^\d+\s*[-._ ]\s*", "", path.stem)
    return {
        "title": tags.get("title") or stem,
        "artist": tags.get("artist") or (parts[-3] if len(parts) >= 3 else "") or "Unknown artist",
        "album": tags.get("album") or (parts[-2] if len(parts) >= 2 else "") or "Unknown album",
        "albumArtist": tags.get("album_artist") or tags.get("albumartist") or "",
        "track": number(tags.get("track") or re.match(r"^(\d+)", path.stem) and path.stem),
        "disc": number(tags.get("disc")),
        "year": number(tags.get("date") or tags.get("year")),
        "duration": round(float(fmt.get("duration") or 0), 1),
        "embedded": has_pic,
    }


def folder_cover(folder: Path) -> str:
    try:
        names = {p.name.lower(): p for p in folder.iterdir() if p.is_file()}
    except OSError:
        return ""
    for base in COVER_NAMES:
        for ext in COVER_EXT:
            if base + ext in names:
                return str(names[base + ext])
    pictures = sorted(p for n, p in names.items() if n.endswith(COVER_EXT))
    return str(pictures[0]) if pictures else ""


def embedded_cover(song: Path) -> str:
    out = CACHE / "covers" / (hashlib.sha1(str(song.parent).encode()).hexdigest() + ".jpg")
    if out.exists() and out.stat().st_size > 0:
        return str(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run([FFMPEG, "-v", "error", "-y", "-i", str(song), "-an", "-frames:v", "1", "-vf", "scale=512:-1", str(out)],
                       capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return str(out) if out.exists() and out.stat().st_size > 0 else ""


def scan(root: Path) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    store = CACHE / "library.json"
    try:
        known = json.loads(store.read_text())
    except (OSError, json.JSONDecodeError):
        known = {}
    files = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if Path(name).suffix.lower() in AUDIO:
                files.append(Path(dirpath) / name)
    keyed = {}
    todo = []
    for f in files:
        try:
            st = f.stat()
        except OSError:
            continue
        key = f"{st.st_size}:{int(st.st_mtime)}"
        old = known.get(str(f))
        if old and old.get("key") == key:
            keyed[str(f)] = old
        else:
            todo.append((f, key))
    with ThreadPoolExecutor(max_workers=min(8, (os.cpu_count() or 2))) as pool:
        for (f, key), info in zip(todo, pool.map(lambda fk: probe(fk[0]), todo)):
            keyed[str(f)] = dict(info, key=key)
    # covers: one per album folder
    covers = {}
    for path, info in keyed.items():
        folder = str(Path(path).parent)
        if folder in covers and covers[folder]:
            continue
        cover = folder_cover(Path(folder))
        if not cover and info.get("embedded"):
            cover = embedded_cover(Path(path))
        covers[folder] = cover
    tmp = store.with_suffix(".tmp")
    tmp.write_text(json.dumps(keyed))
    tmp.replace(store)
    songs = []
    for path, info in keyed.items():
        song = {k: v for k, v in info.items() if k not in ("key", "embedded")}
        song["path"] = path
        song["cover"] = covers.get(str(Path(path).parent), "")
        songs.append(song)
    songs.sort(key=lambda s: ((s["albumArtist"] or s["artist"]).lower(), s["album"].lower(), s["disc"], s["track"], s["title"].lower()))
    return {"songs": songs, "scanned": len(files), "read": len(todo)}


def video_info(path: Path) -> dict:
    try:
        out = subprocess.run([FFPROBE, "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)],
                             capture_output=True, text=True, timeout=20).stdout
        duration = float(json.loads(out or "{}").get("format", {}).get("duration") or 0)
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError, ValueError):
        duration = 0.0
    thumb = CACHE / "thumbs" / (hashlib.sha1(str(path).encode()).hexdigest() + ".jpg")
    thumb.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run([FFMPEG, "-v", "error", "-y", "-ss", str(round(duration * 0.1, 1)), "-i", str(path), "-frames:v", "1",
                        "-vf", "scale=480:-2", str(thumb)], capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return {"duration": round(duration, 1), "thumb": str(thumb) if thumb.exists() and thumb.stat().st_size > 0 else ""}


def scan_videos(root: Path) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    store = CACHE / "videos.json"
    try:
        known = json.loads(store.read_text())
    except (OSError, json.JSONDecodeError):
        known = {}
    found, todo = {}, []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            f = Path(dirpath) / name
            if f.suffix.lower() not in VIDEO:
                continue
            try:
                st = f.stat()
            except OSError:
                continue
            key = f"{st.st_size}:{int(st.st_mtime)}"
            old = known.get(str(f))
            if old and old.get("key") == key and (not old.get("thumb") or Path(old["thumb"]).exists()):
                found[str(f)] = old
            else:
                todo.append((f, key, st.st_mtime))
    with ThreadPoolExecutor(max_workers=min(4, (os.cpu_count() or 2))) as pool:
        for (f, key, mtime), info in zip(todo, pool.map(lambda t: video_info(t[0]), todo)):
            found[str(f)] = dict(info, key=key, time=int(mtime))
    tmp = store.with_suffix(".tmp")
    tmp.write_text(json.dumps(found))
    tmp.replace(store)
    videos = []
    for path, info in found.items():
        p = Path(path)
        folder = p.parent.name if p.parent != root else ""
        videos.append({"path": path, "title": re.sub(r"[._]+", " ", p.stem).strip(), "folder": folder,
                       "duration": info.get("duration", 0), "thumb": info.get("thumb", ""), "time": info.get("time", 0)})
    videos.sort(key=lambda v: -v["time"])
    return {"videos": videos, "scanned": len(found), "read": len(todo)}


def main(argv: list[str]) -> int:
    if len(argv) > 1 and argv[1] == "videos":
        root = Path(argv[2]).expanduser() if len(argv) > 2 else user_dir("VIDEOS", "Videos")
        print(json.dumps(scan_videos(root) if root.is_dir() else {"videos": [], "scanned": 0, "read": 0}))
        return 0
    if len(argv) < 2 or argv[1] != "scan":
        print("usage: music-library.py scan [DIR] | videos [DIR]", file=sys.stderr)
        return 3
    root = Path(argv[2]).expanduser() if len(argv) > 2 else music_dir()
    print(json.dumps(scan(root) if root.is_dir() else {"songs": [], "scanned": 0, "read": 0}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
