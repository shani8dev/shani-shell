"""Static tests for Software and Chronoa panel gap fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_software_remove_hidden_when_not_installed():
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    # The detail-page Remove button must only show for installed apps.
    idx = w.index('Tr.t("Click again to remove")')
    nearby = w[idx - 120 : idx]
    assert "visible: !!appCol.a.installed" in nearby


def test_software_clears_stale_error_on_user_actions():
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    assert 'function search(words) {\n        win.error = "";' in w
    assert 'function showCategory(c) {\n        win.error = "";' in w
    assert 'function openApp(id) {\n        win.error = "";' in w


def test_software_tab_change_resets_update_confirm():
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    assert "updateAllConfirm.disarm()" in w
    # It should be in the tab click handler.
    assert (
        "win.tab = modelData[0]; win.app = null; updateAllConfirm.disarm();"
        in w
    )


def test_software_leftovers_wait_for_load_before_empty_state():
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    assert "property bool leftoversLoaded: false" in w
    assert "win.leftoversLoaded = false;" in w
    assert "win.leftoversLoaded = true;" in w
    assert (
        'visible: win.tab === "leftovers" && (win.leftoversLoaded || win.leftovers.length > 0)'
        in w
    )


def test_chronoa_listening_stop_toggles_listening():
    w = read("shani/Modules/Chronoa/ChronoaPanel.qml")
    # The stop button shown while listening must stop listening, not TTS.
    block = 'visible: panel.state === "listening"'
    assert block in w
    idx = w.index(block)
    nearby = w[idx : idx + 700]
    assert 'panel.action("toggle-listening")' in nearby
    assert 'panel.action("stop-speaking")' not in nearby
