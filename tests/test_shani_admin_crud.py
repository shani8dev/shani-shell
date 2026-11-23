import importlib.util, json, subprocess
from pathlib import Path

import pytest


def load_admin(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("sa_crud", str(Path(__file__).resolve().parent.parent / "bridge/shani-admin.py"))
    sa = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sa)
    # isolate files
    sa.SSHD_DROPIN = tmp_path / "sshd_dropin.conf"
    sa.PWQUALITY = tmp_path / "pwquality.conf"
    sa.SUDOERS_DROPIN = tmp_path / "sudoers.d" / "50-shani-shell"
    sa.SUDOERS_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(sa.shutil, "which", lambda x: None)
    real_run = subprocess.run
    def fake_run(cmd, *a, **k):
        # avoid real systemctl/visudo/apparmor
        if cmd[0] in ("systemctl", "aa-enforce", "aa-complain", "/usr/sbin/aa-enforce", "/usr/sbin/aa-complain"):
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[0] == "visudo":
            return subprocess.CompletedProcess(cmd, 0, "ok", "")
        return real_run(cmd, *a, **k)
    monkeypatch.setattr(sa.subprocess, "run", fake_run)
    return sa


def test_remote_access_set_writes_dropin(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    r = sa.remote_access_set({"password": False, "pubkey": True, "root": False})
    assert r["password"] is False and r["pubkey"] is True and r["root"] is False
    txt = sa.SSHD_DROPIN.read_text()
    assert "PasswordAuthentication no" in txt
    assert "PermitRootLogin prohibit-password" in txt


def test_pwquality_set_preserves_unknown_lines(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    sa.PWQUALITY.write_text("# comment\nminlen = 8\nother = keep\n", encoding="utf-8")
    r = sa.pwquality_set({"settings": {"minlen": 12, "dcredit": -1}})
    assert r["settings"]["minlen"] == "12"
    txt = sa.PWQUALITY.read_text()
    assert "minlen = 12" in txt
    assert "dcredit = -1" in txt
    assert "other = keep" in txt


def test_pwquality_rejects_unknown_key(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    with pytest.raises(Exception):
        sa.pwquality_set({"settings": {"evil": 1}})


def test_hosts_set_validates_and_writes(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    hosts = tmp_path / "hosts"
    real_path = Path
    monkeypatch.setattr(sa, "Path", lambda p: hosts if str(p) == "/etc/hosts" else real_path(p))
    monkeypatch.setattr(sa.os, "chmod", lambda *a, **k: None)
    with pytest.raises(Exception):
        sa.hosts_set({"text": "not-an-ip host\n"})
    r = sa.hosts_set({"text": "127.0.0.1 localhost\n::1 localhost\n"})
    assert "127.0.0.1" in r["text"]
    assert hosts.read_text().startswith("127.0.0.1")


def test_sudoers_set_validates_and_writes(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    r = sa.sudoers_set({"text": "%wheel ALL=(ALL:ALL) ALL\n"})
    assert "wheel" in r["text"]
    assert sa.SUDOERS_DROPIN.exists()


def test_sudoers_empty_removes(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    sa.SUDOERS_DROPIN.write_text("x\n", encoding="utf-8")
    r = sa.sudoers_set({"text": ""})
    assert r["text"] == ""
    assert not sa.SUDOERS_DROPIN.exists()


def test_apparmor_set_validates(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    with pytest.raises(Exception):
        sa.apparmor_set({"profile": "bad;rm", "mode": "enforce"})
    with pytest.raises(Exception):
        sa.apparmor_set({"profile": "/usr/bin/foo", "mode": "nope"})
    r = sa.apparmor_set({"profile": "/usr/bin/foo", "mode": "complain"})
    assert r["mode"] == "complain"
