"""bridge/drives.py against a stand-in udisks2 on a private session bus: only the
removable drive is listed and accepted, a format is a fresh MBR table plus one
partition, a write lands the image's bytes (unpacked if packed) through
OpenForRestore after unmounting what was mounted."""
import json
import lzma
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
BRIDGE = HERE.parent / "bridge" / "drives.py"
FAKE = HERE / "fixtures" / "fake_udisks.py"
pytestmark = pytest.mark.skipif(not shutil.which("dbus-run-session"), reason="no dbus-run-session")


def run(tmp_path, *args, stdin=""):
    script = (f"rm -f {tmp_path}/ready; "
              f'{sys.executable} -W ignore {FAKE} & f=$!; i=0; while [ ! -e {tmp_path}/ready ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; '
              f'{sys.executable} {BRIDGE} "$@"; echo "rc=$?"; kill $f')
    env = dict(os.environ, FAKE_UDISKS_DIR=str(tmp_path), SHANI_UDISKS_BUS="session")
    r = subprocess.run(["dbus-run-session", "--", "sh", "-c", script, "sh", *args], input=stdin, capture_output=True, text=True, timeout=60, env=env)
    lines = r.stdout.strip().splitlines()
    return [json.loads(x) for x in lines[:-1]], int(lines[-1][3:])


def calls(tmp_path):
    p = tmp_path / "calls"
    return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []


def test_lists_only_the_removable_drive(tmp_path):
    (out,), rc = run(tmp_path, "list")
    assert rc == 0 and [d["device"] for d in out] == ["/dev/sdb"]
    assert out[0]["name"] == "SanDisk Cruzer Blade"
    assert out[0]["parts"] == [{"device": "/dev/sdb1", "label": "STICK", "fs": "vfat", "mounted": ["/run/media/me/STICK"]}]


def test_format_is_a_table_and_one_partition(tmp_path):
    (out,), rc = run(tmp_path, "format", "/dev/sdb", "exfat", "PHOTOS")
    assert rc == 0 and out["ok"]
    assert calls(tmp_path) == [["sdb1", "Unmount", [{}]],
                               ["sdb", "Format", ["dos", {}]],
                               ["sdb", "CreatePartitionAndFormat", [1048576, 0, "0x07", "", "exfat", {}, {"label": "PHOTOS"}]]]


def test_the_computers_own_disk_is_refused(tmp_path):
    (out,), rc = run(tmp_path, "format", "/dev/nvme0n1", "exfat", "X")
    assert rc == 1 and "not a removable drive" in out["error"] and calls(tmp_path) == []


def test_write_raw_and_packed(tmp_path):
    img = tmp_path / "os.img"; img.write_bytes(os.urandom(9 << 20))
    out, rc = run(tmp_path, "write", str(img), "/dev/sdb")
    assert rc == 0 and out[-1] == {"ok": True, "written": 9 << 20} and out[-2]["done"] == out[-2]["total"]
    assert (tmp_path / "sdb.img").read_bytes() == img.read_bytes()
    assert [c[1] for c in calls(tmp_path)] == ["Unmount", "OpenForRestore"]
    xz = tmp_path / "os.img.xz"; xz.write_bytes(lzma.compress(img.read_bytes()))
    out, rc = run(tmp_path, "write", str(xz), "/dev/sdb")
    assert rc == 0 and out[-1]["written"] == 9 << 20
    assert (tmp_path / "sdb.img").read_bytes() == img.read_bytes()


def test_an_image_bigger_than_the_drive_is_refused(tmp_path):
    big = tmp_path / "big.img"
    with open(big, "wb") as f:
        f.truncate((1 << 30) + 1)
    (out,), rc = run(tmp_path, "write", str(big), "/dev/sdb")
    assert rc == 1 and "bigger" in out["error"] and calls(tmp_path) == []


def test_mount_image_read_only(tmp_path):
    iso = tmp_path / "arch.iso"; iso.write_bytes(b"\0" * 4096)
    (out,), rc = run(tmp_path, "mount-image", str(iso))
    assert rc == 0 and out == {"paths": ["/run/media/me/ARCH_202611"], "device": "/dev/loop0"}
    assert calls(tmp_path) == [["Manager", "LoopSetup", ["arch.iso", {"read-only": True}]],
                               ["loop0", "SetAutoclear", [True, {}]], ["loop0", "Mount", []]]


def test_format_encrypted_takes_the_password_from_stdin(tmp_path):
    (out,), rc = run(tmp_path, "format", "/dev/sdb", "btrfs", "SAFE", "--encrypt", stdin="s3cret\n")
    assert rc == 0 and out["ok"]
    assert calls(tmp_path)[-1] == ["sdb", "CreatePartitionAndFormat", [1048576, 0, "0x83", "", "btrfs", {},
                                   {"label": "SAFE", "encrypt.passphrase": "s3cret", "encrypt.type": "luks2"}]]
    (out,), rc = run(tmp_path, "format", "/dev/sdb", "zfs", "X")
    assert rc == 1 and "unknown file system" in out["error"]


def test_backup_a_drive_to_an_image(tmp_path):
    (tmp_path / "sdb.disk").write_bytes(b"DISK" * 300000)
    out = tmp_path / "stick.img"
    lines, rc = run(tmp_path, "backup", "/dev/sdb", str(out))
    assert rc == 0 and lines[-1]["ok"] and out.read_bytes() == b"DISK" * 300000
    lines, rc = run(tmp_path, "backup", "/dev/sdb", str(out))
    assert rc == 1 and "there already" in lines[-1]["error"]
    lines, rc = run(tmp_path, "backup", "/dev/nvme0n1", str(tmp_path / "own.img"))
    assert rc == 1 and not (tmp_path / "own.img").exists()


def test_change_a_locked_drives_password(tmp_path, monkeypatch):
    monkeypatch.setenv("FAKE_LUKS", "1")
    (out,), rc = run(tmp_path, "passphrase", "/dev/sdb", stdin=json.dumps({"old": "old-pw", "new": "n3w"}) + "\n")
    assert rc == 0 and out == {"ok": True}
    (out,), rc = run(tmp_path, "passphrase", "/dev/sdb", stdin=json.dumps({"old": "wrong", "new": "n3w"}) + "\n")
    assert rc == 1 and out["error"] == "the old password is not right"
    monkeypatch.delenv("FAKE_LUKS")
    (out,), rc = run(tmp_path, "passphrase", "/dev/sdb", stdin=json.dumps({"old": "x", "new": "y"}) + "\n")
    assert "not locked" in out["error"]
