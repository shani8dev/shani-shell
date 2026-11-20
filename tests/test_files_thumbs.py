"""bridge/files.py thumbs: the freedesktop thumbnail cache (thumbnail-spec).

A stand-in .thumbnailer in a scratch XDG_DATA_DIRS (its Exec writes a PNG to %o)
for video/mp4: the thumbnail lands at thumbnails/normal/<md5 of the URI>.png,
is reused while newer than the file, made again when the file changes; a type
no thumbnailer has is marked in fail/shani-files and not tried again."""
import hashlib
import importlib.util
import io
import json
import os
import time
import urllib.parse
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("files_th", Path(__file__).resolve().parent.parent / "bridge" / "files.py")
files = importlib.util.module_from_spec(spec)
spec.loader.exec_module(files)
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 32


@pytest.fixture
def env(tmp_path, monkeypatch):
    share = tmp_path / "share" / "thumbnailers"; share.mkdir(parents=True)
    tool = tmp_path / "thumb.sh"
    (tmp_path / "made.png").write_bytes(PNG)
    tool.write_text(f"#!/bin/sh\necho \"$@\" >> {tmp_path}/calls\ncp {tmp_path}/made.png \"$2\"\n")
    tool.chmod(0o755)
    (share / "fake.thumbnailer").write_text(f"[Thumbnailer Entry]\nTryExec={tool}\nExec={tool} %i %o %s\nMimeType=video/mp4;\n")
    monkeypatch.setenv("XDG_DATA_DIRS", str(tmp_path / "share"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "nothing"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    return tmp_path


def md5(p):
    return hashlib.md5(("file://" + urllib.parse.quote(str(p))).encode()).hexdigest()


def test_made_where_the_spec_says_and_reused(env):
    v = env / "clip.mp4"; v.write_bytes(b"video")
    out = io.StringIO()
    files.thumbs("normal", [str(v)], out=out)
    want = env / "cache" / "thumbnails" / "normal" / (md5(v) + ".png")
    assert json.loads(out.getvalue()) == {"path": str(v), "thumb": str(want)}
    assert want.read_bytes() == PNG
    assert (env / "calls").read_text().split()[2] == "128"                 # %s: the normal size
    files.thumbs("normal", [str(v)], out=io.StringIO())
    assert len((env / "calls").read_text().splitlines()) == 1               # the cache, not a second run
    time.sleep(0.01); os.utime(v, (time.time() + 5, time.time() + 5))      # the file changed
    files.thumbs("normal", [str(v)], out=io.StringIO())
    assert len((env / "calls").read_text().splitlines()) == 2


def test_no_thumbnailer_is_marked_and_not_tried_again(env, monkeypatch):
    f = env / "notes.xyz"; f.write_text("x")
    out = io.StringIO()
    files.thumbs("large", [str(f)], out=out)
    assert out.getvalue() == ""
    assert (env / "cache" / "thumbnails" / "fail" / "shani-files" / (md5(f) + ".png")).exists()
    monkeypatch.setattr(files, "_thumbnailers", lambda: (_ for _ in ()).throw(AssertionError("asked again")))
    assert files.thumb_for(str(f), "large", None) == ""


@pytest.mark.skipif(not __import__("shutil").which("pdftoppm"), reason="no pdftoppm")
def test_a_pdf_by_pdftoppm(env, tmp_path):
    pdf = tmp_path / "doc.pdf"
    pdf.write_bytes(b"%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj "
                    b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n")
    t = files.thumb_for(str(pdf), "normal", [])
    assert t.endswith(md5(pdf) + ".png") and Path(t).read_bytes()[:8] == PNG[:8]
