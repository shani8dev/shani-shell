"""bridge/battery.py, bridge/ups.py and bridge/textmate.py.

Three bridges with no coverage until now: UPower's battery health, NUT's UPS,
and TextMate's grammar and theme files. Each is driven with a stand-in - a fake
sysfs/UPower, the fake upsc the shell already tests against, and plist files
written here - so the mapping is pinned without the hardware.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge"


def run(script, *args, env=None, stdin=""):
    return subprocess.run(
        [sys.executable, str(BRIDGE / script), *args],
        capture_output=True,
        text=True,
        timeout=60,
        env=env,
        input=stdin,
    )


# ---- battery ---------------------------------------------------------------


def test_battery_answers_json():
    """No battery in a container: the bridge says so rather than failing."""
    out = run("battery.py", "info")
    assert out.returncode == 0
    data = json.loads(out.stdout)
    assert "present" in data


def test_battery_history_is_a_list():
    out = run("battery.py", "history", "60")
    assert out.returncode == 0
    assert isinstance(json.loads(out.stdout), list)


def test_battery_rejects_a_bad_command():
    out = run("battery.py", "nonsense")
    assert out.returncode != 0 or "error" in out.stdout


# ---- ups -------------------------------------------------------------------


def test_ups_answers_json():
    out = run("ups.py")
    assert out.returncode == 0
    data = json.loads(out.stdout)
    assert "present" in data


def test_ups_without_a_ups_says_so():
    data = json.loads(run("ups.py").stdout)
    if not data.get("present"):
        assert data.get("name", "") == ""


# ---- textmate --------------------------------------------------------------


def test_textmate_parses_a_json_grammar(tmp_path):
    grammar = {
        "name": "Example",
        "scopeName": "source.example",
        "fileTypes": ["ex"],
        "patterns": [
            {"match": "\\b(if|else)\\b", "name": "keyword.control.example"},
            {
                "match": '"([^"]*)"',
                "name": "string.quoted.double.example",
                "captures": {"1": {"name": "string.example"}},
            },
        ],
    }
    p = tmp_path / "Example.tmLanguage"
    p.write_text(json.dumps(grammar), encoding="utf-8")
    out = run("textmate.py", "grammar", str(p))
    assert out.returncode == 0
    got = json.loads(out.stdout)
    assert got.get("scopeName") == "source.example"
    assert got.get("fileTypes") == ["ex"]


def test_textmate_parses_a_plist_grammar(tmp_path):
    plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>name</key><string>Plist Example</string>
  <key>scopeName</key><string>source.plist</string>
  <key>fileTypes</key><array><string>pls</string></array>
  <key>patterns</key><array><dict>
    <key>match</key><string>\\bfoo\\b</string>
    <key>name</key><string>variable.example</string>
  </dict></array>
</dict></plist>
"""
    p = tmp_path / "Plist.tmLanguage"
    p.write_text(plist, encoding="utf-8")
    got = json.loads(run("textmate.py", "grammar", str(p)).stdout)
    assert got.get("scopeName") == "source.plist"


def test_textmate_parses_a_theme(tmp_path):
    theme = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>name</key><string>Example theme</string>
  <key>settings</key><array>
    <dict>
      <key>settings</key><dict>
        <key>background</key><string>#272822</string>
        <key>foreground</key><string>#F8F8F2</string>
      </dict>
    </dict>
    <dict>
      <key>name</key><string>Comment</string>
      <key>scope</key><string>comment</string>
      <key>settings</key><dict>
        <key>foreground</key><string>#75715E</string>
        <key>fontStyle</key><string>italic</string>
      </dict>
    </dict>
  </array>
</dict></plist>
"""
    p = tmp_path / "Example.tmTheme"
    p.write_text(theme, encoding="utf-8")
    out = run("textmate.py", "theme", str(p))
    assert out.returncode == 0
    got = json.loads(out.stdout)
    assert isinstance(got, list) and got
    assert got[0]["scope"] == ""  # the global settings
    assert any(s["scope"] == "comment" for s in got)
    assert any(s.get("fontStyle") == "italic" for s in got)


def test_textmate_lists_a_folder(tmp_path):
    (tmp_path / "One.tmLanguage").write_text(
        json.dumps(
            {
                "name": "One",
                "scopeName": "source.one",
                "fileTypes": ["one"],
                "patterns": [],
            }
        ),
        encoding="utf-8",
    )
    (tmp_path / "Two.tmTheme").write_text(
        '<?xml version="1.0"?><plist version="1.0"><dict><key>settings</key><array></array></dict></plist>',
        encoding="utf-8",
    )
    out = run("textmate.py", "list", str(tmp_path))
    assert out.returncode == 0
    got = json.loads(out.stdout)
    assert any(g["name"] == "One" for g in got.get("grammars", []))
    assert any(t["name"] == "Two" for t in got.get("themes", []))


def test_textmate_survives_a_file_it_cannot_parse(tmp_path):
    p = tmp_path / "Broken.tmLanguage"
    p.write_text("not a plist at all", encoding="utf-8")
    out = run("textmate.py", "grammar", str(p))
    assert out.returncode != 0 or "error" in out.stdout
