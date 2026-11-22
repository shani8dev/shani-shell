#!/usr/bin/env python3
"""note-crypto — symmetric encryption for locked notes, with gpg.

    note-crypto.py encrypt PATH   stdin: {"passphrase": "...", "text": "..."}
                                  writes PATH (gpg symmetric, AES256) and
                                  removes any plaintext file beside it.
    note-crypto.py decrypt PATH   stdin: {"passphrase": "..."}
                                  prints the plaintext to stdout.
    note-crypto.py seal PATH PASSPHRASE
                                  (convenience: encrypt a plaintext file)

The passphrase is never on a command line: it is read from this script's
stdin (Quickshell writes it with Process.stdinEnabled) and handed to gpg on
its own stdin via --passphrase-fd 0. Plaintext only ever lives in this
process's memory or a 0600 temp file under /dev/shm, deleted on exit.
Requires gpg (present on ShaniOS); no new dependencies.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def gpg_available() -> bool:
    return shutil.which("gpg") is not None


def encrypt(path_str: str, passphrase: str, text: str) -> int:
    if not passphrase:
        print("empty passphrase", file=sys.stderr)
        return 2
    if not gpg_available():
        print("gpg is not installed", file=sys.stderr)
        return 1
    dest = Path(path_str)
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        prefix="shani-note-", dir="/dev/shm" if os.path.isdir("/dev/shm") else None
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.chmod(tmp, 0o600)
        r = subprocess.run(
            [
                "gpg",
                "--batch",
                "--yes",
                "--pinentry-mode",
                "loopback",
                "--passphrase-fd",
                "0",
                "--cipher-algo",
                "AES256",
                "--symmetric",
                "--output",
                str(dest),
                tmp,
            ],
            input=(passphrase + "\n").encode(),
            capture_output=True,
        )
        if r.returncode != 0:
            print(r.stderr.decode(errors="replace").strip(), file=sys.stderr)
            return 1
        # the plaintext file this encrypted copy replaces must go
        plain = dest.with_suffix("")
        if plain != dest and plain.is_file():
            plain.unlink()
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    return 0


def decrypt(path_str: str, passphrase: str) -> int:
    if not gpg_available():
        print("gpg is not installed", file=sys.stderr)
        return 1
    src = Path(path_str)
    if not src.is_file():
        return 1
    r = subprocess.run(
        [
            "gpg",
            "--batch",
            "--yes",
            "--pinentry-mode",
            "loopback",
            "--passphrase-fd",
            "0",
            "--decrypt",
            str(src),
        ],
        input=(passphrase + "\n").encode(),
        capture_output=True,
    )
    if r.returncode != 0:
        return {"error": "Wrong passphrase or a damaged note"}
    return {"ok": True, "text": r.stdout.decode(errors="replace")}


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "probe":
        print(json.dumps({"gpg": gpg_available()}))
        return 0
    if len(argv) < 3:
        print("usage: note-crypto.py encrypt|decrypt PATH", file=sys.stderr)
        return 2
    cmd = argv[1]
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        print("stdin is not JSON", file=sys.stderr)
        return 2
    passphrase = str(payload.get("passphrase", "") or "")
    if cmd == "encrypt":
        err = encrypt(argv[2], passphrase, str(payload.get("text", "") or ""))
        r = {"error": err} if err else {"ok": True}
    elif cmd == "decrypt":
        r = decrypt(argv[2], passphrase)
    else:
        return 2
    print(json.dumps(r))
    return 1 if "error" in r else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
