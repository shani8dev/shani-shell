"""Static checks for the Proxy service hardening.

Five small fixes, one test each: validated host:port, normalised proxy mode,
settings values out of argv (and still applied immediately), PAC scheme checks,
and a clean switch back to Off/Auto with a private environment file.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def qml():
    return (ROOT / "shani/Services/Proxy.qml").read_text(encoding="utf-8")


def test_host_port_validates_host_and_port():
    text = qml()
    pattern = re.search(r"const m = /(.+?)/\.exec\(s", text).group(1)
    rx = re.compile(pattern)
    for valid in (
        "proxy.example.com:8080",
        "127.0.0.1:1080",
        "[::1]:1080",
        "localhost:1",
    ):
        assert rx.match(valid), valid
    for invalid in (
        "user:secret@proxy.example.com:8080",  # credentials must never be accepted
        "http://proxy.example.com:8080",
        "proxy.example.com:abcdef",
        "proxy.example.com;rm -rf /:8080",
    ):
        assert not rx.match(invalid), invalid
    assert 'port >= 1 && port <= 65535 ? [m[1], m[2]] : ["", "0"]' in text
    assert 'if (!m) return ["", "0"];' in text


def test_unknown_mode_including_system_is_treated_as_off():
    text = qml()
    assert 'return m === "manual" || m === "auto" ? m : "none";' in text
    assert 'gsettings set $p mode "$mode"' in text
    assert 'mode="$SH_PROXY_MODE"' in text
    assert "SH_PROXY_MODE: root.effectiveMode()" in text


def test_settings_values_are_not_in_argv_and_changes_reapply():
    text = qml()
    assert 'command: ["sh", "-c",' in text
    cmd = re.search(r"command:\s*\[.*?\]\s*\n\s*environment:", text, re.S)
    assert cmd is not None
    assert "root.d." not in cmd.group(0)
    assert "root.httpTarget" not in cmd.group(0)
    assert "environment: root.proxyEnv" in text
    assert "onProxyEnvChanged: if (Settings.loaded) proxy.running = true" in text
    for key in (
        "SH_PROXY_MODE",
        "SH_PROXY_PAC",
        "SH_PROXY_HTTP_HOST",
        "SH_PROXY_SOCKS_PORT",
    ):
        assert key in text, key


def test_pac_url_is_scheme_checked():
    text = qml()
    assert r'return /^(https?|file):\/\//i.test(u) ? u : "";' in text
    assert "SH_PROXY_PAC: root.effectivePac()" in text
    assert 'gsettings set $p autoconfig-url "$SH_PROXY_PAC"' in text
    assert 'gsettings set $p autoconfig-url ""' in text


def test_mode_switch_clears_stale_config_and_protects_env_file():
    text = qml()
    assert (
        'for k in http https socks; do gsettings set $p.$k host ""; '
        "gsettings set $p.$k port 0; done" in text
    )
    assert 'rm -f "$e"' in text
    assert "umask 077" in text
    assert 'chmod 600 "$e"' in text
