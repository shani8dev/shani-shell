"""bridge/containers_apptainer.py against dev/fake-apptainer.py: list, pull,
run/shell argv and remove of .sif images, checked by what the stand-in recorded
in calls/ and images/, not by reading the bridge."""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "containers_apptainer.py"
FAKE = ROOT / "dev" / "fake-apptainer.py"


@pytest.fixture
def apptainer(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    link = bindir / "apptainer"
    link.symlink_to(FAKE)
    env = dict(
        os.environ,
        FAKE_APPTAINER=str(tmp_path),
        PATH="%s:%s" % (bindir, os.environ["PATH"]),
        SHANI_APPTAINER=str(link),
    )
    # Let the stand-in create its default images/ and state.json.
    subprocess.run(
        [sys.executable, str(link), "run", "init"],
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    return tmp_path, env, link, tmp_path / "images"


def invoke(fake, *args):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        capture_output=True,
        text=True,
        env=fake[1],
    )
    return [json.loads(l) for l in r.stdout.splitlines() if l.strip()], r


def one(fake, *args):
    lines, r = invoke(fake, *args)
    assert len(lines) == 1, lines
    return lines[0], r.returncode


def calls(fake):
    p = fake[0] / "calls"
    return p.read_text() if p.exists() else ""


def test_command_catalog():
    spec = importlib.util.spec_from_file_location("containers_apptainer", BRIDGE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    assert set(m.COMMANDS) == {
        "apptainer-list",
        "apptainer-pull",
        "apptainer-run",
        "apptainer-shell",
        "apptainer-remove",
    }


def test_apptainer_list(apptainer):
    images = apptainer[3]
    out, rc = one(apptainer, "apptainer-list", str(images))
    assert rc == 0 and out["hasApptainer"] is True
    assert [i["name"] for i in out["images"]] == [
        "python_3.11.sif",
        "ubuntu_22.04.sif",
    ]
    first = out["images"][0]
    assert first["path"] == str(images / "python_3.11.sif")
    assert first["size"] == (images / "python_3.11.sif").stat().st_size

    missing, rc = one(apptainer, "apptainer-list", str(apptainer[0] / "no-such-folder"))
    assert rc == 0 and missing == {"images": [], "hasApptainer": True}


def test_apptainer_pull(apptainer):
    images = apptainer[3]
    lines, r = invoke(apptainer, "apptainer-pull", "docker://ubuntu:22.04", "myimg")
    assert r.returncode == 0 and lines[-1] == {"ok": True}
    assert {"line": "Pulling docker://ubuntu:22.04"} in lines
    assert {"line": "Saved myimg.sif"} in lines
    assert "apptainer pull --name myimg.sif docker://ubuntu:22.04" in calls(apptainer)
    assert (images / "myimg.sif").is_file()
    state = json.loads((apptainer[0] / "state.json").read_text())
    assert "myimg.sif" in state["images"]


def test_apptainer_pull_rejects_bad_ref_and_name(apptainer):
    for args in (
        ("apptainer-pull", "ubuntu:22.04", "ok"),
        ("apptainer-pull", "http://example.com/x", "ok"),
        ("apptainer-pull", "docker://ubuntu:22.04", "../evil"),
        ("apptainer-pull", "docker://ubuntu:22.04", "bad name"),
        ("apptainer-pull", "docker://ubuntu:22.04", ".."),
    ):
        out, rc = one(apptainer, *args)
        assert rc == 1 and "error" in out, args
    assert "pull" not in calls(apptainer)


def test_apptainer_run(apptainer):
    link, images = apptainer[2], apptainer[3]
    path = str(images / "python_3.11.sif")
    out, rc = one(apptainer, "apptainer-run", path)
    assert rc == 0
    assert out == {"argv": ["xdg-terminal-exec", str(link), "run", path]}
    for bad in (str(images / "missing.sif"), str(images / "notes.txt")):
        out, rc = one(apptainer, "apptainer-run", bad)
        assert rc == 1 and "error" in out


def test_apptainer_shell(apptainer):
    link, images = apptainer[2], apptainer[3]
    path = str(images / "ubuntu_22.04.sif")
    out, rc = one(apptainer, "apptainer-shell", path)
    assert rc == 0
    assert out == {"argv": ["xdg-terminal-exec", str(link), "shell", path]}
    for bad in (str(images / "missing.sif"), str(images / "notes.txt")):
        out, rc = one(apptainer, "apptainer-shell", bad)
        assert rc == 1 and "error" in out


def test_apptainer_remove(apptainer):
    images = apptainer[3]
    target = images / "ubuntu_22.04.sif"
    assert target.is_file()
    out, rc = one(apptainer, "apptainer-remove", str(target))
    assert rc == 0 and out == {"ok": True}
    assert not target.exists()
    assert (images / "python_3.11.sif").is_file()

    note = images / "notes.txt"
    note.write_text("keep")
    out, rc = one(apptainer, "apptainer-remove", str(note))
    assert rc == 1 and "error" in out
    assert note.is_file()

    out, rc = one(apptainer, "apptainer-remove", "/nonexistent/outside.sif")
    assert rc == 1 and "error" in out
    listed, rc = one(apptainer, "apptainer-list", str(images))
    assert rc == 0 and [i["name"] for i in listed["images"]] == ["python_3.11.sif"]
