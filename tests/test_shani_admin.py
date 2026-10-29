"""shani-admin.py: what it refuses, whoever asks.

The account database and every command are stand-ins here; dev/admin-test.sh
runs the real useradd/userdel/gpasswd/chpasswd, greetd and logind drop-ins in
a systemd-booted dev container.
"""
from __future__ import annotations

import grp
import importlib.util
import pwd
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("shani_admin", Path(__file__).resolve().parents[1] / "bridge" / "shani-admin.py")
sa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sa)


def account(name, uid):
    return pwd.struct_passwd((name, "x", uid, uid, name.title(), "/home/" + name, "/bin/bash"))


@pytest.fixture
def machine(monkeypatch, tmp_path):
    """root, a system account, two people — asha (admin, the caller) and ravi."""
    people = [account("root", 0), account("colord", 970), account("asha", 1000), account("ravi", 1001)]
    monkeypatch.setattr(sa.pwd, "getpwall", lambda: people)
    monkeypatch.setattr(sa.pwd, "getpwnam", lambda n: next((p for p in people if p.pw_name == n), None) or (_ for _ in ()).throw(KeyError(n)))
    monkeypatch.setattr(sa.pwd, "getpwuid", lambda u: next(p for p in people if p.pw_uid == u))
    wheel = ["asha"]
    monkeypatch.setattr(sa.grp, "getgrnam", lambda g: grp.struct_group(("wheel", "x", 998, wheel)))
    monkeypatch.setenv("PKEXEC_UID", "1000")
    calls = []
    monkeypatch.setattr(sa, "run", lambda cmd, stdin=None: calls.append((cmd, stdin)))
    for name in ("GREETD_CONFIG", "AUTOLOGIN_CONFIG", "AUTOLOGIN_DROPIN", "LOGIND_DROPIN"):
        monkeypatch.setattr(sa, name, tmp_path / name)
    (tmp_path / "GREETD_CONFIG").write_text('[terminal]\nvt = 1\n\n[default_session]\ncommand = "niri"\nuser = "greeter"\n')
    return calls, wheel


def refused(fn, req, why):
    with pytest.raises(sa.Refused, match=why):
        fn(req)


def test_system_accounts_are_off_limits(machine):
    refused(sa.user_password, {"username": "root", "password": "x"}, "system account")
    refused(sa.user_remove, {"username": "colord"}, "system account")
    refused(sa.user_admin, {"username": "root", "admin": True}, "system account")


def test_you_cannot_remove_or_demote_yourself(machine):
    refused(sa.user_remove, {"username": "asha"}, "your own account")
    refused(sa.user_admin, {"username": "asha", "admin": False}, "your own administrator")


def test_the_last_administrator_stays(machine, monkeypatch):
    monkeypatch.setenv("PKEXEC_UID", "1001")         # ravi asks (polkit made him prove admin)
    refused(sa.user_remove, {"username": "asha"}, "only administrator")
    refused(sa.user_admin, {"username": "asha", "admin": False}, "only administrator")


def test_add_a_standard_and_an_admin_user(machine, monkeypatch):
    calls, _ = machine
    # every person joins sambashare where it exists (sharing a folder works at once)
    monkeypatch.setattr(sa, "extra_groups", lambda: ["sambashare"])
    sa.user_add({"username": "meera", "fullname": "Meera K", "password": "pw"})
    sa.user_add({"username": "dev", "fullname": "", "password": "pw", "admin": True})
    cmds = [c for c, _ in calls]
    assert cmds[0] == ["useradd", "-m", "-c", "Meera K", "-s", "/bin/bash", "-G", "sambashare", "meera"]
    assert calls[1] == (["chpasswd"], "meera:pw\n")
    assert cmds[2] == ["useradd", "-m", "-c", "", "-s", "/bin/bash", "-G", "wheel,sambashare", "dev"]


@pytest.mark.parametrize("req, why", [
    ({"username": "ravi", "password": "x"}, "taken"),
    ({"username": "Bad", "password": "x"}, "user name"),
    ({"username": "root", "password": "x"}, "user name"),
    ({"username": "ok", "password": ""}, "password"),
    ({"username": "ok", "fullname": "a:b", "password": "x"}, "cannot contain"),
])
def test_add_refuses(machine, req, why):
    refused(sa.user_add, req, why)


def test_remove_keeps_or_deletes_files(machine):
    calls, _ = machine
    sa.user_remove({"username": "ravi"})
    sa.user_remove({"username": "ravi", "deleteHome": True})
    assert [c for c, _ in calls] == [["userdel", "ravi"], ["userdel", "-r", "ravi"]]


def test_autologin_writes_a_copy_and_a_dropin_and_undoes_both(machine):
    calls, _ = machine
    sa.autologin({"username": "ravi"})
    conf = sa.AUTOLOGIN_CONFIG.read_text()
    assert '[default_session]\ncommand = "niri"' in conf and conf.rstrip().endswith('[initial_session]\ncommand = "niri-session"\nuser = "ravi"')
    assert f"ExecStart=/usr/bin/greetd --config {sa.AUTOLOGIN_CONFIG}" in sa.AUTOLOGIN_DROPIN.read_text()
    assert sa.autologin_user() == "ravi"
    sa.autologin({"username": "asha"})                # switching replaces, never stacks
    assert sa.AUTOLOGIN_CONFIG.read_text().count("[initial_session]") == 1 and sa.autologin_user() == "asha"
    sa.autologin({"username": ""})
    assert not sa.AUTOLOGIN_CONFIG.exists() and not sa.AUTOLOGIN_DROPIN.exists()
    refused(sa.autologin, {"username": "root"}, "system account")


def test_removing_the_autologin_user_turns_it_off(machine):
    sa.autologin({"username": "ravi"})
    sa.user_remove({"username": "ravi"})
    assert sa.autologin_user() == ""


def test_power_keys(machine, monkeypatch):
    monkeypatch.setattr(sa.subprocess, "run", lambda *a, **k: None)
    sa.power_keys({"lid": "lock", "lidOnPower": "ignore", "powerKey": "suspend"})
    assert "HandleLidSwitch=lock\nHandleLidSwitchExternalPower=ignore\nHandlePowerKey=suspend\n" in sa.LOGIND_DROPIN.read_text()
    refused(sa.power_keys, {"lid": "rm -rf /"}, "unknown action")


def test_only_known_commands(capsys):
    assert sa.main(["x", "user-add autologin"]) == 2
    assert sa.main(["x"]) == 2


def test_battery_limit(machine, tmp_path, monkeypatch):
    ps = tmp_path / "ps"
    (ps / "BAT0").mkdir(parents=True)
    (ps / "BAT0" / "charge_control_end_threshold").write_text("100\n")
    monkeypatch.setattr(sa, "POWER_SUPPLY", ps)
    monkeypatch.setattr(sa, "BATTERY_TMPFILES", tmp_path / "tmpfiles.conf")
    assert sa.battery_limit({"percent": 80}) == {"batteries": 1}
    assert (ps / "BAT0" / "charge_control_end_threshold").read_text() == "80\n"
    assert "w " + str(ps / "BAT0" / "charge_control_end_threshold") + " - - - - 80" in (tmp_path / "tmpfiles.conf").read_text()
    sa.battery_limit({"percent": 100})
    assert not (tmp_path / "tmpfiles.conf").exists()
    refused(sa.battery_limit, {"percent": 20}, "between 50 and 100")
    refused(sa.battery_limit, {"percent": "80; reboot"}, "between 50 and 100")


def test_no_battery_no_limit(machine, tmp_path, monkeypatch):
    monkeypatch.setattr(sa, "POWER_SUPPLY", tmp_path)
    refused(sa.battery_limit, {"percent": 80}, "no charge limit")
