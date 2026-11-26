"""Deferred Containers features: building an image from a Dockerfile and browsing
a running container's files. The bridge is checked through dev/fake-podman.py's
call log; the window is checked as static wiring to those bridge commands."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "containers_podman.py"
FAKE = ROOT / "dev" / "fake-podman.py"


@pytest.fixture
def podman(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    link = bindir / "podman"
    link.symlink_to(FAKE)
    env = dict(
        os.environ,
        FAKE_PODMAN=str(tmp_path),
        PATH="%s:%s" % (bindir, os.environ["PATH"]),
        SHANI_PODMAN=str(link),
    )
    return env, link


def run(tmp_path, env, cmd, *args):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), cmd, *args],
        capture_output=True,
        text=True,
        env=env,
    )
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return (lines if len(lines) > 1 else lines[0]), r.returncode


def calls(tmp_path):
    return (tmp_path / "calls").read_text()


def state(tmp_path):
    return json.loads((tmp_path / "state.json").read_text())


def test_image_build_from_folder_and_dockerfile(tmp_path, podman):
    env, _ = podman
    ctx = tmp_path / "ctx"
    ctx.mkdir()
    df = ctx / "Dockerfile"
    df.write_text("FROM alpine\nCOPY . /app\n")
    lines, rc = run(tmp_path, env, "image-build", "my-app:1", str(ctx), "dir")
    assert rc == 0 and lines[-1] == {"ok": True}
    assert any("Step 1/2" in l.get("line", "") for l in lines)
    assert "Successfully built my-app:1" in [l.get("line") for l in lines]
    assert "podman build -t my-app:1 %s" % ctx in calls(tmp_path)
    assert any("my-app:1" in n for i in state(tmp_path)["images"] for n in i["Names"])

    lines, rc = run(tmp_path, env, "image-build", "other:2", str(df), "file")
    assert rc == 0 and lines[-1] == {"ok": True}
    assert "podman build -t other:2 -f %s %s" % (df, ctx) in calls(tmp_path)


def test_container_files_and_copy_out(tmp_path, podman):
    env, _ = podman
    out, rc = run(tmp_path, env, "container-files", "web")
    assert rc == 0 and out["path"] == "/"
    names = {e["name"]: e for e in out["entries"]}
    assert names["notes.txt"]["dir"] is False and names["notes.txt"]["size"] == 12
    assert names["docs"]["dir"] is True
    assert "podman exec web ls -lA /" in calls(tmp_path)
    out, rc = run(tmp_path, env, "container-files", "web", "/docs")
    assert rc == 0 and out["path"] == "/docs" and len(out["entries"]) == 2

    dest = tmp_path / "saved.txt"
    assert run(
        tmp_path, env, "container-file-copy", "web", "/notes.txt", str(dest)
    ) == (
        {"ok": True},
        0,
    )
    assert "podman cp web:/notes.txt %s" % dest in calls(tmp_path)
    assert dest.read_text() == "copied from web:/notes.txt\n"


def test_build_and_files_reject_bad_arguments(tmp_path, podman):
    env, _ = podman
    for args in (
        ("image-build", "bad;tag", "/tmp", "dir"),
        ("image-build", "ok:1", "/tmp; touch /tmp/x", "dir"),
        ("image-build", "ok:1", "/tmp", "nope"),
        ("image-build", "ok:1", "/tmp"),
        ("container-files", "bad name"),
        ("container-files", "web", "/etc; rm -rf ~"),
        ("container-file-copy", "web", "/a", "relative/path"),
    ):
        out, rc = run(tmp_path, env, *args)
        assert rc == 1 and "error" in out, args
    log = calls(tmp_path) if (tmp_path / "calls").exists() else ""
    assert "rm -rf" not in log and "touch" not in log


def test_window_wires_the_new_commands():
    s = (ROOT / "shani/Modules/Containers/ContainersWindow.qml").read_text()
    for frag in (
        '["image-build", tag, win.buildSource, win.buildKind]',
        '["container-files", name, path]',
        '["container-file-copy", name, src, paths[0]]',
        'mode: "save", defaultName: entry.name',
        "function browseUp()",
        "function browseBack()",
        "function closeFiles()",
    ):
        assert frag in s, frag
