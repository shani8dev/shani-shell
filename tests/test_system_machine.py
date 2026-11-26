"""bridge/system_machine.py against dev/fake-system-info.py: one lspci read for
graphics, the privileged helper's JSON for system changes, strict path checks
before any helper command, and a read-only view of what lives under /data.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_machine.py"
FAKE = ROOT / "dev" / "fake-system-info.py"
TOOLS = ("lspci", "glxinfo", "shani-etc-changes")
MISSING = "/nonexistent/no-such-tool"

MOUNTINFO = """25 0 0:24 / / rw,relatime - overlay overlay rw,lowerdir=/data/lower
36 25 253:1 /home /var/lib/accounts rw,relatime - ext4 /dev/nvme0n1p4 rw
49 25 0:35 /data/apps /var/lib/apps rw,relatime - overlay overlay rw
50 25 0:36 /data/cache /var/cache/notes rw,relatime - overlay overlay rw
51 25 0:37 /data/home /home/someone rw,relatime - overlay overlay rw
52 25 0:38 tmpfs /var/tmp rw,nosuid - tmpfs tmpfs rw
"""


def setup(tmp_path, tools=TOOLS, dri=True, mounts=True, data=True):
    for name in TOOLS:
        p = tmp_path / name
        if name in tools and not p.exists():
            p.symlink_to(FAKE)
    dri_dir = tmp_path / "dri"
    if dri:
        dri_dir.mkdir(exist_ok=True)
        for name in ("renderD128", "renderD129", "card0"):
            (dri_dir / name).touch()
    mountinfo = tmp_path / "mountinfo"
    if mounts:
        mountinfo.write_text(MOUNTINFO, encoding="utf-8")
    data_dir = tmp_path / "data"
    if data:
        for name in ("accounts", "apps"):
            d = data_dir / name
            d.mkdir(parents=True, exist_ok=True)
            (d / "file").write_bytes(b"x" * 2048)
        (data_dir / "loose-file").write_text("not a dir", encoding="utf-8")
    return dri_dir, mountinfo, data_dir


def run(tmp_path, *args, env_extra=None, **kw):
    dri_dir, mountinfo, data_dir = setup(tmp_path, **kw)
    env = dict(
        os.environ,
        FAKE_SYSTEM_INFO=str(tmp_path),
        PATH="%s:%s" % (tmp_path, os.environ["PATH"]),
    )
    for k in (
        "SHANI_LSPCI",
        "SHANI_GLXINFO",
        "SHANI_ETC_CHANGES",
        "SHANI_DRI_DIR",
        "SHANI_MOUNTINFO",
        "SHANI_DATA_DIR",
        "SHANI_DATA_SIZE",
        "FAKE_SYSTEM_INFO_FAIL",
        "FAKE_SYSTEM_ETC_DIR",
        "FAKE_SYSTEM_ETC_FAIL",
    ):
        env.pop(k, None)
    env["SHANI_LSPCI"] = (
        str(tmp_path / "lspci") if "lspci" in kw.get("tools", TOOLS) else MISSING
    )
    env["SHANI_GLXINFO"] = (
        str(tmp_path / "glxinfo") if "glxinfo" in kw.get("tools", TOOLS) else MISSING
    )
    env["SHANI_ETC_CHANGES"] = (
        str(tmp_path / "shani-etc-changes")
        if "shani-etc-changes" in kw.get("tools", TOOLS)
        else MISSING
    )
    env["SHANI_DRI_DIR"] = str(dri_dir)
    env["SHANI_MOUNTINFO"] = str(mountinfo)
    env["SHANI_DATA_DIR"] = str(data_dir)
    if env_extra:
        env.update(env_extra)
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env
    )
    return json.loads(r.stdout), r.returncode


def calls(tmp_path):
    p = tmp_path / "calls"
    return p.read_text(encoding="utf-8").splitlines() if p.exists() else []


def test_graphics_reads_blocks_render_nodes_and_renderer(tmp_path):
    got, rc = run(tmp_path, "graphics")
    assert rc == 0
    assert got == {
        "have": {"lspci": True},
        "devices": [
            {
                "name": "Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics]",
                "driver": "i915",
                "vendor": "Intel Corporation",
            },
            {
                "name": "NVIDIA Corporation TU117M [GeForce GTX 1650 Mobile]",
                "driver": "nvidia",
                "vendor": "NVIDIA Corporation",
            },
            {
                "name": "Advanced Micro Devices, Inc. [AMD/ATI] Topaz XT [Radeon R7 M260]",
                "driver": "",
                "vendor": "AMD",
            },
        ],
        "render": [
            str(tmp_path / "dri" / "renderD128"),
            str(tmp_path / "dri" / "renderD129"),
        ],
        "gl": "Mesa Intel(R) Xe Graphics (TGL GT2)",
    }
    assert calls(tmp_path) == ["lspci -nnk", "glxinfo -B"]


def test_graphics_without_lspci_is_honest_but_still_shows_render_nodes(tmp_path):
    got, _ = run(tmp_path, "graphics", tools=("glxinfo",))
    assert got["have"]["lspci"] is False and got["devices"] == []
    assert len(got["render"]) == 2 and got["gl"].startswith("Mesa")
    assert "glxinfo -B" in calls(tmp_path) and not any(
        "lspci" in c for c in calls(tmp_path)
    )


def test_etc_list_uses_the_helper_json(tmp_path):
    got, rc = run(tmp_path, "etc-list")
    assert rc == 0
    assert got == {
        "ok": True,
        "changes": [
            {
                "path": "/etc/hosts",
                "kind": "edited file",
                "protected": False,
                "secret": False,
                "pending": True,
            },
            {
                "path": "/etc/ssh/sshd_config",
                "kind": "settings",
                "protected": True,
                "secret": False,
                "pending": True,
            },
            {
                "path": "/etc/shadow",
                "kind": "password file",
                "protected": True,
                "secret": True,
                "pending": False,
            },
        ],
        "pending": ["/etc/hosts", "/etc/ssh/sshd_config"],
        "done": ["/etc/shadow"],
        "error": "",
    }
    assert calls(tmp_path) == ["shani-etc-changes list --json"]


def test_etc_list_failure_never_invents_rows(tmp_path):
    got, rc = run(
        tmp_path, "etc-list", env_extra={"FAKE_SYSTEM_INFO_FAIL": "shani-etc-changes"}
    )
    assert rc == 1
    assert got == {
        "ok": False,
        "changes": [],
        "pending": [],
        "done": [],
        "error": "tool failed on purpose",
    }
    fixture = tmp_path / "etcfix"
    fixture.mkdir()
    (fixture / "list.json").write_text("not json at all", encoding="utf-8")
    got, _ = run(tmp_path, "etc-list", env_extra={"FAKE_SYSTEM_ETC_DIR": str(fixture)})
    assert got["ok"] is False and got["error"] and not got["changes"]
    (fixture / "list.json").write_text(
        json.dumps({"ok": False, "error": "overlay is locked", "changes": []}),
        encoding="utf-8",
    )
    got, _ = run(tmp_path, "etc-list", env_extra={"FAKE_SYSTEM_ETC_DIR": str(fixture)})
    assert got == {
        "ok": False,
        "changes": [],
        "pending": [],
        "done": [],
        "error": "overlay is locked",
    }


def test_etc_verbs_pass_the_exact_path_and_hide_secrets(tmp_path):
    assert run(tmp_path, "etc-diff", "/etc/hosts")[0] == {
        "ok": True,
        "diff": "--- a/etc/hosts\n+++ b/etc/hosts\n@@ -1 +1 @@\n-old line\n+new line\n",
        "hidden": False,
        "binary": False,
        "error": "",
    }
    assert run(tmp_path, "etc-diff", "/etc/shadow")[0]["hidden"] is True
    assert run(tmp_path, "etc-diff", "/etc/logo.png")[0]["binary"] is True
    assert run(tmp_path, "etc-restore", "/etc/hosts")[0] == {
        "ok": True,
        "queued": True,
        "error": "",
    }
    assert run(tmp_path, "etc-cancel", "/etc/hosts")[0] == {
        "ok": True,
        "queued": False,
        "error": "",
    }
    assert calls(tmp_path) == [
        "shani-etc-changes diff /etc/hosts",
        "shani-etc-changes diff /etc/shadow",
        "shani-etc-changes diff /etc/logo.png",
        "shani-etc-changes restore /etc/hosts",
        "shani-etc-changes cancel /etc/hosts",
    ]


def test_bad_paths_are_rejected_before_the_helper_runs(tmp_path):
    before = calls(tmp_path)
    bad = (
        "../etc/shadow",
        "; rm -rf ~",
        "/etc/../shadow",
        "etc/passwd",
        "/etc/shadow;",
        "/" + "a" * 250,
    )
    for path in bad:
        for verb in ("etc-diff", "etc-restore", "etc-cancel"):
            got, rc = run(tmp_path, verb, path)
            assert rc == 1 and got["error"] and got["ok"] is False
    assert calls(tmp_path) == before
    good = "/etc/shani-etc.d/file_1+a.conf"
    assert run(tmp_path, "etc-diff", good)[0]["ok"] is True
    assert calls(tmp_path) == before + ["shani-etc-changes diff " + good]


def test_persistence_reads_bind_mounts_and_data_dirs(tmp_path):
    got, _ = run(tmp_path, "persistence")
    assert got["error"] == ""
    assert got["mounts"] == [
        {
            "path": "/var/lib/apps",
            "source": "/data/apps",
            "note": "kept across system updates",
        },
        {
            "path": "/var/cache/notes",
            "source": "/data/cache",
            "note": "kept across system updates",
        },
    ]
    assert got["data"] == [
        {"path": str(tmp_path / "data" / "accounts"), "size": ""},
        {"path": str(tmp_path / "data" / "apps"), "size": ""},
    ]
    sized, _ = run(tmp_path, "persistence", env_extra={"SHANI_DATA_SIZE": "1"})
    assert all(d["size"] == "2 KB" for d in sized["data"])
    unreadable, _ = run(tmp_path, "persistence", env_extra={"SHANI_MOUNTINFO": MISSING})
    assert (
        unreadable["mounts"] == []
        and unreadable["error"]
        and len(unreadable["data"]) == 2
    )
    assert calls(tmp_path) == []  # persistence reads files, never starts a tool
