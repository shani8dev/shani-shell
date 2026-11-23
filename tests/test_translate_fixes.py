"""Static checks for five Translate fixes not covered by the other Translate tests.

There is no QML runtime here, so each check reads the source of the window it
guards. Together they cover the stale-result race, the stale error state,
read-aloud, keyboard access to the answer, and stale endpoint status.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WIN = (ROOT / "shani/Modules/Translate/TranslateWindow.qml").read_text()


def _section(start_marker, end_marker):
    start = WIN.index(start_marker)
    return WIN[start : WIN.index(end_marker, start)]


def test_in_flight_answer_cannot_repopulate_an_abandoned_pane():
    """A cancelled or superseded request is ignored; runs never overlap."""
    assert "property int generation: 0" in WIN
    assert "property bool restart: false" in WIN
    assert "runner.generation = ++win.generation;" in WIN
    # only the reply whose generation still matches may write result/error
    assert "if (win.generation === runner.generation) {" in WIN
    # a changed language/mode mid-flight is queued, not run on the same Process
    assert "if (runner.running) { win.restart = true; return; }" in WIN
    assert "if (win.restart) { win.restart = false; win.go(); }" in WIN


def test_stale_error_and_answer_are_cleared_on_every_abandon_action():
    """cancel() is the single place that drops old text/error, and it is wired in."""
    body = _section("function cancel()", "function go()")
    assert 'win.result = ""' in body
    assert 'win.error = ""' in body
    assert "onTextChanged: win.cancel()" in WIN  # typing
    assert 'onClicked: { win.cancel(); input.text = ""; }' in WIN  # Clear
    assert WIN.count("win.cancel(); win.mode =") == 3  # Text/Batch/File
    assert "win.cancel();" in _section("function swap()", "function checkEndpoint()")
    assert "win.cancel(); win.source = modelData[0]" in WIN
    assert "win.cancel(); win.target = modelData[0]" in WIN


def test_answer_can_be_read_aloud():
    """Reuse the existing Speak singleton; stop when it is already speaking."""
    assert "import qs.Services" in WIN
    assert 'text: Tr.t("Read aloud")' in WIN
    assert "Speak.speaking ? Speak.stop() : Speak.speak(win.result)" in WIN
    assert "function speak(text)" in (ROOT / "shani/Services/Speak.qml").read_text()


def test_answer_pane_is_reachable_by_keyboard():
    """Tab reaches the read-only result; arrows at its edges move on."""
    out = _section("id: outText", 'Accessible.name: Tr.t("Translation")')
    assert "readOnly: true" in out
    assert "activeFocusOnTab: true" in out
    assert "Ui.leaveAtEdge(outText, true)" in out
    assert "Ui.leaveAtEdge(outText, false)" in out


def test_endpoint_change_drops_the_old_model_status():
    """Changing the endpoint clears the old 'ready' answer; blank input is ignored."""
    setter = _section("function setEndpoint", "Process {")
    assert 'const v = (value || "").trim();' in setter
    assert 'if (v === "" || v === win.endpoint) return;' in setter
    assert "win.endpoint = v;" in setter
    assert "statusOk = false;" in setter and 'statusText = "";' in setter
    assert "onAccepted: win.setEndpoint(text)" in WIN
    assert "onClicked: win.setEndpoint(endpointField.text)" in WIN
    check = _section("function checkEndpoint()", "function setEndpoint")
    assert "statusOk = false;" in check
