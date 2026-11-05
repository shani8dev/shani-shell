"""bridge/u2f.py: registering security keys into pam_u2f's file, with fake tools."""
import json
import os
import pwd
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge" / "u2f.py"
ME = pwd.getpwuid(os.getuid()).pw_name


@pytest.fixture
def env(tmp_path):
    (tmp_path / "home").mkdir()
    return dict(os.environ, HOME=str(tmp_path / "home"), FAKE_FIDO_KEY=str(tmp_path / "key"),
                FAKE_U2F_LOG=str(tmp_path / "log"),
                SHANI_FIDO2_TOKEN=str(ROOT / "dev/fake-fido2-token.sh"), SHANI_PAMU2FCFG=str(ROOT / "dev/fake-pamu2fcfg.sh"))


def run(env, cmd):
    return subprocess.run([sys.executable, str(BRIDGE), cmd], capture_output=True, text=True, env=env, timeout=20)


def keys(env):
    return Path(env["HOME"], ".config/Yubico/u2f_keys")


def test_no_key_nothing_registered(env):
    assert json.loads(run(env, "probe").stdout) == {"key": False, "keys": [], "registered": 0}


def test_register_one_then_a_second_on_the_same_line(env):
    Path(env["FAKE_FIDO_KEY"]).touch()
    assert json.loads(run(env, "probe").stdout)["keys"] == ["Yubico YubiKey OTP+FIDO+CCID"]
    p = run(env, "register")
    assert p.stdout.split() == ["touch", "done"]
    first = keys(env).read_text()
    assert first.startswith(ME + ":h") and first.count("\n") == 1
    assert oct(keys(env).stat().st_mode & 0o777) == "0o600"
    assert run(env, "register").stdout.split() == ["touch", "done"]
    line = keys(env).read_text()
    assert line.startswith(first.rstrip("\n") + ":h") and line.count("\n") == 1   # the first kept
    log = Path(env["FAKE_U2F_LOG"]).read_text().splitlines()
    assert log == [f"-u {ME}", f"-u {ME} -n"]
    assert json.loads(run(env, "probe").stdout)["registered"] == 2


def test_no_touch_changes_nothing(env):
    p = run(env, "register")
    assert p.returncode == 1 and p.stdout.splitlines()[-1] == "failed: No device found. Aborting."
    assert not keys(env).exists()


def test_remove_forgets_mine_and_keeps_anyone_elses(env):
    keys(env).parent.mkdir(parents=True)
    keys(env).write_text(f"{ME}:a,b,es256,+presence\nsomeone:c,d,es256,+presence\n")
    run(env, "remove")
    assert keys(env).read_text() == "someone:c,d,es256,+presence\n"
    keys(env).write_text(f"{ME}:a,b,es256,+presence\n")
    run(env, "remove")
    assert not keys(env).exists()
    assert json.loads(run(env, "probe").stdout)["registered"] == 0
