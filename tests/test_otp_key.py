"""bridge/otp.py: OATH codes kept on a YubiKey (yubikey-manager's ykman) join the
Authenticator's list - plain ones with their code, touch-only ones asked for on
demand - and a counter-based (HOTP) account, which has no code by the clock, is
left out. Against dev/fake-ykman.sh."""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OTP = ROOT / "bridge" / "otp.py"
FAKE = ROOT / "dev" / "fake-ykman.sh"


def run(*args, none=False):
    env = dict(os.environ, SHANI_YKMAN=str(FAKE))
    if none:
        env["SHANI_FAKE_YKMAN_NONE"] = "1"
    return subprocess.run([sys.executable, str(OTP), *args], capture_output=True, text=True, env=env, timeout=30)


def key_rows(out):
    return [r for r in json.loads(out) if r.get("fromKey")]


def test_key_codes_join_the_list():
    r = run("list")
    if r.returncode == 2:          # no keyring here: list() refuses before the key is read
        import pytest
        pytest.skip("no Secret Service in this environment")
    rows = key_rows(r.stdout)
    by = {x["name"]: x for x in rows}
    assert by["GitHub:me@example.com"]["code"] == "482913" and not by["GitHub:me@example.com"]["touch"]
    assert by["Bank:savings"]["touch"] and by["Bank:savings"]["code"] == ""
    assert "VPN:office" not in by          # HOTP: no clock code


def test_key_code_waits_for_the_touch():
    r = run("key-code", "Bank:savings")
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout) == {"code": "731044"}


def test_no_key_no_rows():
    import importlib.util
    spec = importlib.util.spec_from_file_location("otp", OTP)
    otp = importlib.util.module_from_spec(spec)
    os.environ["SHANI_FAKE_YKMAN_NONE"] = "1"
    try:
        spec.loader.exec_module(otp)
        otp.YKMAN = str(FAKE)
        assert otp.key_codes() == []
    finally:
        del os.environ["SHANI_FAKE_YKMAN_NONE"]


def test_parsing_from_the_module():
    import importlib.util
    spec = importlib.util.spec_from_file_location("otp", OTP)
    otp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(otp)
    otp.YKMAN = str(FAKE)
    rows = otp.key_codes()
    assert [r["name"] for r in rows] == ["GitHub:me@example.com", "Bank:savings"]
    assert rows[0]["issuer"] == "GitHub" and rows[0]["account"] == "me@example.com"


def test_a_locked_key_says_so():
    import importlib.util
    spec = importlib.util.spec_from_file_location("otp", OTP)
    otp = importlib.util.module_from_spec(spec)
    os.environ["SHANI_FAKE_YKMAN_LOCKED"] = "1"
    try:
        spec.loader.exec_module(otp)
        otp.YKMAN = str(FAKE)
        rows = otp.key_codes()
        assert len(rows) == 1 and rows[0]["locked"] and rows[0]["fromKey"]
    finally:
        del os.environ["SHANI_FAKE_YKMAN_LOCKED"]
