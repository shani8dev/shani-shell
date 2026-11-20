#!/usr/bin/env python3
"""zipcrypt — ZIP files with a password (AES-256, WinZip's way: 7-Zip, WinRAR,
Keka and Linux's own tools open them), made and opened with libarchive - the
library bsdtar is, which the system has - through ctypes, so the password goes
into the library and never onto a command line (where any user reads it in
/proc). Used by lock.py; on its own:

    zipcrypt.py make <out.zip> <path>...   password on stdin
    zipcrypt.py extract <zip> <folder>     password on stdin; {"saved"} or
                                           {"wrongPassword": true}
    zipcrypt.py encrypted <zip>            {"encrypted": bool}

Extracting writes only inside <folder>: a name that climbs out (../, /) or a link
is not written.
"""
from __future__ import annotations

import ctypes
import ctypes.util
import json
import os
import stat
import sys

_lib = None


def lib():
    global _lib
    if _lib is None:
        name = ctypes.util.find_library("archive") or "libarchive.so.13"
        L = ctypes.CDLL(name)
        vp, cp, i64 = ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int64
        sig = {
            "archive_write_new": (vp, []), "archive_write_set_format_zip": (ctypes.c_int, [vp]),
            "archive_write_set_options": (ctypes.c_int, [vp, cp]), "archive_write_set_passphrase": (ctypes.c_int, [vp, cp]),
            "archive_write_open_filename": (ctypes.c_int, [vp, cp]), "archive_write_header": (ctypes.c_int, [vp, vp]),
            "archive_write_data": (ctypes.c_ssize_t, [vp, ctypes.c_char_p, ctypes.c_size_t]),
            "archive_write_close": (ctypes.c_int, [vp]), "archive_write_free": (ctypes.c_int, [vp]),
            "archive_entry_new": (vp, []), "archive_entry_free": (None, [vp]),
            "archive_entry_set_pathname_utf8": (None, [vp, cp]), "archive_entry_set_size": (None, [vp, i64]),
            "archive_entry_set_filetype": (None, [vp, ctypes.c_uint]), "archive_entry_set_perm": (None, [vp, ctypes.c_uint]),
            "archive_entry_set_mtime": (None, [vp, ctypes.c_long, ctypes.c_long]),
            "archive_entry_pathname_utf8": (cp, [vp]), "archive_entry_filetype": (ctypes.c_uint, [vp]),
            "archive_entry_is_encrypted": (ctypes.c_int, [vp]), "archive_entry_perm": (ctypes.c_uint, [vp]),
            "archive_read_new": (vp, []), "archive_read_support_format_zip": (ctypes.c_int, [vp]),
            "archive_read_add_passphrase": (ctypes.c_int, [vp, cp]),
            "archive_read_open_filename": (ctypes.c_int, [vp, cp, ctypes.c_size_t]),
            "archive_read_next_header": (ctypes.c_int, [vp, ctypes.POINTER(vp)]),
            "archive_read_data": (ctypes.c_ssize_t, [vp, ctypes.c_char_p, ctypes.c_size_t]),
            "archive_read_data_skip": (ctypes.c_int, [vp]), "archive_read_free": (ctypes.c_int, [vp]),
            "archive_error_string": (cp, [vp]),
        }
        for n, (res, args) in sig.items():
            f = getattr(L, n)
            f.restype, f.argtypes = res, args
        _lib = L
    return _lib


def _err(a) -> str:
    s = lib().archive_error_string(a)
    return s.decode(errors="replace") if s else "libarchive failed"


def make(out: str, paths: list[str], password: str) -> dict:
    L = lib()
    a = L.archive_write_new()
    try:
        if (L.archive_write_set_format_zip(a) or L.archive_write_set_options(a, b"zip:encryption=aes256")
                or L.archive_write_set_passphrase(a, password.encode()) or L.archive_write_open_filename(a, out.encode())):
            return {"error": _err(a)}
        for top in paths:
            top = os.path.abspath(top.rstrip("/"))
            base = os.path.dirname(top)
            walk = [(top, [], [])] if not os.path.isdir(top) else os.walk(top)
            for d, dirs, files in walk:
                dirs.sort()
                items = [d] + [os.path.join(d, f) for f in sorted(files)] if os.path.isdir(top) else [top]
                for p in items:
                    st = os.lstat(p)
                    if not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)):
                        continue                                  # links, devices: not carried
                    e = L.archive_entry_new()
                    try:
                        L.archive_entry_set_pathname_utf8(e, os.path.relpath(p, base).encode() + (b"/" if stat.S_ISDIR(st.st_mode) else b""))
                        L.archive_entry_set_filetype(e, stat.S_IFMT(st.st_mode))
                        L.archive_entry_set_perm(e, stat.S_IMODE(st.st_mode))
                        L.archive_entry_set_mtime(e, int(st.st_mtime), 0)
                        L.archive_entry_set_size(e, st.st_size if stat.S_ISREG(st.st_mode) else 0)
                        if L.archive_write_header(a, e) < -20:
                            return {"error": _err(a)}
                        if stat.S_ISREG(st.st_mode):
                            with open(p, "rb") as f:
                                while chunk := f.read(1 << 20):
                                    if L.archive_write_data(a, chunk, len(chunk)) < 0:
                                        return {"error": _err(a)}
                    finally:
                        L.archive_entry_free(e)
        if L.archive_write_close(a):
            return {"error": _err(a)}
    finally:
        L.archive_write_free(a)
    return {"saved": out}


def _entries(path: str, password: str = ""):
    L = lib()
    a = L.archive_read_new()
    L.archive_read_support_format_zip(a)
    if password:
        L.archive_read_add_passphrase(a, password.encode())
    if L.archive_read_open_filename(a, path.encode(), 1 << 16):
        L.archive_read_free(a)
        raise OSError(_err(a))
    return a


def encrypted(path: str) -> bool:
    L = lib()
    try:
        a = _entries(path)
    except OSError:
        return False
    try:
        e = ctypes.c_void_p()
        while L.archive_read_next_header(a, ctypes.byref(e)) in (0, -20):
            if L.archive_entry_is_encrypted(e):
                return True
            L.archive_read_data_skip(a)
        return False
    finally:
        L.archive_read_free(a)


def extract(path: str, dest: str, password: str) -> dict:
    """Into dest (made here, and taken back on a wrong password)."""
    L = lib()
    os.mkdir(dest)
    made = []
    a = _entries(path, password)
    try:
        e = ctypes.c_void_p()
        buf = ctypes.create_string_buffer(1 << 20)
        while True:
            r = L.archive_read_next_header(a, ctypes.byref(e))
            if r == 1:
                break
            if r < -20:
                raise OSError(_err(a))
            name = (L.archive_entry_pathname_utf8(e) or b"").decode(errors="replace")
            parts = [x for x in name.split("/") if x not in ("", ".")]
            if not parts or ".." in parts or name.startswith("/"):
                L.archive_read_data_skip(a)
                continue
            out = os.path.join(dest, *parts)
            kind = L.archive_entry_filetype(e)
            if kind == stat.S_IFDIR:
                os.makedirs(out, exist_ok=True)
                continue
            if kind != stat.S_IFREG:
                L.archive_read_data_skip(a)
                continue
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "xb") as f:
                made.append(out)
                while True:
                    n = L.archive_read_data(a, buf, len(buf))
                    if n < 0:
                        msg = _err(a)
                        if "passphrase" in msg.lower() or "decrypt" in msg.lower():
                            raise PermissionError(msg)
                        raise OSError(msg)
                    if n == 0:
                        break
                    f.write(buf.raw[:n])
            os.chmod(out, L.archive_entry_perm(e) & 0o777 or 0o644)
    except PermissionError:
        _take_back(dest, made)
        return {"wrongPassword": True}
    except OSError as x:
        if "passphrase" in str(x).lower():
            _take_back(dest, made)
            return {"wrongPassword": True}
        return {"error": str(x)}
    finally:
        L.archive_read_free(a)
    return {"saved": dest}


def _take_back(dest: str, made: list[str]) -> None:
    """Only what this extraction wrote, then its emptied folders."""
    for p in made:
        try:
            os.remove(p)
        except OSError:
            pass
    for d, _, _ in sorted(os.walk(dest), key=lambda x: -len(x[0])):
        try:
            os.rmdir(d)
        except OSError:
            pass


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if cmd == "encrypted" and len(args) == 1:
        print(json.dumps({"encrypted": encrypted(args[0])}))
        return 0
    if cmd in ("make", "extract") and len(args) >= 2:
        pw = sys.stdin.readline().rstrip("\n")
        r = make(args[0], args[1:], pw) if cmd == "make" else extract(args[0], args[1], pw)
        print(json.dumps(r))
        return 0 if "saved" in r else 1
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
