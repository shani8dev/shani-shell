"""Gaps 4-7: digest-staged writes, rollback and rejecting command stand-ins."""

from __future__ import annotations

import hashlib
import importlib.util
import subprocess
from pathlib import Path

import pytest

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "shani-admin.py"


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("admin_gaps", str(BRIDGE))
    sa = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sa)
    sa.SSHD_DROPIN = tmp_path / "sshd.d" / "50-shani-shell.conf"
    sa.SUDOERS_DROPIN = tmp_path / "sudoers.d" / "50-shani-shell"
    sa.HOSTS_FILE = tmp_path / "hosts"
    sa.EXPORTS_FILE = tmp_path / "exports.d" / "50-shani-shell.exports"
    sa.SMB_DROPIN = tmp_path / "smb.conf.d" / "50-shani-shell.conf"
    sa.PAM_U2F_CONF = tmp_path / "pam_u2f.conf"
    sa.PAM_YUBICO_CONF = tmp_path / "pam_yubico.conf"
    sa.PKCS11_MAP_FILE = tmp_path / "subject_mapping"
    sa.SSHD_TOOL = "sshd"
    sa.SYSTEMCTL_TOOL = "systemctl"
    sa.VISUDO_TOOL = "visudo"
    sa.EXPORTFS_TOOL = "exportfs"
    sa.TESTPARM_TOOL = "testparm"
    monkeypatch.setattr(
        sa.shutil,
        "which",
        lambda name: "/usr/bin/" + name if name == sa.SSHD_TOOL else None,
    )
    return sa


def fake_run(sa, monkeypatch, failures=None):
    """Accept only the exact argv the bridge is allowed to use."""
    calls = []
    failures = failures or {}

    def run(cmd, *args, **kwargs):
        cmd = list(cmd)
        calls.append(cmd)
        if cmd[:3] == [sa.SSHD_TOOL, "-t", "-f"] and len(cmd) == 4:
            allowed = True
        elif cmd == [sa.SSHD_TOOL, "-t"]:
            allowed = True
        elif cmd in (
            [sa.SYSTEMCTL_TOOL, "reload-or-restart", "sshd"],
            [sa.SYSTEMCTL_TOOL, "is-active", "sshd"],
            [sa.VISUDO_TOOL, "-c"],
            [sa.EXPORTFS_TOOL, "-ra"],
        ):
            allowed = True
        elif cmd[:3] == [sa.VISUDO_TOOL, "-c", "-f"] and len(cmd) == 4:
            allowed = True
        elif cmd[:2] == [sa.TESTPARM_TOOL, "-s"] and len(cmd) == 3:
            allowed = True
        else:
            raise AssertionError("unexpected command: " + repr(cmd))
        if tuple(cmd) in failures:
            return subprocess.CompletedProcess(cmd, 1, "", failures[tuple(cmd)])
        if cmd == [sa.SYSTEMCTL_TOOL, "is-active", "sshd"]:
            return subprocess.CompletedProcess(cmd, 0, "inactive\n", "")
        return subprocess.CompletedProcess(cmd, 0, "", "")

    monkeypatch.setattr(sa.subprocess, "run", run)
    return calls


def test_staged_sshd_writes_checks_both_and_returns_meta(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    calls = fake_run(sa, monkeypatch)
    sa.SSHD_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    sa.SSHD_DROPIN.write_text("PasswordAuthentication yes\n", encoding="utf-8")
    text = "# my staged note\nPubkeyAuthentication yes\nMaxAuthTries 4\n"
    r = sa.remote_access_set({"text": text, "sha256": digest(text)})
    assert sa.SSHD_DROPIN.read_text(encoding="utf-8") == text
    assert "# my staged note" in sa.SSHD_DROPIN.read_text(encoding="utf-8")
    assert r["mode"] == "644" and ":" in r["owner"]
    assert r["pubkey"] is True and r["maxAuthTries"] == "4"
    sshd = [c for c in calls if c[0] == sa.SSHD_TOOL]
    assert sshd[0][:3] == [sa.SSHD_TOOL, "-t", "-f"] and len(sshd[0]) == 4
    assert Path(sshd[0][3]).parent == sa.SSHD_DROPIN.parent
    assert sshd[1] == [sa.SSHD_TOOL, "-t"]
    assert [sa.SYSTEMCTL_TOOL, "reload-or-restart", "sshd"] in calls


def test_staged_sshd_bad_digest_does_not_write(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    calls = fake_run(sa, monkeypatch)
    sa.SSHD_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    sa.SSHD_DROPIN.write_text("old\n", encoding="utf-8")
    with pytest.raises(sa.Refused, match="SHA-256 does not match the content"):
        sa.remote_access_set({"text": "new\n", "sha256": "0" * 64})
    assert sa.SSHD_DROPIN.read_text(encoding="utf-8") == "old\n"
    assert calls == []
    with pytest.raises(sa.Refused, match="sha256 required"):
        sa.remote_access_set({"text": "new\n"})


def test_staged_sshd_post_failure_restores_old_bytes(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    fake_run(sa, monkeypatch, {(sa.SSHD_TOOL, "-t"): "post check failed"})
    sa.SSHD_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    sa.SSHD_DROPIN.write_text(
        "# old bytes\nPasswordAuthentication yes\n", encoding="utf-8"
    )
    text = "PubkeyAuthentication no\n"
    with pytest.raises(sa.Refused, match="post check failed"):
        sa.remote_access_set({"text": text, "sha256": digest(text)})
    assert (
        sa.SSHD_DROPIN.read_text(encoding="utf-8")
        == "# old bytes\nPasswordAuthentication yes\n"
    )


def test_legacy_sshd_request_preserves_unmanaged_lines(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    calls = fake_run(sa, monkeypatch)
    sa.SSHD_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    sa.SSHD_DROPIN.write_text(
        "# admin note\nX11Forwarding yes\nCustomDirective keep\n\n", encoding="utf-8"
    )
    r = sa.remote_access_set(
        {"password": False, "pubkey": True, "x11Forwarding": False}
    )
    text = sa.SSHD_DROPIN.read_text(encoding="utf-8")
    assert "# admin note" in text and "CustomDirective keep" in text
    assert "X11Forwarding no" in text and text.count("X11Forwarding") == 1
    assert "PasswordAuthentication no" in text
    assert r["mode"] == "644"
    assert [c for c in calls if c[0] == sa.SSHD_TOOL][:2] == [
        [sa.SSHD_TOOL, "-t", "-f", calls[0][3]],
        [sa.SSHD_TOOL, "-t"],
    ]


def test_sudoers_rows_keep_checks_mode_and_all_warning(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    calls = fake_run(sa, monkeypatch)
    r = sa.sudoers_set(
        {
            "rows": [
                {
                    "who": "%wheel",
                    "runas": "ALL:ALL",
                    "tags": ["NOPASSWD"],
                    "commands": ["ALL"],
                },
                {
                    "who": "asha",
                    "runas": "root",
                    "tags": ["PASSWD", "EXEC"],
                    "commands": ["/usr/bin/id -u", "/usr/bin/whoami"],
                },
            ],
            "other": ["# managed"],
        }
    )
    text = sa.SUDOERS_DROPIN.read_text(encoding="utf-8")
    assert "# managed" in text
    assert "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" in text
    assert "asha ALL=(root) PASSWD, EXEC: /usr/bin/id -u, /usr/bin/whoami" in text
    assert r["rows"][0]["warning"] == "all_commands"
    assert "warning" not in r["rows"][1]
    assert r["mode"] == "440" and ":" in r["owner"]
    assert [c[:3] for c in calls if c[0] == sa.VISUDO_TOOL] == [
        [sa.VISUDO_TOOL, "-c", "-f"],
        [sa.VISUDO_TOOL, "-c"],
    ]
    parsed = sa.sudoers_rows_get({})
    assert len(parsed["rows"]) == 2 and parsed["unreadable"] == []
    assert parsed["rows"][0]["warning"] == "all_commands"


def test_sudoers_rows_refuse_bad_principals_and_metacharacters(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    fake_run(sa, monkeypatch)
    base = {
        "who": "%wheel",
        "runas": "ALL",
        "tags": ["NOPASSWD"],
        "commands": ["/bin/id"],
    }
    for bad in (
        {"who": "bad;name"},
        {"who": "%wheel;rm"},
        {"commands": ["/bin/id; touch /tmp/x"]},
        {"commands": ["ALL $(id)"]},
        {"commands": ["relative/path"]},
        {"tags": ["EVIL"]},
    ):
        row = dict(base)
        row.update(bad)
        with pytest.raises(sa.Refused):
            sa.sudoers_set({"rows": [row]})
    assert not sa.SUDOERS_DROPIN.exists()


def test_sudoers_text_digest_checked_when_given(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    fake_run(sa, monkeypatch)
    text = "%wheel ALL=(ALL:ALL) ALL\n"
    with pytest.raises(sa.Refused, match="SHA-256 does not match the content"):
        sa.sudoers_set({"text": text, "sha256": "0" * 64})
    assert not sa.SUDOERS_DROPIN.exists()
    assert "wheel" in sa.sudoers_set({"text": text, "sha256": digest(text)})["text"]


def test_hosts_set_keeps_system_addresses(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    base = (
        "127.0.0.1 localhost\n"
        "127.0.1.1 mybox\n"
        "::1 localhost ip6-localhost\n"
        "192.0.2.10 example.test example\n"
    )
    sa.HOSTS_FILE.write_text(base, encoding="utf-8")
    for dropped in ("127.0.0.1", "127.0.1.1", "::1"):
        new = "".join(
            line
            for line in base.splitlines(keepends=True)
            if not line.startswith(dropped)
        )
        with pytest.raises(sa.Refused, match="system address"):
            sa.hosts_set({"text": new})
        assert sa.HOSTS_FILE.read_text(encoding="utf-8") == base
    rewritten = (
        "127.0.0.1 localhost localdomain\n"
        "127.0.1.1 renamed\n"
        "::1 ip6-localhost\n"
        "192.0.2.11 new.test new\n"
    )
    r = sa.hosts_set({"text": rewritten, "sha256": digest(rewritten)})
    assert "127.0.0.1" in r["text"] and "127.0.1.1" in r["text"] and "::1" in r["text"]
    assert sa.HOSTS_FILE.read_text(encoding="utf-8").startswith(
        "127.0.0.1 localhost localdomain"
    )
    with pytest.raises(sa.Refused, match="SHA-256 does not match the content"):
        sa.hosts_set({"text": base, "sha256": "0" * 64})


NEW_VERBS = [
    ("nfs_exports_set", "EXPORTS_FILE", "exportfs", "ra"),
    ("smb_share_set", "SMB_DROPIN", "testparm", "s"),
    ("pam_config_set", "PAM_U2F_CONF", None, None),
    ("pkcs11_mapping_set", "PKCS11_MAP_FILE", None, None),
]


def staged_req(verb, text):
    req = {"text": text, "sha256": digest(text)}
    if verb == "pam_config_set":
        req["target"] = "fido2"
    return req


def postcheck_call(sa, verb, path):
    if verb == "nfs_exports_set":
        return [sa.EXPORTFS_TOOL, "-ra"]
    if verb == "smb_share_set":
        return [sa.TESTPARM_TOOL, "-s", str(path)]
    return None


@pytest.mark.parametrize("verb,path_attr,tool,flag", NEW_VERBS)
def test_new_verbs_digest_install_check_and_rollback(
    tmp_path, monkeypatch, verb, path_attr, tool, flag
):
    sa = load(tmp_path, monkeypatch)
    path = getattr(sa, path_attr)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "/srv/share *(ro)\n" if verb == "nfs_exports_set" else "staged config\n"
    old = b"# old bytes\n"

    calls = fake_run(sa, monkeypatch)
    r = getattr(sa, verb)(staged_req(verb, text))
    assert path.read_text(encoding="utf-8") == text
    assert r["mode"] == "644" and ":" in r["owner"] and r["ok"] is True
    expected = postcheck_call(sa, verb, path)
    if expected:
        assert expected in calls
    else:
        assert calls == []

    with pytest.raises(sa.Refused, match="SHA-256 does not match the content"):
        getattr(sa, verb)({**staged_req(verb, text), "sha256": "0" * 64})
    assert path.read_text(encoding="utf-8") == text

    path.write_bytes(old)
    check = postcheck_call(sa, verb, path)
    if check:
        fake_run(sa, monkeypatch, {tuple(check): "post-check failed"})
    else:

        def broken(path, text):
            def check():
                raise sa.Refused("post-check failed")

            return check

        monkeypatch.setattr(sa, "_readback_check", broken)
    with pytest.raises(sa.Refused, match="post-check failed"):
        getattr(sa, verb)(staged_req(verb, text))
    assert path.read_bytes() == old


def test_pam_config_targets_are_fixed_paths(tmp_path, monkeypatch):
    sa = load(tmp_path, monkeypatch)
    fake_run(sa, monkeypatch)
    for target, path in (("fido2", sa.PAM_U2F_CONF), ("yubico", sa.PAM_YUBICO_CONF)):
        text = f"# {target}\n"
        r = sa.pam_config_set({"target": target, "text": text, "sha256": digest(text)})
        assert path.read_text(encoding="utf-8") == text and r["mode"] == "644"
    with pytest.raises(sa.Refused, match="unknown PAM target"):
        sa.pam_config_set({"target": "../evil", "text": "x", "sha256": digest("x")})
