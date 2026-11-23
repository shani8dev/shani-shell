"""Static + small JS checks for the remaining automation/hooks fixes."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def node(prog):
    return json.loads(
        subprocess.run(
            ["node", "-e", prog], capture_output=True, text=True, check=True
        ).stdout
    )


def js_function(source, name):
    start = source.index("function " + name + "(")
    depth = 0
    for end in range(start, len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
            if depth == 0:
                break
    return source[start : end + 1]


AUTOMATIONS = "shani/Services/Automations.qml"
SETTINGS = "shani/Modules/Settings/SettingsAutomations.qml"
PICKER = "shani/Common/TimePicker.qml"


def test_conflict_fires_once_and_warns():
    a = read(AUTOMATIONS)
    s = read(SETTINGS)
    # one definition of a conflict, shared by the engine and the settings chip
    assert "function conflictKey(r)" in a
    assert "function conflictsAt(i)" in a
    assert "const firedKeys = {}" in a
    assert "if (!firedKeys[key]) { act(r); firedKeys[key] = true; }" in a
    assert "Automations.conflictsAt(index)" in s
    assert 'tone: "warn"' in s
    assert 'Tr.t("Conflicting rule")' in s


@pytest.mark.skipif(shutil.which("node") is None, reason="node is not installed")
def test_conflict_key_ignores_action_argument():
    fn = js_function(read(AUTOMATIONS), "conflictKey")
    prog = (
        fn + "\nprocess.stdout.write(JSON.stringify(["
        "conflictKey({when:'wifi',is:'Office',then:'volume',arg:'50'}),"
        "conflictKey({when:'wifi',is:'Office',then:'volume',arg:'80'}),"
        "conflictKey({when:'wifi',is:'Office',then:'focus',arg:'50'})]));"
    )
    a, b, c = node(prog)
    assert a == b  # different args, same target -> same conflict group
    assert a != c  # a different action is a different group


def test_run_action_has_timeout_and_syntax_preflight():
    a = read(AUTOMATIONS)
    s = read(SETTINGS)
    assert '"timeout", "10s", "sh", "-c", a' in a
    assert 'Proc.run("automation-command-check", ["sh", "-n", "-c", page.arg]' in s
    assert "if (code === 0) page.commitRule();" in s
    assert 'Tr.t("That command has a syntax error — check it and try again")' in s


def test_exact_duplicate_is_refused():
    s = read(SETTINGS)
    assert "function commitRule()" in s
    assert "i !== page.editIndex" in s
    assert "x.when === rule.when && x.is === rule.is" in s
    assert 'Tr.t("That rule already exists")' in s
    assert "if (dup) { page.showNote" in s


@pytest.mark.skipif(shutil.which("node") is None, reason="node is not installed")
def test_timepicker_renders_12h_preference():
    s = read(PICKER)
    assert "!Settings.data.use24h" in s
    assert 'Tr.t("AM")' in s and 'Tr.t("PM")' in s
    # real extraction: formatPreset must show 12h when ampm is on
    fmt = js_function(s, "formatPreset")
    prog = (
        "var ampm=true; var Tr={t:function(x){return x;}};\n"
        + fmt
        + "\nprocess.stdout.write(JSON.stringify(["
        "formatPreset('09:00'),formatPreset('21:30'),formatPreset('00:15')]));"
    )
    assert node(prog) == ["9:00 AM", "9:30 PM", "12:15 AM"]
