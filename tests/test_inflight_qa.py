"""Final-integration pins for the parallel UI-uniformity wave.

Static and pure-logic checks only: QML cannot be instantiated here, so these
catch the drift that a running shell would only show as a silent gap — a
component that is not on the import path, a tool declared once and used under
another name, an app registered in the shell but not in the CLI, a translator
string nobody catalogued, or a control with no name for assistive tech.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
COMMON = SHANI / "Common"

NEW_COMMON = [
    "AppWindow.qml",
    "BusyNote.qml",
    "Choice.qml",
    "ConfirmButton.qml",
    "EmptyState.qml",
    "InfoBanner.qml",
    "ListRow.qml",
    "Settings.qml",
    "Ui.qml",
]
NEW_HELPERS = ["Tools.js", "Time.js", "SearchField.qml"]
NEW_APPS = [
    "dictionary",
    "podcasts",
    "teleprompter",
    "network-tools",
    "database-browser",
    "nearby-share",
    "paste-history",
]
TOOL_FLAGS = (
    "dictionary",
    "podcasts",
    "teleprompter",
    "netTools",
    "databaseBrowser",
    "startupManager",
    "nearby",
    "pasteHistory",
    "scheduled",
)


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


# ---- the shared components are where the imports say they are ----------------


def test_new_common_components_are_on_the_qml_import_path():
    for name in NEW_COMMON + ["SearchField.qml"]:
        assert (COMMON / name).is_file(), f"Common/{name} missing from qs.Common"
    for name in NEW_HELPERS:
        assert (COMMON / name).is_file(), f"Common/{name} missing"


def test_relative_helper_imports_resolve_to_real_files():
    """A bad ../.. level fails only at runtime, when Quickshell loads the surface."""
    bad = []
    for path in SHANI.rglob("*.qml"):
        text = path.read_text(encoding="utf-8")
        for m in re.finditer(r'^\s*import\s+"([^"]+\.js)"\s+as\s+\w+', text, re.M):
            target = (path.parent / m.group(1)).resolve()
            if not target.is_file():
                bad.append(f"{path.relative_to(ROOT)}: {m.group(1)}")
    assert not bad, f"unresolved JS imports: {bad}"


def test_js_library_imports_inside_js_resolve_to_real_files():
    bad = []
    for path in SHANI.rglob("*.js"):
        for m in re.finditer(
            r'^\.import\s+"([^"]+\.js)"\s+as\s+\w+', path.read_text(), re.M
        ):
            if not (path.parent / m.group(1)).resolve().is_file():
                bad.append(f"{path.relative_to(ROOT)}: {m.group(1)}")
    assert not bad, f"unresolved .import paths: {bad}"


# ---- no duplicate or reserved declarations in the new components -------------


def test_new_components_have_no_duplicate_top_level_declarations():
    for name in NEW_COMMON + ["SearchField.qml", "LeftRail.qml"]:
        path = (
            COMMON / name
            if name in NEW_COMMON + ["SearchField.qml"]
            else SHANI / "Modules/LeftRail/LeftRail.qml"
        )
        seen = set()
        for line in path.read_text().splitlines():
            m = re.match(r"    (?:readonly\s+)?property\s+\w+\s+(\w+)\s*[:=]", line)
            m = m or re.match(r"    signal\s+(\w+)\s*\(", line)
            if not m:
                continue
            assert m.group(1) not in seen, (
                f"{path.relative_to(ROOT)}: duplicate {m.group(1)}"
            )
            seen.add(m.group(1))


def test_confirm_button_does_not_shadow_the_reserved_id_attribute():
    """QML's `id` is a language attribute and cannot be redeclared as a property."""
    assert "property string id:" not in read("shani/Common/ConfirmButton.qml")


# ---- one tool catalog, registered in every surface --------------------------


def test_tools_catalog_has_nine_unique_well_formed_entries():
    tools = read("shani/Common/Tools.js")
    entries = re.findall(
        r'\{\s*label:\s*"([^"]+)",\s*icon:\s*"([^"]+)",\s*flag:\s*"([^"]+)",\s*op:\s*"([^"]+)"',
        tools,
    )
    assert len(entries) == 9, f"expected nine tool entries, got {len(entries)}"
    assert len({e[0] for e in entries}) == 9
    assert {e[2] for e in entries} == set(TOOL_FLAGS)
    for label, icon, flag, op in entries:
        assert label and icon
        assert op == flag + "Open", (label, op)


def test_new_apps_are_registered_in_cli_shell_ids_and_ipc():
    from importlib.machinery import SourceFileLoader
    import importlib.util

    loader = SourceFileLoader("shani_cli_qa", str(ROOT / "bin/shani"))
    mod = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("shani_cli_qa", loader)
    )
    loader.exec_module(mod)
    apps = mod.APPS
    shell = read("shani/shell.qml")
    ids = read("shani/Services/ShellApps.js")
    for name in NEW_APPS:
        assert name in apps, f"bin/shani has no {name}"
        spec = apps[name]
        assert spec[8], f"{name} has no open-state probe"
        assert spec[6], f"{name} has no open call"
        assert spec[8] in shell, f"shell.qml never sets {spec[8]}"
        title = spec[1]
        assert f'"{title}"' in ids, f"ShellApps.js has no {title}"
    for flag in TOOL_FLAGS:
        if flag in ("startupManager", "scheduled"):     # Settings pages now: the IPC opens the page
            assert f"{flag}Open() {{ Ui.openSettings(" in shell, flag
            continue
        assert f"Ui.{flag}" in shell, f"shell.qml does not load the {flag} surface"
        assert f"{flag}Open" in shell, f"shell.qml has no {flag}Open IPC"


def test_i18n_template_covers_every_translated_literal():
    template = json.loads(read("shani/i18n/template.json"))
    missing = []
    for path in sorted(SHANI.rglob("*.qml")):
        text = path.read_text(encoding="utf-8")
        for m in re.finditer(r'Tr\.t\(\s*("(?:[^"\\]|\\.)*")', text):
            literal = json.loads(m.group(1))
            if literal not in template:
                missing.append(f"{path.relative_to(ROOT)}: {literal[:60]}")
    assert not missing, f"literals missing from i18n/template.json: {missing}"


# ---- safety and accessibility of the new surfaces ---------------------------


READ_ONLY_NEW_SURFACES = [
    "shani/Modules/DatabaseBrowser.qml",
    "shani/Modules/Dictionary.qml",
    "shani/Modules/NetTools.qml",
    "shani/Modules/Teleprompter.qml",
    "shani/Modules/LeftRail/LeftRail.qml",
]


def test_read_only_new_surfaces_never_escalate():
    for rel in READ_ONLY_NEW_SURFACES:
        assert "pkexec" not in read(rel), f"{rel} escalates for a read-only job"


def test_new_shared_components_have_no_idle_pollers():
    for name in ("BusyNote.qml", "ConfirmButton.qml", "SearchField.qml"):
        assert "repeat: true" not in read(f"shani/Common/{name}")


def test_interactive_controls_in_new_surfaces_are_named():
    kinds = {
        "IconButton": ("tip",),
        "Button": ("text", "label"),
        "Choice": ("text",),
        "SwitchRow": ("text",),
        "ListRow": ("title",),
        "TextField": ("placeholder", "placeholderText", "label"),
    }
    surfaces = [
        "shani/Modules/MediaPlayer/MediaPlayerWindow.qml",
        "shani/Modules/LeftRail/LeftRail.qml",
        "shani/Common/SearchField.qml",
        "shani/Common/BusyNote.qml",
        "shani/Common/ConfirmButton.qml",
    ]
    unnamed = []
    for rel in surfaces:
        text = read(rel)
        for kind, props in kinds.items():
            for m in re.finditer(r"\b" + kind + r"\s*\{", text):
                start = m.end() - 1
                depth = 0
                for j in range(start, len(text)):
                    if text[j] == "{":
                        depth += 1
                    elif text[j] == "}":
                        depth -= 1
                        if depth == 0:
                            body = text[start + 1 : j]
                            line = text.count("\n", 0, m.start()) + 1
                            break
                else:
                    continue
                has_prop = any(
                    re.search(r"(?<![\w.])" + p + r"\s*:", body) for p in props
                )
                named = re.search(r"(?:Accessible\.name|accessibleName)\s*:", body)
                if not (has_prop or named or "modelData" in body):
                    unnamed.append(f"{rel}:{line} ({kind})")
    assert not unnamed, f"controls with no accessible name: {unnamed}"


# ---- pure-logic pins for the extracted helpers ------------------------------


def _node_eval(script):
    if not shutil.which("node"):
        return None
    return subprocess.run(
        ["node", "-e", script], capture_output=True, text=True, check=True
    ).stdout.strip()


def test_time_helper_formats_seconds_without_drifting():
    out = _node_eval(
        """
const fs = require('fs');
const src = fs.readFileSync(%s, 'utf8').replace(/^\\.pragma library\\s*/, '');
eval(src + '\\nglobalThis.result = [clock(0), clock(65), clockLong(3661), duration(3661), clock(undefined), duration(null)];');
console.log(JSON.stringify(globalThis.result));
"""
        % json.dumps(str(COMMON / "Time.js"))
    )
    if out is None:
        return
    assert json.loads(out) == [
        "0:00",
        "1:05",
        "1:01:01",
        "1-01-01",
        "0:00",
        "0-00-00",
    ]


def test_tools_catalog_is_readable_as_plain_javascript():
    out = _node_eval(
        """
const fs = require('fs');
eval(fs.readFileSync(%s, 'utf8') + '\\nglobalThis.flags = list.map(t => t.flag);');
console.log(JSON.stringify(globalThis.flags));
"""
        % json.dumps(str(COMMON / "Tools.js"))
    )
    if out is None:
        return
    assert json.loads(out) == list(TOOL_FLAGS)
