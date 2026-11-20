"""bridge/serve.py: a folder to phones behind a secret link - listed, downloaded,
added to only with --upload and never over a file; nothing outside the folder,
nothing hidden, nothing without the secret."""
import json
import os
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import pytest

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "serve.py"


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p


@pytest.fixture
def served(tmp_path):
    def start(*extra):
        port = free_port()
        p = subprocess.Popen([sys.executable, str(BRIDGE), str(tmp_path / "share"), *extra], stdout=subprocess.PIPE, text=True,
                             env=dict(os.environ, SHANI_SERVE_PORT=str(port)))
        first = json.loads(p.stdout.readline())
        procs.append(p)
        token = first["url"].rstrip("/").rsplit("/", 1)[1]
        return "http://127.0.0.1:%d/%s/" % (port, token), p
    procs = []
    d = tmp_path / "share"; (d / "sub").mkdir(parents=True)
    (d / "photo.jpg").write_bytes(b"JPEG"); (d / ".secret").write_text("no"); (d / "sub" / "a.txt").write_text("a")
    (tmp_path / "outside.txt").write_text("private"); os.symlink(tmp_path / "outside.txt", d / "link.txt")
    yield start
    for p in procs:
        p.terminate(); p.wait(5)


def get(url, method="GET", data=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method=method, data=data), timeout=5) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""


def test_lists_and_hands_out(served):
    url, _ = served()
    code, body = get(url)
    assert code == 200 and b"photo.jpg" in body and b"sub" in body and b".secret" not in body and b"<input" not in body
    assert get(url + "photo.jpg") == (200, b"JPEG")
    assert get(url + "sub/a.txt") == (200, b"a")


def test_nothing_without_the_secret_or_outside(served):
    url, _ = served()
    base = url.rsplit("/", 2)[0] + "/"
    assert get(base)[0] == 404 and get(base + "wrongtoken/photo.jpg")[0] == 404
    assert get(url + ".secret")[0] == 404
    assert get(url + "link.txt")[0] == 404                 # a link that points out
    assert get(url + "..%2Foutside.txt")[0] == 404
    assert get(url + "x.txt", "PUT", b"no")[0] == 403      # read-only unless --upload


def test_upload_adds_never_overwrites(served, tmp_path):
    url, p = served("--upload")
    assert b"<input" in get(url)[1]
    assert get(url + "photo.jpg", "PUT", b"NEW")[0] == 201
    assert (tmp_path / "share" / "photo.jpg").read_bytes() == b"JPEG"
    assert (tmp_path / "share" / "photo 2.jpg").read_bytes() == b"NEW"
    assert get(url + "sub/b.txt", "PUT", b"b")[0] == 201 and (tmp_path / "share" / "sub" / "b.txt").read_text() == "b"
    assert get(url + ".hidden", "PUT", b"x")[0] == 403
    assert json.loads(p.stdout.readline()) == {"got": str(tmp_path / "share" / "photo 2.jpg")}
