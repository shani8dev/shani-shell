"""bridge/system_net.py against the stand-ins in dev/fake-system-net.py:
the resolver file and the resolver's own status, listening ports and sshd,
discovered services with a timeout that cannot hang, the Caddyfile's sites
without its secret, a tunnel listing without its token, and mail's smart host.
Every answer is one JSON object; no caller-supplied word reaches an argv.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_net.py"
FAKE = ROOT / "dev" / "fake-system-net.py"
TOOLS = ("resolvectl", "systemctl", "ss", "avahi-browse", "caddy", "cloudflared")


@pytest.fixture
def env(tmp_path):
    for name in TOOLS:
        link = tmp_path / name
        if not link.exists():
            link.symlink_to(FAKE)
    e = dict(
        os.environ,
        FAKE_SYSTEM_NET=str(tmp_path),
        PATH="%s:%s" % (tmp_path, os.environ["PATH"]),
        SHANI_RESOLV_CONF=str(tmp_path / "resolv.conf"),
        SHANI_RESOLVECTL="resolvectl",
        SHANI_SYSTEM_SYSTEMCTL="systemctl",
        SHANI_SS="ss",
        SHANI_SYSCTL_FILE=str(tmp_path / "ip_forward"),
        SHANI_AVAHI_BROWSE="avahi-browse",
        SHANI_CADDYFILE=str(tmp_path / "Caddyfile"),
        SHANI_CADDY="caddy",
        SHANI_CLOUDFLARED_DIR=str(tmp_path / "cloudflared-config"),
        SHANI_CLOUDFLARED="cloudflared",
        SHANI_EXIM_CONF=str(tmp_path / "exim.conf"),
    )
    subprocess.run(
        [sys.executable, str(FAKE), "fixtures"], env=e, check=True, capture_output=True
    )
    return e


def run(env, verb, *args):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), verb, *args],
        capture_output=True,
        text=True,
        env=env,
    )
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    assert len(lines) == 1, (r.stdout, r.stderr)
    return lines[0], r.returncode


def test_resolver(tmp_path, env):
    r, rc = run(env, "resolver")
    assert rc == 0 and r["error"] == ""
    assert r["conf"] == str(tmp_path / "resolv.conf")
    assert r["target"] == "resolv.conf.real"
    assert r["servers"][:2] == ["1.1.1.1", "8.8.8.8"]
    assert "127.0.0.53" in r["servers"]
    assert "lan" in r["search"] and "home" in r["search"]
    assert r["resolved"] == "active"
    assert r["links"] == ["enp1s0", "wlan0"]


def test_inbound(tmp_path, env):
    r, rc = run(env, "inbound")
    assert rc == 0 and r["error"] == ""
    ports = {(p["port"], p["address"], p["process"]) for p in r["ports"]}
    assert (22, "0.0.0.0", "sshd") in ports
    assert (443, "::", "caddy") in ports
    assert all(p["proto"] == "tcp" for p in r["ports"])
    assert r["sshd"] == "active" and r["forwarding"] == "on"


def test_avahi_services_and_timeout(tmp_path, env):
    r, rc = run(env, "avahi")
    assert rc == 0 and r["installed"] and r["active"] and r["error"] == ""
    assert len(r["services"]) == 2
    assert {s["type"] for s in r["services"]} == {"_ipp._tcp", "_smb._tcp"}
    assert next(s for s in r["services"] if s["type"] == "_ipp._tcp")["port"] == 631

    (tmp_path / "hang-avahi").write_text("")
    started = time.monotonic()
    r, rc = run(env, "avahi")
    assert time.monotonic() - started < 8  # the five-second cap, not the fake's 30
    assert rc == 0 and r["services"] == []


def test_caddy_sites_without_secret(tmp_path, env):
    r, rc = run(env, "caddy")
    assert rc == 0 and r["installed"]
    assert r["file"] == str(tmp_path / "Caddyfile") and r["valid"]
    assert r["sites"] == ["example.com", "localhost:8080"]
    assert "super-secret-value-123" not in json.dumps(r)


def test_cloudflared_tunnels_without_token(tmp_path, env):
    r, rc = run(env, "cloudflared")
    assert rc == 0 and r["installed"] and r["config"] and r["credentials"]
    assert [t["name"] for t in r["tunnels"]] == ["home", "workshop"]
    dumped = json.dumps(r)
    assert "eyJ" not in dumped and "signature" not in dumped


def test_mail_smart_direct_and_plain_host(tmp_path, env):
    smart, rc = run(env, "mail")
    assert rc == 0 and smart["relay"] == "smart host"
    assert smart["host"] == "smtp.example.com"

    direct, _ = run(
        dict(env, SHANI_EXIM_CONF=str(tmp_path / "exim-direct.conf")), "mail"
    )
    assert direct["relay"] == "direct" and direct["host"] == ""

    bad, _ = run(dict(env, SHANI_EXIM_CONF=str(tmp_path / "exim-bad.conf")), "mail")
    assert bad["relay"] == "smart host" and bad["host"] == ""

    missing, _ = run(dict(env, SHANI_EXIM_CONF=str(tmp_path / "absent.conf")), "mail")
    assert missing["relay"] == "unknown" and missing["error"]


def test_no_caller_word_reaches_an_argv(tmp_path, env):
    pwn = tmp_path / "pwn"
    r, rc = run(env, "resolver", "; touch " + str(pwn))
    assert rc == 0 and r["target"] == "resolv.conf.real"  # extra words ignored
    assert "error" in run(env, "resolver;id")[0]
    assert not pwn.exists()
    assert "touch" not in (tmp_path / "calls").read_text()
