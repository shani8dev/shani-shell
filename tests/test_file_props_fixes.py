"""Properties sheet correctness: honest creation date, disk usage, symlink target.

The bridge answers `props` as one JSON object; the sheet in FilesPanel.qml shows
those fields. These check both halves stay in sync.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "files.py"
PANEL = ROOT / "shani" / "Modules" / "Files" / "FilesPanel.qml"


def props(*paths):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), "props", *map(str, paths)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def test_created_row_is_labelled_as_inode_change_on_linux(tmp_path):
    """st_birthtime is read when present; otherwise the row says Changed (inode)."""
    f = tmp_path / "x.txt"
    f.write_text("x")
    st = os.lstat(f)
    out = props(f)
    is_ctime = not getattr(st, "st_birthtime", None)
    assert out["btimeIsCtime"] is is_ctime
    if is_ctime:
        assert out["btime"] == int(st.st_ctime * 1000)
    else:
        assert out["btime"] == int(st.st_birthtime * 1000)
    source = BRIDGE.read_text()
    assert "st_birthtime" in source
    qml = PANEL.read_text()
    assert 'Tr.t("Changed (inode)")' in qml
    assert "p.btimeIsCtime" in qml


def test_disk_usage_is_reported_beside_apparent_size(tmp_path):
    f = tmp_path / "x.txt"
    f.write_bytes(b"x" * 8)
    out = props(f)
    st = os.lstat(f)
    assert out["size"] == 8
    assert out["disk"] == st.st_blocks * 512
    assert 'Tr.t("On disk")' in PANEL.read_text()
    assert "p.disk" in PANEL.read_text()


def test_symlink_target_and_broken_flag_are_shown(tmp_path):
    target = tmp_path / "target.txt"
    target.write_text("hi")
    good = tmp_path / "good.link"
    good.symlink_to(target)
    bad = tmp_path / "bad.link"
    missing = tmp_path / "missing.txt"
    bad.symlink_to(missing)

    ok, broken = props(good), props(bad)
    assert ok["linkTarget"] == str(target)
    assert ok["linkBroken"] is False
    assert broken["linkTarget"] == str(missing)
    assert broken["linkBroken"] is True
    qml = PANEL.read_text()
    assert 'Tr.t("Link target")' in qml
    assert "p.linkBroken" in qml
