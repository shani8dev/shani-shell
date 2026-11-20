#!/usr/bin/env python3
"""lock — files and folders locked with a password, and unlocked again.

    lock.py status <path>              {"locked": bool, "kind": "pdf" | "gpg" | ""}
    lock.py lock <path> [--trash] [--zip]
                                       password on stdin; prints {"saved": path};
                                       --zip: a ZIP with a password (AES-256: 7-Zip,
                                       WinRAR and Keka open it) instead of gpg
    lock.py unlock <path>              password on stdin; prints {"saved": path}
                                       or {"wrongPassword": true}
    lock.py vault-new <folder>         password on stdin: a new, empty encrypted folder
                                       (gocryptfs) - {"saved": folder}
    lock.py vault-open <folder>        password on stdin: it opened (gocryptfs, FUSE) at
                                       $XDG_RUNTIME_DIR/vaults/<name> - {"saved": that};
                                       closed as any FUSE mount (files.py unmount)
    lock.py open-pdf <path> <out>      password on stdin: a locked PDF's unlocked
                                       copy written to <out> (the Document Viewer's,
                                       in its private cache) - {"saved": out}

A PDF gets a PDF password (AES-256, PyMuPDF): every PDF reader asks for it, and
it is still a PDF. Anything else - a file, or a folder (packed first, tar) - is
sealed with GnuPG (symmetric AES-256), already on the system, into "<name>.gpg"
or "<name>.tar.gpg"; Files unlocks those, and any computer with gpg can. The
password travels on a pipe, never on a command line (ps shows those), and gpg is
told not to keep it (--no-symkey-cache). What is made goes beside the original
under a name not taken; the original stays unless --trash (then it goes to the
trash, which can be emptied - locking is about what you send or keep elsewhere).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

try:
    import pymupdf as fitz
except ImportError:
    try:
        import fitz
    except ImportError:
        fitz = None


def _free(path: str) -> str:
    """path, or "name 2.ext", "name 3.ext"... - whichever is not taken."""
    if not os.path.lexists(path):
        return path
    d, n = os.path.split(path)
    stem, ext = (n[:-8], n[-8:]) if n.endswith(".tar.gpg") else os.path.splitext(n)
    i = 2
    while os.path.lexists(os.path.join(d, "%s %d%s" % (stem, i, ext))):
        i += 1
    return os.path.join(d, "%s %d%s" % (stem, i, ext))


def _is_pdf(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(5) == b"%PDF-"
    except OSError:
        return False


def is_vault(path: str) -> bool:
    return os.path.isdir(path) and os.path.isfile(os.path.join(path, "gocryptfs.conf"))


def vault_point(path: str) -> str:
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "vaults", os.path.basename(os.path.abspath(path).rstrip("/")))


def _mounted(point: str) -> bool:
    try:
        with open("/proc/self/mountinfo", encoding="utf-8", errors="replace") as f:
            return any(line.split()[4] == point for line in f)
    except OSError:
        return False


def status(path: str) -> dict:
    if is_vault(path):
        point = vault_point(path)
        return {"locked": not _mounted(point), "kind": "vault", "open": point if _mounted(point) else ""}
    if path.endswith(".gpg") and os.path.isfile(path):
        return {"locked": True, "kind": "gpg"}
    if path.lower().endswith(".zip") and os.path.isfile(path):
        return {"locked": _zip().encrypted(path), "kind": "zip"}
    if _is_pdf(path) and fitz is not None:
        try:
            with fitz.open(path) as doc:
                return {"locked": bool(doc.needs_pass), "kind": "pdf"}
        except (RuntimeError, ValueError):
            return {"locked": False, "kind": "pdf"}
    return {"locked": False, "kind": ""}


def _gpg(args: list[str], password: str, **kw) -> subprocess.CompletedProcess:
    r, w = os.pipe()
    os.write(w, password.encode() + b"\n")
    os.close(w)
    try:
        return subprocess.run(["gpg", "--batch", "--yes", "--quiet", "--no-symkey-cache", "--pinentry-mode", "loopback",
                               "--passphrase-fd", str(r)] + args, pass_fds=(r,), capture_output=True, **kw)
    finally:
        os.close(r)


def _zip():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import zipcrypt
    return zipcrypt


def lock(path: str, password: str, trash: bool = False, as_zip: bool = False) -> dict:
    path = os.path.abspath(path.rstrip("/"))
    if not password:
        return {"error": "no password given"}
    if not os.path.exists(path):
        return {"error": "it is not there any more"}
    if as_zip:
        out = _free(os.path.splitext(path)[0] + ".zip" if os.path.isfile(path) else path + ".zip")
        r = _zip().make(out, [path], password)
        if "error" in r:
            _drop(out)
            return r
    elif _is_pdf(path) and fitz is not None:
        with fitz.open(path) as doc:
            if doc.needs_pass:
                return {"error": "it has a password already"}
            stem = os.path.splitext(path)[0]
            out = _free(stem + " (locked).pdf")
            doc.save(out, encryption=fitz.PDF_ENCRYPT_AES_256, user_pw=password, owner_pw=password,
                     permissions=int(fitz.PDF_PERM_ACCESSIBILITY | fitz.PDF_PERM_PRINT | fitz.PDF_PERM_COPY | fitz.PDF_PERM_ANNOTATE),
                     garbage=1)
    elif os.path.isdir(path):
        out = _free(path + ".tar.gpg")
        tar = subprocess.Popen(["bsdtar", "-cf", "-", "-C", os.path.dirname(path), os.path.basename(path)], stdout=subprocess.PIPE)
        r = _gpg(["--symmetric", "--cipher-algo", "AES256", "-o", out], password, stdin=tar.stdout)
        tar.stdout.close()
        if tar.wait() != 0 or r.returncode != 0:
            _drop(out)
            return {"error": (r.stderr.decode(errors="replace").strip().splitlines() or ["the folder could not be packed"])[-1]}
    else:
        out = _free(path + ".gpg")
        r = _gpg(["--symmetric", "--cipher-algo", "AES256", "-o", out, path], password)
        if r.returncode != 0:
            _drop(out)
            return {"error": (r.stderr.decode(errors="replace").strip().splitlines() or ["it could not be locked"])[-1]}
    if trash:
        subprocess.run(["gio", "trash", "--", path], capture_output=True)
    return {"saved": out}


# ---- vaults: encrypted folders (gocryptfs) - the files stay encrypted on the disk,
#      each on its own (so a backup or a sync carries only what changed), and an
#      opened vault is a FUSE mount showing them in the clear while it is open
def vault_new(path: str, password: str) -> dict:
    path = os.path.abspath(path.rstrip("/"))
    if not password:
        return {"error": "no password given"}
    if os.path.lexists(path):
        return {"error": "%s is there already" % os.path.basename(path)}
    os.mkdir(path, 0o700)
    r = subprocess.run(["gocryptfs", "-init", "-q", "-passfile", "/dev/stdin", path],
                       input=password + "\n", capture_output=True, text=True)
    if r.returncode != 0:
        try:
            for n in os.listdir(path):                    # only what gocryptfs -init made
                if n in ("gocryptfs.conf", "gocryptfs.diriv"):
                    os.remove(os.path.join(path, n))
            os.rmdir(path)
        except OSError:
            pass
        return {"error": (r.stderr.strip().splitlines() or ["the encrypted folder could not be made"])[-1]}
    return {"saved": path}


def vault_open(path: str, password: str) -> dict:
    path = os.path.abspath(path.rstrip("/"))
    if not is_vault(path):
        return {"error": "not an encrypted folder"}
    point = vault_point(path)
    if _mounted(point):
        return {"saved": point}
    os.makedirs(point, exist_ok=True)
    r = subprocess.run(["gocryptfs", "-q", "-passfile", "/dev/stdin", path, point],
                       input=password + "\n", capture_output=True, text=True)
    if r.returncode != 0:
        try:
            os.rmdir(point)
        except OSError:
            pass
        if r.returncode == 12:                             # gocryptfs: "password incorrect"
            return {"wrongPassword": True}
        return {"error": (r.stderr.strip().splitlines() or ["it could not be opened"])[-1]}
    return {"saved": point}


def _drop(made: str) -> None:
    """Takes back only the half-made file this run created."""
    try:
        os.remove(made)
    except OSError:
        pass


def unlock(path: str, password: str, out: str = "") -> dict:
    path = os.path.abspath(path)
    st = status(path)
    if not st["locked"]:
        return {"error": "it has no password"}
    if st["kind"] == "pdf":
        with fitz.open(path) as doc:
            if not doc.authenticate(password):
                return {"wrongPassword": True}
            out = out or _free(os.path.splitext(path)[0].removesuffix(" (locked)") + " (unlocked).pdf")
            doc.save(out, encryption=fitz.PDF_ENCRYPT_NONE, garbage=1)
        return {"saved": out}
    if st["kind"] == "zip":
        return _zip().extract(path, _free(path[:-4]), password)
    # gpg: a folder's .tar.gpg unpacked beside it, a file's .gpg as the file
    if path.endswith(".tar.gpg"):
        dest = _free(path[:-8])
        os.mkdir(dest)
        r = _gpg(["--decrypt", "-o", "-", path], password, timeout=3600)
        if r.returncode != 0:
            os.rmdir(dest)
            return _gpg_error(r)
        x = subprocess.run(["bsdtar", "-xf", "-", "-C", dest, "--strip-components", "1"], input=r.stdout, capture_output=True)
        if x.returncode != 0:
            return {"error": (x.stderr.decode(errors="replace").strip().splitlines() or ["it could not be unpacked"])[-1]}
        return {"saved": dest}
    out = _free(path[:-4])
    r = _gpg(["--decrypt", "-o", out, path], password)
    if r.returncode != 0:
        _drop(out)
        return _gpg_error(r)
    return {"saved": out}


def _gpg_error(r) -> dict:
    err = r.stderr.decode(errors="replace")
    if "Bad session key" in err or "decryption failed" in err or "bad passphrase" in err.lower():
        return {"wrongPassword": True}
    return {"error": (err.strip().splitlines() or ["it could not be unlocked"])[-1]}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if cmd == "status" and len(args) == 1:
        print(json.dumps(status(args[0])))
        return 0
    if cmd in ("lock", "unlock", "open-pdf", "vault-new", "vault-open") and args:
        if fitz is None and cmd == "open-pdf":
            print(json.dumps({"error": "PyMuPDF (python-pymupdf) is not installed"}))
            return 3
        password = sys.stdin.readline().rstrip("\n")
        try:
            if cmd == "lock" and set(args[1:]) <= {"--trash", "--zip"}:
                r = lock(args[0], password, trash="--trash" in args[1:], as_zip="--zip" in args[1:])
            elif cmd == "unlock" and len(args) == 1:
                r = unlock(args[0], password)
            elif cmd == "vault-new" and len(args) == 1:
                r = vault_new(args[0], password)
            elif cmd == "vault-open" and len(args) == 1:
                r = vault_open(args[0], password)
            elif cmd == "open-pdf" and len(args) == 2:
                r = unlock(args[0], password, out=args[1])
            else:
                r = None
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as e:
            r = {"error": str(e)}
        if r is not None:
            print(json.dumps(r))
            return 0 if "saved" in r else 1
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
