"""bridge/cloud.py against a stand-in rclone: remotes listed, an OAuth one added
through rclone's own sign-in, a Nextcloud one with its password obscured through
stdin (never on a command line), mounted under $XDG_RUNTIME_DIR/cloud, removed."""
import json
import os
import subprocess
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "cloud.py"
FAKE = r'''#!/bin/sh
echo "$*" >> "$T/args"
conf="$T/remotes"; touch "$conf"
case "$1" in
listremotes) cat "$conf" ;;
config)
    case "$2" in
    create) [ "$4" = drive ] && [ -e "$T/deny" ] && { echo "auth failed: access_denied" >&2; exit 1; }
            printf '%s: %s\n' "$3" "$4" >> "$conf" ;;
    delete) grep -v "^$3: " "$conf" > "$conf.n"; mv "$conf.n" "$conf" ;;
    esac ;;
obscure) read -r pw; echo "OBSCURED($pw)" | tr -d ' ' > /dev/null; echo "Xobscured" ;;
mount) mkdir -p "$3"; echo "$3" >> "$T/mounts" ;;
esac
'''


def run(tmp_path, *args, stdin=""):
    env = dict(os.environ, PATH="%s:%s" % (tmp_path / "bin", os.environ["PATH"]), T=str(tmp_path), XDG_RUNTIME_DIR=str(tmp_path / "run"))
    r = subprocess.run([sys.executable, str(BRIDGE), *args], input=stdin, capture_output=True, text=True, env=env)
    return json.loads(r.stdout), r.returncode


def setup(tmp_path):
    (tmp_path / "bin").mkdir()
    (tmp_path / "bin" / "rclone").write_text(FAKE); (tmp_path / "bin" / "rclone").chmod(0o755)


def test_add_list_mount_remove(tmp_path):
    setup(tmp_path)
    assert run(tmp_path, "add", "My Drive", "drive") == ({"ok": True, "name": "My Drive"}, 0)
    assert "config create My Drive drive config_is_local=true" in (tmp_path / "args").read_text()
    out, rc = run(tmp_path, "list")
    assert out == [{"name": "My Drive", "type": "drive", "label": "Google Drive", "path": str(tmp_path / "run" / "cloud" / "My Drive"), "mounted": False}]
    assert run(tmp_path, "add", "bad/name", "drive")[0]["error"].startswith("a name")
    assert run(tmp_path, "add", "x", "ftp")[0]["error"].startswith("not a cloud")


def test_nextcloud_password_never_on_the_command_line(tmp_path):
    setup(tmp_path)
    out, rc = run(tmp_path, "add", "work", "webdav", stdin=json.dumps({"url": "https://cloud.example.org/remote.php/dav/files/me", "user": "me", "password": "s3cret"}) + "\n")
    assert rc == 0
    args = (tmp_path / "args").read_text()
    assert "s3cret" not in args and "pass=Xobscured" in args and "vendor=nextcloud" in args
    m, rc = run(tmp_path, "mount", "work")
    assert m == {"path": str(tmp_path / "run" / "cloud" / "work")} and "--vfs-cache-mode writes" in (tmp_path / "args").read_text()
    assert run(tmp_path, "mount", "nope")[0]["error"].startswith("no cloud drive")
    assert run(tmp_path, "remove", "work")[1] == 0
    assert run(tmp_path, "list")[0] == []


def test_a_failed_sign_in_leaves_nothing(tmp_path):
    setup(tmp_path); (tmp_path / "deny").touch()
    out, rc = run(tmp_path, "add", "g", "drive")
    assert rc == 1 and "access_denied" in out["error"]
    assert "config delete g" in (tmp_path / "args").read_text()
    assert run(tmp_path, "list")[0] == []
