"""bridge/system_smb.py against dev/fake-system-smb.py: testparm, pdbedit,
ss, units and usershares parse into plain data with no password leak; staging
refuses guests and bad names/paths; the write goes through pkexec with content
on stdin and the verb in argv.
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_smb.py"
FAKE = ROOT / "dev" / "fake-system-smb.py"

TESTPARM_OUT = """# Global parameters
[global]
\tworkgroup = WORKGROUP
\tserver string = Test server
[homes]
\tbrowseable = No
[Media]
\tpath = /srv/media
\tread only = No
\tguest ok = Yes
\tvalid users = alice
"""
PDBEDIT_OUT = """---------------
Unix username:        alice
Account Flags:        [U          ]
User SID:             S-1-5-21-4093113799-1968890848-1037594576-1000
Home Directory:       /home/alice
Password last set:    Sun, 04 Oct 2026 07:35:26 UTC
Lanman Password Hash: DEADBEEF0123456789
---------------
Unix username:        bob
Account Flags:        [DU         ]
User SID:             S-1-5-21-4093113799-1968890848-1037594576-1001
"""
SS_OUT = (
    'tcp LISTEN 0 50 0.0.0.0:445 0.0.0.0:* users:(("smbd",pid=159,fd=30))\n'
    'tcp LISTEN 0 50 0.0.0.0:139 0.0.0.0:* users:(("smbd",pid=159,fd=31))\n'
    "udp LISTEN 0 50 0.0.0.0:5353 0.0.0.0:*\n"
)


def setup(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    for name in ("testparm", "pdbedit", "ss", "systemctl", "pkexec"):
        (bin_dir / name).symlink_to(FAKE)
    usershares = tmp_path / "usershares"
    usershares.mkdir(exist_ok=True)
    env = dict(os.environ)
    env.update(
        {
            "FAKE_SYSTEM_SMB": str(tmp_path),
            "PATH": str(bin_dir) + ":" + os.environ["PATH"],
            "SHANI_TESTPARM": str(bin_dir / "testparm"),
            "SHANI_PDBEDIT": str(bin_dir / "pdbedit"),
            "SHANI_SS": str(bin_dir / "ss"),
            "SHANI_SYSTEMCTL": str(bin_dir / "systemctl"),
            "SHANI_USERSHARE_DIR": str(usershares),
            "SHANI_SYSTEM_PKEXEC": str(bin_dir / "pkexec"),
            "SHANI_ADMIN_TOOL": "/usr/lib/shani-shell/shani-admin.py",
        }
    )
    return env, usershares


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


def test_state_parses_tools_without_leaking_a_password(tmp_path):
    env, usershares = setup(tmp_path)
    (tmp_path / "testparm.out").write_text(TESTPARM_OUT)
    (tmp_path / "testparm.err").write_text("Loaded services file OK.\n")
    (tmp_path / "pdbedit.out").write_text(PDBEDIT_OUT)
    (tmp_path / "ss.out").write_text(SS_OUT)
    for unit, answer in (
        ("smb.service", "active"),
        ("nmb.service", "inactive"),
        ("winbind.service", "unknown"),
    ):
        (tmp_path / f"systemctl-{unit}.out").write_text(answer + "\n")
    (usershares / "alice").write_text("[Photos]\n\tpath = /home/alice/Photos\n")

    got, _ = call(env, "state")
    tp = got["testparm"]
    assert tp["available"] is True and tp["valid"] is True and tp["error"] == ""
    assert tp["globals"]["workgroup"] == "WORKGROUP"
    assert [s["name"] for s in tp["shares"]] == ["homes", "Media"]
    assert tp["shares"][1]["params"]["guest ok"] == "Yes"
    assert got["accounts"][0] == {
        "user": "alice",
        "flags": "[U          ]",
        "sid": "S-1-5-21-4093113799-1968890848-1037594576-1000",
        "home": "/home/alice",
        "passwordDate": "Sun, 04 Oct 2026 07:35:26 UTC",
    }
    assert got["accounts"][1]["flags"] == "[DU         ]"
    assert {p["port"]: p["listening"] for p in got["ports"]} == {445: True, 139: True}
    assert got["ports"][0]["process"] == "smbd"
    assert got["units"] == {"smb": "active", "nmb": "inactive", "winbind": "unknown"}
    assert got["usershares"] == [{"name": "Photos", "path": "/home/alice/Photos"}]
    assert got["configPath"] == "/etc/samba/smb.conf"
    assert "DEADBEEF" not in json.dumps(got)
    assert "Lanman" not in json.dumps(got)


def test_stage_refuses_guests_and_bad_input(tmp_path):
    env, _ = setup(tmp_path)
    guest, _ = call(
        env,
        "stage",
        {
            "shares": [
                {
                    "name": "Media",
                    "path": "/srv/media",
                    "users": ["alice"],
                    "guestOk": True,
                    "readOnly": True,
                }
            ]
        },
    )
    assert guest["refuse"] and guest["error"] == "guest_denied"
    for key, value, code in (
        ("name", "bad name", "bad_name"),
        ("name", "homes", "reserved_name"),
        ("path", "../etc", "bad_path"),
        ("users", ["Bad:User"], "bad_user"),
    ):
        req = {
            "shares": [
                {
                    "name": "Media",
                    "path": "/srv/media",
                    "users": ["alice"],
                    "guestOk": False,
                    "readOnly": True,
                }
            ]
        }
        req["shares"][0][key] = value
        got, _ = call(env, "stage", req)
        assert got["refuse"] and got["error"] == code


def test_stage_builds_guest_free_sections(tmp_path):
    env, _ = setup(tmp_path)
    req = {
        "shares": [
            {
                "name": "Media",
                "path": "/srv/media",
                "users": ["alice", "bob2"],
                "guestOk": False,
                "readOnly": False,
            },
        ]
    }
    got, _ = call(env, "stage", req)
    assert not got["refuse"] and got["error"] == ""
    assert got["sha256"] == hashlib.sha256(got["text"].encode()).hexdigest()
    assert got["shares"][0]["guestOk"] is False
    assert "[Media]" in got["text"]
    assert "   path = /srv/media" in got["text"]
    assert "   read only = no" in got["text"]
    assert "   guest ok = no" in got["text"]
    assert "   valid users = alice bob2" in got["text"]


def test_set_calls_helper_with_digest_and_argv_clean(tmp_path):
    env, _ = setup(tmp_path)
    (tmp_path / "testparm.out").write_text(TESTPARM_OUT)
    (tmp_path / "testparm.err").write_text("Loaded services file OK.\n")
    req = {
        "shares": [
            {
                "name": "Media",
                "path": "/srv/media",
                "users": ["alice"],
                "guestOk": False,
                "readOnly": True,
            },
        ]
    }
    got, _ = call(env, "set", req)
    assert got["ok"] is True and got["error"] == ""
    assert got["mode"] == "0644" and got["owner"] == "0:0"
    assert got["state"]["testparm"]["valid"] is True
    calls = (tmp_path / "calls").read_text().splitlines()
    argv_line = next(line for line in calls if line.startswith("pkexec "))
    assert "smb-share-set" in argv_line
    assert "/srv/media" not in argv_line
    sent = json.loads((tmp_path / "stdin").read_text())
    assert sent["sha256"] == hashlib.sha256(sent["text"].encode()).hexdigest()
    assert "   guest ok = no" in sent["text"]


def test_strict_tool_options(tmp_path):
    env, _ = setup(tmp_path)
    bin_dir = tmp_path / "bin"
    bad = subprocess.run(
        [str(bin_dir / "testparm"), "-s"], capture_output=True, text=True, env=env
    )
    assert bad.returncode == 2 and "invalid option" in bad.stderr
    good = subprocess.run(
        [str(bin_dir / "testparm"), "-s", "-d", "0"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert good.returncode == 0
