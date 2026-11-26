"""Gap 8, 13 and 6 of bridge/system_access.py: PAM stack wiring, reader states,
staged mapping and sshd drop-ins, and sudoers rows. Every answer is JSON, every
outside command is a rejecting stand-in, and no secret reaches the output.
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_access.py"
FAKE = ROOT / "dev" / "fake-system-access.py"


def setup(tmp_path, commands=("systemctl", "ssh-keygen", "pcsc_scan", "oathtool")):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    for name in commands:
        (bin_dir / name).symlink_to(FAKE)
    etc = tmp_path / "etc"
    etc.mkdir(exist_ok=True)
    env = dict(os.environ)
    env.update(
        {
            "FAKE_SYSTEM_ACCESS": str(tmp_path),
            "PATH": str(bin_dir) + ":" + os.environ["PATH"],
            "SHANI_SYSTEM_SYSTEMCTL": "systemctl",
            "SHANI_NSSWITCH": str(etc / "nsswitch.conf"),
            "SHANI_KRB5_CONF": str(etc / "krb5.conf"),
            "SHANI_KRB5_CCACHE": str(tmp_path / "krb5cc_*"),
            "SHANI_SYSTEM_PAM_DIR": str(tmp_path / "pam.d"),
            "SHANI_PKCS11_CONF": str(etc / "pam_pkcs11.conf"),
            "SHANI_PKCS11_MAP": str(etc / "subject_mapping"),
            "SHANI_POLKIT_DIR": str(etc / "polkit-1" / "rules.d"),
            "SHANI_SUDOERS": str(etc / "sudoers.d" / "50-shani-shell"),
            "SHANI_SSHD_CONF": str(etc / "sshd_config.d" / "50-shani-shell.conf"),
            "SHANI_LSM_FILE": str(tmp_path / "lsm"),
            "SHANI_SYSTEM_SSH_KEYGEN": "ssh-keygen",
            "SHANI_AUTHORIZED_KEYS": str(tmp_path / "authorized_keys"),
            "SHANI_OATH_FILE": str(etc / "users.oath"),
            "SHANI_OATHTOOL": "oathtool",
            "SHANI_PCSC_SCAN": "pcsc_scan",
        }
    )
    return env


def call(env, verb, req=None):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), verb],
        input=json.dumps(req) if req is not None else None,
        capture_output=True,
        text=True,
        env=env,
    )
    return json.loads(r.stdout), r


def pam(tmp_path, files):
    directory = tmp_path / "pam.d"
    directory.mkdir(exist_ok=True)
    for name, text in files.items():
        (directory / name).write_text(text)
    return directory


def oath_file(tmp_path, path, text):
    path = tmp_path / path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o600)
    return path


def test_pam_include_wires_oath_usersfile_and_hidden_file(tmp_path):
    env = setup(tmp_path)
    chosen = oath_file(
        tmp_path,
        "etc/oath/second.oath",
        "HOTP/T30/6 alice - SECRETALICE\n"
        "TOTP/T30/8 bob - SECRETBOB\n"
        "# HOTP/T30/6 carol - SECRETCAROL\n"
        "# just a note\n"
        "not a record\n",
    )
    first = tmp_path / "etc" / "oath" / "first.oath"
    first.parent.mkdir(parents=True, exist_ok=True)
    first.write_text("HOTP/T30/6 dave - SECRETDAVE\n")
    pam(
        tmp_path,
        {
            "common-auth": "@include common-oath\n",
            "common-oath": (
                'auth sufficient pam_oath.so usersfile="'
                + str(first)
                + '" try_first_pass\n'
                + "-auth required pam_oath.so usersfile="
                + str(chosen)
                + "\n"
            ),
        },
    )
    got, _ = call(env, "totp")
    assert got["pamWired"] is True
    assert "common-oath" in got["pamStacks"]
    assert got["usersfile"] == str(chosen)
    assert got["readable"] is True and got["unknown"] is False
    assert got["mode"] == "600" and ":" in got["owner"]
    assert got["skipped"] == 2
    assert got["toolVersion"] == "oathtool 2.4.1"
    assert got["users"] == [
        {"user": "alice", "enabled": True, "digits": 6, "period": 30},
        {"user": "bob", "enabled": True, "digits": 8, "period": 30},
        {"user": "carol", "enabled": False, "digits": 6, "period": 30},
    ]
    assert "SECRET" not in json.dumps(got)

    hidden = oath_file(
        tmp_path, "etc/oath/hidden.oath", "TOTP/T30/6 mallory - SECRETMALLORY\n"
    )
    if os.access(hidden, os.R_OK):
        hidden.chmod(0o000)
    if os.access(hidden, os.R_OK):  # root can still read a mode-000 file
        hidden.unlink()
        hidden.mkdir()
    (tmp_path / "pam.d" / "common-oath").unlink()
    pam(
        tmp_path,
        {"common-auth": "auth required pam_oath.so usersfile=" + str(hidden) + "\n"},
    )
    unknown, _ = call(env, "totp")
    assert unknown["unknown"] is True and unknown["readable"] is False
    assert unknown["users"] == [] and unknown["error"]
    assert "SECRETMALLORY" not in json.dumps(unknown)


def test_reader_states_and_pkcs11_from_included_stack(tmp_path):
    env = setup(tmp_path)
    pam(
        tmp_path,
        {
            "common-auth": "@include common-pkcs11\n",
            "common-pkcs11": "auth sufficient pam_pkcs11.so try_first_pass\n",
        },
    )
    fixture = tmp_path / "pcsc_scan.out"
    fixture.write_text(
        "Scanning present readers...\n"
        "Reader 0: GemPC Twin 00 00\n"
        "  Card state: Card inserted\n"
        "  ATR: 3B00 PIN1234 CERTBYTES\n"
    )
    got, _ = call(env, "smartcard")
    assert got["readers"] == [{"state": "ready", "name": "GemPC Twin 00 00"}]
    assert got["pamPkcs11"] is True
    assert "PIN1234" not in json.dumps(got) and "CERTBYTES" not in json.dumps(got)

    fixture.write_text("PCSC daemon is not running\n")
    down, _ = call(env, "smartcard")
    assert down["readers"] == [{"state": "daemon_down", "name": ""}]

    fixture.write_text("Scanning present readers...\n")
    empty, _ = call(env, "smartcard")
    assert empty["readers"] == [{"state": "no_reader", "name": ""}]

    missing, _ = call(dict(env, SHANI_PCSC_SCAN="no-such-pcsc-scan"), "smartcard")
    assert missing["readers"] == [{"state": "tool_missing", "name": ""}]


def test_smartcard_stage_keeps_comments_and_refuses_bad_mappings(tmp_path):
    env = setup(tmp_path)
    mapping = tmp_path / "etc" / "subject_mapping"
    mapping.parent.mkdir(parents=True, exist_ok=True)
    mapping.write_text("# keep this comment\nalice@example -> alice\n\nother note\n")
    got, _ = call(
        env,
        "smartcard-stage",
        {"mappings": [{"identity": "bob@example", "login": "bob"}]},
    )
    assert got["refuse"] is False and got["error"] == ""
    assert "# keep this comment\n" in got["text"]
    assert "other note\n" in got["other"]
    assert "alice@example -> alice" not in got["text"]
    assert "bob@example -> bob\n" in got["text"]
    assert got["sha256"] == hashlib.sha256(got["text"].encode("utf-8")).hexdigest()
    assert got["mappings"] == [{"identity": "bob@example", "login": "bob"}]

    dupe, _ = call(
        env,
        "smartcard-stage",
        {
            "mappings": [
                {"identity": "a", "login": "b"},
                {"identity": "a", "login": "b"},
            ]
        },
    )
    assert dupe["refuse"] is True and dupe["error"] == "duplicate_mapping"
    bad, _ = call(
        env,
        "smartcard-stage",
        {
            "mappings": [
                {"identity": "a->b", "login": "b"},
                {"identity": "ok", "login": ""},
                {"identity": "a\nb", "login": "b"},
                {"identity": "x" * 257, "login": "b"},
            ]
        },
    )
    assert bad["refuse"] is True and bad["error"] == "bad_mapping"


def test_sudoers_rows_and_sshd_stage(tmp_path):
    env = setup(tmp_path)
    sudoers = tmp_path / "etc" / "sudoers.d" / "50-shani-shell"
    sudoers.parent.mkdir(parents=True, exist_ok=True)
    sudoers.write_text(
        "%wheel ALL=(ALL) NOPASSWD: ALL\n# note\nDefaults !requiretty\nweird line\n"
    )
    s, _ = call(env, "sudoers")
    assert len(s["rows"]) == 1
    row = s["rows"][0]
    assert row["who"] == "%wheel ALL" and row["runas"] == "ALL"
    assert row["tags"] == ["NOPASSWD"] and row["commands"] == ["ALL"]
    assert row["nopasswd"] is True and row["warning"] == "all_commands"
    assert any("# note\n" in line for line in s["other"])
    assert any("Defaults" in line for line in s["other"])
    assert any("weird line" in line for line in s["unreadable"])

    dropin = tmp_path / "etc" / "sshd_config.d" / "50-shani-shell.conf"
    dropin.parent.mkdir(parents=True, exist_ok=True)
    dropin.write_text(
        "PasswordAuthentication yes\n"
        "Match User alice\n"
        "X11Forwarding no\n"
        "KeyValue=abc\n"
        "AuthorizedKeysCommand /usr/bin/fetch --token SECRETVALUE123456\n"
    )
    req = {
        "password": False,
        "pubkey": True,
        "root": "prohibit-password",
        "allowUsers": "alice bob",
        "allowGroups": "wheel",
        "tcpForwarding": False,
        "x11Forwarding": False,
        "maxAuthTries": 5,
    }
    staged, _ = call(env, "sshd-stage", req)
    assert staged["refuse"] is True
    assert any("Match User alice\n" == line for line in staged["unreadable"])
    assert any("KeyValue=abc\n" == line for line in staged["unreadable"])
    assert "Match User alice\n" in staged["text"]
    assert "PasswordAuthentication no\n" in staged["text"]
    assert "PermitRootLogin prohibit-password\n" in staged["text"]
    assert "AllowUsers alice bob\n" in staged["text"]
    assert (
        staged["sha256"] == hashlib.sha256(staged["text"].encode("utf-8")).hexdigest()
    )
    assert "SECRETVALUE123456" not in json.dumps(staged)
    values = {item["keyword"]: item["value"] for item in staged["settings"]}
    assert values["PasswordAuthentication"] == "no"
    assert values["PermitRootLogin"] == "prohibit-password"
    assert values["MaxAuthTries"] == "5"

    read, _ = call(env, "sshd")
    assert read["mode"] and ":" in read["owner"]
    assert any("Match" in line for line in read["unreadable"])
    assert "SECRETVALUE123456" not in json.dumps(read)

    dropin.write_text("PasswordAuthentication yes\nPermitRootLogin no\n")
    clean, _ = call(env, "sshd-stage", req)
    assert clean["refuse"] is False and clean["error"] == ""
    assert clean["unreadable"] == []
    assert "PermitRootLogin prohibit-password\n" in clean["text"]
    assert clean["sha256"] == hashlib.sha256(clean["text"].encode("utf-8")).hexdigest()
