"""Static guards for the Models/Modem dialog fixes.

These two files are only loaded by Quickshell, so the tests assert on source
rather than instantiating the types. Each test covers one fix:

1. deleting an installed model asks for confirmation first;
2. deleting the active model clears the now-dangling Chronoa preference;
3. the connect dialog can be dismissed and drops the typed API key;
4. the PIN field asks for a numeric keypad and refuses an empty PIN;
5. sending a text is gated on the modem being ready, with a visible reason.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODELS_WIN = ROOT / "shani/Modules/Models/ModelsWindow.qml"
MODEM_DIALOG = ROOT / "shani/Modules/Modem/ModemDialog.qml"


def test_remove_asks_for_confirmation():
    """Fix 1: the trash icon arms a confirm instead of deleting immediately."""
    t = MODELS_WIN.read_text()
    assert 'property string pendingRemove: ""' in t
    # the row's trash button only arms the dialog
    assert "onClicked: win.pendingRemove = modelData.name" in t
    assert "onClicked: Models.remove(modelData.name)" not in t
    # a single modal confirm owns the actual destructive call
    body = t[t.index("id: removeConfirm") :]
    assert "standardButtons: Dialog.No | Dialog.Yes" in body
    assert 'visible: win.pendingRemove !== ""' in body
    assert 'onRejected: win.pendingRemove = ""' in body
    assert "Models.remove(name);" in body
    # say what is being lost, so the confirm is informed
    assert "Remove %1?" in body and "win.pendingRemove" in body


def test_removing_active_model_clears_preference():
    """Fix 2: a preference pointing at a deleted model no longer dangles."""
    t = MODELS_WIN.read_text()
    body = t[
        t.index("id: removeConfirm") : t.index(
            "contentItem: Text", t.index("id: removeConfirm")
        )
    ]
    assert "Settings.data.chronoaPreferredModel === name" in body
    assert 'Settings.data.chronoaPreferredModel = ""' in body
    # the clearing must happen before the model is actually removed
    assert body.index('chronoaPreferredModel = ""') < body.index("Models.remove(name)")


def test_connect_dialog_is_dismissible_and_forgets_the_key():
    """Fix 3: No/Cancel/Escape close the dialog; the secret is not kept live."""
    t = MODELS_WIN.read_text()
    body = t[
        t.index("id: connectDialog") : t.index(
            "Component.onCompleted", t.index("id: connectDialog")
        )
    ]
    assert "onRejected:" in body
    assert 'win.connectId = ""' in body
    # visible is bound to connectId, so a reject that does not clear it re-opens
    assert 'visible: win.connectId !== ""' in t
    # the typed key is dropped on both paths
    assert 'win.connectKey = "";' in body
    assert "AIProviders.connect(" in body


def test_pin_field_hardening():
    """Fix 4: numeric OSK for the PIN and no empty-PIN unlock attempt."""
    t = MODEM_DIALOG.read_text()
    pin = t[t.index("id: pin") : t.index("id: to")]
    assert 'mode: "digits"' in pin
    assert 'onAccepted: { if (text.trim() === "") return; Modem.unlock(text);' in pin
    send = t[t.index("id: send") :]
    assert 'enabled: win.mode === "pin" ? pin.text.trim() !== ""' in send
    assert 'if (pin.text.trim() === "") return;' in send


def test_text_send_is_gated_on_modem_state():
    """Fix 5: no send with no service, and a visible reason why not."""
    t = MODEM_DIALOG.read_text()
    assert 'Modem.canText && to.text.trim() !== "" && body.text.trim() !== ""' in t
    assert "} else if (Modem.canText && to.text.trim() && body.text.trim()) {" in t
    hint = t[t.index("Unlock the SIM and wait for network service") :]
    assert 'visible: win.mode === "sms" && !Modem.canText' in t
    assert "color: Theme.amber" in hint
