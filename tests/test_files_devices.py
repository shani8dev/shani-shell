"""bridge/files.py devices: drives, phones and network places from `gio mount -li`
(fixture: gio's own layout - a drive's volumes and mounts indented under it, a
phone's volume and a network mount with no drive), and connect's address check."""
import importlib.util
import json
import os
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("files_dev", HERE.parent / "bridge" / "files.py")
files = importlib.util.module_from_spec(spec)
spec.loader.exec_module(files)
LISTING = (HERE / "fixtures" / "gio-mount-li.txt").read_text()


class R:
    def __init__(self, out="", rc=0, err=""):
        self.stdout, self.returncode, self.stderr = out, rc, err


@pytest.fixture
def gio(monkeypatch):
    calls = []

    def fake(*args, stdin=None, timeout=60):
        calls.append((args, stdin))
        if args[:2] == ("mount", "-li"):
            return R(LISTING)
        if args[0] == "info":
            uri = args[-1]
            return R(f"display name: x\nlocal path: /run/user/1000/gvfs/smb-share:server=nas,share=share\n") if uri.startswith("smb://") else R("")
        if args[:2] == ("mount", "smb://nas/locked/") and "pw" not in (stdin or ""):
            return R(rc=2, err="gio: smb://nas/locked/: Permission denied")
        return R()
    monkeypatch.setattr(files, "_gio", fake)
    return calls


def test_devices_lists_what_a_person_can_open(gio):
    d = {x["name"]: x for x in files.devices()["devices"]}
    assert set(d) == {"Windows", "STICK", "Pixel 8", "share on nas"}            # no loop device
    assert d["STICK"] == {"name": "STICK", "path": "/run/media/ann/STICK", "mounted": True, "mount": "/dev/sdb1",
                          "icon": "drive-removable-media", "internal": False, "canEject": True, "canUnmount": True}
    assert d["Pixel 8"]["mounted"] is False and d["Pixel 8"]["mount"] == "mtp://Google_Pixel_8_3A1B/" and d["Pixel 8"]["icon"] == "phone"
    assert d["Windows"]["internal"] is True and d["Windows"]["mounted"] is False and d["Windows"]["mount"] == "/dev/nvme0n1p3"
    assert d["share on nas"]["path"] == "/run/user/1000/gvfs/smb-share:server=nas,share=share" and d["share on nas"]["network"] is True


def test_mount_a_device_by_node_and_a_phone_by_uri(gio):
    files.mount("/dev/nvme0n1p3")
    files.mount("mtp://Google_Pixel_8_3A1B/")
    assert ("mount", "-d", "/dev/nvme0n1p3") in [c[0] for c in gio]
    assert ("mount", "mtp://Google_Pixel_8_3A1B/") in [c[0] for c in gio]


def test_unmount_and_eject(gio):
    files.unmount("/run/media/ann/STICK")
    files.unmount("/run/media/ann/STICK", eject=True)
    assert [c[0] for c in gio if c[0][0] == "mount"][-2:] == [("mount", "-u", "/run/media/ann/STICK"), ("mount", "-e", "/run/media/ann/STICK")]


def test_connect_answers_the_login_and_says_when_it_is_needed(gio):
    r = files.connect("smb://nas/locked/", {"user": "ann"})
    assert r["needsLogin"] is True and "Permission denied" in r["error"]
    r = files.connect("smb://nas/locked/", {"user": "ann", "domain": "", "password": "pw"})
    assert "error" not in r
    assert [c for c in gio if c[0][0] == "mount"][-1][1] == "ann\n\npw\n"          # user, domain, password


@pytest.mark.parametrize("bad", ["file:///etc", "smb://", "http://x", "/dev/sda1", "smb://a b", ""])
def test_connect_refuses_what_is_no_server(gio, bad):
    assert "not a server address" in files.connect(bad, {})["error"]


def test_fuse_mounts_a_person_made(tmp_path, monkeypatch):
    """sshfs, rclone and the like are places; gvfs's own and the portals' are not."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("files_bridge", Path(__file__).resolve().parent.parent / "bridge" / "files.py")
    fb = importlib.util.module_from_spec(spec); spec.loader.exec_module(fb)
    mi = tmp_path / "mountinfo"
    mi.write_text(
        "36 25 0:32 / /run/user/1000/gvfs rw,nosuid,nodev - fuse.gvfsd-fuse gvfsd-fuse rw,user_id=1000\n"
        "37 25 0:33 / /run/user/1000/doc rw - fuse.portal portal rw\n"
        "38 25 0:34 / /home/me/Server\\040Box rw,nosuid - fuse.sshfs me@box:/srv rw,user_id=1000\n"
        "39 25 0:35 / /home/me/Drive rw - fuse.rclone gdrive: rw\n"
        "40 25 0:36 / /sys/fs/fuse/connections rw - fusectl fusectl rw\n"
        "41 25 0:37 / /tmp/.mount_KritaX rw - fuse.Krita.AppImage Krita.AppImage ro\n"
        "42 25 8:17 / /data rw - fuseblk /dev/sdb1 rw\n"
        "43 25 0:38 / /home/me/.local/share/flatpak/x rw - fuse.revokefs-fuse revokefs ro\n")
    monkeypatch.setenv("HOME", "/home/me")
    got = [(f["name"], f["path"], f["fuse"], f["icon"]) for f in fb.fuse_mounts(str(mi))]
    assert got == [("Server Box · sshfs", "/home/me/Server Box", "sshfs", "folder-remote"),
                   ("Drive · rclone", "/home/me/Drive", "rclone", "folder-remote")]


def test_ssh_addresses_mount_with_sshfs(tmp_path, monkeypatch):
    """ssh:// and user@host:path go to sshfs (FUSE), password on its stdin, keys
    only when there is none; any other address stays gio's."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("files_bridge2", Path(__file__).resolve().parent.parent / "bridge" / "files.py")
    fb = importlib.util.module_from_spec(spec); spec.loader.exec_module(fb)
    bin_ = tmp_path / "bin"; bin_.mkdir()
    (bin_ / "sshfs").write_text('#!/bin/sh\necho "$*" >> %s/args; cat >> %s/stdin 2>/dev/null; [ "$(tail -1 %s/stdin 2>/dev/null)" = bad ] && { echo "read: Connection reset by peer" >&2; echo "Permission denied (password)" >&2; exit 1; }; exit 0\n' % (tmp_path, tmp_path, tmp_path))
    (bin_ / "sshfs").chmod(0o755)
    monkeypatch.setenv("PATH", "%s:%s" % (bin_, os.environ["PATH"]))
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    r = fb.connect("ssh://me@box:2222/srv/data", {"password": "s3cret"})
    assert r == {"path": str(tmp_path / "sshfs" / "box")}
    args = (tmp_path / "args").read_text().splitlines()
    assert args[0].startswith("me@box:/srv/data %s/sshfs/box -o " % tmp_path) and "password_stdin" in args[0] and args[0].endswith("-p 2222")
    assert (tmp_path / "stdin").read_text() == "s3cret\n"
    fb.connect("me@nas:/media", {})
    assert "BatchMode=yes" in (tmp_path / "args").read_text().splitlines()[1]
    r = fb.connect("ssh://other/x", {"password": "bad"})
    assert r["needsLogin"] and not (tmp_path / "sshfs" / "other").exists()


def test_network_servers_from_gvfs(tmp_path, monkeypatch):
    import importlib.util
    spec = importlib.util.spec_from_file_location("files_bridge3", Path(__file__).resolve().parent.parent / "bridge" / "files.py")
    fb = importlib.util.module_from_spec(spec); spec.loader.exec_module(fb)
    monkeypatch.setenv("SHANI_GIO", "sh %s" % (Path(__file__).resolve().parent.parent / "dev" / "fake-gio.sh"))
    monkeypatch.setenv("FAKE_GIO_LOG", str(tmp_path / "log")); monkeypatch.setenv("FAKE_GIO_MOUNTED", str(tmp_path / "m"))
    got = [(s["name"], s["uri"], s["kind"]) for s in fb.network()["servers"]]
    assert ("Office NAS", "smb://nas.local/", "Windows share") in got and ("media", "nfs://media.local/export", "NFS") in got
    assert len(got) == 4
