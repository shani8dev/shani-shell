#!/usr/bin/env python3
"""files — the file manager's backend: list a directory, watch it, and change it.

  files.py list <path> [--hidden] [--sort name|size|mtime|btime|type] [--desc]
                    [--filter ext,ext] [--limit N] [--offset N]
  files.py watch <path>            # one JSON object per change, until killed
  files.py stat <path>
  files.py mkdir <path>
  files.py rename <path> <name>
  files.py symlink <target> <link-path>       # Create Link (Ctrl+M): a link to target
  files.py trash <path> [<path>...]
  files.py places                  # home, the XDG folders, the mounted drives, bookmarks
  files.py paste <dest> copy|move <path>...   # into dest, never over anything: "name (2)"
  files.py job <dest> copy|move|auto <path>...  # the same, for the big ones (auto: a drop -
                                   # moved on the same drive, copied from another): one JSON line of
                                   # progress after another, then the result; SIGTERM cancels
  files.py move-pairs '<json [[from, to], ...]>'   # undo: each moved back, never over anything
  files.py trash-list              # what is in the trash, and where each came from
  files.py restore <name>...       # out of the trash, back where it came from
  files.py empty-trash [<name>...] # for good: those, or everything
  files.py search <dir> <words>    # in that folder and every folder under it, by name
  files.py props <path>...         # size (folders counted through), dates, owner, rights
  files.py batch-rename <pattern> <path>...   # "Holiday #" -> Holiday 1.jpg, Holiday 2.jpg ...
  files.py bookmark-add <path> | bookmark-remove <path>   # GTK's bookmarks file
  files.py thumbs <normal|large> <path>...   # freedesktop thumbnails: one JSON line per file
                                   # that has (or now gets) one: {"path", "thumb"}
  files.py star-add|star-remove <path>... | starred-list   # stars; `list starred:` shows them
  files.py templates               # ~/Templates: the "New document" kinds
  files.py chmod-pairs '<json [[path, mode], ...]>'   # rights set; the old ones answered (undo)
  files.py network                 # the servers the network announces (gvfs network://)
  files.py unlock <device>         # an encrypted volume opened: {"password"} on stdin
  files.py free <path>             # free and total bytes of its drive
  files.py compare <a> <b>         # two files side by side (text, line by line) or two folders
  files.py devices                 # drives, phones, cameras, network places (gio mount -li)
  files.py mount <uri|/dev/...>    # mount one, answer its local path
  files.py unmount <path> | eject <path>
  files.py local <uri>             # a gvfs URI's local path (/run/user/<uid>/gvfs/...)
  files.py connect <uri>           # a server: smb://, sftp://, ftp://, dav(s)://; a JSON line
                                   # {"user", "domain", "password"} on stdin answers its questions

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
import tempfile
import time
import urllib.parse

MAX_COMPARE_BYTES = (
    16 * 1024 * 1024
)  # bound stdin: a merged file larger than this is refused

IMAGE_EXTS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".bmp",
    ".svg",
    ".avif",
    ".heic",
    ".heif",
    ".tif",
    ".tiff",
}

# ---- listing ----------------------------------------------------------------


def entry_of(name, path, st, is_dir):
    ext = os.path.splitext(name)[1].lower()
    # Linux often has no st_birthtime: ctime is the closest the platform gives
    # for "date created" (inode change time) and is always present.
    birth = getattr(st, "st_birthtime", None) or st.st_ctime
    return {
        "name": name,
        "path": path,
        "isDir": is_dir,
        "size": 0 if is_dir else int(st.st_size),
        "mtime": int(st.st_mtime * 1000),
        "btime": int(birth * 1000),
        "ext": ext,
        "image": ext in IMAGE_EXTS,
    }


RECENT = "recent:"
STARRED = "starred:"  # the files and folders starred, wherever they are
KIND = (
    "kind:"  # kind:pictures|music|videos|documents|archives - every one in your folders
)
KINDS = ("pictures", "music", "videos", "documents", "archives")
DOC_EXT = {
    "pdf",
    "doc",
    "docx",
    "odt",
    "rtf",
    "txt",
    "md",
    "xls",
    "xlsx",
    "ods",
    "csv",
    "ppt",
    "pptx",
    "odp",
    "epub",
    "djvu",
    "xps",
    "tex",
    "pages",
    "numbers",
    "key",
}
ARCHIVE_EXT = {
    "zip",
    "7z",
    "rar",
    "tar",
    "gz",
    "tgz",
    "xz",
    "txz",
    "bz2",
    "tbz2",
    "zst",
    "tzst",
    "lz",
    "lzma",
    "cab",
    "iso",
    "deb",
    "rpm",
    "gpg",
}
# not looked in: caches, app data, build output, version control, the trash
KIND_SKIP = {
    "node_modules",
    "__pycache__",
    "target",
    "build",
    "dist",
    "venv",
    ".venv",
    "site-packages",
}


def recent_files():
    """The files the person opened lately, newest first: GTK's recently-used.xbel,
    which GTK and Qt apps (and the shell's own) write. Only what is still there."""
    import xml.etree.ElementTree as ET
    from urllib.parse import unquote, urlparse

    xbel = os.path.join(
        os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
        "recently-used.xbel",
    )
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
        out.append(
            (
                bm.get("visited") or bm.get("modified") or "",
                entry_of(os.path.basename(path), path, st, os.path.isdir(path)),
            )
        )
    out.sort(key=lambda x: x[0], reverse=True)
    return [e for _, e in out[:200]]


SEARCH = "search:"  # "search:<words>\t<folder>": the folder and every folder under it


def kind_of_name(name):
    """pictures | music | videos | documents | archives | "" - by the name's extension."""
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if ext in ARCHIVE_EXT:
        return "archives"
    if ext in DOC_EXT:
        return "documents"
    mime = mimetypes.guess_type(name)[0] or ""
    return {"image": "pictures", "audio": "music", "video": "videos"}.get(
        mime.split("/")[0], ""
    )


def _same_dev(p, dev):
    try:
        return os.stat(p, follow_symlinks=False).st_dev == dev
    except OSError:
        return False


def by_kind(kind, root=None, cap=5000, budget=4.0):
    """Every file of that kind under your home (ES File Explorer's Library): not in
    hidden folders, caches or build output. Newest first; a big home is walked for a
    few seconds at most and said to be cut short."""
    root = root or os.path.expanduser("~")
    started, out, truncated = time.monotonic(), [], False
    dev = os.stat(root).st_dev
    for d, dirs, files in os.walk(root):
        # not hidden folders or build output, and not into another drive, a share or a
        # cloud mounted inside home (walking those would be slow, and they are theirs)
        dirs[:] = [
            x
            for x in dirs
            if not x.startswith(".")
            and x not in KIND_SKIP
            and _same_dev(os.path.join(d, x), dev)
        ]
        for n in files:
            if n.startswith(".") or kind_of_name(n) != kind:
                continue
            p = os.path.join(d, n)
            try:
                st = os.lstat(p)
            except OSError:
                continue
            if stat_mod.S_ISREG(st.st_mode):
                out.append(entry_of(n, p, st, False))
        if len(out) >= cap or time.monotonic() - started > budget:
            truncated = True
            break
    out.sort(key=lambda e: -e.get("mtime", 0))
    return {"entries": out[:cap], "truncated": truncated}


def listdir(
    path, hidden=False, sort_key="name", desc=False, filters=(), limit=0, offset=0
):
    if path.startswith(KIND) and path[len(KIND) :] in KINDS:
        found = by_kind(path[len(KIND) :])
        out = (
            sort_entries(found["entries"], sort_key, desc, filters, limit, offset)
            if sort_key != "name"
            else {"entries": found["entries"], "total": len(found["entries"])}
        )
        out["truncated"] = found["truncated"]
        return out
    if path.startswith(SEARCH):
        words, _, root = path[len(SEARCH) :].partition("\t")
        found = search(root or os.path.expanduser("~"), words, hidden)
        out = (
            sort_entries(found["entries"], sort_key, desc, filters, limit, offset)
            if sort_key != "name"
            else {"entries": found["entries"], "total": len(found["entries"])}
        )
        out["truncated"] = found["truncated"]
        return out
    if path == STARRED:
        entries = []
        for p in starred():
            try:
                st = os.lstat(p)
            except OSError:
                continue  # gone: not shown, kept in case it comes back
            entries.append(
                entry_of(os.path.basename(p), p, st, stat_mod.S_ISDIR(st.st_mode))
            )
        return sort_entries(entries, sort_key, desc, filters, limit, offset)
    if path == RECENT:
        entries = recent_files()
        # newest first unless a sort was asked for
        return (
            sort_entries(entries, sort_key, desc, filters, limit, offset)
            if sort_key != "name"
            else {"entries": entries, "total": len(entries)}
        )
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
    elif sort_key == "btime":
        entries.sort(
            key=lambda e: (not e["isDir"], -e.get("btime", 0), e["name"].lower())
        )
    elif sort_key == "type":
        entries.sort(key=lambda e: (not e["isDir"], e["ext"], natural_key(e["name"])))
    else:
        entries.sort(key=lambda e: (not e["isDir"], natural_key(e["name"])))
    if desc:
        # folders stay first, but inside each group the order flips
        entries = [e for e in entries if e["isDir"]] + [
            e for e in entries if not e["isDir"]
        ][::-1]
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
    return {
        "entry": entry_of(os.path.basename(path.rstrip("/")) or path, path, st, is_dir)
    }


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
WATCH_MASK = (
    IN_ATTRIB
    | IN_CLOSE_WRITE
    | IN_MODIFY
    | IN_MOVED_FROM
    | IN_MOVED_TO
    | IN_CREATE
    | IN_DELETE
    | IN_DELETE_SELF
    | IN_MOVE_SELF
)


def watch(path, hidden=False, sort_key="name", desc=False, filters=()):
    """Prints the listing, then one listing per change, until killed."""

    def emit(payload):
        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()

    def snapshot():
        try:
            return listdir(path, hidden, sort_key, desc, filters)
        except OSError as e:
            return {
                "error": e.strerror or str(e),
                "code": errno_name(e.errno),
                "entries": [],
                "total": 0,
            }

    emit({"kind": "list", **snapshot()})
    if path.startswith(SEARCH) or path.startswith(KIND):
        # answered once: the shell asks again when the words change. Sleeping
        # forever here leaked a thread/process on every reopen of a search.
        return
    watched = path
    if path == RECENT:
        # Recent changes when GTK's list does: watch that file's folder, not a clock
        watched = os.environ.get("XDG_DATA_HOME") or os.path.expanduser(
            "~/.local/share"
        )
    if path == STARRED:
        # the stars change when their file does
        watched = os.path.dirname(_starred_file())
        os.makedirs(watched, exist_ok=True)
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
            emit(
                {
                    "kind": "list",
                    "error": e.strerror or str(e),
                    "code": errno_name(e.errno),
                    "entries": [],
                    "total": 0,
                }
            )
            return
        if now != last:
            last = now
            emit({"kind": "list", **now})


def inotify_fd(path):
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint32,
        ]
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


def symlink(target, linkpath):
    """Create a symbolic link at linkpath pointing at target. Both arrive as
    argv slots, never inside a shell string, so spaces and quotes are safe."""
    if not linkpath:
        return {"error": "that is not a name", "code": "EINVAL"}
    if os.path.lexists(linkpath):
        return {"error": "already exists", "code": "EEXIST"}
    target = os.path.abspath(target)
    try:
        os.symlink(target, linkpath)
    except OSError as e:
        return {"error": e.strerror or str(e), "code": errno_name(e.errno)}
    return {"path": linkpath, "target": target}


def trash_dir():
    return os.path.join(
        os.environ.get("XDG_DATA_HOME")
        or os.path.join(os.path.expanduser("~"), ".local", "share"),
        "Trash",
    )


def free_name(directory, name):
    """name, or "name (2).ext", "name (3).ext" ... - the first not taken."""
    if not os.path.lexists(os.path.join(directory, name)):
        return os.path.join(directory, name)
    stem, ext = os.path.splitext(name)
    if stem.endswith(".tar"):  # archive.tar.gz stays one extension
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
                raise OSError(18, "another drive")  # EXDEV: that drive's own trash
            target = free_name(files_dir, os.path.basename(p))
            name = os.path.basename(target)
            with open(
                os.path.join(info_dir, name + ".trashinfo"), "x", encoding="utf-8"
            ) as fh:
                fh.write(
                    "[Trash Info]\nPath=%s\nDeletionDate=%s\n"
                    % (urllib.parse.quote(p), time.strftime("%Y-%m-%dT%H:%M:%S"))
                )
            os.rename(p, target)
            pairs.append([p, name])
        except OSError as e:
            if e.errno == 18 and shutil.which("gio"):
                r = subprocess.run(
                    ["gio", "trash", "--", p],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                if r.returncode == 0:
                    continue
                failed.append(
                    {"path": p, "error": (r.stderr or "trash failed").strip()}
                )
            else:
                failed.append({"path": p, "error": e.strerror or str(e)})
    out = {"trashed": len(paths) - len(failed), "pairs": pairs}
    if failed:
        out.update({"error": failed[0]["error"], "code": "EIO", "failed": failed})
    return out


def trash_info(name):
    # names come from argv/JSON: a ".." must never escape the trash directory
    name = os.path.basename(str(name))
    try:
        with open(
            os.path.join(trash_dir(), "info", name + ".trashinfo"), encoding="utf-8"
        ) as fh:
            text = fh.read()
    except OSError:
        return None
    m = re.search(r"^Path=(.*)$", text, re.M)
    d = re.search(r"^DeletionDate=(.*)$", text, re.M)
    original = urllib.parse.unquote(m.group(1)) if m else ""
    # a trashinfo can be edited: only an absolute original may be restored
    if original and not os.path.isabs(original):
        original = ""
    return {"original": original, "deleted": d.group(1) if d else ""}


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
        out.append(
            {
                "name": name,
                "path": p,
                "original": info["original"],
                "deleted": info["deleted"],
                "isDir": stat_mod.S_ISDIR(st.st_mode),
                "size": st.st_size,
            }
        )
    out.sort(key=lambda e: e["deleted"], reverse=True)
    return {"items": out}


def restore(names):
    """Out of the trash, back where each came from (beside it, if that name is taken now)."""
    base = trash_dir()
    pairs, failed = [], []
    for name in names:
        name = os.path.basename(str(name))
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
    names = (
        names or [n for n in os.listdir(os.path.join(base, "files"))]
        if os.path.isdir(os.path.join(base, "files"))
        else []
    )
    gone = 0
    for name in names:
        name = os.path.basename(str(name))
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
            continue  # already here
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


class Cancelled(Exception):
    pass


def job(dest, mode, paths, out=sys.stdout, chunk=1 << 20, opts=None):
    """A copy or move with progress (copyjob.py does it: pause, verify, conflict
    rules, skip-and-go-on, history)."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import copyjob

    return copyjob.Job(out=out, chunk=chunk, opts=opts).run(dest, mode, paths)


# ---- starred, templates, permissions, free space -----------------------------------
def _starred_file():
    return os.path.join(
        os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
        "shani-shell",
        "starred",
    )


def starred():
    try:
        with open(_starred_file(), encoding="utf-8") as fh:
            return [l.rstrip("\n") for l in fh if l.strip()]
    except OSError:
        return []


def set_starred(paths, on):
    have = starred()
    paths = [os.path.abspath(p) for p in paths]
    new = (
        (have + [p for p in paths if p not in have])
        if on
        else [p for p in have if p not in paths]
    )
    f = _starred_file()
    os.makedirs(os.path.dirname(f), exist_ok=True)
    tmp = f + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.writelines(p + "\n" for p in new)
    os.replace(tmp, f)
    return {"starred": new}


def templates():
    """~/Templates (the XDG folder): each file a "New document" kind."""
    d = user_dirs().get("templates") or os.path.join(
        os.path.expanduser("~"), "Templates"
    )
    out = []
    try:
        for e in sorted(os.scandir(d), key=lambda e: e.name.lower()):
            if e.is_file() and not e.name.startswith("."):
                out.append({"name": os.path.splitext(e.name)[0], "path": e.path})
    except OSError:
        pass
    return {"templates": out, "dir": d}


def chmod_pairs(pairs):
    """[[path, mode], ...]: each path's rights set to mode (octal int); the old
    modes answered, so an undo is the same call with them."""
    done, failed = [], []
    for p, mode in pairs:
        try:
            old = stat_mod.S_IMODE(os.lstat(p).st_mode)
            os.chmod(p, int(mode) & 0o7777)
            done.append([p, old])
        except (OSError, ValueError, TypeError) as e:
            failed.append({"path": p, "error": getattr(e, "strerror", None) or str(e)})
    out = {"pairs": done}
    if failed:
        out.update({"error": failed[0]["error"], "failed": failed})
    return out


def free_space(path):
    try:
        s = os.statvfs(path)
    except OSError as e:
        return {"error": e.strerror or str(e)}
    return {"free": s.f_bavail * s.f_frsize, "total": s.f_blocks * s.f_frsize}


# ---- compare (Meld parity): two files line by line, or two folders ------------------
def _text_lines(p, limit=20000):
    with open(p, "rb") as fh:
        data = fh.read(8 << 20)
    if b"\0" in data[:8192]:
        return None  # binary
    return data.decode("utf-8", errors="replace").splitlines()[:limit]


def compare(a, b):
    """{"kind": "text", "rows": [{"l", "r", "tag"}...], "changes"} for two text files;
    {"kind": "binary", "same"} for two others; {"kind": "folders", "rows": [{"path",
    "state": only-left|only-right|differs}...]} for two folders (same ones not listed)."""
    import difflib
    import filecmp

    if os.path.isdir(a) and os.path.isdir(b):
        rows = []

        def walk(rel):
            c = filecmp.dircmp(os.path.join(a, rel), os.path.join(b, rel))
            for n in sorted(c.left_only):
                rows.append({"path": os.path.join(rel, n), "state": "only-left"})
            for n in sorted(c.right_only):
                rows.append({"path": os.path.join(rel, n), "state": "only-right"})
            for n in sorted(c.common_files):
                if not filecmp.cmp(
                    os.path.join(a, rel, n), os.path.join(b, rel, n), shallow=False
                ):
                    rows.append({"path": os.path.join(rel, n), "state": "differs"})
            for n in sorted(c.common_dirs):
                walk(os.path.join(rel, n))

        walk("")
        return {"kind": "folders", "rows": rows[:5000], "changes": len(rows)}
    if os.path.isdir(a) or os.path.isdir(b):
        return {"error": "a folder is compared with a folder, a file with a file"}
    try:
        la, lb = _text_lines(a), _text_lines(b)
    except OSError as e:
        return {"error": e.strerror or str(e)}
    if la is None or lb is None:
        import filecmp

        return {"kind": "binary", "same": filecmp.cmp(a, b, shallow=False)}
    rows, changes = [], 0
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(
        None, la, lb, autojunk=False
    ).get_opcodes():
        if tag != "equal":
            changes += 1
        n = max(i2 - i1, j2 - j1)
        for k in range(n):
            rows.append(
                {
                    "l": la[i1 + k] if i1 + k < i2 else None,
                    "r": lb[j1 + k] if j1 + k < j2 else None,
                    "tag": tag,
                    "ln": i1 + k + 1 if i1 + k < i2 else 0,
                    "rn": j1 + k + 1 if j1 + k < j2 else 0,
                }
            )
    return {"kind": "text", "rows": rows, "changes": changes}


# ---- thumbnails: the freedesktop cache every file manager and GTK app shares ---------
# ~/.cache/thumbnails/<normal|large>/<md5 of the file's URI>.png, made by the
# .thumbnailer whose MimeType has the file's type (ffmpegthumbnailer, the GStreamer
# and gdk-pixbuf ones...), pdftoppm for a PDF; a file none can do is marked in
# fail/shani-files/ so it is not tried again until it changes.
THUMB_SIZES = {"normal": 128, "large": 256}


def _thumbnailers():
    out = []
    for d in [
        os.path.join(p, "thumbnailers")
        for p in [
            os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        ]
        + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    ]:
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for n in names:
            if not n.endswith(".thumbnailer"):
                continue
            entry = {}
            try:
                for line in open(os.path.join(d, n), encoding="utf-8"):
                    if "=" in line and not line.startswith("#"):
                        k, v = line.split("=", 1)
                        entry[k.strip()] = v.strip()
            except OSError:
                continue
            if entry.get("Exec") and entry.get("MimeType"):
                entry["mimes"] = [m for m in entry["MimeType"].split(";") if m]
                out.append(entry)
    return out


def thumb_for(path, size_name, thumbnailers=None):
    """The thumbnail's path, made now when the cache has none newer than the file;
    "" when nothing can make one (then not tried again until the file changes)."""
    import hashlib
    import shlex

    try:
        st = os.stat(path)
    except OSError:
        return ""
    uri = "file://" + urllib.parse.quote(os.path.abspath(path))
    md5 = hashlib.md5(uri.encode()).hexdigest()
    cache = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    target = os.path.join(cache, "thumbnails", size_name, md5 + ".png")
    fail = os.path.join(cache, "thumbnails", "fail", "shani-files", md5 + ".png")
    for p in (target, fail):
        try:
            if os.stat(p).st_mtime >= st.st_mtime:
                return target if p == target else ""
        except OSError:
            pass
    mime = mimetypes.guess_type(path)[0] or ""
    px = THUMB_SIZES[size_name]
    os.makedirs(os.path.dirname(target), exist_ok=True)
    tmp = target + f".shani-{os.getpid()}.png"
    made = False
    for th in thumbnailers if thumbnailers is not None else _thumbnailers():
        if mime not in th["mimes"]:
            continue
        if th.get("TryExec") and not shutil.which(th["TryExec"]):
            continue
        args = [
            a.replace("%i", path)
            .replace("%u", uri)
            .replace("%o", tmp)
            .replace("%s", str(px))
            .replace("%%", "%")
            for a in shlex.split(th["Exec"])
        ]
        try:
            made = (
                subprocess.run(args, capture_output=True, timeout=30).returncode == 0
                and os.path.getsize(tmp) > 0
            )
        except (OSError, subprocess.TimeoutExpired):
            made = False
        if made:
            break
    if not made and mime == "application/pdf" and shutil.which("pdftoppm"):
        try:
            made = subprocess.run(
                [
                    "pdftoppm",
                    "-png",
                    "-singlefile",
                    "-f",
                    "1",
                    "-l",
                    "1",
                    "-scale-to",
                    str(px),
                    path,
                    tmp[:-4],
                ],
                capture_output=True,
                timeout=30,
            ).returncode == 0 and os.path.exists(tmp)
        except (OSError, subprocess.TimeoutExpired):
            made = False
    if made:
        os.replace(tmp, target)
        return target
    try:
        os.remove(tmp)
    except OSError:
        pass
    os.makedirs(os.path.dirname(fail), exist_ok=True)
    open(fail, "wb").close()
    return ""


def thumbs(size_name, paths, out=sys.stdout):
    if size_name not in THUMB_SIZES:
        size_name = "normal"
    ths = _thumbnailers()
    for p in paths:
        t = thumb_for(p, size_name, ths)
        if t:
            out.write(json.dumps({"path": p, "thumb": t}) + "\n")
            out.flush()
    return 0


# ---- drives, phones, cameras and network places: GLib's own gio ---------------------
def _gio(*args, stdin=None, timeout=60):
    import shlex

    return subprocess.run(
        shlex.split(os.environ.get("SHANI_GIO", "gio")) + list(args),
        input=stdin,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def parse_gio_mounts(text):
    """`gio mount -li` -> its drives, volumes and mounts, each a dict of what it
    says (name, kind, indent, flags=1/0, ids, activation_root, default_location,
    the mount's target), the volumes and mounts under a drive knowing it."""
    items, stack = [], []
    head = re.compile(r"^( *)(Drive|Volume|Mount)\(\d+\): (.*)$")
    for line in text.splitlines():
        m = head.match(line)
        if m:
            indent, kind, rest = len(m.group(1)), m.group(2).lower(), m.group(3)
            it = {"kind": kind, "indent": indent, "name": rest, "ids": {}}
            if kind == "mount" and " -> " in rest:
                it["name"], it["target"] = rest.rsplit(" -> ", 1)
            while stack and stack[-1]["indent"] >= indent:
                stack.pop()
            if stack:
                it["parent"] = stack[-1]
            stack.append(it)
            items.append(it)
            continue
        if not stack:
            continue
        cur = stack[-1]
        s = line.strip()
        idm = re.match(r"^(unix-device|class|uuid|label): '(.*)'$", s)
        if idm:
            cur["ids"][idm.group(1)] = idm.group(2)
        elif "=" in s and not s.startswith(("themed icons", "symbolic themed")):
            k, v = s.split("=", 1)
            cur[k] = v
    return items


def _icon(it):
    root = it.get("activation_root", "") + it.get("target", "")
    for scheme, icon in (
        ("mtp://", "phone"),
        ("afc://", "phone"),
        ("gphoto2://", "camera-photo"),
        ("smb://", "folder-remote"),
        ("sftp://", "folder-remote"),
        ("ftp://", "folder-remote"),
        ("dav", "folder-remote"),
        ("nfs://", "folder-remote"),
    ):
        if scheme in root:
            return icon
    return "drive-removable-media"


def local_path(uri):
    """A gvfs URI's place on disk (gvfsd-fuse: /run/user/<uid>/gvfs/...), "" if none."""
    if uri.startswith("file://"):
        return urllib.parse.unquote(uri[7:])
    if uri.startswith("/"):
        return uri
    r = _gio("info", "-a", "standard::name", uri, timeout=20)
    m = re.search(r"^local path: (.+)$", r.stdout, re.M)
    return m.group(1).strip() if m else ""


def devices():
    """What the sidebar's Devices and Network show: removable drives, a drive's
    volumes, phones and cameras (volumes with no drive), network mounts, and the
    other drives in this computer that are not mounted. Not loop devices."""
    try:
        items = parse_gio_mounts(_gio("mount", "-li", timeout=20).stdout)
    except (OSError, subprocess.TimeoutExpired):
        return {"devices": [], "error": "gio is not available"}
    mounts = [i for i in items if i["kind"] == "mount"]
    out, seen = [], set()
    for v in (i for i in items if i["kind"] == "volume"):
        drive = v.get("parent") if v.get("parent", {}).get("kind") == "drive" else None
        # its mount: under it, or the mount whose location is its activation root
        mount = next((m for m in mounts if m.get("parent") is v), None) or next(
            (
                m
                for m in mounts
                if v.get("activation_root")
                and m.get("default_location", m.get("target", "")).startswith(
                    v["activation_root"]
                )
            ),
            None,
        )
        if v["ids"].get("class") == "loop" or "/dev/loop" in v["ids"].get(
            "unix-device", ""
        ):
            if not mount:
                continue  # a snap's or the system's loop: not a place
            drive = None  # a disk image opened: Eject lets it go
        removable = (
            not drive
            or drive.get("is_removable") == "1"
            or drive.get("can_eject") == "1"
        )
        if not removable and mount:
            continue  # an internal drive in use: the system's, not a place
        path = (
            local_path(mount.get("default_location") or mount.get("target", ""))
            if mount
            else ""
        )
        key = (
            path or v.get("activation_root") or v["ids"].get("unix-device") or v["name"]
        )
        if key in seen:
            continue
        seen.add(key)
        out.append(
            {
                "name": v["name"],
                "path": path,
                "mounted": bool(mount),
                "mount": v.get("activation_root") or v["ids"].get("unix-device", ""),
                "icon": _icon({**v, **(mount or {})}),
                "internal": not removable,
                "canEject": (mount or v).get("can_eject") == "1"
                or (drive or {}).get("can_eject") == "1",
                "canUnmount": bool(mount) and mount.get("can_unmount") == "1",
            }
        )
    # network places and anything else mounted with no volume of its own
    for m in mounts:
        if m.get("parent"):
            continue
        loc = m.get("default_location") or m.get("target", "")
        if loc.startswith("file://") or not loc:
            continue
        path = local_path(loc)
        if path and path not in seen:
            seen.add(path)
            out.append(
                {
                    "name": m["name"],
                    "path": path,
                    "mounted": True,
                    "mount": loc,
                    "icon": _icon(m),
                    "internal": False,
                    "canEject": m.get("can_eject") == "1",
                    "canUnmount": m.get("can_unmount") == "1",
                    "network": True,
                }
            )
    for f in fuse_mounts():
        if f["path"] not in seen:
            seen.add(f["path"])
            out.append(f)
    return {"devices": out}


# FUSE file systems a person mounted themselves (sshfs, rclone, an archive opened
# with fuse-archive...): the kernel's list of mounts says which; gvfs's own and
# the portals' are not places. Closed with fusermount3 -u, as they were opened.
FUSE_NOT_PLACES = {
    "fuse.gvfsd-fuse",
    "fuse.portal",
    "fuse.xdg-document-portal",
    "fuse.lxcfs",
    "fuse.snapfuse",
    "fusectl",
    "fuse.gocryptfs-cache",
}


def _a_persons_place(path):
    """Where people mount things: their home (not a hidden folder in it), the
    removable-media folders, /mnt, and the shell's own sshfs/cloud/vault folders."""
    home = os.path.expanduser("~")
    run = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    if any(
        path.startswith(os.path.join(run, d) + "/")
        for d in ("sshfs", "cloud", "vaults")
    ):
        return True
    if path.startswith(home + "/"):
        return not any(p.startswith(".") for p in path[len(home) + 1 :].split("/"))
    return any(
        path == r or path.startswith(r + "/") for r in ("/run/media", "/media", "/mnt")
    )


def fuse_mounts(mountinfo="/proc/self/mountinfo"):
    out = []
    try:
        lines = open(mountinfo, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return out
    for line in lines:
        left, _, right = line.partition(" - ")
        fields, rest = left.split(), right.split()
        if len(fields) < 5 or len(rest) < 2:
            continue
        fstype, source = rest[0], rest[1]
        if not fstype.startswith("fuse.") or fstype in FUSE_NOT_PLACES:
            continue  # fuseblk (NTFS, exFAT on a drive) is gio's: listed as the drive
        path = re.sub(
            r"\\(\d{3})", lambda m: chr(int(m.group(1), 8)), fields[4]
        )  # \040 = a space
        if not _a_persons_place(path):
            continue  # an AppImage's, Flatpak's, a container's: not a place
        kind = fstype.split(".", 1)[1] if "." in fstype else fstype
        name = os.path.basename(path.rstrip("/")) or path
        out.append(
            {
                "name": "%s · %s" % (name, kind),
                "path": path,
                "mounted": True,
                "mount": path,
                "icon": "folder-remote"
                if kind in ("sshfs", "rclone", "davfs", "curlftpfs", "s3fs")
                else "drive-harddisk",
                "internal": False,
                "canEject": False,
                "canUnmount": True,
                "fuse": kind,
                "source": source,
            }
        )
    return out


def mount(what, password=""):
    """A volume opened. An encrypted one (LUKS, BitLocker, VeraCrypt - whatever
    udisks unlocks) makes gio ask for its passphrase on stdin: the one given, or
    an empty one, after which the answer is {"needsPassword": true} and the
    person is asked."""
    if not what:
        return {"error": "nothing to mount"}
    stdin = password + "\n"
    r = (
        _gio("mount", "-d", what, stdin=stdin)
        if what.startswith("/dev/")
        else _gio("mount", what, stdin=stdin)
    )
    if r.returncode != 0:
        err = (r.stderr.strip().splitlines() or ["could not mount it"])[-1]
        locked = bool(
            re.search(r"unlock|passphrase|password|encrypted", err + r.stdout, re.I)
        )
        return {"error": err, "needsPassword": locked}
    for d in devices().get("devices", []):
        if d["mount"] == what and d["path"]:
            return {"path": d["path"]}
    return {"path": "" if what.startswith("/dev/") else local_path(what)}


def unmount(path, eject=False):
    if not path:
        return {"error": "nothing to unmount"}
    if any(f["path"] == path for f in fuse_mounts()):
        tool = shutil.which("fusermount3") or "fusermount3"
        r = subprocess.run([tool, "-u", path], capture_output=True, text=True)
        if r.returncode != 0:
            return {
                "error": (r.stderr.strip().splitlines() or ["it is still in use"])[-1]
            }
        return {"ok": True}
    r = _gio("mount", "-e" if eject else "-u", path)
    if r.returncode != 0:
        return {"error": (r.stderr.strip().splitlines() or ["it is still in use"])[-1]}
    return {"ok": True}


def connect(uri, answers):
    """A server (smb://, sftp://, ftp://, dav://, davs://, nfs://): gio mount asks
    for what it needs on stdin - user, domain, password - in that order; the
    answers given fill them (empty: anonymous where the server allows)."""
    if (uri or "").startswith("ssh://") or re.match(
        r"^[^\s/:@]+@[^\s/:]+:\S*$", uri or ""
    ):
        return connect_sshfs(uri, answers)
    if not re.match(r"^(smb|sftp|ftp|ftps|dav|davs|nfs|afp)://[^\s]+$", uri or ""):
        return {
            "error": "not a server address (smb://, sftp://, ftp://, dav://, davs://, nfs://, ssh://)"
        }
    stdin = (
        "\n".join(
            [
                answers.get("user", ""),
                answers.get("domain", ""),
                answers.get("password", ""),
            ]
        )
        + "\n"
    )
    r = _gio("mount", uri, stdin=stdin)
    if r.returncode != 0:
        err = (r.stderr.strip().splitlines() or ["could not connect"])[-1]
        return {
            "error": err,
            "needsLogin": bool(re.search(r"password|denied|auth|login", err, re.I)),
        }
    return {"path": local_path(uri)}


def network():
    """The servers this network announces (gvfs's network://: mDNS/DNS-SD for SMB,
    NFS, FTP, SFTP and WebDAV, WS-Discovery for Windows machines, the SMB
    workgroup), each with the address Connect to server opens."""
    try:
        r = _gio(
            "list",
            "-a",
            "standard::display-name,standard::target-uri",
            "network:///",
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {"servers": []}
    out, seen = [], set()
    for line in r.stdout.splitlines():
        m = re.search(r"standard::target-uri=(\S+)", line)
        if not m:
            continue
        uri = m.group(1)
        rest = line.replace(m.group(0), "")
        n = re.search(r"standard::display-name=(.*?)\s*$", rest)
        name = n.group(1).strip() if n else uri
        if uri in seen:
            continue
        seen.add(uri)
        scheme = uri.split(":", 1)[0]
        out.append(
            {
                "name": name,
                "uri": uri,
                "kind": {
                    "smb": "Windows share",
                    "sftp": "SSH",
                    "ftp": "FTP",
                    "nfs": "NFS",
                    "dav": "WebDAV",
                    "davs": "WebDAV",
                    "afp": "Mac share",
                }.get(scheme, scheme),
            }
        )
    return {"servers": sorted(out, key=lambda s: (s["name"].lower(), s["uri"]))}


def connect_sshfs(uri, answers):
    """ssh://[user@]host[:port][/path] or user@host:path - mounted with sshfs (FUSE),
    so the files have real paths every app opens and it is quicker than gvfs's
    sftp. Under $XDG_RUNTIME_DIR/sshfs/<host>; listed with the FUSE mounts, closed
    with fusermount3. A password goes on sshfs's stdin; with none, keys only (no
    prompt to hang on). A host seen for the first time is remembered, one already
    known with a different key refused (StrictHostKeyChecking=accept-new)."""
    m = re.match(
        r"^ssh://(?:([^@/\s]+)@)?([^:/\s]+)(?::(\d+))?(/\S*)?$", uri
    ) or re.match(r"^()([^@\s]+@[^:\s]+?)():(\S*)$", uri)
    if not m:
        return {"error": "not an ssh address (ssh://user@host/path or user@host:/path)"}
    user, host, port, path = (
        m.group(1) or answers.get("user", ""),
        m.group(2),
        m.group(3),
        m.group(4) or "",
    )
    if "@" in host:  # the user@host:path form
        user, host = host.split("@", 1)
    tool = shutil.which("sshfs")
    if not tool:
        return {"error": "sshfs is not installed"}
    point = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "sshfs", host)
    if any(f["path"] == point for f in fuse_mounts()):
        return {"path": point}
    os.makedirs(point, exist_ok=True)
    pw = answers.get("password", "")
    opts = (
        "reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,idmap=user,StrictHostKeyChecking=accept-new,"
        + ("password_stdin" if pw else "BatchMode=yes")
    )
    cmd = [
        tool,
        ("%s@%s" % (user, host) if user else host) + ":" + path,
        point,
        "-o",
        opts,
    ] + (["-p", port] if port else [])
    try:
        r = subprocess.run(
            cmd,
            input=(pw + "\n") if pw else None,
            stdin=None if pw else subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return {"error": "the server did not answer"}
    if r.returncode != 0:
        try:
            os.rmdir(point)
        except OSError:
            pass
        err = (r.stderr.strip().splitlines() or ["could not connect"])[-1]
        return {
            "error": err,
            "needsLogin": bool(
                re.search(r"permission denied|password|auth", err, re.I)
            ),
        }
    return {"path": point}


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
            if (not hidden and name.startswith(".")) or not all(
                w in name.lower() for w in words
            ):
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
    names = {e["path"] for e in found}
    for p in inside(root, query, hidden, limit=max(0, limit - len(found))):
        if p in names:
            continue
        try:
            st = os.lstat(p)
        except OSError:
            continue
        e = entry_of(os.path.basename(p), p, st, False)
        e["inside"] = True  # matched by what it says, not its name
        found.append(e)
    return {"entries": found, "truncated": truncated}


def inside(root, query, hidden=False, limit=100, seconds=4.0):
    """Files under root whose text has the words: ripgrep, else grep, bounded in time
    and count. Not the desktop's index (localsearch): it covers only the folders it
    is told to (measured: a folder outside them finds nothing), and this search is
    one folder and what is under it. Paths, absolute."""
    q = query.strip()
    if len(q) < 3 or limit <= 0:
        return []
    root = os.path.abspath(root)
    try:
        if shutil.which("rg"):
            cmd = (
                ["rg", "-l", "-i", "-F", "--max-filesize", "20M", "--max-count", "1"]
                + (["--hidden"] if hidden else [])
                + ["--", q, root]
            )
        else:
            cmd = (
                ["grep", "-rlI", "-i", "-F", "-m", "1"]
                + ([] if hidden else ["--exclude-dir=.*"])
                + ["--", q, root]
            )
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=seconds)
        return [l for l in r.stdout.splitlines() if l][:limit]
    except (OSError, subprocess.TimeoutExpired):
        return []


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
    out = {
        "size": total,
        "files": files,
        "dirs": dirs,
        "partial": partial,
        "count": len(paths),
    }
    if len(paths) == 1:
        p = paths[0]
        try:
            st = os.lstat(p)
            out.update(
                {
                    "path": p,
                    "name": os.path.basename(p),
                    "mtime": int(st.st_mtime * 1000),
                    "atime": int(st.st_atime * 1000),
                    "mode": stat_mod.filemode(st.st_mode),
                    "perm": stat_mod.S_IMODE(st.st_mode),
                    "owner": pwd.getpwuid(st.st_uid).pw_name,
                    "group": grp.getgrgid(st.st_gid).gr_name,
                    "type": "folder"
                    if stat_mod.S_ISDIR(st.st_mode)
                    else (mimetypes.guess_type(p)[0] or "file"),
                }
            )
            birth = getattr(st, "st_birthtime", None)
            if birth:
                out["btime"] = int(birth * 1000)
        except (OSError, KeyError):
            pass
    return out


def batch_rename(pattern, paths):
    """ "Holiday #" -> "Holiday 01.jpg", "Holiday 02.jpg" ... in the order given; the
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
    return os.path.join(
        os.environ.get("XDG_CONFIG_HOME")
        or os.path.join(os.path.expanduser("~"), ".config"),
        "gtk-3.0",
        "bookmarks",
    )


def bookmarks():
    out = []
    try:
        with open(bookmarks_file(), encoding="utf-8") as fh:
            for line in fh:
                uri, _, label = line.strip().partition(" ")
                if uri.startswith("file://"):
                    p = urllib.parse.unquote(uri[7:])
                    out.append(
                        {
                            "name": label or os.path.basename(p.rstrip("/")) or p,
                            "path": p,
                            "icon": "user-bookmarks",
                            "bookmark": True,
                        }
                    )
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
    for key, icon in (
        ("desktop", "user-desktop"),
        ("documents", "user-bookmarks"),
        ("downloads", "folder-download"),
        ("pictures", "user-pictures"),
        ("videos", "user-videos"),
        ("music", "user-music"),
        ("public", "folder-publicshare"),
    ):
        p = dirs.get(key)
        if p and os.path.isdir(p):
            out.append({"name": key.capitalize(), "path": p, "icon": icon})
    # removable drives: what udisks mounted, and what was plugged in by hand
    for base in (
        "/run/media/" + os.path.basename(home),
        "/media/" + os.path.basename(home),
        "/media",
    ):
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
                empty = True  # it cannot be read: not a place either
            if not os.path.ismount(p) and empty:
                continue
            out.append({"name": name, "path": p, "icon": "drive-harddisk"})
    # the person's bookmarks (GTK's file: the same ones GTK apps and their file
    # choosers show), after the folders and drives
    seen = {o["path"] for o in out}
    out += [b for b in bookmarks() if b["path"] not in seen]
    return {"places": out}


# ---- the commands ----------------------------------------------------------------

# commands that read their own stdin: each runs in a process of its own, never over serve
STDIN_COMMANDS = {"connect", "unlock", "compare-save", "serve", "job", "watch"}


def serve():
    """files.py serve: one long-lived process answering requests, one JSON line
    each way - {"id", "args"} in, {"id", "out"} back, where "out" is what
    `files.py <args>` would have printed. Files' listings, stars, renames and
    the like then cost no interpreter start (37 ms a call before, ~1 ms now).
    Requests are read from a copy of stdin; stdin itself is /dev/null, so a
    program a command runs (gio asking for a password) cannot swallow the next
    request - each call saw the same before, as a process of its own."""
    import contextlib
    import io

    requests = os.fdopen(os.dup(0), "r", encoding="utf-8", errors="replace")
    null = os.open(os.devnull, os.O_RDONLY)
    os.dup2(null, 0)
    os.close(null)
    sys.stdin = open(os.devnull, encoding="utf-8")
    answer = sys.stdout
    for line in requests:
        try:
            req = json.loads(line)
            args = [str(a) for a in req.get("args", [])]
        except (ValueError, AttributeError):
            continue
        buf = io.StringIO()
        if args and args[0] in STDIN_COMMANDS:
            buf.write(json.dumps({"error": "%s is not answered over serve" % args[0]}))
        else:
            try:
                with contextlib.redirect_stdout(buf):
                    main(["files.py"] + args)
            except SystemExit:
                pass
            except Exception as e:  # one bad request must not end the service
                buf = io.StringIO(
                    json.dumps({"error": "%s: %s" % (type(e).__name__, e)})
                )
        answer.write(
            json.dumps({"id": req.get("id"), "out": buf.getvalue().strip()}) + "\n"
        )
        answer.flush()
    return 0


def main(argv):
    if len(argv) < 2:
        print(json.dumps({"error": "no command"}))
        return 2
    cmd = argv[1]
    args = argv[2:]
    if cmd == "serve" and argv[0] != "files.py":
        return serve()
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
            print(
                json.dumps(
                    listdir(path, hidden, sort_key, desc, filters, limit, offset)
                )
            )
        except OSError as e:
            print(
                json.dumps(
                    {
                        "error": e.strerror or str(e),
                        "code": errno_name(e.errno),
                        "entries": [],
                        "total": 0,
                    }
                )
            )
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
        print(
            json.dumps(
                rename(args[0] if args else "", args[1] if len(args) > 1 else "")
            )
        )
        return 0
    if cmd == "symlink" and len(args) >= 2:
        print(json.dumps(symlink(args[0], args[1])))
        return 0
    if cmd == "trash":
        print(json.dumps(trash([a for a in args if a])))
        return 0
    if cmd == "places":
        print(json.dumps(places()))
        return 0
    if cmd in ("star-add", "star-remove"):
        print(json.dumps(set_starred(args, cmd == "star-add")))
        return 0
    if cmd == "starred-list":
        print(json.dumps({"starred": starred()}))
        return 0
    if cmd == "templates":
        print(json.dumps(templates()))
        return 0
    if cmd == "chmod-pairs" and args:
        print(json.dumps(chmod_pairs(json.loads(args[0]))))
        return 0
    if cmd == "network" and not args:
        print(json.dumps(network()))
        return 0
    if cmd == "compare-save" and len(args) == 1:
        # a side of Compare after merging (Meld's job): the text on stdin replaces
        # the file, its previous version to the trash so it can be put back.
        # Write beside the target FIRST: trashing before a failing write used to
        # leave the original only in the trash with no answer on stdout.
        target = os.path.abspath(args[0])
        text = sys.stdin.read(MAX_COMPARE_BYTES + 1)
        if len(text) > MAX_COMPARE_BYTES:
            print(json.dumps({"error": "the text is too large to save"}))
            return 1
        tmp = ""
        trashed = False
        try:
            fd, tmp = tempfile.mkstemp(
                prefix=".shani-compare-", dir=os.path.dirname(target)
            )
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(text)
            r = subprocess.run(
                ["gio", "trash", "--", target], capture_output=True, text=True
            )
            if r.returncode != 0:
                raise OSError(
                    (
                        r.stderr.strip().splitlines()
                        or ["the old version could not go to the trash"]
                    )[-1]
                )
            trashed = True
            os.replace(tmp, target)
            tmp = ""
            print(json.dumps({"saved": target}))
            return 0
        except OSError as e:
            msg = str(e)
            if trashed and tmp:
                # the original is already in the trash: keep the merged text
                # on disk and tell the person where to find it
                msg += " (the merged text is kept at " + tmp + ")"
                tmp = ""
            print(json.dumps({"error": msg}))
            return 1
        finally:
            if tmp:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
    if cmd == "compare" and len(args) == 2:
        print(json.dumps(compare(args[0], args[1])))
        return 0
    if cmd == "free":
        print(json.dumps(free_space(args[0] if args else "/")))
        return 0
    if cmd == "thumbs" and args:
        return thumbs(args[0], args[1:])
    if cmd == "devices":
        print(json.dumps(devices()))
        return 0
    if cmd in ("mount", "unlock", "unmount", "eject", "local", "connect"):
        a = args[0] if args else ""
        if cmd == "mount":
            print(json.dumps(mount(a)))
        elif cmd == "unlock":
            try:
                pw = json.loads(sys.stdin.readline() or "{}").get("password", "")
            except (ValueError, AttributeError):
                pw = ""
            print(json.dumps(mount(a, pw)))
        elif cmd == "local":
            print(json.dumps({"path": local_path(a)}))
        elif cmd == "connect":
            try:
                answers = json.loads(sys.stdin.readline() or "{}")
            except ValueError:
                answers = {}
            print(json.dumps(connect(a, answers if isinstance(answers, dict) else {})))
        else:
            print(json.dumps(unmount(a, eject=cmd == "eject")))
        return 0
    if cmd == "job" and len(args) >= 3:
        # the copy engine (pause, verify, conflict rules, skip-and-go-on, checksums,
        # history: TeraCopy's) lives in copyjob.py, beside this file
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import copyjob

        return copyjob.main(args[0], args[1], args[2:])
    if cmd == "scripts":
        d = os.path.join(
            os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
            "nautilus",
            "scripts",
        )
        out = []
        for r, dirs, names in os.walk(d):
            dirs.sort()
            for n in sorted(names):
                p = os.path.join(r, n)
                if os.access(p, os.X_OK) and os.path.isfile(p):
                    out.append(
                        {
                            "name": os.path.relpath(p, d)
                            .replace("/", " › ")
                            .replace("_", " "),
                            "path": p,
                        }
                    )
        print(json.dumps({"scripts": out}))
        return 0
    if cmd == "conflicts" and len(args) >= 2:
        d = os.path.abspath(args[0])
        names = [
            os.path.basename(p.rstrip("/"))
            for p in args[1:]
            if os.path.dirname(os.path.abspath(p)) != d
            and os.path.lexists(os.path.join(d, os.path.basename(p.rstrip("/"))))
        ]
        print(json.dumps({"names": names}))
        return 0
    if cmd == "copy-history":
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import copyjob

        print(json.dumps({"history": copyjob.history()}))
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
            print(
                json.dumps(
                    search(
                        args[0],
                        " ".join(a for a in args[1:] if a != "--hidden"),
                        "--hidden" in args,
                    )
                )
            )
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
