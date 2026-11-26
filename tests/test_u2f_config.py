"""bridge/u2f.py: PAM module settings and privileged writes, with rejecting stand-ins."""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge" / "u2f.py"
YKMAN = ROOT / "dev" / "fake-ykman.py"

# pkexec stand-in: records argv and stdin, answers ok. Never echoes stdin.
FAKE_PKEXEC = """#!/usr/bin/env python3
import json
import os
import sys
record = {"argv": sys.argv[1:], "stdin": sys.stdin.read()}
with open(os.environ["FAKE_PKEXEC_LOG"], "a") as f:
    print(json.dumps(record), file=f)
print(json.dumps({"ok": True}))
"""


@pytest.fixture
def env(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    pkexec = tmp_path / "fake-pkexec.py"
    pkexec.write_text(FAKE_PKEXEC)
    pkexec.chmod(0o755)
    return dict(
        os.environ,
        HOME=str(home),
        SHANI_PAM_U2F_CONF=str(tmp_path / "pam_u2f.conf"),
        SHANI_PAM_YUBICO_CONF=str(tmp_path / "pam_yubico.conf"),
        SHANI_YKMAN=str(YKMAN),
        SHANI_SYSTEM_PKEXEC=str(pkexec),
        SHANI_ADMIN_TOOL="/usr/lib/shani-shell/shani-admin.py",
        SHANI_FIDO2_TOKEN=str(ROOT / "dev/fake-fido2-token.sh"),
        FAKE_PKEXEC_LOG=str(tmp_path / "pkexec.log"),
    )


def run(env, verb, payload=None):
    request = None if payload is None else json.dumps(payload)
    return subprocess.run(
        [sys.executable, str(BRIDGE), verb],
        input=request,
        capture_output=True,
        text=True,
        env=env,
        timeout=20,
    )


def data(process):
    assert process.returncode == 0, process.stderr
    return json.loads(process.stdout)


def writes(env):
    log = Path(env["FAKE_PKEXEC_LOG"])
    return (
        [json.loads(line) for line in log.read_text().splitlines()]
        if log.exists()
        else []
    )


def test_config_reads_both_modules_hides_key_counts_credentials(env, tmp_path):
    authfile = tmp_path / "authorized_keys"
    authfile.write_text("# a comment\nuser:cred-a:cred-b\nuser2:cred-c\n\n")
    Path(env["SHANI_PAM_U2F_CONF"]).write_text(
        "# pam settings\nauth sufficient pam_u2f.so authfile=%s cue nouserok origin=https://example.test\n"
        % authfile
    )
    Path(env["SHANI_PAM_YUBICO_CONF"]).write_text(
        "auth required pam_yubico.so mode=challenge-response key=ONE-TIME-SECRET try_first_pass debug\n"
    )
    out = data(run(env, "config"))
    fido2 = out["fido2"]
    assert fido2["available"] is True
    assert fido2["values"]["authfile"] == str(authfile)
    assert fido2["values"]["origin"] == "https://example.test"
    assert "cue" in fido2["flags"] and "nouserok" in fido2["flags"]
    assert fido2["knownOnly"] is True
    assert fido2["authfileCount"] == 2
    assert fido2["path"] == env["SHANI_PAM_U2F_CONF"]
    yubico = out["yubico"]
    assert yubico["available"] is True
    assert yubico["values"]["key"] == "[hidden]"
    assert "ONE-TIME-SECRET" not in json.dumps(out)
    assert yubico["mode"] == "challenge-response"
    assert yubico["modes"] == ["client", "challenge-response"]
    assert "try_first_pass" in yubico["flags"] and "debug" in yubico["flags"]
    assert yubico["knownOnly"] is True
    assert yubico["path"] == env["SHANI_PAM_YUBICO_CONF"]
    assert out["registered"] == 0
    assert out["ykman"] == {"available": True, "version": "5.4.1"}
    assert out["error"] == ""


@pytest.mark.parametrize(
    "target,settings",
    [
        ("fido2", {"bogus": "x"}),
        ("yubico", {"mode": "magic"}),
        ("fido2", {"origin": "https://x;touch /tmp/x"}),
        ("yubico", {"urllist": "https://x`id`"}),
        ("fido2", {"appid": "$HOME"}),
        ("fido2", {"origin": "a|b"}),
        ("fido2", {"authfile": "a&b"}),
        ("fido2", {"origin": "a\nb"}),
        ("nope", {"cue": True}),
    ],
)
def test_config_set_refuses_before_pkexec(env, target, settings):
    out = data(
        run(env, "config-set", {"target": target, "settings": settings, "confirm": ""})
    )
    assert out["ok"] is False
    assert out["error"]
    assert out["needsConfirm"] == ""
    assert writes(env) == []


def test_alwaysok_needs_its_exact_word(env):
    conf = Path(env["SHANI_PAM_U2F_CONF"])
    conf.write_text(
        "# keep me\nauth sufficient pam_u2f.so cue\nauth sufficient pam_u2f.so mystery=keep\n"
    )
    request = {"target": "fido2", "settings": {"alwaysok": True}, "confirm": ""}
    out = data(run(env, "config-set", request))
    assert (
        out["ok"] is False and out["error"] == "" and out["needsConfirm"] == "alwaysok"
    )
    assert writes(env) == []
    request["confirm"] = "yes"
    out = data(run(env, "config-set", request))
    assert out["ok"] is False and out["error"] and out["needsConfirm"] == "alwaysok"
    assert writes(env) == []
    request["confirm"] = "alwaysok"
    out = data(run(env, "config-set", request))
    assert out["ok"] is True and out["needsConfirm"] == "" and out["error"] == ""
    assert set(out["config"]) == {"fido2", "yubico", "registered", "ykman", "error"}
    record = writes(env)[-1]
    assert record["argv"] == ["/usr/lib/shani-shell/shani-admin.py", "pam-config-set"]
    sent = json.loads(record["stdin"])
    assert sent["target"] == "fido2"
    assert hashlib.sha256(sent["text"].encode("utf-8")).hexdigest() == sent["sha256"]
    assert "alwaysok" in sent["text"]
    assert "# keep me" in sent["text"] and "mystery=keep" in sent["text"]
    assert "alwaysok" not in " ".join(record["argv"])


def test_nouserok_needs_its_own_word(env):
    Path(env["SHANI_PAM_U2F_CONF"]).write_text("auth sufficient pam_u2f.so cue\n")
    request = {"target": "fido2", "settings": {"nouserok": True}, "confirm": "alwaysok"}
    out = data(run(env, "config-set", request))
    assert out["ok"] is False and out["needsConfirm"] == "nouserok"
    assert writes(env) == []
    request["confirm"] = "nouserok"
    out = data(run(env, "config-set", request))
    assert out["ok"] is True
    text = json.loads(writes(env)[-1]["stdin"])["text"]
    assert "nouserok" in text


def test_turning_a_flag_off_needs_no_confirmation(env):
    Path(env["SHANI_PAM_U2F_CONF"]).write_text(
        "auth sufficient pam_u2f.so alwaysok nouserok\n"
    )
    out = data(
        run(
            env,
            "config-set",
            {"target": "fido2", "settings": {"alwaysok": False}, "confirm": ""},
        )
    )
    assert out["ok"] is True and out["needsConfirm"] == ""
    text = json.loads(writes(env)[-1]["stdin"])["text"]
    assert "alwaysok" not in text and "nouserok" in text


def test_yubico_write_sends_text_on_stdin_only(env):
    Path(env["SHANI_PAM_YUBICO_CONF"]).write_text(
        "auth required pam_yubico.so mode=client\n"
    )
    out = data(
        run(
            env,
            "config-set",
            {
                "target": "yubico",
                "settings": {"mode": "challenge-response", "debug": True},
                "confirm": "",
            },
        )
    )
    assert out["ok"] is True
    record = writes(env)[-1]
    sent = json.loads(record["stdin"])
    assert sent["target"] == "yubico"
    assert "mode=challenge-response" in sent["text"]
    assert hashlib.sha256(sent["text"].encode("utf-8")).hexdigest() == sent["sha256"]
    assert "mode=challenge-response" not in " ".join(record["argv"])
    assert out["config"]["yubico"]["modes"] == ["client", "challenge-response"]
