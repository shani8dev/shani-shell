"""Static wiring for the polkit / Bluetooth-pairing dialog fixes.

Both dialogs hand a secret to a system service. These check that a credential
never survives into a different request, that a bad code is refused in the
field instead of silently rejected by BlueZ, and that Esc cancels the prompt.
Static on purpose: neither dialog can be driven without a real PAM/BlueZ stack.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLKIT = ROOT / "shani" / "Modules" / "Polkit" / "PolkitDialog.qml"
PAIR = ROOT / "shani" / "Modules" / "Pair" / "PairDialog.qml"


def block(src, start):
    """`start` through the next line at the same indentation — one handler."""
    lines = src.splitlines()
    i = next(n for n, line in enumerate(lines) if start in line)
    indent = len(lines[i]) - len(lines[i].lstrip())
    out = [lines[i]]
    for line in lines[i + 1 :]:
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        out.append(line)
    return "\n".join(out)


def test_polkit_clears_the_password_when_a_new_flow_replaces_the_old_one():
    """Polkit can hand over a second action while the window is still up."""
    src = POLKIT.read_text()
    assert "target: Polkit" in src
    handler = block(src, "function onFlowChanged()")
    assert 'pass.text = "";' in handler
    assert "pass.revealed = false;" in handler
    assert "win.focusPrompt();" in handler


def test_polkit_submits_and_cancels_through_guarded_helpers():
    """No submit path may touch a null flow, and none may leave a secret revealed."""
    src = POLKIT.read_text()
    submit = block(src, "function submitPass()")
    assert "!win.flow" in submit
    assert "win.flow.submit(pass.text);" in submit
    assert 'pass.text = "";' in submit
    assert "pass.revealed = false;" in submit
    assert "if (win.flow)" in block(src, "function cancelPass()")

    # all three ways of submitting (Enter, button, on-screen keyboard) share it
    assert src.count("win.submitPass()") == 3
    assert src.count(".submit(") == 1  # only the guarded helper calls it
    assert src.count("win.cancelPass()") == 2  # Cancel button + Esc

    # the secret stays in the field, never in a process' argv
    assert "secret: win.flow" in src
    assert "echoMode" not in src and "Process" not in src and "command:" not in src


def test_escape_cancels_the_active_prompt_in_both_dialogs():
    src = POLKIT.read_text()
    assert "Keys.onEscapePressed: win.cancelPass()" in src
    pair = PAIR.read_text()
    assert (
        "Keys.onEscapePressed: win.show ? BtAgent.dismiss() : BtAgent.answer(false)"
        in pair
    )


def test_pair_refuses_empty_and_non_numeric_codes_with_inline_feedback():
    """BlueZ silently rejects a bad code; the field must say why before replying."""
    src = PAIR.read_text()
    body = block(src, "function submitCode()")
    assert "if (!ask)" in body
    assert 'code.error = "Enter the code first"' in body
    assert r"/^\d+$/.test(v)" in body
    assert 'code.error = "Use digits only"' in body
    assert "BtAgent.answer(true, v);" in body

    # both ways of confirming use the validator; no raw answer is left behind
    assert src.count("win.submitCode()") == 2
    assert src.count("BtAgent.answer(true") == 1
    assert "BtAgent.answer(true, code.text.trim())" not in src
    assert 'onTextChanged: if (text !== "") error = ""' in src
    assert "echoMode" not in src and "Process" not in src


def test_pair_clears_a_stale_code_when_a_new_request_arrives():
    """Two PIN prompts in a row must not show the first one's code."""
    src = PAIR.read_text()
    assert "property int lastCodeAsk: -1" in src
    assert "target: BtAgent" in src
    handler = block(src, "function onAskChanged()")
    assert "ask.id !== win.lastCodeAsk" in handler
    assert "win.lastCodeAsk = ask.id;" in handler
    assert 'code.text = "";' in handler
    assert 'code.error = "";' in handler


def test_polkit_cancel_and_submit_clear_secrets_and_guard_empty_submit():
    """Cancel/submit must never leave a secret, and empty/irrelevant submits are refused."""
    src = POLKIT.read_text()
    submit = block(src, "function submitPass()")
    assert "if (!win.flow || !win.flow.isResponseRequired)" in submit
    assert 'if (pass.text.trim() === "")' in submit
    assert "win.flow.submit(pass.text);" in submit
    assert 'pass.text = "";' in submit
    assert "pass.revealed = false;" in submit

    cancel = block(src, "function cancelPass()")
    assert 'pass.text = "";' in cancel
    assert "pass.revealed = false;" in cancel
    assert "win.flow.cancelAuthenticationRequest();" in cancel

    # Authenticate is only meaningful when a response is required and typed
    assert (
        'enabled: win.flow && win.flow.isResponseRequired && pass.text.trim() !== ""'
        in src
    )
    # hiding the dialog must not leave the secret behind
    assert "onVisibleChanged:" in src
    assert "else {" in src


def test_polkit_refocuses_and_clears_password_on_auth_failure():
    """A wrong password should be cleared and the prompt refocused for retry."""
    src = POLKIT.read_text()
    handler = block(src, "function onErrorChanged()")
    assert 'Polkit.error !== ""' in handler
    assert "win.visible" in handler
    assert 'pass.text = "";' in handler
    assert "pass.revealed = false;" in handler
    assert "win.focusPrompt();" in handler


def test_polkit_focus_and_accessibility_for_prompt_modes():
    """Fingerprint-only prompts need focus on a visible control; dialog is announced."""
    src = POLKIT.read_text()
    focus = block(src, "function focusPrompt()")
    assert "if (pass.visible)" in focus
    assert "pass.input.forceActiveFocus();" in focus
    assert "cancelBtn.forceActiveFocus();" in focus
    assert "id: cancelBtn" in src
    assert "Accessible.role: Accessible.Dialog" in src
    assert 'Accessible.name: Tr.t("Authentication required")' in src


def test_pair_dialog_focuses_actions_and_announces_itself_for_keyboard_at():
    """Non-typed pairing prompts must be keyboard reachable without a mouse."""
    src = PAIR.read_text()
    focus = block(src, "function focusPrompt()")
    assert "if (win.typed)" in focus
    assert "code.input.forceActiveFocus();" in focus
    assert "primaryBtn.forceActiveFocus();" in focus
    assert "closeBtn.forceActiveFocus();" in focus
    assert "onVisibleChanged: if (visible) win.focusPrompt()" in src
    assert "Qt.callLater(win.focusPrompt);" in src
    assert "id: closeBtn" in src
    assert "id: primaryBtn" in src
    assert "Accessible.role: Accessible.Dialog" in src
    assert 'Accessible.name: Tr.t("Bluetooth pairing")' in src


def test_pair_show_code_displays_expiry_countdown():
    """A displayed pairing code should warn before BtAgent's 60s expiry drops it."""
    src = PAIR.read_text()
    assert "property int showSecsLeft: 60" in src
    assert "id: showCountdown" in src
    assert "repeat: true" in src
    assert "running: win.show !== null && win.visible" in src
    assert "win.showSecsLeft = 60;" in src
    assert "Expires in %1s" in src
