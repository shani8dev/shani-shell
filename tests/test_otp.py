"""bridge/otp.py: the codes against RFC 6238's own table, the otpauth:// parsing
and what it refuses, and - where a keyring daemon is installed - the secrets
stored in it for real and never printed."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[1] / "bridge" / "otp.py"
spec = importlib.util.spec_from_file_location("otp", TOOL)
otp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(otp)

# RFC 6238 appendix B: the seeds are ASCII "1234567890" repeated to the hash's length
SEEDS = {"SHA1": b"12345678901234567890", "SHA256": b"12345678901234567890123456789012",
         "SHA512": b"1234567890123456789012345678901234567890123456789012345678901234"}
TABLE = [(59, "94287082", "46119246", "90693936"), (1111111109, "07081804", "68084774", "25091201"),
         (1111111111, "14050471", "67062674", "99943326"), (1234567890, "89005924", "91819424", "93441116"),
         (2000000000, "69279037", "90698825", "38618901"), (20000000000, "65353130", "77737706", "47863826")]


def test_codes_match_rfc_6238():
    for at, sha1, sha256, sha512 in TABLE:
        assert otp.totp(SEEDS["SHA1"], at, 30, 8, "SHA1") == sha1
        assert otp.totp(SEEDS["SHA256"], at, 30, 8, "SHA256") == sha256
        assert otp.totp(SEEDS["SHA512"], at, 30, 8, "SHA512") == sha512


def test_otpauth_addresses():
    e = otp.parse("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example")
    assert (e["issuer"], e["account"], e["digits"], e["period"], e["algorithm"]) == ("Example", "alice@example.com", 6, 30, "SHA1")
    assert otp.parse("otpauth://totp/bob?secret=jbsw y3dp ehpk 3pxp")["secret"] == "JBSWY3DPEHPK3PXP"
    for bad in ("otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=1", "otpauth://totp/x?secret=not*base32",
                "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=12", "https://example.com", "otpauth://totp/?secret=JBSWY3DPEHPK3PXP"):
        with pytest.raises(ValueError):
            otp.parse(bad)


@pytest.mark.skipif(not (shutil.which("gnome-keyring-daemon") and shutil.which("dbus-run-session")), reason="no keyring daemon here")
def test_secrets_live_in_the_keyring_and_are_never_printed(tmp_path):
    script = f"""
set -e
export HOME={tmp_path} XDG_DATA_HOME={tmp_path}/data XDG_RUNTIME_DIR={tmp_path}/run
mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
# a login keyring, as pam_gnome_keyring makes and unlocks at sign-in (shani-greetd)
printf 'test' | gnome-keyring-daemon --unlock --components=secrets >/dev/null
python3 {TOOL} add 'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example'
python3 {TOOL} list
"""
    out = subprocess.run(["dbus-run-session", "--", "sh", "-c", script], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    added, listed = [json.loads(line) for line in out.stdout.strip().splitlines()[-2:]]
    assert added["ok"] and listed[0]["issuer"] == "Example" and len(listed[0]["code"]) == 6
    assert "JBSWY3DPEHPK3PXP" not in out.stdout
    assert not list(tmp_path.rglob("*.json"))          # nothing of it in a file of ours
    plain = subprocess.run(["grep", "-rl", "JBSWY3DPEHPK3PXP", str(tmp_path)], capture_output=True, text=True).stdout
    assert plain == ""                                 # and not in the clear anywhere (the keyring file is encrypted)
