"""bridge/system_access.py against dev/fake-system-access.py and file fixtures:
service states and nsswitch, realm/cache/PAM, smartcard mappings, polkit ids,
the two read-only config files, kernel modules, fingerprints and sign-in users.
No secret or key blob may reach the answer; a missing file stays empty or says why.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_access.py"
FAKE = ROOT / "dev" / "fake-system-access.py"


def setup(tmp_path, commands=("systemctl", "ssh-keygen")):
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
            "SHANI_SYSTEMCTL": "systemctl",
            "SHANI_NSSWITCH": str(etc / "nsswitch.conf"),
            "SHANI_KRB5_CONF": str(etc / "krb5.conf"),
            "SHANI_KRB5_CCACHE": str(tmp_path / "krb5cc_*"),
            "SHANI_PAM_DIR": str(tmp_path / "pam.d"),
            "SHANI_PKCS11_CONF": str(etc / "pam_pkcs11.conf"),
            "SHANI_PKCS11_MAP": str(etc / "subject_mapping"),
            "SHANI_POLKIT_DIR": str(etc / "polkit-1" / "rules.d"),
            "SHANI_SUDOERS": str(etc / "sudoers.d" / "50-shani-shell"),
            "SHANI_SSHD_CONF": str(etc / "sshd_config.d" / "50-shani-shell.conf"),
            "SHANI_LSM_FILE": str(tmp_path / "lsm"),
            "SHANI_SSH_KEYGEN": "ssh-keygen",
            "SHANI_AUTHORIZED_KEYS": str(tmp_path / "authorized_keys"),
            "SHANI_OATH_FILE": str(etc / "users.oath"),
        }
    )
    return env


def call(env, verb):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), verb], capture_output=True, text=True, env=env
    )
    return json.loads(r.stdout), r


def test_directory_states_and_name_switches(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "etc" / "nsswitch.conf").write_text(
        "# generated\npasswd: files sss\ngroup: files sss systemd\nhosts: files dns\n"
    )
    (tmp_path / "systemctl-sssd.service.out").write_text("active\n")
    (tmp_path / "systemctl-slapd.service.out").write_text("inactive\n")
    got, _ = call(env, "directory")
    assert got["sssd"] == "active" and got["slapd"] == "inactive"
    assert got["nsswitch"] == "passwd: files sss, group: files sss systemd"
    assert got["error"] == ""
    (tmp_path / "etc" / "nsswitch.conf").unlink()
    missing, _ = call(env, "directory")
    assert missing["nsswitch"] == ""
    assert missing["error"]


def test_kerberos_realm_cache_and_pam(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "etc" / "krb5.conf").write_text(
        "[libdefaults]\n  default_realm = EXAMPLE.COM\n\n"
        "[domain_realm]\n  .example.com = EXAMPLE.COM\n  example.com = EXAMPLE.COM\n"
    )
    (tmp_path / "krb5cc_1000").write_text("")
    pam = tmp_path / "pam.d"
    pam.mkdir()
    (pam / "common-auth").write_text("auth sufficient pam_krb5.so use_first_pass\n")
    got, _ = call(env, "kerberos")
    assert got["realm"] == "EXAMPLE.COM"
    assert got["domainRealm"] == ".example.com = EXAMPLE.COM"
    assert got["cache"] == str(tmp_path / "krb5cc_1000")
    assert got["loaded"] is True and got["error"] == ""
    (tmp_path / "krb5cc_1000").unlink()
    (pam / "common-auth").write_text("auth required pam_unix.so\n")
    gone, _ = call(env, "kerberos")
    assert gone["cache"] == "" and gone["loaded"] is False


def test_smartcard_mapper_provider_and_mappings(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "etc" / "pam_pkcs11.conf").write_text(
        "use_mappers = digest, subject;\n"
        "mapper digest {\n  module = /usr/lib/pam_pkcs11/digest_mapper.so;\n}\n"
        'pkcs11_module = "/usr/lib/pkcs11/provider.so";\n'
    )
    (tmp_path / "etc" / "subject_mapping").write_text(
        "# identity -> login\nalice@example.com -> alice\nbob@example.com -> bob\n"
    )
    got, _ = call(env, "smartcard")
    assert got["mapper"] == "digest, subject"
    assert got["provider"] == "/usr/lib/pkcs11/provider.so"
    assert [(m["identity"], m["login"]) for m in got["mappings"]] == [
        ("alice@example.com", "alice"),
        ("bob@example.com", "bob"),
    ]
    assert "CN=" not in json.dumps(got)


def test_privileges_only_ids_inside_rule_blocks(tmp_path):
    env = setup(tmp_path)
    rules = tmp_path / "etc" / "polkit-1" / "rules.d"
    rules.mkdir(parents=True)
    (rules / "50-local.rules").write_text(
        "polkit.addRule(function(action, subject) {\n"
        '  if (action.id == "org.freedesktop.systemd1.manage-units" ||\n'
        '      action.id in ["org.example.shani.test"]) {\n'
        "    return polkit.Result.YES;\n  }\n});\n"
        'var ignored = "org.example.outside";\n'
    )
    got, _ = call(env, "privileges")
    assert got["rules"] == [
        {
            "file": str(rules / "50-local.rules"),
            "actions": [
                "org.freedesktop.systemd1.manage-units",
                "org.example.shani.test",
            ],
        }
    ]
    assert got["error"] == ""
    env["SHANI_POLKIT_DIR"] = str(tmp_path / "no-such-dir")
    missing, _ = call(env, "privileges")
    assert missing["rules"] == [] and missing["error"]


def test_sudoers_and_sshd_without_secret_values(tmp_path):
    env = setup(tmp_path)
    sudoers = tmp_path / "etc" / "sudoers.d" / "50-shani-shell"
    sudoers.parent.mkdir(parents=True)
    sudoers.write_text("%wheel ALL=(ALL) NOPASSWD: ALL\n")
    dropin = tmp_path / "etc" / "sshd_config.d" / "50-shani-shell.conf"
    dropin.parent.mkdir(parents=True)
    dropin.write_text(
        "PasswordAuthentication no\nPermitRootLogin no\nPubkeyAuthentication yes\n"
        "AuthorizedKeysCommand /usr/bin/fetch --token SECRETVALUE123456\n"
    )
    s, _ = call(env, "sudoers")
    assert s["text"].strip() == "%wheel ALL=(ALL) NOPASSWD: ALL" and s["error"] == ""
    d, _ = call(env, "sshd")
    assert d["settings"]["PasswordAuthentication"] == "no"
    assert d["settings"]["PermitRootLogin"] == "no"
    assert "SECRETVALUE123456" not in json.dumps(d)
    sudoers.unlink()
    empty, _ = call(env, "sudoers")
    assert empty["text"] == "" and empty["error"] == ""


def test_lsm_known_and_unknown_modules(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "lsm").write_text("capability,seccomp,custom_module\n")
    got, _ = call(env, "lsm")
    assert got["active"] == ["capability", "seccomp", "custom_module"]
    assert got["available"] == ["capability", "seccomp"]
    (tmp_path / "lsm").unlink()
    missing, _ = call(env, "lsm")
    assert missing["active"] == [] and missing["error"]


def test_sshkeys_gives_fingerprints_not_key_data(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "authorized_keys").write_text(
        "ssh-ed25519 AAAAKEYBLOBONE alice@host\n# ignored\nssh-rsa BBBBKEYBLOBTWO bob@host\n"
    )
    (tmp_path / "ssh-keygen.out").write_text(
        "256 SHA256:fpALICE alice@host (ED25519)\n3072 SHA256:fpBOB bob@host (RSA)\n"
    )
    got, _ = call(env, "sshkeys")
    assert got["keys"] == [
        {"type": "ED25519", "comment": "alice@host", "fingerprint": "SHA256:fpALICE"},
        {"type": "RSA", "comment": "bob@host", "fingerprint": "SHA256:fpBOB"},
    ]
    text = json.dumps(got)
    assert "AAAAKEYBLOBONE" not in text and "BBBBKEYBLOBTWO" not in text
    empty_dir = tmp_path / "empty"
    empty_dir.mkdir()
    no_tool, _ = call(dict(env, PATH=str(empty_dir)), "sshkeys")
    assert no_tool["keys"] == [] and "ssh-keygen" in no_tool["error"]
    (tmp_path / "authorized_keys").unlink()
    empty, _ = call(env, "sshkeys")
    assert empty["keys"] == [] and empty["error"] == ""


def test_totp_users_never_print_secrets(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "etc" / "users.oath").write_text(
        "HOTP/T30/6 alice - SECRETALICE\n"
        "TOTP/T30/8 bob - SECRETBOB\n"
        "# HOTP/T30/6 carol - SECRETCAROL\n"
        "# just a note\n"
    )
    got, _ = call(env, "totp")
    assert got["users"] == [
        {"user": "alice", "enabled": True, "digits": 6, "period": 30},
        {"user": "bob", "enabled": True, "digits": 8, "period": 30},
        {"user": "carol", "enabled": False, "digits": 6, "period": 30},
    ]
    assert "SECRET" not in json.dumps(got)
    (tmp_path / "etc" / "users.oath").unlink()
    missing, _ = call(env, "totp")
    assert missing["users"] == [] and missing["error"]
