"""bridge/system_security_boot.py against dev/fake-gen-efi.py.

The bridge runs as a subprocess, so its JSON-out contract is checked for real.
Secrets go on stdin only; the fake logs subcommand + options, never secrets.
"""

import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_security_boot.py"
FAKE = ROOT / "dev" / "fake-gen-efi.py"
KEY_RE = re.compile(r"[cbdefghijklnrtuv]{8}(-[cbdefghijklnrtuv]{8}){7}")


def env(tmp_path, **extra):
    base = dict(
        os.environ,
        SHANI_SECURITY_PKEXEC=sys.executable,
        SHANI_GEN_EFI=str(FAKE),
        FAKE_GEN_EFI_DIR=str(tmp_path),
    )
    base.pop("FAKE_GEN_EFI_FAIL", None)
    base.update(extra)
    return base


def run(tmp_path, *args, body="", **extra):
    return subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        input=body,
        capture_output=True,
        text=True,
        cwd=tmp_path,
        env=env(tmp_path, **extra),
    )


def fake(tmp_path, *args, body=b"", **extra):
    return subprocess.run(
        [sys.executable, str(FAKE), *args],
        input=body,
        capture_output=True,
        cwd=tmp_path,
        env=env(tmp_path, **extra),
    )


def one_json(r):
    lines = [json.loads(line) for line in r.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, r.stdout
    return lines[0]


def calls(tmp_path):
    path = tmp_path / "calls"
    return path.read_text() if path.exists() else ""


def files(tmp_path):
    return [p for p in tmp_path.rglob("*") if p.is_file()]


STATUS = {
    "encrypted-tpm": {
        "ok": True,
        "encrypted": True,
        "tpm2_present": True,
        "tpm2_enrolled": True,
        "tpm2_pin": False,
        "tpm2_slots": 1,
        "secure_boot": True,
        "luks": {
            "version": "2",
            "cipher": "aes-xts-plain64",
            "kdf": "argon2id",
            "keyslots": 1,
            "device": "/dev/nvme0n1p3",
        },
        "policy": {
            "available": True,
            "mode": "literal",
            "literal_pcrs": "7",
            "policy_hash": None,
            "entry_tokens": ["tok-a", "tok-b"],
            "path": "/etc/secureboot/pcrlock.json",
        },
        "error": "",
    },
    "encrypted-tpm-pin": {
        "ok": True,
        "encrypted": True,
        "tpm2_present": True,
        "tpm2_enrolled": True,
        "tpm2_pin": True,
        "tpm2_slots": 1,
        "secure_boot": True,
        "luks": {
            "version": "2",
            "cipher": "aes-xts-plain64",
            "kdf": "argon2id",
            "keyslots": 1,
            "device": "/dev/nvme0n1p3",
        },
        "policy": {
            "available": True,
            "mode": "pcrlock",
            "literal_pcrs": None,
            "policy_hash": "b0d3" * 16,
            "entry_tokens": ["tok-a"],
            "path": "/etc/secureboot/pcrlock.json",
        },
        "error": "",
    },
    "encrypted-no-tpm": {
        "ok": True,
        "encrypted": True,
        "tpm2_present": False,
        "tpm2_enrolled": False,
        "tpm2_pin": False,
        "tpm2_slots": 0,
        "secure_boot": True,
        "luks": {
            "version": "2",
            "cipher": "aes-xts-plain64",
            "kdf": "argon2id",
            "keyslots": 1,
            "device": "/dev/nvme0n1p3",
        },
        "policy": {
            "available": True,
            "mode": None,
            "literal_pcrs": None,
            "policy_hash": None,
            "entry_tokens": [],
            "path": "/etc/secureboot/pcrlock.json",
        },
        "error": "",
    },
    "plain": {
        "ok": True,
        "encrypted": False,
        "tpm2_present": False,
        "tpm2_enrolled": False,
        "tpm2_pin": False,
        "tpm2_slots": 0,
        "secure_boot": False,
        "luks": {
            "version": "",
            "cipher": "",
            "kdf": "",
            "keyslots": None,
            "device": "",
        },
        "policy": {
            "available": False,
            "mode": None,
            "literal_pcrs": None,
            "policy_hash": None,
            "entry_tokens": [],
            "path": None,
        },
        "error": "",
    },
}


@pytest.mark.parametrize("state", sorted(STATUS))
def test_status_merges_both_json_documents(tmp_path, state):
    (tmp_path / "state").write_text(state)
    r = run(tmp_path, "status")
    assert r.returncode == 0
    assert one_json(r) == STATUS[state]
    assert "tpm2-status --json" in calls(tmp_path)
    assert "pcrlock-status --json" in calls(tmp_path)


def test_status_keeps_the_working_read_when_one_fails(tmp_path):
    (tmp_path / "state").write_text("encrypted-tpm")
    r = run(tmp_path, "status", FAKE_GEN_EFI_FAIL="pcrlock-status")
    got = one_json(r)
    assert r.returncode == 0 and got["ok"] is False and got["error"]
    assert got["encrypted"] is True and got["tpm2_enrolled"] is True
    assert got["luks"]["version"] == "2"
    assert got["policy"] == STATUS["plain"]["policy"]


@pytest.mark.parametrize(
    "sub,fields",
    [
        (
            "tpm2-status",
            {
                "encrypted",
                "tpm2_present",
                "tpm2_enrolled",
                "tpm2_slots",
                "tpm2_pin",
                "secure_boot",
                "luks_device",
                "luks_version",
                "luks_cipher",
                "luks_kdf",
                "luks_keyslots_in_use",
            },
        ),
        (
            "pcrlock-status",
            {
                "pcrlock_policy_available",
                "pcrlock_policy_path",
                "enrolled_mode",
                "literal_pcrs",
                "policy_hash",
                "entry_tokens",
                "luks_device",
            },
        ),
    ],
)
def test_fake_emits_gen_efi_field_names(tmp_path, sub, fields):
    r = fake(tmp_path, sub, "--json")
    assert r.returncode == 0
    assert set(json.loads(r.stdout)) == fields


@pytest.mark.parametrize(
    "pin,body,expected_call,state",
    [
        ("", "right passphrase\n", "enroll-tpm2 --stdin", "encrypted-tpm"),
        (
            "987654",
            "right passphrase\n987654\n",
            "enroll-tpm2 --stdin --with-pin",
            "encrypted-tpm-pin",
        ),
    ],
)
def test_enroll_sends_secrets_on_stdin_only(tmp_path, pin, body, expected_call, state):
    r = run(tmp_path, "enroll", body=body)
    got = one_json(r)
    assert r.returncode == 0 and got == {"ok": True, "error": ""}
    assert (tmp_path / "state").read_text().strip() == state
    assert calls(tmp_path).strip() == expected_call
    for secret in ("right passphrase", pin):
        if secret:
            assert secret not in r.stdout and secret not in r.stderr
            assert all(
                secret not in p.read_bytes().decode("utf-8", "replace")
                for p in files(tmp_path)
            )


@pytest.mark.parametrize(
    "body",
    ["", "\n987654\n", "right passphrase\n\n", "right passphrase\n987654\nextra\n"],
)
def test_enroll_rejects_bad_secret_lines(tmp_path, body):
    r = run(tmp_path, "enroll", body=body)
    got = one_json(r)
    assert r.returncode == 0 and got["ok"] is False and got["error"]
    assert not calls(tmp_path)


def test_remove_sends_confirmation_and_flips_state(tmp_path):
    (tmp_path / "state").write_text("encrypted-tpm")
    r = run(tmp_path, "remove", body="y\n")
    assert r.returncode == 0
    assert one_json(r) == {"ok": True, "error": ""}
    assert (tmp_path / "state").read_text().strip() == "encrypted-no-tpm"
    assert calls(tmp_path).strip() == "remove-tpm2"


def test_fake_remove_needs_a_confirmation(tmp_path):
    (tmp_path / "state").write_text("encrypted-tpm")
    r = fake(tmp_path, "remove-tpm2", body=b"n\n")
    assert r.returncode == 0
    assert (tmp_path / "state").read_text().strip() == "encrypted-tpm"


def test_recovery_key_is_shown_once_and_never_saved(tmp_path):
    r = run(tmp_path, "recovery-key", body="right passphrase\n")
    got = one_json(r)
    assert r.returncode == 0 and got["ok"] is True and got["error"] == ""
    assert KEY_RE.fullmatch(got["key"])
    assert r.stdout.count(got["key"]) == 1
    raw_dir = tmp_path / "raw"
    raw_dir.mkdir()
    raw = fake(raw_dir, "recovery-key", "--stdin", body=b"right passphrase\n")
    assert raw.stdout.decode("utf-8").count("RECOVERY_KEY=") == 1
    assert calls(tmp_path).strip() == "recovery-key --stdin"
    assert "right passphrase" not in r.stdout + r.stderr + calls(tmp_path)
    for p in files(tmp_path):
        assert got["key"] not in p.read_bytes().decode("utf-8", "replace")


def test_header_backup_is_binary_and_private(tmp_path):
    target = tmp_path / "header.bak"
    r = run(tmp_path, "header-backup", str(target))
    got = one_json(r)
    assert r.returncode == 0 and got["ok"] is True and got["error"] == ""
    assert got["path"] == str(target) and got["bytes"] > 0
    data = target.read_bytes()
    assert data.startswith(b"LUKS\xba\xbe") and len(data) == got["bytes"]
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    assert calls(tmp_path).strip() == "luks-header-backup"


@pytest.mark.parametrize("path", ["relative.bak", "", "sub/header.bak"])
def test_header_backup_refuses_non_absolute_paths(tmp_path, path):
    r = run(tmp_path, "header-backup", path)
    assert r.returncode == 2 and not r.stdout
    assert "usage" in r.stderr.lower()
    assert not calls(tmp_path)
    assert not list(tmp_path.glob("**/*.bak"))


@pytest.mark.parametrize("action", ["enroll-mok", "cleanup-mok"])
def test_mok_actions_use_the_real_subcommands(tmp_path, action):
    r = run(tmp_path, action)
    assert r.returncode == 0
    assert one_json(r) == {"ok": True, "error": ""}
    assert calls(tmp_path).strip() == action


@pytest.mark.parametrize(
    "args",
    [
        (),
        ("bogus",),
        ("status", "extra"),
        ("enroll", "extra"),
        ("recovery-key", "--stdin"),
        ("header-backup",),
        ("header-backup", str(Path("/tmp") / "h"), "extra"),
    ],
)
def test_bad_bridge_argv_exits_two(tmp_path, args):
    r = run(tmp_path, *args)
    assert r.returncode == 2 and not r.stdout
    assert "usage" in r.stderr.lower()
    assert not calls(tmp_path)


@pytest.mark.parametrize(
    "args",
    [
        ("tpm2-status", "--bad"),
        ("tpm2-status",),
        ("pcrlock-status",),
        ("pcrlock-status", "--bad"),
        ("recovery-key",),
        ("enroll-tpm2",),
        ("enroll-tpm2", "--with-pin"),
        ("enroll-tpm2", "--stdin", "--bad"),
        ("luks-header-backup", "--extra"),
        ("cleanup-tpm2",),
        ("bogus",),
    ],
)
def test_fake_rejects_what_gen_efi_rejects(tmp_path, args):
    r = fake(tmp_path, *args, body=b"right passphrase\n")
    assert r.returncode == 2 and not r.stdout
    assert "usage" in r.stderr.decode("utf-8").lower()
    assert not calls(tmp_path)


def test_the_page_saves_a_recovery_key_private(tmp_path):
    # The page writes the shown key to a file the person picks. Read the very
    # command out of the QML so this cannot pass while the page writes 0644.
    qml = (ROOT / "shani/Modules/Settings/SettingsEncryptionBoot.qml").read_text()
    m = re.search(r'saveKeyProc\.command = \["python3", "-c", "(.*?)", path\]', qml)
    assert m, "the page no longer writes the key through its own command"
    target = tmp_path / "key.txt"
    r = subprocess.run(
        [sys.executable, "-c", m.group(1).replace("\\\\", "\\"), str(target)],
        input="a-recovery-key\n",
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    assert target.read_text().strip() == "a-recovery-key"
