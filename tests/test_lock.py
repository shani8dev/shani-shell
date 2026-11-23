"""bridge/lock.py: a PDF locked with a PDF password (and opened with it), any
other file or a folder sealed with gpg and unsealed; a wrong password is said as
such; the password never on a command line; nothing overwritten."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "lock.py"
try:
    import pymupdf as fitz
except ImportError:
    fitz = None


def run(*args, pw=""):
    env = dict(os.environ, GNUPGHOME=os.environ.get("_LOCK_GNUPG", ""))
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *map(str, args)],
        input=pw + "\n",
        capture_output=True,
        text=True,
        env=env,
    )
    return json.loads(r.stdout), r.returncode


@pytest.fixture(autouse=True)
def gnupg(tmp_path, monkeypatch):
    g = tmp_path / "gnupg"
    g.mkdir(mode=0o700)
    monkeypatch.setenv("_LOCK_GNUPG", str(g))


def make_pdf(p):
    with fitz.open() as d:
        d.new_page().insert_text((72, 72), "secret plans")
        d.save(p)


@pytest.mark.skipif(fitz is None, reason="no PyMuPDF")
def test_pdf_lock_and_unlock(tmp_path):
    p = tmp_path / "plans.pdf"
    make_pdf(p)
    out, rc = run("lock", p, pw="hunter2")
    assert rc == 0 and out["saved"] == str(tmp_path / "plans (locked).pdf")
    with fitz.open(out["saved"]) as d:
        assert d.needs_pass and not d.authenticate("nope") and d.authenticate("hunter2")
        assert "secret plans" in d[0].get_text()
    assert run("status", out["saved"])[0] == {"locked": True, "kind": "pdf"}
    assert run("unlock", out["saved"], pw="nope") == ({"wrongPassword": True}, 1)
    un, rc = run("unlock", out["saved"], pw="hunter2")
    assert rc == 0 and un["saved"] == str(tmp_path / "plans (unlocked).pdf")
    with fitz.open(un["saved"]) as d:
        assert not d.needs_pass
    v = tmp_path / "view.pdf"
    assert run("open-pdf", out["saved"], v, pw="hunter2")[0] == {"saved": str(v)}
    assert p.exists()  # the original kept


@pytest.mark.skipif(not shutil.which("gpg"), reason="no gpg")
def test_file_sealed_with_gpg(tmp_path):
    f = tmp_path / "notes.txt"
    f.write_text("bank pin 1234")
    out, rc = run("lock", f, pw="open sesame")
    assert rc == 0 and out["saved"] == str(f) + ".gpg"
    assert b"bank pin" not in Path(out["saved"]).read_bytes()
    assert run("unlock", out["saved"], pw="wrong")[0] == {"wrongPassword": True}
    un, rc = run("unlock", out["saved"], pw="open sesame")
    assert rc == 0 and un["saved"] == str(
        tmp_path / "notes 2.txt"
    )  # notes.txt is still there
    assert Path(un["saved"]).read_text() == "bank pin 1234"


@pytest.mark.skipif(
    not (shutil.which("gpg") and shutil.which("bsdtar")), reason="no gpg/bsdtar"
)
def test_folder_sealed_and_unpacked(tmp_path):
    d = tmp_path / "Taxes"
    (d / "2026").mkdir(parents=True)
    (d / "2026" / "form.txt").write_text("x")
    out, rc = run("lock", d, pw="pw")
    assert rc == 0 and out["saved"] == str(tmp_path / "Taxes.tar.gpg")
    un, rc = run("unlock", out["saved"], pw="pw")
    assert rc == 0 and un["saved"] == str(tmp_path / "Taxes 2")
    assert (tmp_path / "Taxes 2" / "2026" / "form.txt").read_text() == "x"
    assert run("unlock", out["saved"], pw="no")[0] == {"wrongPassword": True}
    assert not (tmp_path / "Taxes 3").exists()


def test_no_password_no_lock(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("a")
    assert run("lock", f, pw="")[0] == {"error": "no password given"}


def test_vaults_with_gocryptfs(tmp_path, monkeypatch):
    """A stand-in gocryptfs (the real one needs /dev/fuse): what it is run with,
    the password on its stdin, never on its command line; exit 12 = wrong one."""
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    (bin_ / "gocryptfs").write_text(
        '#!/bin/sh\necho "$*" >> %s/args; read -r pw; echo "$pw" >> %s/pw\n'
        'case "$1" in -init) eval "d=\\${$#}"; touch "$d/gocryptfs.conf" "$d/gocryptfs.diriv"; exit 0;; esac\n'
        '[ "$pw" = right ] || exit 12\nexit 0\n' % (tmp_path, tmp_path)
    )
    (bin_ / "gocryptfs").chmod(0o755)
    monkeypatch.setenv("PATH", "%s:%s" % (bin_, os.environ["PATH"]))
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path / "run"))
    v = tmp_path / "Private"
    assert run("vault-new", v, pw="right") == ({"saved": str(v)}, 0)
    assert (v / "gocryptfs.conf").exists() and oct(v.stat().st_mode & 0o777) == "0o700"
    assert run("vault-new", v, pw="right")[0]["error"].endswith("there already")
    assert run("status", v)[0] == {"locked": True, "kind": "vault", "open": ""}
    assert run("vault-open", v, pw="wrong") == ({"wrongPassword": True}, 1)
    # mount points carry an 8-hex hash of the absolute path so two "Private"
    # vaults cannot collide (bridge/lock.py vault_point)
    import hashlib

    tag = hashlib.sha256(str(v).encode("utf-8")).hexdigest()[:8]
    mount = tmp_path / "run" / "vaults" / ("Private-" + tag)
    assert not mount.exists()
    assert run("vault-open", v, pw="right") == ({"saved": str(mount)}, 0)
    args = (tmp_path / "args").read_text()
    assert "right" not in args and "-passfile /dev/stdin" in args
    assert (tmp_path / "pw").read_text().split() == ["right", "wrong", "right"]


def test_zip_with_a_password(tmp_path):
    d = tmp_path / "Taxes"
    (d / "2026").mkdir(parents=True)
    (d / "2026" / "form.txt").write_text("secret form")
    out, rc = run("lock", d, "--zip", pw="pw")
    assert rc == 0 and out["saved"] == str(tmp_path / "Taxes.zip")
    assert b"secret form" not in Path(out["saved"]).read_bytes()
    assert run("status", out["saved"])[0] == {"locked": True, "kind": "zip"}
    assert run("unlock", out["saved"], pw="nope")[0] == {"wrongPassword": True}
    assert not (tmp_path / "Taxes 2").exists()  # taken back
    un, rc = run("unlock", out["saved"], pw="pw")
    assert (
        rc == 0
        and (Path(un["saved"]) / "Taxes" / "2026" / "form.txt").read_text()
        == "secret form"
    )
    if shutil.which("7z"):  # what a Windows person opens it with
        r = subprocess.run(
            ["7z", "x", "-ppw", "-o%s" % (tmp_path / "7z"), out["saved"]],
            capture_output=True,
        )
        assert (
            r.returncode == 0
            and (tmp_path / "7z" / "Taxes" / "2026" / "form.txt").read_text()
            == "secret form"
        )
    f = tmp_path / "a.txt"
    f.write_text("x")
    assert run("lock", f, "--zip", pw="pw")[0] == {"saved": str(tmp_path / "a.zip")}
    plain = tmp_path / "plain.zip"
    subprocess.run(
        [
            "python3",
            "-c",
            "import zipfile,sys; zipfile.ZipFile(sys.argv[1],'w').writestr('x','y')",
            str(plain),
        ]
    )
    assert run("status", plain)[0] == {"locked": False, "kind": "zip"}
