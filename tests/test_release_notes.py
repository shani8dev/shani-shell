"""Settings > About release-notes reader: static wiring plus the pure rules.

The reader and its service are QML, so their wiring is checked from source. The
markdown → rows, version split and path check are plain functions in the
service; they are extracted and run in node, the way test_whatsnew.py runs its
rules.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
ABOUT = ROOT / "shani/Modules/Settings/SettingsAbout.qml"
READER = ROOT / "shani/Modules/Settings/SettingsReleaseNotes.qml"
SERVICE = ROOT / "shani/Services/ReleaseNotes.qml"
SHIPPED = ROOT / "data/whats-new.md"
NODE = shutil.which("node")


def read(path):
    return path.read_text()


# ---- static wiring ---------------------------------------------------------


def test_about_hosts_the_reader_without_disturbing_computer_info():
    src = read(ABOUT)
    assert 'Tr.t("What changed")' in src
    assert "SettingsReleaseNotes { Layout.fillWidth: true }" in src
    for marker in (
        'Tr.t("This computer")',
        "id: hostnameField",
        "id: healthProc",
        "id: reportProc",
        'Tr.t("More settings")',
    ):
        assert marker in src
    # appended, not inserted into the machine-info section
    assert src.index("SettingsReleaseNotes") > src.index("id: healthProc")


def test_reader_is_a_scrollable_accessible_surface():
    src = read(READER)
    flick = src.split("Flickable {", 1)[1].split("Column {", 1)[0]
    assert "clip: true" in flick
    assert "contentHeight: body.implicitHeight" in flick
    assert "Keys.onUpPressed" in flick and "Keys.onDownPressed" in flick
    assert "KeyFocus {" in src and "notesFlick.forceActiveFocus()" in src
    assert "Accessible.role: Accessible.StaticText" in src
    assert "Accessible.name: text" in src
    assert "page.sections.length > 1" in src
    assert '"See all past notes"' in src
    assert "Theme.surface1" in src and "Theme.stroke" in src
    assert 'Theme.type("body")' in src   # on the type scale (docs/DESIGN.md)
    # no hard-coded colour: the reader follows the theme
    assert not re.search(r'color:\s*"(?:#|rgb|rgba)', src)
    # honest loading / error / empty states
    for marker in ("Loading", "failed", "page.empty", 'Tr.t("Retry")'):
        assert marker in src


def test_service_reads_a_configured_path_without_shell_interpolation():
    src = read(SERVICE)
    assert 'Quickshell.env("SHANI_RELEASE_NOTES_FILE")' in src
    assert "configuredPath: safeNotesPath(" in src
    assert '"/usr/share/shani/whats-new.md"' in src
    assert '"$@"' in src and "cat --" in src
    assert '["sh", "-c",' in src and ".concat(root.candidatePaths)" in src
    # the env value is never pasted into the shell script
    assert "+ Quickshell.env" not in src


# ---- pure rules, run in node ------------------------------------------------


def logic_source():
    """The named functions from the service, with their bodies."""
    src = read(SERVICE)
    chunks = []
    for name in ("safeNotesPath", "plainText", "parseRows", "splitVersions"):
        m = re.search(r"\bfunction\s+" + name + r"\s*\(", src)
        assert m, name
        start = src.index("{", m.end())
        depth = 0
        for j in range(start, len(src)):
            if src[j] == "{":
                depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0:
                    chunks.append(src[m.start() : j + 1])
                    break
        else:
            pytest.fail("unbalanced function " + name)
    return "\n".join(chunks)


def call(expr):
    if NODE is None:
        pytest.skip("node is not installed")
    prog = logic_source() + "\nprocess.stdout.write(JSON.stringify(%s));" % expr
    result = subprocess.run([NODE, "-e", prog], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_markdown_headings_bullets_and_continuations_become_rows():
    md = "# Title\n\n## Sign in\n- **Face** sign-in\n  works on lock\n- Fingerprint\n\nplain *text*"
    assert call("parseRows(%s)" % json.dumps(md)) == [
        {"kind": "heading", "level": 1, "text": "Title"},
        {"kind": "heading", "level": 2, "text": "Sign in"},
        {"kind": "bullet", "text": "Face sign-in works on lock"},
        {"kind": "bullet", "text": "Fingerprint"},
        {"kind": "para", "text": "plain text"},
    ]


def test_file_markup_cannot_become_rich_text():
    md = "<img src=x onerror=alert(1)>\n[label](https://example.org) <b>x</b>"
    assert call("parseRows(%s)" % json.dumps(md)) == [
        {"kind": "para", "text": "label x"},
    ]


def test_version_headings_split_past_notes():
    md = "# What's new\nintro\n\n## v2.0\n- new thing\n\n## Version 1.0\n- old thing\n"
    parts = call("splitVersions(%s)" % json.dumps(md))
    assert len(parts) == 3
    assert parts[0]["label"] == "" and "intro" in parts[0]["md"]
    assert parts[1]["label"] == "v2.0" and "new thing" in parts[1]["md"]
    assert parts[2]["label"] == "Version 1.0"


def test_shipped_undated_file_is_one_section_with_readable_rows():
    md = read(SHIPPED)
    assert len(call("splitVersions(%s)" % json.dumps(md))) == 1
    rows = call("parseRows(%s)" % json.dumps(md))
    assert {"heading", "bullet"} <= {row["kind"] for row in rows}
    assert any(row["text"] == "What's new on this desktop" for row in rows)
    assert "**" not in " ".join(row["text"] for row in rows)


def test_only_plain_absolute_paths_are_accepted():
    good = "/home/asha/Documents/shani/shani-shell/data/whats-new.md"
    assert (
        call('safeNotesPath("/usr/share/shani/whats-new.md")')
        == "/usr/share/shani/whats-new.md"
    )
    assert call("safeNotesPath(%s)" % json.dumps(good)) == good
    for bad in (
        "",
        "notes.md",
        "/etc/../passwd",
        "/tmp/a; id",
        "/tmp/$(id)",
        "/tmp/`id`",
        "/tmp/a'b",
        "/tmp/a\nb",
        "/tmp/a b",
    ):
        assert call("safeNotesPath(%s)" % json.dumps(bad)) == "", bad
