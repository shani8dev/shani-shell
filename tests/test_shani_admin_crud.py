import importlib.util, json, subprocess
from pathlib import Path

import pytest


def load_admin(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location(
        "sa_crud", str(Path(__file__).resolve().parent.parent / "bridge/shani-admin.py")
    )
    sa = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sa)
    # isolate files
    sa.SSHD_DROPIN = tmp_path / "sshd_dropin.conf"
    sa.PWQUALITY = tmp_path / "pwquality.conf"
    sa.FAILLOCK_CONF = tmp_path / "faillock.conf"
    sa.SUDOERS_DROPIN = tmp_path / "sudoers.d" / "50-shani-shell"
    sa.SUDOERS_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    sa.MODPROBE_DROPIN = tmp_path / "modprobe.d" / "50-shani-shell.conf"
    sa.MODULES_LOAD_DROPIN = tmp_path / "modules-load.d" / "50-shani-shell.conf"
    sa.JOURNALD_DROPIN = tmp_path / "journald.conf.d" / "50-shani-shell.conf"
    sa.SYSCTL_DROPIN = tmp_path / "sysctl.d" / "50-shani-shell.conf"
    sa.TIMESYNCD_DROPIN = tmp_path / "timesyncd.conf.d" / "50-shani-shell.conf"
    sa.RESOLVED_DROPIN = tmp_path / "resolved.conf.d" / "50-shani-shell.conf"
    sa.LOGIN_DEFS = tmp_path / "login.defs"
    monkeypatch.setattr(sa.shutil, "which", lambda x: "/usr/bin/" + x if x in ("visudo", "aa-enforce", "aa-complain") else None)
    real_exists = sa.os.path.exists
    monkeypatch.setattr(sa.os.path, "exists", lambda pth: True if str(pth) in ("/usr/bin/visudo", "/usr/bin/aa-enforce", "/usr/bin/aa-complain") else real_exists(pth))
    real_run = subprocess.run

    def fake_run(cmd, *a, **k):
        # avoid real systemctl/visudo/apparmor
        if cmd[0] in (
            "systemctl",
            "aa-enforce", "aa-complain",
            "/usr/sbin/aa-enforce", "/usr/sbin/aa-complain",
            "/usr/bin/aa-enforce", "/usr/bin/aa-complain",
        ):
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[0] in ("visudo", "/usr/sbin/visudo", "/usr/bin/visudo"):
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
    monkeypatch.setattr(
        sa, "Path", lambda p: hosts if str(p) == "/etc/hosts" else real_path(p)
    )
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


def test_modprobe_blacklist_crud(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    r = sa.modprobe_blacklist_set({"modules": ["nouveau", "pcspkr"]})
    assert r["modules"] == ["nouveau", "pcspkr"]
    txt = sa.MODPROBE_DROPIN.read_text()
    assert "blacklist nouveau" in txt
    assert "install pcspkr /bin/false" in txt
    r = sa.modprobe_blacklist_set({"modules": []})
    assert r["modules"] == []
    assert not sa.MODPROBE_DROPIN.exists()


def test_modules_load_crud(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    r = sa.modules_load_set({"modules": ["vfio-pci", "kvm"]})
    assert r["modules"] == ["vfio-pci", "kvm"]
    assert "vfio-pci\n" in sa.MODULES_LOAD_DROPIN.read_text()
    with pytest.raises(Exception):
        sa.modules_load_set({"modules": ["bad;name"]})


def test_journald_set_and_vacuum(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    r = sa.journald_set({"settings": {"Storage": "persistent", "SystemMaxUse": "500M"}})
    assert r["settings"]["Storage"] == "persistent"
    txt = sa.JOURNALD_DROPIN.read_text()
    assert "[Journal]" in txt and "SystemMaxUse=500M" in txt
    with pytest.raises(Exception):
        sa.journald_set({"settings": {"Storage": "bad"}})
    with pytest.raises(Exception):
        sa.journald_vacuum({"mode": "size", "value": "bad;rm"})
    r = sa.journald_vacuum({"mode": "size", "value": "500M"})
    assert r["ok"] is True


def test_sysctl_allowlist_and_range(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    r = sa.sysctl_set({"settings": {"vm.swappiness": 10}})
    assert r["settings"]["vm.swappiness"] == "10"
    assert "vm.swappiness = 10" in sa.SYSCTL_DROPIN.read_text()
    with pytest.raises(Exception):
        sa.sysctl_set({"settings": {"kernel.randomize_va_space": 0}})
    with pytest.raises(Exception):
        sa.sysctl_set({"settings": {"vm.swappiness": 999}})


def test_timesyncd_crud(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    r = sa.timesyncd_set(
        {"settings": {"NTP": "time.example.com 0.pool.ntp.org", "FallbackNTP": ""}}
    )
    assert "time.example.com" in r["settings"]["NTP"]
    txt = sa.TIMESYNCD_DROPIN.read_text()
    assert "NTP=time.example.com 0.pool.ntp.org" in txt
    with pytest.raises(Exception):
        sa.timesyncd_set({"settings": {"NTP": "bad host;rm"}})


def test_faillock_get_set_and_validate(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    sa.FAILLOCK_CONF.write_text("# comment\ndeny = 3\nother = keep\n", encoding="utf-8")
    r = sa.faillock_set(
        {"settings": {"deny": 5, "unlock_time": 600, "even_deny_root": True}}
    )
    assert r["settings"]["deny"] == "5"
    assert r["settings"]["unlock_time"] == "600"
    assert r["settings"]["even_deny_root"] == "1"
    txt = sa.FAILLOCK_CONF.read_text()
    assert "deny = 5" in txt
    assert "unlock_time = 600" in txt
    assert "even_deny_root = 1" in txt
    assert "other = keep" in txt
    with pytest.raises(Exception):
        sa.faillock_set({"settings": {"deny": 1001}})
    with pytest.raises(Exception):
        sa.faillock_set({"settings": {"evil": 1}})


def test_resolved_get_set_and_validate(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    r = sa.resolved_set(
        {
            "settings": {
                "DNS": "1.1.1.1 2606:4700:4700::1111",
                "FallbackDNS": "9.9.9.9",
                "DNSOverTLS": "opportunistic",
                "DNSSEC": "allow-downgrade",
            }
        }
    )
    assert r["settings"]["DNS"] == "1.1.1.1 2606:4700:4700::1111"
    txt = sa.RESOLVED_DROPIN.read_text()
    assert "[Resolve]" in txt
    assert "DNS=1.1.1.1 2606:4700:4700::1111" in txt
    assert "DNSOverTLS=opportunistic" in txt
    assert "DNSSEC=allow-downgrade" in txt
    with pytest.raises(Exception):
        sa.resolved_set({"settings": {"DNSOverTLS": "maybe"}})
    with pytest.raises(Exception):
        sa.resolved_set({"settings": {"DNS": "bad host;rm"}})
    with pytest.raises(Exception):
        sa.resolved_set({"settings": {"unknown": "x"}})
    r = sa.resolved_set({"settings": {}})
    assert not sa.RESOLVED_DROPIN.exists()


def test_login_defs_get_set_preserves_other_lines(tmp_path, monkeypatch):
    sa = load_admin(tmp_path, monkeypatch)
    sa.LOGIN_DEFS.write_text(
        "# comment\nPASS_MAX_DAYS\t99999\nPASS_MIN_DAYS\t0\nOTHER_KEY\tkeep\n",
        encoding="utf-8",
    )
    r = sa.login_defs_set(
        {"settings": {"PASS_MAX_DAYS": 90, "PASS_WARN_AGE": 14, "LOGIN_RETRIES": 5}}
    )
    assert r["settings"]["PASS_MAX_DAYS"] == "90"
    assert r["settings"]["PASS_WARN_AGE"] == "14"
    txt = sa.LOGIN_DEFS.read_text()
    assert "PASS_MAX_DAYS\t90" in txt
    assert "PASS_WARN_AGE\t14" in txt
    assert "OTHER_KEY\tkeep" in txt
    assert "# comment" in txt
    with pytest.raises(Exception):
        sa.login_defs_set({"settings": {"PASS_MAX_DAYS": 100000}})
    with pytest.raises(Exception):
        sa.login_defs_set({"settings": {"EVIL": 1}})
