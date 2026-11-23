"""Static guards for the pass-22 Chronoa / startup-hook / launcher-search fixes."""

from pathlib import Path

SHANI = Path(__file__).parent.parent / "shani"


def test_chronoa_reply_text_is_plain_text():
    """LLM/tool output is untrusted: the assistant reply must not render RichText."""
    src = (SHANI / "Modules/Chronoa/ChronoaPanel.qml").read_text()
    block = src.split("id: asstText", 1)[1].split("// tool activity", 1)[0]
    assert "text: row.text" in block
    assert "textFormat: Text.PlainText" in block


def test_startup_hook_waits_for_settings_load():
    """Settings.hooks is the disabled default until the async read finishes."""
    src = (SHANI / "Services/Hooks.qml").read_text()
    assert "Component.onCompleted: Qt.callLater(executeStartupHook)" not in src
    assert "function onLoadedChanged()" in src
    assert "if (Settings.loaded) executeStartupHook();" in src


def test_content_search_uses_configured_folders():
    """Inside-files search must honour Settings > Search folders, like name search."""
    src = (SHANI / "Modules/Launcher/Launcher.qml").read_text()
    assert 'd="$HOME/Documents $HOME/Desktop $HOME/Downloads"' not in src
    assert "Settings.data.searchFolders" in src
    assert '.replace(/^~/, Quickshell.env("HOME"))' in src
