"""Archive-safety fixes: entry types, cancellation, multi-folder Compress.

The extraction half is a real unit test against bridge/zipcrypt.py (libarchive
is available here); the QML half is static, since Quickshell needs a session.
"""

import io
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import zipcrypt  # noqa: E402

ARCHIVE = ROOT / "shani/Services/Archive.qml"


def read(rel):
    return (ROOT / rel).read_text()


libarchive = pytest.mark.skipif(
    zipcrypt.ctypes.util.find_library("archive") is None,
    reason="libarchive is not installed",
)


@libarchive
def test_links_are_not_written_and_are_not_listed(tmp_path):
    """A planted `invoice.pdf -> ~/.bashrc` must never reach the destination."""
    arc = tmp_path / "e.tar"
    with tarfile.open(arc, "w") as t:
        link = tarfile.TarInfo("invoice.pdf")
        link.type = tarfile.SYMTYPE
        link.linkname = "/home/u/.bashrc"
        t.addfile(link)
        body = b"fine"
        good = tarfile.TarInfo("ok.txt")
        good.size = len(body)
        t.addfile(good, io.BytesIO(body))

    dest = tmp_path / "out"
    assert zipcrypt.extract(str(arc), str(dest), "") == {"saved": str(dest)}
    assert not (dest / "invoice.pdf").exists()
    assert not (dest / "invoice.pdf").is_symlink()
    assert (dest / "ok.txt").read_bytes() == body

    qml = ARCHIVE.read_text()
    # the listing drops every kind that is not a regular file or a directory
    assert 'kind !== "-" && kind !== "d"' in qml
    assert 'root.pass + "\\n"' in qml  # secret goes on stdin, not argv
    assert 'python3 "$3" extract "$4" "$d"' in qml


def test_cancel_stops_jobs_and_close_clears_the_secret():
    qml = ARCHIVE.read_text()
    assert "function cancel()" in qml
    for job in ("lister", "hardOne", "extractor", "maker", "appender"):
        assert f"{job}.running = false" in qml
    body = qml.split("function close() {", 1)[1].split("}", 1)[0]
    assert "cancel();" in body
    assert 'passphrase = ""' in body
    assert "needsPassword = false" in body


def test_multi_folder_compress_stages_full_paths():
    qml = ARCHIVE.read_text()
    create = qml.split("function create(given, ext, name, pass) {", 1)[1].split(
        "\n    }", 1
    )[0]
    # every input is copied into the staging dir under a unique name, then the
    # staged names (not the basenames of paths[0]'s siblings) are archived
    assert 'for src in "$@"; do' in create
    assert 'cp -a -- "$src" "$stage/$n"' in create
    assert (
        'n="$b ($i)"' in create
    )  # counter named i: k+1 is flagged by check-deps as a program
    assert '"${names[@]}"' in create
    assert 'paths.map(p => p.split("/").pop())' not in create
    assert '.concat(opts, ["--"], paths)' in create
