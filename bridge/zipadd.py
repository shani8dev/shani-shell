#!/usr/bin/env python3
"""Add files to an existing zip.

bsdtar cannot: libarchive reads a zip back only to write a new one, so `-r` on
an archive that exists answers "Unrecognized archive format" (measured, bsdtar
3.8.11), and the image ships no zip(1). The standard library is the one thing
that can append, and it does it in place.

Files go in under their own name, relative to the folder the archive sits in,
and a name that is already there is replaced - which is what "add" means when a
person adds a file they have just edited. A protected archive is refused: the
library can neither read nor write it, and silently writing a readable copy
would be worse than saying no.

    zipadd.py add <archive.zip> <file> [<file>...]
    zipadd.py names <archive.zip>

One JSON answer on stdout, as every bridge does.
"""

import json
import os
import sys
import zipfile

READABLE = "zip:encryption=zipcrypt", "zip:encryption=aes128", "zip:encryption=aes256"


def is_encrypted(path):
    """A member whose header says it is encrypted: the library can list names
    but cannot read or rewrite the contents."""
    try:
        with zipfile.ZipFile(path) as z:
            return any(i.flag_bits & 0x1 for i in z.infolist())
    except Exception:
        return False


def cmd_add(path, files):
    if not os.path.isfile(path):
        return {"error": "no such archive"}
    if is_encrypted(path):
        return {"error": "protected"}
    parent = os.path.dirname(os.path.abspath(path)) or "."
    try:
        with zipfile.ZipFile(path) as z:
            infos = z.infolist()
            held = {i.filename: z.read(i) for i in infos if not i.is_dir()}
    except Exception as exc:
        return {"error": str(exc)[:120]}

    # the files, by the name they take in the archive (as given when the caller
    # ran in their folder, else beside the archive)
    incoming = []
    for f in files:
        src = f if os.path.isfile(f) else os.path.join(parent, f)
        if os.path.isfile(src):
            incoming.append((os.path.relpath(os.path.abspath(src), parent), src))
    if not incoming:
        return {"ok": True, "added": []}

    # the library can neither delete a member nor rewrite one in place, so a
    # replaced name means writing the archive again: every entry that stays, in
    # its own metadata, then the new files. A zip of any size is read and
    # written once, which is what "replace" has to cost.
    replaced = {name for name, _ in incoming}
    tmp = path + ".shani-add"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as out:
        for i in infos:
            if i.filename in replaced:
                continue
            out.writestr(i, b"" if i.is_dir() else held[i.filename])
        for name, src in incoming:
            out.write(src, name)
    os.replace(tmp, path)
    return {"ok": True, "added": [name for name, _ in incoming]}


def cmd_names(path):
    if not os.path.isfile(path):
        return {"error": "no such archive"}
    try:
        with zipfile.ZipFile(path) as z:
            return [i.filename for i in z.infolist()]
    except Exception as exc:
        return {"error": str(exc)[:120]}


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "usage: zipadd.py add|names <archive> [files...]"}))
        return 2
    cmd, path, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
    if cmd == "add":
        print(json.dumps(cmd_add(path, rest), ensure_ascii=False))
        return 0
    if cmd == "names":
        print(json.dumps(cmd_names(path), ensure_ascii=False))
        return 0
    print(json.dumps({"error": "unknown command: " + cmd}))
    return 2


if __name__ == "__main__":
    sys.exit(main())
