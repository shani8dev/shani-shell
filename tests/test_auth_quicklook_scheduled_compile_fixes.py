"""Static checks for three QML compile errors from the shared-control refactor."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "shani"


def _read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_authenticator_empty_state_uses_action_signal():
    src = _read("Modules/Authenticator/AuthenticatorWindow.qml")
    assert "action: win.refresh()" not in src
    assert "onAction: win.refresh()" in src


def test_quicklook_listing_is_readonly_textedit():
    src = _read("Modules/QuickLook/QuickLookSheet.qml")
    before, listing = src.split("id: listing\n", 1)
    listing = listing.split("font.pixelSize", 1)[0]
    assert before.rstrip().endswith("TextEdit {")
    assert "readOnly: true" in listing
    assert "selectByMouse: true" in listing
    assert "textFormat: TextEdit.RichText" in listing
    assert "wrapMode: TextEdit.WrapAnywhere" in listing
    assert "textFormat: Text.RichText" not in listing
    assert "wrapMode: Text.WrapAnywhere" not in listing

