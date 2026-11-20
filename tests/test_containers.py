"""bridge/containers.py against a stand-in podman and distrobox (dev/fake-podman.py):
the listing in podman's JSON, toolboxes told apart by distrobox's label, start/stop/
logs, a toolbox made with progress and its apps offered for the menu, images pruned,
and nothing passed on that is not a container name."""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "containers.py"


def run(tmp_path, *args):
    for n in ("podman", "distrobox"):
        p = tmp_path / n
        if not p.exists():
            p.symlink_to(ROOT / "dev" / "fake-podman.py")
    env = dict(os.environ, FAKE_PODMAN=str(tmp_path), PATH="%s:%s" % (tmp_path, os.environ["PATH"]))
    r = subprocess.run([sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env)
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return (lines if len(lines) > 1 else lines[0]), r.returncode


def test_listing_and_actions(tmp_path):
    l, _ = run(tmp_path, "list")
    assert l["podman"] and l["distrobox"] and [c["name"] for c in l["containers"]] == ["web"]
    assert l["containers"][0]["ports"] == "8080→80" and l["containers"][0]["state"] == "running"
    assert [i["used"] for i in l["images"]] == [True, False]
    assert run(tmp_path, "stop", "web")[0] == {"ok": True}
    assert run(tmp_path, "list")[0]["containers"][0]["state"] == "exited"
    assert run(tmp_path, "logs", "web")[0]["text"].startswith("line one")
    assert "error" in run(tmp_path, "stop", "web; rm -rf ~")[0]


def test_toolbox_made_its_apps_and_removed(tmp_path):
    lines, rc = run(tmp_path, "box-create", "dev-arch", "docker.io/library/archlinux:latest")
    assert rc == 0 and lines[-1] == {"ok": True} and {"line": "Distrobox created"} in lines
    l, _ = run(tmp_path, "list")
    assert [c["name"] for c in l["containers"]] == ["dev-arch", "web"] and l["containers"][0]["box"] is True   # toolboxes first
    apps, _ = run(tmp_path, "box-apps", "dev-arch")
    assert apps == [{"id": "firefox", "name": "Firefox"}, {"id": "org.gnome.gedit", "name": "Text Editor"}]
    assert run(tmp_path, "box-export", "dev-arch", "firefox")[0] == {"ok": True}
    assert "distrobox enter dev-arch -- distrobox-export --app firefox" in (tmp_path / "calls").read_text()
    assert run(tmp_path, "box-remove", "dev-arch")[0] == {"ok": True}
    assert [c["name"] for c in run(tmp_path, "list")[0]["containers"]] == ["web"]


def test_prune_keeps_what_is_used(tmp_path):
    r, _ = run(tmp_path, "prune")
    assert r == {"ok": True, "removed": 1}
    assert [i["name"] for i in run(tmp_path, "list")[0]["images"]] == ["docker.io/library/nginx:latest"]
