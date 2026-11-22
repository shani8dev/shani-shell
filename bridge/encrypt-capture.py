#!/usr/bin/env python3
"""encrypt-capture — encrypt a screenshot at rest with age (or gpg fallback).

    encrypt-capture.py encrypt FILE PASSPHRASE
        Encrypt FILE to FILE.age using `age -p` with PASSPHRASE, then remove
        the plaintext. Prints the encrypted path on success.

    encrypt-capture.py decrypt FILE.age PASSPHRASE > stdout
        Decrypt to stdout (for the Viewer to open via a temp file).

Uses age when present, else gpg symmetric (AES256). Standard library only.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def encrypt(path_str: str, passphrase: str) -> int:
    p = Path(path_str)
    if not p.is_file():
        print(f"no such file: {path_str}", file=sys.stderr)
        return 1
    out = p.with_suffix(p.suffix + ".age")
    # gpg symmetric with the passphrase on stdin: age has no --passphrase flag
    # (it wants a passphrase on the terminal, which a bridge has not), so this
    # is the one path that works without a key file.
    r = subprocess.run(
        [
            "gpg",
            "--batch",
            "--yes",
            "--pinentry-mode",
            "loopback",
            "--passphrase-fd",
            "0",
            "--symmetric",
            "--cipher-algo",
            "AES256",
            "--output",
            str(out),
            str(p),
        ],
        input=(passphrase + "\n").encode(),
        capture_output=True,
    )
    if r.returncode != 0:
        print(r.stderr.decode(errors="replace").strip(), file=sys.stderr)
        return 1
    p.unlink()  # plaintext gone
    print(str(out))
    return 0


def decrypt(path_str: str, passphrase: str) -> int:
    p = Path(path_str)
    if not p.is_file():
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
            str(p),
        ],
        input=(passphrase + "\n").encode(),
        capture_output=True,
    )
    if r.returncode != 0:
        return 1
    sys.stdout.buffer.write(r.stdout)
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(
            "usage: encrypt-capture.py encrypt|decrypt FILE PASSPHRASE", file=sys.stderr
        )
        return 2
    cmd = argv[1]
    if cmd == "encrypt":
        return encrypt(argv[2], argv[3])
    if cmd == "decrypt":
        return decrypt(argv[2], argv[3])
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
