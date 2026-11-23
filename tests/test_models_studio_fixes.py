"""Static guards for the Models/Studio fixes: installed-model size parsing,
fit-check honesty, remove/refresh race, empty API keys and Enter-to-generate.

These QML files are only loaded by Quickshell, so the tests assert on source
rather than instantiating the types.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "shani/Services/Models.qml"
MODELS_WIN = ROOT / "shani/Modules/Models/ModelsWindow.qml"
STUDIO_WIN = ROOT / "shani/Modules/Studio/StudioWindow.qml"


def test_installed_size_keeps_its_unit():
    """Fix 1: ollama SIZE is '2.0 GB', not the truncated '2.0'."""
    t = MODELS.read_text()
    assert r"([\d.]+\s*(?:GB|MB|GiB|MiB|B))" in t
    assert "name: m[1]" in t and "size: m[2].replace(" in t
    assert "const parts = line.trim().split" not in t  # old truncating parse


def test_fit_check_is_honest_about_unknown_sizes():
    """Fix 2: unparseable sizes are not reported as fitting; MB is understood."""
    t = MODELS.read_text()
    body = t[t.index("function fitsInRam") : t.index("function refresh")]
    assert "unknown size: don't claim it fits" in body
    assert "if (!m) return false;" in body
    assert "MiB" in body and "MiB)$/i.test(m[2])" in body
    assert "? 1024 : 1" in body
    assert "root.ramAvailable <= 0" in body  # unknown RAM must not block downloads


def test_remove_drops_the_row_and_refreshes_afterward():
    """Fix 3: deleting a model no longer leaves a stale row until manual refresh."""
    t = MODELS.read_text()
    assert "Timer { id: removeRefresh" in t
    body = t[t.index("function remove") :]
    assert "root.installed = root.installed.filter(m => m.name !== name);" in body
    assert "removeRefresh.restart();" in body
    assert "Qt.callLater(root.refresh)" not in body


def test_connect_requires_an_api_key():
    """Fix 4: blank keys cannot mark a provider as connected."""
    t = MODELS_WIN.read_text()
    assert "connectDialog.standardButton(Dialog.Yes)" in t
    assert 'Qt.binding(() => win.connectKey.trim() !== "")' in t
    assert 'if (win.connectKey.trim() === "") return;' in t
    assert "Enter an API key to enable Connect" in t
    assert "secret: true" in t and "echoMode" not in t  # Common TextField API


def test_enter_key_respects_busy_guard():
    """Fix 5: pressing Enter while generating cannot start a second job."""
    t = STUDIO_WIN.read_text()
    assert (
        "onAccepted: { if (Studio.busy) return; Studio.generate(win.description);" in t
    )
    assert "onAccepted: { Studio.generate(win.description);" not in t
    assert 'enabled: win.description.trim() !== "" && !Studio.busy' in t
