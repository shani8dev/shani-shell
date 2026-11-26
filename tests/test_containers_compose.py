"""bridge/containers_compose.py against dev/fake-compose.py and
dev/fake-systemctl-user.py: every command checked by streamed JSON and by what
the stand-ins recorded in calls/, not by reading the bridge."""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "containers_compose.py"
FAKE_COMPOSE = ROOT / "dev" / "fake-compose.py"
FAKE_SYSTEMCTL = ROOT / "dev" / "fake-systemctl-user.py"


@pytest.fixture
def env(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    comp = bindir / "podman-compose"
    comp.symlink_to(FAKE_COMPOSE)
    ctl = bindir / "systemctl"
    ctl.symlink_to(FAKE_SYSTEMCTL)
    quadlet = tmp_path / "quadlet"
    e = dict(
        os.environ,
        FAKE_COMPOSE=str(tmp_path),
        PATH="%s:%s" % (bindir, os.environ["PATH"]),
        SHANI_COMPOSE=str(comp),
        SHANI_SYSTEMCTL=str(ctl),
        SHANI_QUADLET_DIR=str(quadlet),
    )
    return e, quadlet


def run(env, cmd, *args):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), cmd, *args],
        capture_output=True,
        text=True,
        env=env,
    )
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    out = None if not lines else (lines if len(lines) > 1 else lines[0])
    return out, r.returncode, r.stderr


def calls(tmp_path):
    return (tmp_path / "calls").read_text()


def test_command_catalog():
    spec = importlib.util.spec_from_file_location("containers_compose", BRIDGE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    assert set(m.COMMANDS) == {
        "compose-up",
        "compose-down",
        "compose-logs",
        "service-create",
        "service-status",
        "service-remove",
    }


def test_compose_choice_and_stream(tmp_path, env):
    e, _ = env
    folder = tmp_path / "stack"
    folder.mkdir()
    (folder / "docker-compose.yaml").write_text("x")
    (folder / "docker-compose.yml").write_text("x")
    (folder / "compose.yml").write_text("x")
    chosen = folder / "compose.yaml"
    chosen.write_text("x")

    out, rc, err = run(e, "compose-up", str(folder))
    assert rc == 0 and out == [
        {"line": "Creating compose stack"},
        {"line": "Started"},
        {"ok": True},
    ], err
    assert "podman-compose -f %s up -d" % chosen in calls(tmp_path)
    assert "compose.yml" not in calls(tmp_path)
    assert "docker-compose" not in calls(tmp_path)

    out, rc, err = run(e, "compose-down", str(folder))
    assert rc == 0 and out == [{"line": "Stopped"}, {"ok": True}], err
    assert "podman-compose -f %s down" % chosen in calls(tmp_path)

    out, rc, err = run(e, "compose-logs", str(folder))
    assert rc == 0 and out == [
        {"line": "service one: line"},
        {"line": "service two: line"},
        {"ok": True},
    ], err
    assert "podman-compose -f %s logs" % chosen in calls(tmp_path)


def test_compose_legacy_name(tmp_path, env):
    e, _ = env
    folder = tmp_path / "legacy"
    folder.mkdir()
    chosen = folder / "docker-compose.yml"
    chosen.write_text("x")
    out, rc, err = run(e, "compose-up", str(folder))
    assert rc == 0 and out[-1] == {"ok": True}, err
    assert "podman-compose -f %s up -d" % chosen in calls(tmp_path)


def test_compose_missing(tmp_path, env):
    e, _ = env
    folder = tmp_path / "empty"
    folder.mkdir()
    out, rc, err = run(e, "compose-up", str(folder))
    assert rc == 1 and "no compose file" in out["error"], err
    out, rc, err = run(e, "compose-logs", str(tmp_path / "nope"))
    assert rc == 1 and "not a folder" in out["error"], err
    assert not (tmp_path / "calls").exists()


def test_service_create_writes_unit(tmp_path, env):
    e, quadlet = env
    out, rc, err = run(
        e,
        "service-create",
        "webapp",
        "docker.io/library/alpine:latest",
        "--ports",
        "8080:80,443:443",
        "--volumes",
        "/host:/data,/a:/b",
        "--env",
        "K=V,MODE=prod",
        "--gpu",
    )
    assert rc == 0 and out[-1] == {"ok": True}, err
    assert any(l.get("line", "").startswith("Wrote") for l in out[:-1])
    unit = (quadlet / "webapp.container").read_text().splitlines()
    assert unit[0] == "[Container]"
    for line in (
        "Image=docker.io/library/alpine:latest",
        "ContainerName=webapp",
        "AutoUpdate=registry",
        "PublishPort=8080:80",
        "PublishPort=443:443",
        "Volume=/host:/data",
        "Volume=/a:/b",
        "Environment=K=V",
        "Environment=MODE=prod",
        "Device=nvidia.com/gpu=all",
        "SecurityOpt=label=disable",
    ):
        assert line in unit
    log = calls(tmp_path)
    assert "systemctl --user daemon-reload" in log
    assert "systemctl --user start webapp.service" in log


def test_service_status_active_after_create_inactive_after_remove(tmp_path, env):
    e, quadlet = env
    out, rc, err = run(e, "service-create", "svc", "alpine")
    assert rc == 0 and out[-1] == {"ok": True}, err

    st, rc, err = run(e, "service-status", "svc")
    assert rc == 0, err
    assert st["active"] is True
    assert st["sub"] == "running"
    assert st["description"] == "svc service"
    assert isinstance(st["hasPodlet"], bool)
    assert (
        "systemctl --user show -p ActiveState -p SubState -p Description svc.service"
        in calls(tmp_path)
    )

    out, rc, err = run(e, "service-remove", "svc")
    assert rc == 0 and out == {"ok": True}, err
    assert not (quadlet / "svc.container").exists()
    st, rc, err = run(e, "service-status", "svc")
    assert rc == 0, err
    assert st["active"] is False and st["sub"] == "dead"
    assert "systemctl --user stop svc.service" in calls(tmp_path)


def test_service_remove_missing(tmp_path, env):
    e, _ = env
    out, rc, err = run(e, "service-remove", "ghost")
    assert rc == 1 and "no service" in out["error"], err
    assert not (tmp_path / "calls").exists()


@pytest.mark.parametrize(
    "args",
    [
        ("bad/name", "alpine"),
        ("svc", "bad image"),
        ("svc",),
        (),
        ("svc", "alpine", "--bogus", "x"),
    ],
)
def test_service_create_bad_args(tmp_path, env, args):
    e, _ = env
    out, rc, err = run(e, "service-create", *args)
    assert rc == 1 and "error" in out, err
    assert not list((tmp_path / "quadlet").glob("*.container"))


def test_bad_names_status_remove(tmp_path, env):
    e, _ = env
    out, rc, _ = run(e, "service-status", "bad/name")
    assert rc == 1 and "error" in out
    out, rc, _ = run(e, "service-remove", "bad/name")
    assert rc == 1 and "error" in out
