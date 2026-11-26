"""bridge/containers_podman.py against dev/fake-podman.py: every Podman-only
flow of the Containers window - run, shell argv, logs, pause/resume/kill, rename,
commit, stats, readable inspect, search, pull, pods and volumes - checked by what
the stand-in recorded in calls/state.json, not by reading the bridge."""

import importlib.util
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


def test_command_catalog():
    spec = importlib.util.spec_from_file_location("containers_podman", BRIDGE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    assert set(m.COMMANDS) == {
        "container-run",
        "container-shell",
        "logs-follow",
        "container-pause",
        "container-resume",
        "container-kill",
        "container-rename",
        "container-commit",
        "container-stats",
        "container-inspect",
        "image-search",
        "image-pull",
        "pod-list",
        "pod-start",
        "pod-stop",
        "pod-remove",
        "volume-list",
        "volume-create",
        "volume-remove",
        "volume-prune",
        "gpu-status",
    }


def test_run_shell_and_readable_inspect(tmp_path, podman):
    env, link = podman
    out, rc = run(
        tmp_path,
        env,
        "container-run",
        "web2",
        "docker.io/library/ubuntu:latest",
        "--ports",
        "8080:80,443:443",
        "--volumes",
        "/host:/container,/a:/b",
        "--env",
        "K=V,K2=V2",
        "--command",
        "echo 'hello world'",
    )
    assert rc == 0 and out == {"ok": True}
    log = calls(tmp_path)
    assert "podman run -d --name web2" in log
    for bit in (
        "-p 8080:80",
        "-p 443:443",
        "-v /host:/container",
        "-v /a:/b",
        "-e K=V",
        "-e K2=V2",
        "docker.io/library/ubuntu:latest",
        "echo hello world",
    ):
        assert bit in log
    c = next(c for c in state(tmp_path)["containers"] if "web2" in c["Names"])
    assert (
        len(c["Ports"]) == 2 and len(c["Mounts"]) == 2 and c["Env"] == ["K=V", "K2=V2"]
    )
    assert c["Cmd"] == ["echo", "hello world"]

    sh, rc = run(tmp_path, env, "container-shell", "web2")
    assert rc == 0 and sh == {
        "argv": ["xdg-terminal-exec", str(link), "exec", "-it", "web2", "bash"]
    }
    assert run(tmp_path, env, "container-shell", "web")[0]["argv"][-1] == "sh"

    info, rc = run(tmp_path, env, "container-inspect", "web2")
    assert rc == 0
    assert info["name"] == "web2" and info["state"] == "running"
    assert (
        info["image"] == "docker.io/library/ubuntu:latest" and 0 < len(info["id"]) <= 12
    )
    assert info["command"] == "echo hello world"
    assert info["ports"] == "8080→80, 443→443"
    assert info["mounts"] == "/host→/container, /a→/b"
    assert isinstance(info["created"], int)


def test_pause_resume_kill_rename_commit_stats(tmp_path, podman):
    env, _ = podman
    assert run(tmp_path, env, "container-pause", "web") == ({"ok": True}, 0)
    assert state(tmp_path)["containers"][0]["State"] == "paused"
    assert "podman pause web" in calls(tmp_path)
    assert run(tmp_path, env, "container-resume", "web") == ({"ok": True}, 0)
    assert state(tmp_path)["containers"][0]["State"] == "running"
    assert "podman unpause web" in calls(tmp_path)
    assert run(tmp_path, env, "container-rename", "web", "web3") == ({"ok": True}, 0)
    assert "web3" in state(tmp_path)["containers"][0]["Names"]
    assert "podman rename web web3" in calls(tmp_path)
    assert run(tmp_path, env, "container-commit", "web3", "myimg:1") == (
        {"ok": True},
        0,
    )
    assert "myimg:1" in [n for i in state(tmp_path)["images"] for n in i["Names"]]
    assert "podman commit web3 myimg:1" in calls(tmp_path)
    assert run(tmp_path, env, "container-kill", "web3") == ({"ok": True}, 0)
    assert state(tmp_path)["containers"][0]["State"] == "exited"
    assert "podman kill web3" in calls(tmp_path)
    stats, rc = run(tmp_path, env, "container-stats", "web3")
    assert rc == 0 and stats == {"cpu": "12.5%", "mem": "10MiB / 1GiB"}
    assert "--no-stream --format {{.Name}}|{{.CPUPerc}}|{{.MemUsage}} web3" in calls(
        tmp_path
    )


def test_logs_follow_and_image_pull_stream(tmp_path, podman):
    env, _ = podman
    lines, rc = run(tmp_path, env, "logs-follow", "web")
    assert rc == 0 and lines == [
        {"line": "follow one"},
        {"line": "follow two"},
        {"ok": True},
    ]
    assert "podman logs --follow web" in calls(tmp_path)
    lines, rc = run(tmp_path, env, "image-pull", "alpine")
    assert rc == 0 and lines[-1] == {"ok": True}
    assert {"line": "Pulling alpine"} in lines and {
        "line": "Downloaded alpine"
    } in lines
    assert "podman pull alpine" in calls(tmp_path)
    assert any("alpine" in n for i in state(tmp_path)["images"] for n in i["Names"])


def test_image_search_sorted(tmp_path, podman):
    env, _ = podman
    rows, rc = run(tmp_path, env, "image-search", "nginx")
    assert rc == 0
    assert [r["name"] for r in rows] == [
        "docker.io/library/nginx",
        "docker.io/nginx/community",
        "docker.io/other/nginx",
    ]
    assert [r["stars"] for r in rows] == [123, 42, 7]
    assert [r["official"] for r in rows] == [True, False, False]
    assert all({"name", "description", "stars", "official"} <= set(r) for r in rows)
    assert "podman search --format json --limit 8 nginx" in calls(tmp_path)


def test_pods(tmp_path, podman):
    env, _ = podman
    out, rc = run(tmp_path, env, "pod-list")
    assert rc == 0 and out == {
        "pods": [{"name": "webpod", "status": "running", "containers": 1, "created": 1}]
    }
    assert run(tmp_path, env, "pod-stop", "webpod") == ({"ok": True}, 0)
    assert state(tmp_path)["pods"][0]["Status"] == "exited"
    assert "podman pod stop webpod" in calls(tmp_path)
    assert run(tmp_path, env, "pod-start", "webpod") == ({"ok": True}, 0)
    assert state(tmp_path)["pods"][0]["Status"] == "running"
    assert "podman pod start webpod" in calls(tmp_path)
    assert run(tmp_path, env, "pod-remove", "webpod") == ({"ok": True}, 0)
    assert state(tmp_path)["pods"] == []
    assert "podman pod rm -f webpod" in calls(tmp_path)


def test_volumes(tmp_path, podman):
    env, _ = podman
    out, rc = run(tmp_path, env, "volume-list")
    assert rc == 0 and out == {
        "volumes": [{"name": "site", "driver": "local", "size": 1234567, "created": 1}]
    }
    assert run(tmp_path, env, "volume-create", "cache") == ({"ok": True}, 0)
    assert "cache" in [v["Name"] for v in state(tmp_path)["volumes"]]
    assert "podman volume create cache" in calls(tmp_path)
    assert run(tmp_path, env, "volume-remove", "cache") == ({"ok": True}, 0)
    assert "cache" not in [v["Name"] for v in state(tmp_path)["volumes"]]
    assert "podman volume rm cache" in calls(tmp_path)
    assert run(tmp_path, env, "volume-prune") == ({"ok": True, "removed": 1}, 0)
    assert state(tmp_path)["volumes"] == []
    assert "podman volume prune -f" in calls(tmp_path)


def test_errors_do_not_reach_podman(tmp_path, podman):
    env, _ = podman
    for args in (
        ("container-run", "web"),
        ("container-pause", "web; rm -rf ~"),
        ("container-inspect", "bad name"),
        ("image-pull", "img; touch /tmp/x"),
        ("container-run", "w", "img", "--ports", "80;drop"),
        ("container-run", "w", "img", "--volumes", "/host;rm:/c"),
        ("container-run", "w", "img", "--env", "BAD"),
        ("bogus",),
    ):
        out, rc = run(tmp_path, env, *args)
        assert rc == 1 and "error" in out, args
    log = calls(tmp_path) if (tmp_path / "calls").exists() else ""
    assert "rm -rf" not in log and "touch" not in log
    assert not state_exists(tmp_path)


def state_exists(tmp_path):
    return (tmp_path / "state.json").exists()


def test_gpu_needs_a_cdi_spec(tmp_path, podman):
    env, _ = podman
    cdi = tmp_path / "cdi"
    cdi.mkdir()
    env = dict(env, SHANI_CDI_DIR=str(cdi))
    assert run(tmp_path, env, "gpu-status") == (
        {"cdi": False, "directory": str(cdi)},
        0,
    )
    out, rc = run(tmp_path, env, "container-run", "gpu", "alpine", "--gpu")
    assert rc == 1 and "nvidia-container-toolkit is not in the image" in out["error"]
    log = calls(tmp_path) if (tmp_path / "calls").exists() else ""
    assert "podman run" not in log

    (cdi / "nvidia.yaml").write_text("nvidia.com/gpu=all:\n")
    assert run(tmp_path, env, "gpu-status")[0]["cdi"] is True
    assert run(tmp_path, env, "container-run", "gpu", "alpine", "--gpu") == (
        {"ok": True},
        0,
    )
    log = calls(tmp_path)
    assert "--device nvidia.com/gpu=all" in log
    assert "--security-opt label=disable" in log
