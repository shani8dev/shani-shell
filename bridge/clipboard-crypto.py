#!/usr/bin/env python3
"""clipboard-crypto — encrypt the cliphist database at rest with gpg.

cliphist stores history in a binary DB ($XDG_CACHE_HOME/cliphist/db, or
~/.cache/cliphist/db). This wrapper keeps that file encrypted except during
the brief moment a cliphist command runs:

    clipboard-crypto.py wrap <cliphist args...>
        decrypt DB to a 0600 temp file, run cliphist with CLIPHIST_DB pointing
        at it (or the standard path via a bind-free swap), re-encrypt, restore.
    clipboard-crypto.py enable|disable       manage the encrypted state
    clipboard-crypto.py status               {"encrypted": bool, "hasKey": bool}

The passphrase lives in the Secret Service keyring (item "shani clipboard
encryption"), never in argv or settings. gpg symmetric AES256, passphrase on
a pipe fd. When encryption is off, cliphist runs unwrapped (no behaviour
change). No new dependency: gpg + python-dbus are already present on ShaniOS.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DB = (
    Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    / "cliphist"
    / "db"
)
ENC = DB.with_suffix(".db.gpg")
STATE = (
    Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    / "shani-clipboard-encrypted"
)
LABEL = "shani clipboard encryption"
GPG = "gpg"


def _keyring_get() -> str:
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import passwords

        for i in passwords.list_all().get("items", []):
            if i.get("label") == LABEL:
                return passwords.reveal(i["path"]).get("secret", "")
    except Exception:  # noqa: BLE001
        pass
    return ""


def _keyring_set(value: str) -> None:
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import passwords

        items = passwords.list_all().get("items", [])
        for i in items:
            if i.get("label") == LABEL:
                passwords.set_secret(i["path"], value)
                return
        passwords.add(
            passwords.list_all().get("default", ""),
            LABEL,
            {"application": "shani-shell", "type": "clipboard-key"},
            value,
        )
    except Exception:  # noqa: BLE001
        pass


def _gpg(
    args: list[str], pw: str, data: bytes | None = None
) -> subprocess.CompletedProcess:
    r, w = os.pipe()
    os.write(w, pw.encode() + b"\n")
    os.close(w)
    try:
        return subprocess.run(
            [
                GPG,
                "--batch",
                "--yes",
                "--pinentry-mode",
                "loopback",
                "--passphrase-fd",
                str(r),
            ]
            + args,
            pass_fds=(r,),
            input=data,
            capture_output=True,
            timeout=30,
        )
    finally:
        os.close(r)


def decrypt_db(pw: str, dest: Path) -> bool:
    if not ENC.exists():
        return False
    raw = ENC.read_bytes()
    p = _gpg(["--decrypt"], pw, raw)
    if p.returncode != 0:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(p.stdout)
    os.chmod(dest, 0o600)
    return True


def encrypt_db(pw: str, plain: Path) -> bool:
    p = _gpg(
        ["--symmetric", "--cipher-algo", "AES256", "--output", str(ENC), "-"],
        pw,
        plain.read_bytes(),
    )
    return p.returncode == 0


def enabled() -> bool:
    try:
        return STATE.read_text().strip() == "1"
    except OSError:
        return False


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "status":
        print(json.dumps({"encrypted": enabled(), "hasKey": bool(_keyring_get())}))
        return 0
    if cmd == "enable":
        pw = _keyring_get()
        if not pw:
            pw = (
                subprocess.check_output(
                    ["python3", "-c", "import secrets; print(secrets.token_hex(32))"]
                )
                .decode()
                .strip()
            )
            _keyring_set(pw)
        # encrypt the current DB if present
        if DB.exists() and not ENC.exists():
            encrypt_db(pw, DB)
            DB.unlink()
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text("1")
        print(json.dumps({"ok": True}))
        return 0
    if cmd == "disable":
        pw = _keyring_get()
        if ENC.exists() and pw:
            tmp = DB.with_suffix(".db.tmp")
            if decrypt_db(pw, tmp):
                os.replace(tmp, DB)
                ENC.unlink()
        STATE.write_text("0")
        print(json.dumps({"ok": True}))
        return 0
    if cmd == "wrap":
        args = argv[2:]
        if not enabled() or not ENC.exists():
            os.execvp("cliphist", ["cliphist"] + args)  # noqa: S606 - fixed argv
        pw = _keyring_get()
        if not pw:
            return 1
        tmp = DB.with_suffix(".db.wrap")
        if not decrypt_db(pw, tmp):
            return 1
        # point cliphist at the temp DB via symlink swap (atomic for our use)
        backup = None
        if DB.exists():
            backup = DB.with_suffix(".db.plain")
            os.replace(DB, backup)
        os.symlink(tmp, DB)
        try:
            rc = subprocess.run(["cliphist"] + args, timeout=60).returncode
        finally:
            DB.unlink(missing_ok=True)
            if backup:
                os.replace(backup, DB)
            encrypt_db(pw, tmp)
            tmp.unlink(missing_ok=True)
        return rc
    print(
        "usage: clipboard-crypto.py status|enable|disable|wrap <cliphist args>",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
