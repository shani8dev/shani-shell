"""One ToolPath helper (Common/ToolPath.js) is the single source of the bridge
tool install prefix.

The helper is plain JS with `.pragma library`; it cannot see QML globals, so
callers pass the env value: `ToolPath.of(Quickshell.env("KEY"), "file.py")`.
Node runs the helper directly to verify the boundary (env set vs unset).
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLPATH_JS = ROOT / "shani/Common/ToolPath.js"
NODE = shutil.which("node") or shutil.which("nodejs")
node_mark = pytest.mark.skipif(NODE is None, reason="node is not installed")


@pytest.fixture(scope="module")
def js():
    body = TOOLPATH_JS.read_text(encoding="utf-8")
    return "\n".join(line for line in body.splitlines() if not line.startswith(".pragma"))


@node_mark
def call(js, env_value, fallback):
    prog = (
        js
        + "\nconsole.log(JSON.stringify(of("
        + json.dumps(env_value)
        + ", "
        + json.dumps(fallback)
        + ")));\n"
    )
    out = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


def test_helper_is_a_pragma_library_single_source():
    body = TOOLPATH_JS.read_text(encoding="utf-8")
    assert body.splitlines()[0].strip() == ".pragma library"
    assert "function of(envValue, fallback)" in body
    assert 'var DEFAULT_DIR = "/usr/lib/shani-shell"' in body
    # prefix spelled once as the constant; never hardcoded as a joined path
    assert body.count("/usr/lib/shani-shell/") == 0
    # must not depend on QML globals from inside a pragma library
    code = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("//"))
    assert "Quickshell" not in code


@node_mark
def test_of_uses_env_override_when_set(js):
    assert call(js, "/opt/feeds.py", "feeds.py") == "/opt/feeds.py"


@node_mark
def test_of_falls_back_to_default_dir(js):
    assert call(js, "", "feeds.py") == "/usr/lib/shani-shell/feeds.py"
    assert call(js, None, "feeds.py") == "/usr/lib/shani-shell/feeds.py"


def test_no_old_three_arg_api_in_qml():
    # old broken form: ToolPath.of("name", "ENV_KEY", "fallback")
    bad = []
    for f in (ROOT / "shani").rglob("*"):
        if f.suffix not in (".qml", ".js") or f.name == "ToolPath.js":
            continue
        txt = f.read_text(encoding="utf-8")
        if 'ToolPath.of("' in txt and 'Quickshell.env("' not in txt.split('ToolPath.of(')[1][:80]:
            # rough check; precise below
            pass
        import re
        if re.search(r'ToolPath\.of\(\s*"[^"]+"\s*,\s*"[^"]+"\s*,\s*"[^"]+"\s*\)', txt):
            bad.append(str(f.relative_to(ROOT)))
    assert not bad, f"old 3-arg ToolPath.of still present: {bad}"


def test_callers_pass_quickshell_env():
    # Every ToolPath.of call should pass Quickshell.env(...) as first arg.
    import re
    missing = []
    for f in (ROOT / "shani").rglob("*"):
        if f.suffix not in (".qml", ".js") or f.name == "ToolPath.js":
            continue
        txt = f.read_text(encoding="utf-8")
        for m in re.finditer(r'ToolPath\.of\(([^,]+),', txt):
            arg = m.group(1).strip()
            if not arg.startswith('Quickshell.env(') and not arg.startswith('envValue'):
                missing.append(f"{f.relative_to(ROOT)}: {arg}")
    assert not missing, f"ToolPath.of first arg should be Quickshell.env(...): {missing}"
