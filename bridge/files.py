#!/usr/bin/env python3
"""files — the file manager's backend: list a directory, watch it, and change it.

  files.py list <path> [--hidden] [--sort name|size|mtime] [--desc]
                    [--filter ext,ext] [--limit N] [--offset N]
  files.py watch <path>            # one JSON object per change, until killed
  files.py stat <path>
  files.py mkdir <path>
  files.py rename <path> <name>
  files.py trash <path> [<path>...]
  files.py places                  # home, the XDG folders, the mounted drives, bookmarks
  files.py paste <dest> copy|move <path>...   # into dest, never over anything: "name (2)"
  files.py move-pairs '<json [[from, to], ...]>'   # undo: each moved back, never over anything
  files.py trash-list              # what is in the trash, and where each came from
  files.py restore <name>...       # out of the trash, back where it came from
  files.py empty-trash [<name>...] # for good: those, or everything
  files.py search <dir> <words>    # in that folder and every folder under it, by name
  files.py props <path>...         # size (folders counted through), dates, owner, rights
  files.py batch-rename <pattern> <path>...   # "Holiday #" -> Holiday 1.jpg, Holiday 2.jpg ...
  files.py bookmark-add <path> | bookmark-remove <path>   # GTK's bookmarks file

Every command answers one JSON object on stdout (`watch` answers one per
change). The shell's Files service reads them with a line splitter; nothing
else is expected of it.

The directory listing is one os.scandir pass: the name, whether it is a
directory, its size and its mtime (milliseconds), and whether it is an
image (so the grid can show it). Sorting is natural by name (file2 before
file10), by size or by mtime, always with the folders first unless asked
otherwise. `--filter` keeps only the extensions given (with or without the
dot), so a picker for pictures does not list everything.

`watch` uses inotify and re-lists the directory on every change, so the
model is replaced wholesale rather than patched - a rename or a delete
cannot leave a stale row behind. Where inotify is not available it falls
back to comparing a snapshot every second.

Nothing is deleted by `trash`: the file goes to the desktop trash - the
freedesktop one in ~/.local/share/Trash, with the .trashinfo that says where it
came from, so `restore` and an undo put it back exactly; a file on another drive
goes through `gio trash` (that drive's own trash). Every command that changes
files answers the moves it made ("pairs"), which is what the shell's undo replays
backwards.
"""
import ctypes
import json
import mimetypes
import os
import re
import shutil
import stat as stat_mod
import subprocess
import sys
import time
import urllib.parse

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".avif", ".heic", ".heif", ".tif", ".tiff"}

# ---- listing ----------------------------------------------------------------

def entry_of(name, path, st, is_dir):
    ext = os.path.splitext(name)[1].lower()
    return {
        "name": name,
        "path": path,
        "isDir": is_dir,
        "size": 0 if is_dir else int(st.st_size),
        "mtime": int(st.st_mtime * 1000),
        "ext": ext,
        "image": ext in IMAGE_EXTS,
    }


RECENT = "recent:"


def recent_files():
    """The files the person opened lately, newest first: GTK's recently-used.xbel,
    which GTK and Qt apps (and the shell's own) write. Only what is still there."""
    import xml.etree.ElementTree as ET
    from urllib.parse import unquote, urlparse
    xbel = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "recently-used.xbel")
    try:
        root = ET.parse(xbel).getroot()
    except (OSError, ET.ParseError):
        return []
    seen, out = set(), []
    for bm in root.iter("bookmark"):
        href = bm.get("href", "")
        if not href.startswith("file://"):
            continue
        path = unquote(urlparse(href).path)
        if path in seen:
            continue
        seen.add(path)
        try:
            st = os.stat(path)
        except OSError:
            continue
        out.append((bm.get("visited") or bm.get("modified") or "", entry_of(os.path.basename(path), path, st, os.path.isdir(path))))
    out.sort(key=lambda x: x[0], reverse=True)
    return [e for _, e in out[:200]]


SEARCH = "search:"   # "search:<words>\t<folder>": the folder and every folder under it


def listdir(path, hidden=False, sort_key="name", desc=False, filters=(), limit=0, offset=0):
    if path.startswith(SEARCH):
        words, _, root = path[len(SEARCH):].partition("\t")
        found = search(root or os.path.expanduser("~"), words, hidden)
        out = sort_entries(found["entries"], sort_key, desc, filters, limit, offset) if sort_key != "name" else {"entries": found["entries"], "total": len(found["entries"])}
        out["truncated"] = found["truncated"]
        return out
    if path == RECENT:
        entries = recent_files()
        # newest first unless a sort was asked for
        return sort_entries(entries, sort_key, desc, filters, limit, offset) if sort_key != "name" else {"entries": entries, "total": len(entries)}
    with os.scandir(path) as it:
        entries = []
        for de in it:
            if not hidden and de.name.startswith("."):
                continue
            try:
                st = de.stat(follow_symlinks=False)
            except OSError:
                continue
            is_dir = de.is_dir(follow_symlinks=True)
            if is_dir and de.is_symlink():
                # a link to a folder is a folder to walk into
                try:
                    st = de.stat(follow_symlinks=True)
                except OSError:
                    pass
            entries.append(entry_of(de.name, de.path, st, is_dir))
    return sort_entries(entries, sort_key, desc, filters, limit, offset)


def sort_entries(entries, sort_key="name", desc=False, filters=(), limit=0, offset=0):
    if filters:
        wanted = {f.lower() if f.startswith(".") else "." + f.lower() for f in filters}
        entries = [e for e in entries if e["isDir"] or e["ext"] in wanted]
    if sort_key == "size":
        entries.sort(key=lambda e: (not e["isDir"], e["size"], e["name"].lower()))
    elif sort_key == "mtime":
        entries.sort(key=lambda e: (not e["isDir"], -e["mtime"], e["name"].lower()))
    else:
        entries.sort(key=lambda e: (not e["isDir"], natural_key(e["name"])))
    if desc:
        # folders stay first, but inside each group the order flips
        entries = [e for e in entries if e["isDir"]] + [e for e in entries if not e["isDir"]][::-1]
    total = len(entries)
    if offset:
        entries = entries[offset:]
    if limit:
        entries = entries[:limit]
    return {"entries": entries, "total": total}


def natural_key(name):
    """file2 before file10: the digit runs compare as numbers."""
    return [int(p) if p.isdigit() else p.lower() for p in re.split(r"(\d+)", name)]


def stat_path(path):
    try:
        st = os.stat(path)
    except OSError as e:
        return {"error": e.strerror or str(e), "code": errno_name(e.errno)}
    is_dir = os.path.isdir(path)
    return {"entry": entry_of(os.path.basename(path.rstrip("/")) or path, path, st, is_dir)}


def errno_name(code):
    import errno
    for name in dir(errno):
        if name.startswith("E") and getattr(errno, name) == code:
            return name
    return ""


# ---- watching ----------------------------------------------------------------

IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MODIFY = 0x00000002
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
WATCH_MASK = (IN_ATTRIB | IN_CLOSE_WRITE | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO
              | IN_CREATE | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF)


def watch(path, hidden=False, sort_key="name", desc=False, filters=()):
    """Prints the listing, then one listing per change, until killed."""
    def emit(payload):
        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()

    def snapshot():
        try:
            return listdir(path, hidden, sort_key, desc, filters)
        except OSError as e:
            return {"error": e.strerror or str(e), "code": errno_name(e.errno), "entries": [], "total": 0}

    emit({"kind": "list", **snapshot()})
    if path.startswith(SEARCH):
        # a search is answered once - walking a whole tree again every second would
        # cost what a folder's watch never does; the shell asks again when the words change
        while True:
            time.sleep(3600)
    watched = path
    if path == RECENT:
        # Recent changes when GTK's list does: watch that file's folder, not a clock
        watched = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    fd = inotify_fd(watched)
    if fd is None:
        poll_watch(path, hidden, sort_key, desc, filters, emit)
        return 0
    try:
        while True:
            if not read_inotify(fd):
                break
            emit({"kind": "list", **snapshot()})
    finally:
        os.close(fd)
    return 0


def poll_watch(path, hidden, sort_key, desc, filters, emit):
    """No inotify: compare a listing every second."""
    import time
    last = None
    while True:
        time.sleep(1.0)
        try:
            now = listdir(path, hidden, sort_key, desc, filters)
        except OSError as e:
            emit({"kind": "list", "error": e.strerror or str(e), "code": errno_name(e.errno), "entries": [], "total": 0})
            return
        if now != last:
            last = now
            emit({"kind": "list", **now})


def inotify_fd(path):
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
        fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if fd < 0:
            return None
        if libc.inotify_add_watch(fd, path.encode(), WATCH_MASK) < 0:
            os.close(fd)
            return None
        return fd
    except (OSError, AttributeError):
        return None


def read_inotify(fd):
    """True when something happened (the buffer is drained)."""
    import select
    try:
        ready, _, _ = select.select([fd], [], [], 5.0)
    except (OSError, ValueError):
        return False
    if not ready:
        return False
    try:
        data = os.read(fd, 65536)
    except BlockingIOError:
        return False
    except OSError:
        return False
    return len(data) > 0


# ---- changing ----------------------------------------------------------------

def make_dir(path):
    try:
        os.makedirs(path, exist_ok=False)
    except FileExistsError:
        return {"error": "already exists", "code": "EEXIST"}
    except OSError as e:
        return {"error": e.strerror or str(e), "code": errno_name(e.errno)}
    return {"path": path}


def rename(path, name):
    if not name or "/" in name or name in (".", ".."):
        return {"error": "that is not a name", "code": "EINVAL"}
    target = os.path.join(os.path.dirname(path), name)
    if os.path.exists(target):
        return {"error": "already exists", "code": "EEXIST"}
    try:
        os.rename(path, target)
    except OSError as e:
        return {"error": e.strerror or str(e), "code": errno_name(e.errno)}
    return {"path": target}


def trash_dir():
    return os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share"), "Trash")


def free_name(directory, name):
    """name, or "name (2).ext", "name (3).ext" ... - the first not taken."""
    if not os.path.lexists(os.path.join(directory, name)):
        return os.path.join(directory, name)
    stem, ext = os.path.splitext(name)
    if stem.endswith(".tar"):                      # archive.tar.gz stays one extension
        stem, ext = stem[:-4], ".tar" + ext
    n = 2
    while os.path.lexists(os.path.join(directory, f"{stem} ({n}){ext}")):
        n += 1
    return os.path.join(directory, f"{stem} ({n}){ext}")


def trash(paths):
    """To the desktop trash, where it can be put back: [[path, name in the trash]]."""
    base = trash_dir()
    files_dir, info_dir = os.path.join(base, "files"), os.path.join(base, "info")
    os.makedirs(files_dir, exist_ok=True)
    os.makedirs(info_dir, exist_ok=True)
    trash_dev = os.stat(files_dir).st_dev
    pairs, failed = [], []
    for p in paths:
        p = os.path.abspath(p)
        try:
            if os.lstat(p).st_dev != trash_dev:
                raise OSError(18, "another drive")            # EXDEV: that drive's own trash
            target = free_name(files_dir, os.path.basename(p))
            name = os.path.basename(target)
            with open(os.path.join(info_dir, name + ".trashinfo"), "x", encoding="utf-8") as fh:
                fh.write("[Trash Info]\nPath=%s\nDeletionDate=%s\n"
                         % (urllib.parse.quote(p), time.strftime("%Y-%m-%dT%H:%M:%S")))
            os.rename(p, target)
            pairs.append([p, name])
        except OSError as e:
            if e.errno == 18 and shutil.which("gio"):
                r = subprocess.run(["gio", "trash", "--", p], capture_output=True, text=True, timeout=30)
                if r.returncode == 0:
                    continue
                failed.append({"path": p, "error": (r.stderr or "trash failed").strip()})
            else:
                failed.append({"path": p, "error": e.strerror or str(e)})
    out = {"trashed": len(paths) - len(failed), "pairs": pairs}
    if failed:
        out.update({"error": failed[0]["error"], "code": "EIO", "failed": failed})
    return out


def trash_info(name):
    try:
        with open(os.path.join(trash_dir(), "info", name + ".trashinfo"), encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    m = re.search(r"^Path=(.*)$", text, re.M)
    d = re.search(r"^DeletionDate=(.*)$", text, re.M)
    return {"original": urllib.parse.unquote(m.group(1)) if m else "", "deleted": d.group(1) if d else ""}


def trash_list():
    files_dir = os.path.join(trash_dir(), "files")
    out = []
    try:
        names = os.listdir(files_dir)
    except OSError:
        names = []
    for name in names:
        info = trash_info(name) or {"original": "", "deleted": ""}
        p = os.path.join(files_dir, name)
        try:
            st = os.lstat(p)
        except OSError:
            continue
        out.append({"name": name, "path": p, "original": info["original"], "deleted": info["deleted"],
                    "isDir": stat_mod.S_ISDIR(st.st_mode), "size": st.st_size})
    out.sort(key=lambda e: e["deleted"], reverse=True)
    return {"items": out}


def restore(names):
    """Out of the trash, back where each came from (beside it, if that name is taken now)."""
    base = trash_dir()
    pairs, failed = [], []
    for name in names:
        info = trash_info(name)
        src = os.path.join(base, "files", name)
        if not info or not info["original"] or not os.path.lexists(src):
            failed.append({"name": name, "error": "not in the trash"})
            continue
        dest = info["original"]
        try:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            dest = free_name(os.path.dirname(dest), os.path.basename(dest))
            shutil.move(src, dest)
            os.remove(os.path.join(base, "info", name + ".trashinfo"))
            pairs.append([name, dest])
        except OSError as e:
            failed.append({"name": name, "error": e.strerror or str(e)})
    out = {"restored": len(pairs), "pairs": pairs}
    if failed:
        out.update({"error": failed[0]["error"], "failed": failed})
    return out


def empty_trash(names=None):
    base = trash_dir()
    names = names or [n for n in os.listdir(os.path.join(base, "files"))] if os.path.isdir(os.path.join(base, "files")) else []
    gone = 0
    for name in names:
        p = os.path.join(base, "files", name)
        try:
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p)
            elif os.path.lexists(p):
                os.remove(p)
            info = os.path.join(base, "info", name + ".trashinfo")
            if os.path.exists(info):
                os.remove(info)
            gone += 1
        except OSError:
            continue
    return {"removed": gone}


def paste(dest, mode, paths):
    """Copies or moves into dest; never over anything there, never a folder into itself."""
    dest = os.path.abspath(dest)
    pairs, failed = [], []
    for p in paths:
        p = os.path.abspath(p)
        if dest == p or dest.startswith(p + os.sep):
            failed.append({"path": p, "error": "a folder cannot go inside itself"})
            continue
        if mode == "move" and os.path.dirname(p) == dest:
            continue                                      # already here
        target = free_name(dest, os.path.basename(p))
        try:
            if mode == "move":
                shutil.move(p, target)
            elif os.path.isdir(p) and not os.path.islink(p):
                shutil.copytree(p, target, symlinks=True)
            else:
                shutil.copy2(p, target, follow_symlinks=False)
            pairs.append([p, target])
        except OSError as e:
            failed.append({"path": p, "error": e.strerror or str(e)})
    out = {"mode": mode, "pairs": pairs}
    if failed:
        out.update({"error": failed[0]["error"], "failed": failed})
    return out


def move_pairs(pairs):
    """Each [from, to] moved - an undo; never over anything that is there now."""
    done, failed = [], []
    for src, dst in pairs:
        if os.path.lexists(dst):
            failed.append({"path": dst, "error": "something else has that name now"})
            continue
        try:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(src, dst)
            done.append([src, dst])
        except OSError as e:
            failed.append({"path": src, "error": e.strerror or str(e)})
    out = {"pairs": done}
    if failed:
        out.update({"error": failed[0]["error"], "failed": failed})
    return out


def search(root, query, hidden=False, limit=300, seconds=4.0):
    """Every file and folder under root whose name has all the words, nearest first."""
    words = [w for w in query.lower().split() if w]
    if not words:
        return {"entries": [], "truncated": False}
    found, end, truncated = [], time.monotonic() + seconds, False
    for here, dirs, files in os.walk(root):
        if not hidden:
            dirs[:] = [d for d in dirs if not d.startswith(".")]
        dirs.sort()
        for name in sorted(dirs) + sorted(files):
            if (not hidden and name.startswith(".")) or not all(w in name.lower() for w in words):
                continue
            p = os.path.join(here, name)
            try:
                st = os.lstat(p)
            except OSError:
                continue
            found.append(entry_of(name, p, st, stat_mod.S_ISDIR(st.st_mode)))
            if len(found) >= limit:
                return {"entries": found, "truncated": True}
        if time.monotonic() > end:
            truncated = True
            break
    return {"entries": found, "truncated": truncated}


def props(paths, seconds=3.0):
    """What Properties shows: the size counted through folders, the dates, owner and rights."""
    import grp
    import pwd
    total, files, dirs, partial = 0, 0, 0, False
    end = time.monotonic() + seconds
    for p in paths:
        try:
            st = os.lstat(p)
        except OSError:
            continue
        if stat_mod.S_ISDIR(st.st_mode):
            dirs += 1
            for here, ds, fs in os.walk(p):
                dirs += len(ds)
                for f in fs:
                    try:
                        total += os.lstat(os.path.join(here, f)).st_size
                        files += 1
                    except OSError:
                        pass
                if time.monotonic() > end:
                    partial = True
                    break
        else:
            files += 1
            total += st.st_size
    out = {"size": total, "files": files, "dirs": dirs, "partial": partial, "count": len(paths)}
    if len(paths) == 1:
        p = paths[0]
        try:
            st = os.lstat(p)
            out.update({"path": p, "name": os.path.basename(p), "mtime": int(st.st_mtime * 1000),
                        "atime": int(st.st_atime * 1000), "mode": stat_mod.filemode(st.st_mode),
                        "owner": pwd.getpwuid(st.st_uid).pw_name, "group": grp.getgrgid(st.st_gid).gr_name,
                        "type": "folder" if stat_mod.S_ISDIR(st.st_mode) else (mimetypes.guess_type(p)[0] or "file")})
            birth = getattr(st, "st_birthtime", None)
            if birth:
                out["btime"] = int(birth * 1000)
        except (OSError, KeyError):
            pass
    return out


def batch_rename(pattern, paths):
    """"Holiday #" -> "Holiday 01.jpg", "Holiday 02.jpg" ... in the order given; the
    extension stays; "#" missing: the number goes after the name. Never over a file
    that is not among those being renamed."""
    width = max(1, len(str(len(paths))))
    plan, taken = [], set()
    for i, p in enumerate(paths, 1):
        d, base = os.path.split(os.path.abspath(p))
        _, ext = os.path.splitext(base)
        num = str(i).zfill(width)
        name = pattern.replace("#", num) if "#" in pattern else f"{pattern} {num}"
        target = os.path.join(d, name.strip() + ext)
        if target in taken:
            return {"error": "two of them would get the same name", "pairs": []}
        taken.add(target)
        plan.append([os.path.abspath(p), target])
    sources = {a for a, _ in plan}
    for _, b in plan:
        if os.path.lexists(b) and b not in sources:
            return {"error": f"{os.path.basename(b)} is there already", "pairs": []}
    # two steps, through names of their own, so a rename onto another one's old name works
    temps = []
    for k, (a, _) in enumerate(plan):
        t = os.path.join(os.path.dirname(a), f".shani-rename-{os.getpid()}-{k}")
        os.rename(a, t)
        temps.append(t)
    for t, (_, b) in zip(temps, plan):
        os.rename(t, b)
    return {"pairs": [[a, b] for a, b in plan if a != b]}


def bookmarks_file():
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"),
                        "gtk-3.0", "bookmarks")


def bookmarks():
    out = []
    try:
        with open(bookmarks_file(), encoding="utf-8") as fh:
            for line in fh:
                uri, _, label = line.strip().partition(" ")
                if uri.startswith("file://"):
                    p = urllib.parse.unquote(uri[7:])
                    out.append({"name": label or os.path.basename(p.rstrip("/")) or p, "path": p,
                                "icon": "user-bookmarks", "bookmark": True})
    except OSError:
        pass
    return out


def bookmark(path, add=True):
    f = bookmarks_file()
    uri = "file://" + urllib.parse.quote(os.path.abspath(path))
    try:
        with open(f, encoding="utf-8") as fh:
            lines = [l.rstrip("\n") for l in fh if l.strip()]
    except OSError:
        lines = []
    lines = [l for l in lines if l.partition(" ")[0] != uri]
    if add:
        lines.append(uri)
    os.makedirs(os.path.dirname(f), exist_ok=True)
    with open(f, "w", encoding="utf-8") as fh:
        fh.write("".join(l + "\n" for l in lines))
    return {"bookmarks": bookmarks()}


# ---- places -------------------------------------------------------------------

def user_dirs():
    """The XDG folders, from ~/.config/user-dirs.dirs."""
    dirs = {}
    path = os.path.join(os.path.expanduser("~"), ".config", "user-dirs.dirs")
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r'\s*XDG_(\w+)_DIR="([^"]*)"', line)
                if not m:
                    continue
                value = m.group(2).replace("$HOME", os.path.expanduser("~"))
                dirs[m.group(1).lower()] = value
    except OSError:
        pass
    return dirs


def places():
    home = os.path.expanduser("~")
    out = [{"name": "Home", "path": home, "icon": "user-home"}]
    dirs = user_dirs()
    for key, icon in (("desktop", "user-desktop"), ("documents", "user-bookmarks"),
                      ("downloads", "folder-download"), ("pictures", "user-pictures"),
                      ("videos", "user-videos"), ("music", "user-music"),
                      ("public", "folder-publicshare")):
        p = dirs.get(key)
        if p and os.path.isdir(p):
            out.append({"name": key.capitalize(), "path": p, "icon": icon})
    # removable drives: what udisks mounted, and what was plugged in by hand
    for base in ("/run/media/" + os.path.basename(home), "/media/" + os.path.basename(home), "/media"):
        try:
            names = sorted(os.listdir(base))
        except OSError:
            continue
        for name in names:
            p = os.path.join(base, name)
            # a drive is mounted or it holds something: an empty /media/root is
            # not a place to send anyone
            if not os.path.isdir(p):
                continue
            try:
                empty = not os.listdir(p)
            except OSError:
                empty = True          # it cannot be read: not a place either
            if not os.path.ismount(p) and empty:
                continue
            out.append({"name": name, "path": p, "icon": "drive-harddisk"})
    # the person's bookmarks (GTK's file: the same ones GTK apps and their file
    # choosers show), after the folders and drives
    seen = {o["path"] for o in out}
    out += [b for b in bookmarks() if b["path"] not in seen]
    return {"places": out}


# ---- the commands ----------------------------------------------------------------

def main(argv):
    if len(argv) < 2:
        print(json.dumps({"error": "no command"}))
        return 2
    cmd = argv[1]
    args = argv[2:]
    if cmd == "list":
        path = args[0] if args else ""
        hidden = "--hidden" in args
        desc = "--desc" in args
        sort_key = "name"
        filters = ()
        limit = 0
        offset = 0
        for a in args[1:]:
            if a.startswith("--sort="):
                sort_key = a.split("=", 1)[1]
            elif a.startswith("--filter="):
                filters = [f for f in a.split("=", 1)[1].split(",") if f]
            elif a.startswith("--limit="):
                limit = int(a.split("=", 1)[1] or 0)
            elif a.startswith("--offset="):
                offset = int(a.split("=", 1)[1] or 0)
        try:
            print(json.dumps(listdir(path, hidden, sort_key, desc, filters, limit, offset)))
        except OSError as e:
            print(json.dumps({"error": e.strerror or str(e), "code": errno_name(e.errno), "entries": [], "total": 0}))
        return 0
    if cmd == "watch":
        path = args[0] if args else ""
        hidden = "--hidden" in args
        desc = "--desc" in args
        sort_key = "name"
        filters = ()
        for a in args[1:]:
            if a.startswith("--sort="):
                sort_key = a.split("=", 1)[1]
            elif a.startswith("--filter="):
                filters = [f for f in a.split("=", 1)[1].split(",") if f]
        return watch(path, hidden, sort_key, desc, filters)
    if cmd == "stat":
        print(json.dumps(stat_path(args[0] if args else "")))
        return 0
    if cmd == "mkdir":
        print(json.dumps(make_dir(args[0] if args else "")))
        return 0
    if cmd == "rename":
        print(json.dumps(rename(args[0] if args else "", args[1] if len(args) > 1 else "")))
        return 0
    if cmd == "trash":
        print(json.dumps(trash([a for a in args if a])))
        return 0
    if cmd == "places":
        print(json.dumps(places()))
        return 0
    try:
        if cmd == "paste" and len(args) >= 3:
            print(json.dumps(paste(args[0], args[1], args[2:])))
        elif cmd == "move-pairs" and args:
            print(json.dumps(move_pairs(json.loads(args[0]))))
        elif cmd == "trash-list":
            print(json.dumps(trash_list()))
        elif cmd == "restore":
            print(json.dumps(restore(args)))
        elif cmd == "empty-trash":
            print(json.dumps(empty_trash(args or None)))
        elif cmd == "search" and len(args) >= 2:
            print(json.dumps(search(args[0], " ".join(a for a in args[1:] if a != "--hidden"), "--hidden" in args)))
        elif cmd == "props" and args:
            print(json.dumps(props(args)))
        elif cmd == "batch-rename" and len(args) >= 2:
            print(json.dumps(batch_rename(args[0], args[1:])))
        elif cmd in ("bookmark-add", "bookmark-remove") and args:
            print(json.dumps(bookmark(args[0], cmd == "bookmark-add")))
        else:
            print(json.dumps({"error": "unknown command: " + cmd}))
            return 2
    except (OSError, ValueError) as e:
        print(json.dumps({"error": getattr(e, "strerror", None) or str(e)}))
    return 0
    print(json.dumps({"error": "unknown command: " + cmd}))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
