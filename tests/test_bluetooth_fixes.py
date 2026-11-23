"""Static regressions for the Bluetooth service fixes.

QML cannot run under pytest here, so these assert the bindings that carry each
fix: a pending prompt can no longer be masked by a passkey display, superseded
pairing requests are rejected instead of stranded, a crashed pairing agent is
reported, an invalid send file fails early with its real error, and a file
picked mid-send is not wiped by the previous transfer's completion.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_new_ask_clears_stale_passkey_display():
    """Fix 1: a stale 'show' would mask the prompt and its button answer a different ask."""
    agent = source("shani/Services/BtAgent.qml")

    assert "root.show = null;" in agent
    # the clearing happens in the m.ask branch, before the new ask is stored
    assert "root.show = null;\n                    if (root.ask)" in agent
    assert "                    root.ask = m;" in agent


def test_superseded_ask_is_rejected_not_stranded():
    """Fix 2: replacing an ask must answer the old BlueZ request instead of hanging it."""
    agent = source("shani/Services/BtAgent.qml")

    assert "if (root.ask)\n                        root.answer(false);" in agent


def test_pairing_agent_failure_is_surfaced():
    """Fix 3: a failed registration (no bus, refused default agent) cannot be silent."""
    agent = source("shani/Services/BtAgent.qml")

    assert 'property string agentError: ""' in agent
    assert "stderr: StdioCollector { id: agentErr }" in agent
    assert "root.agentError = agentErr.text.trim();" in agent
    assert 'code !== 0 && root.agentError !== ""' in agent
    assert '"Bluetooth pairing unavailable"' in agent
    assert "root.agentError.slice(0, 160)" in agent


def test_send_validates_file_and_reports_real_error():
    """Fix 4: a missing file fails before gdbus, and D-Bus errors reach the user."""
    send = source("shani/Services/BtSend.qml")

    assert '[ -f "$f" ] || { echo "not a file: $f" >&2; exit 2; }' in send
    assert 'code === 2 ? "File no longer exists"' in send
    assert "err.text.trim().slice(0, 160)" in send
    assert 'name + (code === 0 ? "" : " — "' in send


def test_file_picked_mid_send_survives_completion():
    """Fix 5: the completion handler must not clear a newer pending file."""
    send = source("shani/Services/BtSend.qml")

    assert 'property string sentFile: ""' in send
    assert "sentFile = file;" in send
    assert 'const name = root.sentFile.split("/").pop();' in send
    assert "if (root.file === root.sentFile)" in send
    assert 'root.sentFile = "";' in send
