#!/usr/bin/env python3
"""files — the file manager's backend: list a directory, watch it, and change it.

  files.py list <path> [--hidden] [--sort name|size|mtime] [--desc]
                    [--filter ext,ext] [--limit N] [--offset N]
  files.py watch <path>            # one JSON object per change, until killed
  files.py stat <path>
  files.py mkdir <path>
  files.py rename <path> <name>
  files.py trash <path> [<path>...]
  files.py places                  # home, the XDG folders, the mounted drives

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

Nothing is deleted by `trash`: the file goes to the desktop trash through
`gio trash`, which is reversible from the trash itself.
"""
import ctypes
import json
import os
import re
import shutil
import subprocess
import sys

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


def listdir(path, hidden=False, sort_key="name", desc=False, filters=(), limit=0, offset=0):
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
    fd = inotify_fd(path)
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


def trash(paths):
    """To the desktop trash, where it can be put back."""
    gio = shutil.which("gio")
    if not gio:
        return {"error": "gio is not installed", "code": "ENOTSUPPORTED"}
    failed = []
    for p in paths:
        r = subprocess.run([gio, "trash", "--", p], capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            failed.append({"path": p, "error": (r.stderr or r.stdout or "trash failed").strip()})
    if failed:
        return {"error": failed[0]["error"], "code": "EIO", "failed": failed}
    return {"trashed": len(paths)}


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
    print(json.dumps({"error": "unknown command: " + cmd}))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
