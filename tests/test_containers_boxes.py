"""The extra toolbox flows in bridge/containers_boxes.py against dev/fake-podman.py:
install a package with the distro's own tool, copy a toolbox, create one with
home/GPU/start-up choices, and read its details - all as streamed JSON or one
object, with bad names, images, files and flags refused."""

import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "bridge" / "containers_boxes.py"
FAKE = ROOT / "dev" / "fake-podman.py"
sys.path.insert(0, str(ROOT / "bridge"))
import containers_boxes as boxes


@pytest.fixture
def fake(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    for name in ("podman", "distrobox"):
        (bindir / name).symlink_to(FAKE)
    env = dict(
        os.environ,
        FAKE_PODMAN=str(tmp_path),
        HOME=str(tmp_path),
        PATH=str(bindir) + os.pathsep + os.environ["PATH"],
        SHANI_PODMAN=str(bindir / "podman"),
        SHANI_DISTROBOX=str(bindir / "distrobox"),
    )

    def run(*args, cwd=tmp_path):
        r = subprocess.run(
            [sys.executable, str(MODULE), *map(str, args)],
            check=False,
            capture_output=True,
            text=True,
            env=env,
            cwd=cwd,
        )
        lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
        out = lines if len(lines) > 1 else (lines[0] if lines else None)
        return out, r.returncode, r

    def distrobox(*args):
        return subprocess.run(
            [str(bindir / "distrobox"), *map(str, args)],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

    def state():
        p = tmp_path / "state.json"
        return json.loads(p.read_text()) if p.exists() else {}

    def calls():
        p = tmp_path / "calls"
        return p.read_text() if p.exists() else ""

    return SimpleNamespace(
        dir=tmp_path,
        bin=bindir,
        env=env,
        run=run,
        distrobox=distrobox,
        calls=calls,
        state=state,
        make=lambda name, image: distrobox(
            "create", "--yes", "--name", name, "--image", image
        ),
    )


@pytest.mark.parametrize("cmd", boxes.COMMANDS)
def test_command_declared_and_guards_its_args(fake, cmd):
    assert cmd in boxes.COMMANDS
    out, rc, _ = fake.run(cmd)
    assert rc == 1 and "error" in out


def test_box_install_streams_and_uses_apt_when_distro_unknown(fake):
    (fake.dir / "pkg.deb").write_bytes(b"deb")
    lines, rc, _ = fake.run("box-install", "web", "pkg.deb")
    assert rc == 0 and lines[-1] == {"ok": True}
    assert {"line": "Installing ./pkg.deb"} in lines
    assert "distrobox enter web -- sudo apt install -y ./pkg.deb" in fake.calls()
    assert not (fake.dir / "exported").exists()  # installing is not exporting an app


def test_box_install_picks_the_tool_of_the_box(fake):
    fake.make("fedbox", "docker.io/library/fedora:latest")
    fake.make("archbox", "docker.io/library/archlinux:latest")
    (fake.dir / "tool.rpm").write_bytes(b"rpm")
    assert fake.run("box-install", "fedbox", "tool.rpm")[1] == 0
    assert "distrobox enter fedbox -- sudo dnf install -y ./tool.rpm" in fake.calls()
    assert fake.run("box-install", "archbox", "tool.rpm")[1] == 0
    assert (
        "distrobox enter archbox -- sudo pacman -U --noconfirm ./tool.rpm"
        in fake.calls()
    )


@pytest.mark.parametrize(
    "args",
    [
        ("web", "notes.txt"),  # not a package
        ("web", "missing.deb"),  # no such file
        ("web; rm -rf ~", "pkg.deb"),  # not a name
    ],
)
def test_box_install_refuses_bad_input(fake, args):
    (fake.dir / "pkg.deb").write_bytes(b"deb")
    out, rc, _ = fake.run("box-install", *args)
    assert rc == 1 and "error" in out
    assert "distrobox enter" not in fake.calls()


def test_box_clone_adds_a_copy_of_the_box(fake):
    fake.make("archbox", "docker.io/library/archlinux:latest")
    lines, rc, _ = fake.run("box-clone", "archbox", "archbox-copy")
    assert rc == 0 and lines[-1] == {"ok": True}
    assert any(l.get("line") for l in lines[:-1])  # progress before the result
    assert "distrobox clone archbox archbox-copy" in fake.calls()
    copy = next(c for c in fake.state()["containers"] if "archbox-copy" in c["Names"])
    assert copy["Image"] == "docker.io/library/archlinux:latest"


@pytest.mark.parametrize("args", [("../escape", "copy"), ("web", "bad name")])
def test_box_clone_refuses_bad_names(fake, args):
    out, rc, _ = fake.run("box-clone", *args)
    assert rc == 1 and "error" in out
    assert "distrobox clone" not in fake.calls()


def test_box_create_options_records_home_graphics_and_hooks(fake):
    lines, rc, _ = fake.run(
        "box-create-options",
        "gpu",
        "docker.io/library/ubuntu:latest",
        "home",
        "nvidia",
        "hooks=echo ready",
    )
    assert rc == 0 and lines[-1] == {"ok": True}
    assert {"line": "Distrobox created"} in lines
    call = [l for l in fake.calls().splitlines() if l.startswith("distrobox create")][
        -1
    ]
    assert "--name gpu --image docker.io/library/ubuntu:latest" in call
    assert "--home " + str(fake.dir / "gpu") in call
    assert " --nvidia " in call
    assert "--init-hooks echo ready" in call
    assert "gpu" in [n for c in fake.state()["containers"] for n in c["Names"]]


@pytest.mark.parametrize(
    "args",
    [
        ("bad name", "image"),  # bad name
        ("gpu", "bad image"),  # bad image
        ("gpu", "image", "rm -rf /"),  # unknown option
    ],
)
def test_box_create_options_refuses_bad_input(fake, args):
    out, rc, _ = fake.run("box-create-options", *args)
    assert rc == 1 and "error" in out
    assert "distrobox create" not in fake.calls()


def test_box_details_has_friendly_distro_numeric_size_and_a_date(fake):
    fake.make("archbox", "docker.io/library/archlinux:latest")
    out, rc, _ = fake.run("box-details", "archbox")
    assert rc == 0
    assert out["image"] == "docker.io/library/archlinux:latest"
    assert out["distro"] == "Arch Linux"
    assert out["size"] == 400000000 and isinstance(out["size"], int)
    assert out["state"] == "exited"
    assert "1970" in out["created"]  # readable UTC date, not a raw timestamp

    plain, rc2, _ = fake.run("box-details", "web")
    assert rc2 == 0 and plain["distro"] == "docker.io/library/nginx:latest"
    assert plain["size"] == 190000000


def test_box_details_refuses_a_bad_name(fake):
    out, rc, _ = fake.run("box-details", "web; rm -rf ~")
    assert rc == 1 and "error" in out
