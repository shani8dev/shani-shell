"""bridge/encrypt-capture.py: encrypting a screenshot at rest.

The point of this bridge is that the plaintext does not stay on the disk, so
the tests are about the lifecycle (encrypt, then the original is gone) and the
round trip (what comes back is what went in), plus the two ways it can be
asked to do something impossible.
"""

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge/encrypt-capture.py"

gpg = pytest.mark.skipif(
    subprocess.run(["sh", "-c", "command -v gpg"], capture_output=True).returncode != 0,
    reason="gpg is not installed",
)


def run(*args):
    """Bytes both ways: a decrypted screenshot is not text."""
    return subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        capture_output=True,
        timeout=120,
    )


def text(out):
    return out.stdout.decode(errors="replace")


# ---- the round trip ---------------------------------------------------------


@gpg
def test_encrypt_then_decrypt_returns_the_same_bytes(tmp_path):
    src = tmp_path / "shot.png"
    src.write_bytes(b"\x89PNG\r\n\x1a\nnot really a picture")
    out = run("encrypt", str(src), "pw")
    assert out.returncode == 0, out.stderr
    enc = Path(text(out).strip())
    assert enc.exists() and enc.name == "shot.png.age"
    back = run("decrypt", str(enc), "pw")
    assert back.returncode == 0
    assert back.stdout == src.read_bytes()  # the plaintext is gone by now


@gpg
def test_the_plaintext_is_removed(tmp_path):
    src = tmp_path / "shot.png"
    src.write_text("secret")
    run("encrypt", str(src), "pw")
    assert not src.exists()


@gpg
def test_a_wrong_passphrase_decrypts_to_nothing(tmp_path):
    src = tmp_path / "shot.png"
    src.write_text("secret")
    enc = Path(text(run("encrypt", str(src), "right")).strip())
    back = run("decrypt", str(enc), "wrong")
    assert back.returncode != 0
    assert back.stdout == ""


# ---- what it cannot do ------------------------------------------------------


def test_a_file_that_is_not_there_is_a_sentence(tmp_path):
    out = run("encrypt", str(tmp_path / "nope.png"), "pw")
    assert out.returncode == 1
    assert "no such file" in out.stderr.decode()


def test_decrypting_a_file_that_is_not_there_fails(tmp_path):
    assert run("decrypt", str(tmp_path / "nope.age"), "pw").returncode != 0


def test_a_missing_command_says_how(tmp_path):
    out = run("encrypt", str(tmp_path / "x"))
    assert out.returncode == 2
    assert "usage" in out.stderr.decode().lower()


def test_an_unknown_command_is_refused():
    out = run("nonsense", "a", "b")
    assert out.returncode == 2
