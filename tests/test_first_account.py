"""first-account.py: what it accepts, and that it refuses once an account exists.

Creating an account needs root and is run for real in dev/setup-test.sh (the
wizard end to end, in the dev container). Here: validation, and the guard,
with the account database seen through a stand-in.
"""
from __future__ import annotations

import importlib.util
import pwd
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("first_account", Path(__file__).resolve().parents[1] / "bridge" / "first-account.py")
fa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fa)

GOOD = {"username": "asha", "fullname": "Asha Patil", "password": "s3cret pass", "hostname": "asha-laptop",
        "keymap": ["us", "in+marathi"], "keymapSwitch": "grp:win_space_toggle", "locale": "mr_IN.UTF-8",
        "timezone": "Asia/Kolkata"}


def entry(name, uid, shell="/bin/bash"):
    return pwd.struct_passwd((name, "x", uid, uid, "", "/home/" + name, shell))


@pytest.mark.parametrize("change, why", [
    ({}, ""),
    ({"username": "Asha"}, "user name"),
    ({"username": "root"}, "user name"),
    ({"username": "greeter"}, "user name"),
    ({"username": "-x"}, "user name"),
    ({"username": "a" * 40}, "user name"),
    ({"fullname": "Asha:0:0"}, "name cannot"),
    ({"password": ""}, "password"),
    ({"password": "a\nb"}, "password"),
    ({"hostname": "my laptop"}, "computer name"),
    ({"keymap": ["us;rm -rf"]}, "keyboard"),
    ({"keymapSwitch": "grp:x; reboot"}, "switch"),
])
def test_validation(change, why):
    got = fa.validate({**GOOD, **change})
    assert (why in got) if why else got == ""


def test_refuses_once_any_account_exists(monkeypatch):
    calls = []
    monkeypatch.setattr(fa, "run", lambda cmd, stdin=None: calls.append(cmd) or "")
    monkeypatch.setattr(fa.pwd, "getpwall", lambda: [entry("root", 0), entry("greeter", 964, "/usr/bin/nologin"), entry("ravi", 1000)])
    assert fa.apply(GOOD) == {"ok": False, "error": "this computer already has an account"}
    assert calls == [], "it ran something on a machine that already has an account"


def test_system_and_nologin_accounts_do_not_count(monkeypatch):
    monkeypatch.setattr(fa.pwd, "getpwall", lambda: [entry("root", 0), entry("greeter", 964, "/usr/bin/nologin"),
                                                     entry("nobody", 65534, "/usr/bin/nologin"), entry("svc", 1001, "/usr/bin/nologin")])
    assert fa.regular_accounts() == []


def test_first_account_is_an_administrator_and_settings_follow(monkeypatch):
    calls = []
    monkeypatch.setattr(fa, "run", lambda cmd, stdin=None: calls.append((cmd, stdin)) or "")
    monkeypatch.setattr(fa.pwd, "getpwall", lambda: [entry("root", 0)])
    monkeypatch.setattr(fa, "listed", lambda cmd: {"mr_IN.UTF-8", "Asia/Kolkata"})
    assert fa.apply(GOOD) == {"ok": True, "warnings": []}
    cmds = [c for c, _ in calls]
    assert cmds[0] == ["useradd", "-m", "-c", "Asha Patil", "-G", "wheel", "-s", "/bin/bash", "asha"]
    assert calls[1] == (["chpasswd"], "asha:s3cret pass\n")
    assert ["localectl", "set-locale", "LANG=mr_IN.UTF-8"] in cmds
    assert ["localectl", "set-x11-keymap", "us,in", "", ",marathi", "grp:win_space_toggle"] in cmds
    assert ["timedatectl", "set-timezone", "Asia/Kolkata"] in cmds
    assert ["hostnamectl", "hostname", "asha-laptop"] in cmds


def test_a_refused_password_takes_the_account_back(monkeypatch):
    calls = []
    monkeypatch.setattr(fa, "run", lambda cmd, stdin=None: calls.append(cmd) or ("bad password" if cmd[0] == "chpasswd" else ""))
    monkeypatch.setattr(fa.pwd, "getpwall", lambda: [])
    assert fa.apply(GOOD) == {"ok": False, "error": "bad password"}
    assert calls[-1] == ["userdel", "-r", "asha"]
