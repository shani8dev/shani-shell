"""bridge/system_disks.py against dev/fake-system-disks.py: the five read-only
verbs and what their JSON says when a tool degrades or is simply not installed.
The stand-in is reached by symlink under each tool's own name, the way
bridge/containers.py reaches dev/fake-podman.py."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge" / "system_disks.py"
FAKE = ROOT / "dev" / "fake-system-disks.py"
TOOLS = ("mdadm", "pvs", "vgs", "lvs", "btrfs", "compsize", "smartctl")

MDSTAT = """Personalities : [raid1] [raid6] [raid5] [raid4]
md127 : active raid1 sda1[0] sdb1[1]
      976630336 blocks super 1.2 [2/2] [UU]

unused devices: <none>
"""
DEGRADED = MDSTAT.replace("[2/2] [UU]", "[2/1] [U_]")


@pytest.fixture
def env(tmp_path):
    for name in TOOLS:
        (tmp_path / name).symlink_to(FAKE)
    for name in ("sda", "sdb", "nvme0n1"):
        (tmp_path / name).touch()
    (tmp_path / "mdstat").write_text(MDSTAT)
    e = dict(os.environ, FAKE_SYSTEM_DISKS=str(tmp_path))
    e["PATH"] = "%s:%s" % (tmp_path, os.environ["PATH"])
    e.update(
        SHANI_MDADM="mdadm",
        SHANI_PVS="pvs",
        SHANI_VGS="vgs",
        SHANI_LVS="lvs",
        SHANI_BTRFS="btrfs",
        SHANI_COMPSIZE="compsize",
        SHANI_SMARTCTL="smartctl",
        SHANI_MDSTAT=str(tmp_path / "mdstat"),
        SHANI_DISK_GLOB="%s/sd? %s/nvme?n1" % (tmp_path, tmp_path),
    )
    return e


def run(env, *args):
    p = subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    lines = [l for l in p.stdout.splitlines() if l.strip()]
    assert len(lines) == 1, p.stdout + p.stderr
    return json.loads(lines[0]), p.returncode


def calls(tmp_path):
    p = tmp_path / "calls"
    return p.read_text().splitlines() if p.exists() else []


def test_raid_tells_a_degraded_array_from_a_healthy_one(tmp_path, env):
    (tmp_path / "mdstat").write_text(DEGRADED)
    r, rc = run(env, "raid")
    assert rc == 0 and r["have"] is True
    (array,) = r["arrays"]
    assert array["name"] == "md127" and array["state"] == "degraded"
    assert array["devices"] == ["sda1", "sdb1"]
    assert "raid1" in array["detail"] and "degraded" in array["detail"]
    assert "mdadm --detail /dev/md127" in calls(tmp_path)

    (tmp_path / "mdstat").write_text(MDSTAT)
    assert run(env, "raid")[0]["arrays"][0]["state"] == "healthy"


def test_no_mdstat_is_an_honest_absence(tmp_path, env):
    (tmp_path / "mdstat").unlink()
    assert run(env, "raid")[0] == {"have": False, "arrays": []}


def test_lvm_reports_are_parsed(tmp_path, env):
    r, rc = run(env, "lvm")
    assert rc == 0 and r["have"] and r["error"] == ""
    assert [(p["name"], p["size"], p["vg"]) for p in r["pvs"]] == [
        ("/dev/sda1", "9.31G", "vg0"),
        ("/dev/sdb1", "9.31G", "vg0"),
    ]
    assert r["vgs"] == [{"name": "vg0", "size": "18.62G", "free": "4.00G"}]
    assert [(l["name"], l["vg"], l["size"], l["attr"]) for l in r["lvs"]] == [
        ("root", "vg0", "10.00G", "-wi-ao----"),
        ("swap", "vg0", "2.00G", "-wi-ao----"),
        ("home", "vg0", "4.62G", "-wi-ao----"),
    ]
    assert "pvs --reportformat json" in calls(tmp_path)


def test_btrfs_subvolumes_usage_and_scrub_text(tmp_path, env):
    r, rc = run(env, "btrfs")
    assert rc == 0 and r["have"] and r["error"] == ""
    assert [s["path"] for s in r["subvolumes"]] == [
        "@",
        "@home",
        "@var",
        "@home/.snapshots",
    ]
    assert [s["id"] for s in r["subvolumes"]] == [256, 257, 258, 259]
    assert r["subvolumes"][3]["parent"] == 257
    assert "Device size" in r["usage"] and "Free (estimated)" in r["usage"]
    assert "finished" in r["scrub"] and "no errors found" in r["scrub"]


def test_compsize_missing_is_absence_not_error(tmp_path, env):
    r, rc = run(env, "compression")
    assert rc == 0 and r["have"] and r["error"] == "" and len(r["lines"]) >= 2
    assert "compsize" in calls(tmp_path)

    (tmp_path / "compsize").unlink()
    assert run(env, "compression")[0] == {"have": False, "lines": [], "error": ""}


def test_smart_reports_health_temperature_and_model(env):
    r, rc = run(env, "smart")
    assert rc == 0 and r["have"] and len(r["disks"]) == 3
    assert next(d for d in r["disks"] if d["name"] == "sda") == {
        "name": "sda",
        "health": "healthy",
        "temp": "32",
        "model": "WDC WD10EZEX-00BN5A0",
    }


@pytest.mark.parametrize("verb", ["raid", "lvm", "btrfs", "compression", "smart"])
def test_every_verb_refuses_extra_argv(tmp_path, env, verb):
    before = calls(tmp_path)
    r, rc = run(env, verb, "extra")
    assert rc != 0 and "error" in r
    assert calls(tmp_path) == before


def test_one_failing_tool_does_not_blank_the_others(tmp_path, env):
    env["FAKE_SYSTEM_DISKS_FAIL"] = "vgs btrfs:usage smartctl:sdb"
    r, _ = run(env, "lvm")
    assert r["error"] and r["have"]
    assert len(r["pvs"]) == 2 and r["vgs"] == [] and len(r["lvs"]) == 3

    r, _ = run(env, "btrfs")
    assert r["error"] and r["have"]
    assert len(r["subvolumes"]) == 4 and r["usage"] == ""
    assert "no errors found" in r["scrub"]

    r, _ = run(env, "smart")
    by_name = {d["name"]: d for d in r["disks"]}
    assert set(by_name) == {"sda", "sdb", "nvme0n1"}
    assert by_name["sda"]["health"] == "healthy"
    assert by_name["sdb"]["health"] == "unknown"
    assert by_name["nvme0n1"]["model"]


def test_all_lvm_tools_failing_invents_no_rows(tmp_path, env):
    env["FAKE_SYSTEM_DISKS_FAIL"] = "pvs vgs lvs"
    r, _ = run(env, "lvm")
    assert r["have"] is False and r["error"]
    assert r["pvs"] == r["vgs"] == r["lvs"] == []
