"""bridge/system_nfs.py against dev/fake-system-nfs.py and a real exports file:
one row per path and client, canonical options and risk warnings, strict
staging, and a privileged write whose content is on stdin, never in argv.
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_nfs.py"
FAKE = ROOT / "dev" / "fake-system-nfs.py"


def setup(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    for name in ("exportfs", "pkexec"):
        (bin_dir / name).symlink_to(FAKE)
    exports = tmp_path / "exports.d" / "50-shani-shell.exports"
    exports.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update(
        {
            "FAKE_SYSTEM_NFS": str(tmp_path),
            "PATH": str(bin_dir) + ":" + os.environ["PATH"],
            "SHANI_EXPORTS_FILE": str(exports),
            "SHANI_SYSTEM_PKEXEC": str(bin_dir / "pkexec"),
            "SHANI_ADMIN_TOOL": "/usr/lib/shani-shell/shani-admin.py",
        }
    )
    return env, exports


def call(env, verb, payload=None):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), verb],
        input=json.dumps(payload) if payload is not None else "",
        capture_output=True,
        text=True,
        env=env,
    )
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout), r


def test_exports_parse_options_and_warnings(tmp_path):
    env, exports = setup(tmp_path)
    exports.write_text(
        "# Managed by this system\n"
        "/srv/data 192.168.1.0/24(ro,sync,no_root_squash) @staff(all_squash)\n"
        "/srv/bad 10.0.0.1(mystery)\n"
        "not a path at all\n"
    )
    got, _ = call(env, "exports")
    assert got["error"] == "" and got["path"] == str(exports)
    assert len(got["rows"]) == 1
    row = got["rows"][0]
    assert row["path"] == "/srv/data" and row["editable"] is True
    assert row["clients"][0]["options"] == ["ro", "sync", "no_root_squash"]
    assert row["clients"][0]["warnings"] == ["no_root_squash"]
    assert row["warnings"] == ["no_root_squash", "all_squash"]
    assert "# Managed by this system" in got["kept"]
    assert len(got["unreadable"]) == 2


def test_stage_refuses_exclusive_unknown_and_traversal(tmp_path):
    env, _ = setup(tmp_path)
    clash, _ = call(
        env,
        "stage",
        {
            "rows": [
                {
                    "path": "/srv/data",
                    "clients": [{"client": "*", "options": ["ro", "rw"]}],
                }
            ]
        },
    )
    assert clash["refuse"] and clash["error"] == "exclusive_clash"
    group, _ = call(
        env,
        "stage",
        {
            "rows": [
                {
                    "path": "/srv/data",
                    "clients": [
                        {"client": "*", "options": ["root_squash", "no_root_squash"]}
                    ],
                }
            ]
        },
    )
    assert group["refuse"] and group["error"] == "exclusive_clash"
    unknown, _ = call(
        env,
        "stage",
        {
            "rows": [
                {
                    "path": "/srv/data",
                    "clients": [{"client": "*", "options": ["bogus"]}],
                }
            ]
        },
    )
    assert unknown["refuse"] and unknown["error"] == "unknown_option"
    dotdot, _ = call(
        env,
        "stage",
        {"rows": [{"path": "../etc", "clients": [{"client": "*", "options": ["ro"]}]}]},
    )
    assert dotdot["refuse"] and dotdot["error"] == "bad_path"


def test_stage_digest_and_remove_confirmation(tmp_path):
    env, _ = setup(tmp_path)
    req = {
        "rows": [
            {
                "path": "/srv/data",
                "clients": [
                    {
                        "client": "192.168.1.0/24",
                        "options": ["sync", "ro", "root_squash"],
                    }
                ],
            }
        ]
    }
    staged, _ = call(env, "stage", req)
    assert not staged["refuse"] and staged["error"] == ""
    assert staged["sha256"] == hashlib.sha256(staged["text"].encode()).hexdigest()
    assert "/srv/data 192.168.1.0/24(ro,sync,root_squash)" in staged["text"]
    assert staged["warnings"] == []
    need, _ = call(env, "stage", {"rows": []})
    assert need["refuse"] and need["error"] == "needsConfirm"
    cleared, _ = call(env, "stage", {"rows": [], "confirm": "REMOVE ALL"})
    assert (
        not cleared["refuse"] and cleared["text"].strip() == "# Managed by this system"
    )


def test_unreadable_lines_are_never_canonicalised(tmp_path):
    env, exports = setup(tmp_path)
    exports.write_text("/srv/ok 192.168.1.0/24(ro,sync)\n/srv/bad 10.0.0.1(mystery)\n")
    read, _ = call(env, "exports")
    assert read["unreadable"] == ["/srv/bad 10.0.0.1(mystery)"]
    staged, _ = call(env, "stage", {"rows": read["rows"], "other": read["kept"]})
    assert not staged["refuse"]
    assert "mystery" not in staged["text"]
    assert len(staged["rows"]) == 1
    refused, _ = call(
        env,
        "stage",
        {
            "rows": [
                {
                    "path": "/srv/bad",
                    "clients": [{"client": "10.0.0.1", "options": ["mystery"]}],
                }
            ]
        },
    )
    assert refused["refuse"] and refused["error"] == "unknown_option"


def test_set_uses_helper_with_digest_on_stdin(tmp_path):
    env, _ = setup(tmp_path)
    req = {
        "rows": [
            {
                "path": "/srv/data",
                "clients": [{"client": "192.168.1.0/24", "options": ["ro", "sync"]}],
            }
        ]
    }
    got, _ = call(env, "set", req)
    assert got["ok"] is True and got["error"] == ""
    assert got["mode"] == "0644" and got["owner"] == "0:0"
    assert got["exports"]["path"].endswith("50-shani-shell.exports")
    calls = (tmp_path / "calls").read_text().splitlines()
    argv_line = next(line for line in calls if line.startswith("pkexec "))
    assert "nfs-exports-set" in argv_line
    assert "/srv/data" not in argv_line
    sent = json.loads((tmp_path / "stdin").read_text())
    assert sent["sha256"] == hashlib.sha256(sent["text"].encode()).hexdigest()
    assert "/srv/data 192.168.1.0/24(ro,sync)" in sent["text"]


def test_strict_exportfs_stand_in(tmp_path):
    env, _ = setup(tmp_path)
    bin_dir = tmp_path / "bin"
    bad = subprocess.run(
        [str(bin_dir / "exportfs"), "-x"], capture_output=True, text=True, env=env
    )
    assert bad.returncode == 2 and "invalid option" in bad.stderr
    good = subprocess.run(
        [str(bin_dir / "exportfs"), "-ra"], capture_output=True, text=True, env=env
    )
    assert good.returncode == 0
